import Foundation

/// La guida per l'Apple Watch dell'app che ospita gdanav (gdahome).
///
/// L'orologio non parla con gdanav: parla col telefono, e il telefono gli
/// passa quello che serve guardando il polso — la prossima manovra, quanto
/// manca, quando si arriva. Qui si mette in una notifica, senza che l'app
/// ospite debba vedere `PonteAuto` (che resta interno), e senza che debba
/// conoscere questo file per compilare: si parlano per nome. Un'app ospite
/// costruita con un gdanav di prima semplicemente non riceve niente.
///
/// - `gdanav.orologio.guida` (da qui): `userInfo` è la fotografia della guida,
///   vedi `fotografia()`. Parte a ogni cambio; chi la ascolta ne tiene una al
///   secondo.
/// - `gdanav.orologio.ferma` (verso qui): finisce la guida, come «Fine»
///   sull'auto.
///
/// «Portami a casa» non passa di qui: c'è già `GdanavCarPlay.vaiA`.
enum GdanavOrologio {
    static let guida = Notification.Name("gdanav.orologio.guida")
    static let ferma = Notification.Name("gdanav.orologio.ferma")

    private static var acceso = false

    static func accendi() {
        guard !acceso else { return }
        acceso = true
        PonteAuto.shared.ascolta {
            NotificationCenter.default.post(name: guida, object: nil, userInfo: fotografia())
        }
        NotificationCenter.default.addObserver(forName: ferma, object: nil, queue: .main) { _ in
            PonteAuto.shared.fermaDallAuto()
        }
    }

    /// Quello che si vede al polso: niente mappa, niente posizione.
    static func fotografia() -> [String: Any] {
        let p = PonteAuto.shared
        var foto: [String: Any] = [
            "attiva": p.guida != nil,
            "casa": p.casa() != nil,
            "lavoro": p.lavoro() != nil,
        ]
        if let m = p.messaggio, !m.isEmpty { foto["messaggio"] = m }
        if let v = p.cruscotto.velocita { foto["velocita"] = v }
        if let l = p.cruscotto.limite { foto["limite"] = l }
        if let g = p.guida {
            foto["tipo"] = g.tipo
            foto["distanza"] = g.distanzaM
            foto["istruzione"] = g.istruzione
            foto["strada"] = g.strada
            foto["restanti"] = g.restantiM
            foto["secondi"] = g.restantiS
            foto["arrivo"] = g.arrivo.timeIntervalSince1970 * 1000
            foto["destinazione"] = g.destinazione
            if let r = g.rotonda { foto["rotonda"] = r }
        }
        return foto
    }
}
