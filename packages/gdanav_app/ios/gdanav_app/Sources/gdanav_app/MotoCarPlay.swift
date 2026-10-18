import Foundation

/// L'auto che scorre su CarPlay, fra una posizione e l'altra: il conto di
/// `MotoFluido` (gdanav_core, con le sue prove), rifatto qui coi suoi numeri
/// come su Android Auto (`MotoAuto.kt`). Lì la spiegazione; in breve:
///
///  - fra due posizioni l'auto va avanti da sola con la velocità e la curva
///    dell'ultima, al più per un secondo e mezzo;
///  - lungo la strada la freccia ha una velocità sua, quella dell'auto più o
///    meno quanto serve a recuperare lo scarto, che cambia piano e non scende
///    mai sotto un quarto di quella dell'auto: andando non si ferma e non
///    torna indietro;
///  - di lato e nella direzione insegue con la costante `tau`;
///  - da fermi rallenta fino al punto, e se il punto è appena dietro resta.
///
/// I tempi sono secondi di `CACurrentMediaTime`.
final class MotoCarPlay {
    static let tau = 0.2
    static let tauLungo = 1.0
    static let tauVelocita = 0.25
    static let oltreAlPiu = 1.5
    static let saltoM = 120.0
    static let fermoSotto = 0.5
    static let giraAlPiu = 45.0
    static let almenoDellaVelocita = 0.25
    static let indietroAlPiuM = 8.0
    static let fotogrammaAlPiu = 0.25
    static let metriPerGrado = 111195.08

    /// Dove è disegnata l'auto, e girata come (gradi da nord).
    private(set) var lat = 0.0
    private(set) var lon = 0.0
    private(set) var rotta = 0.0
    /// Dove guarda la mappa (in guida un po' avanti), portata avanti come la freccia.
    private(set) var rottaMappa = 0.0
    private(set) var velocitaMostrata = 0.0
    /// Non servono più fotogrammi finché non arriva una posizione nuova.
    private(set) var fermo = true
    /// Se c'è già qualcosa da disegnare.
    private(set) var mostrata = false

    private var haFix = false
    private var fixLat = 0.0, fixLon = 0.0, fixRotta = 0.0, fixRottaMappa = 0.0
    private var fixVelocita = 0.0, fixGira = 0.0, fixAlle = 0.0
    private var ultimo = 0.0
    private var pLat = 0.0, pLon = 0.0, pRotta = 0.0, pRottaMappa = 0.0

    func stessaPosizione(_ lat: Double, _ lon: Double) -> Bool { haFix && lat == fixLat && lon == fixLon }

    func posizione(lat: Double, lon: Double, rotta: Double, rottaMappa: Double, velocita: Double, alle: Double) {
        let passo = alle - fixAlle
        if haFix && velocita >= 2 && passo >= 0.2 && passo <= 3 {
            fixGira = min(max(MotoCarPlay.giro(fixRotta, rotta) / passo, -MotoCarPlay.giraAlPiu), MotoCarPlay.giraAlPiu)
        } else if !haFix || passo > 0.2 {
            fixGira = 0
        }
        haFix = true
        fixLat = lat
        fixLon = lon
        fixRotta = rotta
        fixRottaMappa = rottaMappa
        fixVelocita = velocita.isFinite && velocita > 0 ? velocita : 0
        fixAlle = alle
        fermo = false
    }

    func dimentica() {
        mostrata = false
        velocitaMostrata = 0
    }

    /// Si va subito lì (il volo di ritorno sull'auto, un salto).
    func salta(_ adesso: Double) {
        guard haFix else { return }
        prevedi(adesso)
        lat = pLat
        lon = pLon
        rotta = pRotta
        rottaMappa = pRottaMappa
        velocitaMostrata = andando(adesso) ? fixVelocita : 0
        ultimo = adesso
        mostrata = true
    }

    private func andando(_ adesso: Double) -> Bool {
        fixVelocita >= MotoCarPlay.fermoSotto && adesso - fixAlle < MotoCarPlay.oltreAlPiu
    }

    private func prevedi(_ adesso: Double) {
        pLat = fixLat
        pLon = fixLon
        pRotta = fixRotta
        pRottaMappa = fixRottaMappa
        if fixVelocita < MotoCarPlay.fermoSotto { return }
        let t = min(max(adesso - fixAlle, 0), MotoCarPlay.oltreAlPiu)
        let r0 = fixRotta * .pi / 180
        let w = fixGira * .pi / 180
        let est: Double, nord: Double
        if abs(w) < 1e-4 {
            est = fixVelocita * t * sin(r0)
            nord = fixVelocita * t * cos(r0)
        } else {
            let r1 = r0 + w * t
            est = fixVelocita / w * (cos(r0) - cos(r1))
            nord = fixVelocita / w * (sin(r1) - sin(r0))
        }
        pLat = fixLat + nord / MotoCarPlay.metriPerGrado
        pLon = fixLon + est / (MotoCarPlay.metriPerGrado * cos(fixLat * .pi / 180))
        pRotta = MotoCarPlay.norma(fixRotta + fixGira * t)
        pRottaMappa = MotoCarPlay.norma(fixRottaMappa + fixGira * t)
    }

    /// Un fotogramma ad `adesso`. `false` se non c'è ancora niente da disegnare.
    @discardableResult
    func fotogramma(_ adesso: Double) -> Bool {
        guard haFix else { return false }
        prevedi(adesso)
        let coslat = cos(lat * .pi / 180)
        let dx = (pLon - lon) * MotoCarPlay.metriPerGrado * coslat
        let dy = (pLat - lat) * MotoCarPlay.metriPerGrado
        let vaAvanti = andando(adesso)
        if !mostrata || (dx * dx + dy * dy).squareRoot() > MotoCarPlay.saltoM {
            salta(adesso)
            fermo = !vaAvanti
            return true
        }
        let dt = min(max(adesso - ultimo, 0), MotoCarPlay.fotogrammaAlPiu)
        ultimo = adesso
        let r = pRotta * .pi / 180
        let ve = sin(r), vn = cos(r)
        let lungo = dx * ve + dy * vn
        let lato = dx * vn - dy * ve
        let k = dt <= 0 ? 0 : 1 - exp(-dt / MotoCarPlay.tau)
        let kv = dt <= 0 ? 0 : 1 - exp(-dt / MotoCarPlay.tauVelocita)
        var arrivata = false
        let avanti: Double
        if vaAvanti {
            let minima = fixVelocita * MotoCarPlay.almenoDellaVelocita
            let massima = max(fixVelocita * 2, fixVelocita + 10)
            let scarto = lungo - velocitaMostrata * dt
            let voluta = min(max(fixVelocita + scarto / MotoCarPlay.tauLungo, minima), massima)
            velocitaMostrata += (voluta - velocitaMostrata) * kv
            if velocitaMostrata < minima { velocitaMostrata = minima }
            avanti = velocitaMostrata * dt
        } else if lungo < 0 && lungo > -MotoCarPlay.indietroAlPiuM {
            velocitaMostrata = 0
            avanti = 0
            arrivata = abs(lato) < 0.3
        } else if lungo < 0 {
            velocitaMostrata = 0
            avanti = lungo * k
        } else {
            let voluta = lungo / MotoCarPlay.tauLungo * 2
            velocitaMostrata += (voluta - velocitaMostrata) * kv
            if velocitaMostrata < 0 { velocitaMostrata = 0 }
            avanti = min(velocitaMostrata * dt, lungo)
            arrivata = lungo - avanti < 0.3 && abs(lato) < 0.3
            if arrivata { velocitaMostrata = 0 }
        }
        let diLato = lato * k
        let est = avanti * ve + diLato * vn
        let nord = avanti * vn - diLato * ve
        lat += nord / MotoCarPlay.metriPerGrado
        lon += est / (MotoCarPlay.metriPerGrado * coslat)
        rotta = MotoCarPlay.verso(rotta, pRotta, k)
        rottaMappa = MotoCarPlay.verso(rottaMappa, pRottaMappa, k)
        fermo = !vaAvanti && arrivata && abs(MotoCarPlay.giro(rotta, pRotta)) < 0.5
            && abs(MotoCarPlay.giro(rottaMappa, pRottaMappa)) < 0.5
        return true
    }

    /// Di quanto si gira da `da` ad `a`, fra -180 e 180.
    static func giro(_ da: Double, _ a: Double) -> Double {
        ((a - da + 540).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180
    }

    /// Da un angolo all'altro per la via più corta, di una parte `t`.
    static func verso(_ da: Double, _ a: Double, _ t: Double) -> Double { norma(da + giro(da, a) * t) }

    static func norma(_ g: Double) -> Double {
        (g.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// La mappa senza percorso: il conto di `telecameraLibera` (gdanav_core).
    /// 17,5 fino a 30 all'ora, 16,2 da 110 in su; `scarto` dai tasti + e −.
    static func zoomLibero(velocita: Double, scarto: Double) -> Double {
        let kmh = velocita.isFinite && velocita > 0 ? velocita * 3.6 : 0
        let t = min(max((kmh - 30) / (110 - 30), 0), 1)
        let s = t * t * (3 - 2 * t)
        return min(max(17.5 + (16.2 - 17.5) * s + scarto, 10), 19.5)
    }

    /// `icon-size` del segnaposto nello stile (`stile.dart`, strato `io`), allo `zoom`.
    private static let zoomIcona: [Double] = [10, 15, 17, 19]
    private static let valoriIcona: [Double] = [0.45, 0.6, 0.85, 1.0]

    static func dimensioneIcona(_ zoom: Double) -> Double {
        let z = zoomIcona
        let v = valoriIcona
        if zoom <= z[0] { return v[0] }
        for i in 1..<z.count where zoom <= z[i] {
            return v[i - 1] + (v[i] - v[i - 1]) * (zoom - z[i - 1]) / (z[i] - z[i - 1])
        }
        return v[v.count - 1]
    }
}
