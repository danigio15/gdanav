import CarPlay
import UIKit

/// gdanav nel Dashboard di CarPlay: il riquadro della mappa accanto alla
/// musica e al calendario, quando l'app non è a schermo intero.
///
/// Come la mappa a mezzo schermo di Android Auto: la stessa mappa di gdanav
/// (`MappaCarPlay`, senza i dati sopra) che segue l'auto. In guida la manovra
/// e i tempi li scrive CarPlay da sé, accanto alla mappa, dal viaggio che la
/// scena principale ha già aperto (`GdanavCarPlay`). Senza una guida in
/// corso, due tasti: Casa e Lavoro, se sono impostati.
///
/// Chi porta gdanav dentro la mette nell'Info.plist come delegato della scena
/// `CPTemplateApplicationDashboardSceneSessionRoleApplication`, col nome
/// `GdanavDashboardCarPlay`.
@objc(GdanavDashboardCarPlay)
public final class GdanavDashboardCarPlay: UIResponder, CPTemplateApplicationDashboardSceneDelegate {
    private var mappa: MappaCarPlay?
    private weak var controllo: CPDashboardController?
    private var ascolto: UUID?
    /// I tasti mostrati adesso, per non rifarli a ogni posizione.
    private var tastiMostrati: [String] = []

    public func templateApplicationDashboardScene(
        _ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
        didConnect dashboardController: CPDashboardController,
        to window: UIWindow
    ) {
        controllo = dashboardController
        let m = MappaCarPlay(soloMappa: true)
        window.rootViewController = m
        mappa = m
        ascolto = PonteAuto.shared.ascolta { [weak self] in self?.novita() }
        novita()
    }

    public func templateApplicationDashboardScene(
        _ templateApplicationDashboardScene: CPTemplateApplicationDashboardScene,
        didDisconnect dashboardController: CPDashboardController,
        from window: UIWindow
    ) {
        if let a = ascolto { PonteAuto.shared.smetti(a) }
        ascolto = nil
        window.rootViewController = nil
        mappa = nil
        controllo = nil
        tastiMostrati = []
    }

    private func novita() {
        mappa?.aggiorna()
        aggiornaTasti()
    }

    /// Casa e Lavoro, quando non si sta guidando verso una meta. In guida
    /// niente tasti: il riquadro mostra la manovra, che è quello che serve.
    private func aggiornaTasti() {
        guard let controllo else { return }
        let ponte = PonteAuto.shared
        let mete: [(tipo: String, nome: String, simbolo: String)] = ponte.guida != nil ? [] : [
            ("casa", "Casa", "house.fill"),
            ("lavoro", "Lavoro", "briefcase.fill"),
        ].filter { m in ponte.luoghi.contains { $0.tipo == m.tipo } }
        let chiavi = mete.map(\.tipo)
        if chiavi == tastiMostrati { return }
        tastiMostrati = chiavi
        controllo.shortcutButtons = mete.map { meta in
            let luogo = ponte.luoghi.first { $0.tipo == meta.tipo }
            return CPDashboardButton(
                titleVariants: [meta.nome],
                subtitleVariants: luogo.map { [$0.nome] } ?? [],
                image: UIImage(systemName: meta.simbolo) ?? UIImage()
            ) { _ in
                GdanavCarPlay.vaiA(meta.tipo)
            }
        }
    }
}
