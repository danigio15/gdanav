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
/// In guida, con la posizione arriva un pezzo del percorso (la pista): la
/// freccia scorre sopra la linea, inseguendo i metri fatti, come
/// `MotoSullaStrada` in gdanav_core. Agli svincoli e nelle rotonde non esce
/// più di strada.
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
    static let ritrovataEntroM = 15.0
    static let mezzaCordaM = 6.0

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

    // La pista, coi metri cumulati; `mostrataM` dove è la freccia, `fixM` l'ultima posizione.
    private var suPista = false
    private var pistaLat: [Double] = [], pistaLon: [Double] = [], pistaCum: [Double] = []
    private var fixM = 0.0, mostrataM = 0.0

    func stessaPosizione(_ lat: Double, _ lon: Double) -> Bool { haFix && lat == fixLat && lon == fixLon }

    func posizione(
        lat: Double, lon: Double, rotta: Double, rottaMappa: Double, velocita: Double, alle: Double,
        pista: [Double]? = nil, pistaQui: Double = 0
    ) {
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
        guard let pista else {
            suPista = false
            return
        }
        prendiPista(pista)
        // La freccia si ritrova sul pezzo nuovo dov'era; se non c'è, si salta.
        if mostrata && proietta(self.lat, self.lon) > MotoCarPlay.ritrovataEntroM { dimentica() }
        suPista = true
        fixM = min(max(pistaQui, 0), pistaCum.last ?? 0)
    }

    private func prendiPista(_ pista: [Double]) {
        let n = pista.count / 2
        pistaLat = (0..<n).map { pista[2 * $0] }
        pistaLon = (0..<n).map { pista[2 * $0 + 1] }
        pistaCum = [Double](repeating: 0, count: n)
        let coslat = cos(pistaLat[0] * .pi / 180)
        for i in 1..<n {
            let dx = (pistaLon[i] - pistaLon[i - 1]) * MotoCarPlay.metriPerGrado * coslat
            let dy = (pistaLat[i] - pistaLat[i - 1]) * MotoCarPlay.metriPerGrado
            pistaCum[i] = pistaCum[i - 1] + (dx * dx + dy * dy).squareRoot()
        }
    }

    /// Proietta un punto sulla pista: mette i metri in `mostrataM`, dà quanto è lontano.
    private func proietta(_ lat: Double, _ lon: Double) -> Double {
        let kx = MotoCarPlay.metriPerGrado * cos(lat * .pi / 180)
        let ky = MotoCarPlay.metriPerGrado
        var migliore = Double.greatestFiniteMagnitude
        for i in 1..<pistaLat.count {
            let ax = (pistaLon[i - 1] - lon) * kx, ay = (pistaLat[i - 1] - lat) * ky
            let dx = (pistaLon[i] - lon) * kx - ax, dy = (pistaLat[i] - lat) * ky - ay
            let l2 = dx * dx + dy * dy
            let t = l2 == 0 ? 0 : min(max(-(ax * dx + ay * dy) / l2, 0), 1)
            let px = ax + t * dx, py = ay + t * dy
            let d = (px * px + py * py).squareRoot()
            if d < migliore {
                migliore = d
                mostrataM = pistaCum[i - 1] + t * (pistaCum[i] - pistaCum[i - 1])
            }
        }
        return migliore
    }

    /// Il punto della pista a `metri`.
    private func puntoA(_ metri: Double) -> (lat: Double, lon: Double) {
        let c = pistaCum
        let m = min(max(metri, 0), c[c.count - 1])
        var basso = 1, alto = c.count - 1
        while basso < alto {
            let mezzo = (basso + alto) / 2
            if c[mezzo] < m { basso = mezzo + 1 } else { alto = mezzo }
        }
        let j = basso
        let f = c[j] == c[j - 1] ? 0 : min(max((m - c[j - 1]) / (c[j] - c[j - 1]), 0), 1)
        return (pistaLat[j - 1] + f * (pistaLat[j] - pistaLat[j - 1]), pistaLon[j - 1] + f * (pistaLon[j] - pistaLon[j - 1]))
    }

    /// La freccia sulla pista a `metri`: il punto, e la direzione della strada lì.
    private func sullaPista(_ metri: Double) {
        let l = pistaCum[pistaCum.count - 1]
        var da = metri - MotoCarPlay.mezzaCordaM, a = metri + MotoCarPlay.mezzaCordaM
        if a > l {
            da -= a - l
            a = l
        }
        if da < 0 {
            a = min(l, a - da)
            da = 0
        }
        let p = puntoA(da), q = puntoA(a)
        let est = (q.lon - p.lon) * MotoCarPlay.metriPerGrado * cos(p.lat * .pi / 180)
        let nord = (q.lat - p.lat) * MotoCarPlay.metriPerGrado
        if est * est + nord * nord > 1e-4 { rotta = MotoCarPlay.norma(atan2(est, nord) * 180 / .pi) }
        let qui = puntoA(metri)
        lat = qui.lat
        lon = qui.lon
    }

    /// Dove l'auto dovrebbe essere ad `adesso`, in metri sulla pista.
    private func metaPista(_ adesso: Double) -> Double {
        if fixVelocita < MotoCarPlay.fermoSotto { return fixM }
        let t = min(max(adesso - fixAlle, 0), MotoCarPlay.oltreAlPiu)
        return min(max(fixM + fixVelocita * t, 0), pistaCum[pistaCum.count - 1])
    }

    func dimentica() {
        mostrata = false
        velocitaMostrata = 0
    }

    /// Si va subito lì (il volo di ritorno sull'auto, un salto).
    func salta(_ adesso: Double) {
        guard haFix else { return }
        prevedi(adesso)
        if suPista {
            mostrataM = metaPista(adesso)
            sullaPista(mostrataM)
        } else {
            lat = pLat
            lon = pLon
            rotta = pRotta
        }
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
        if suPista { return fotogrammaSullaPista(adesso) }
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

    /// Il fotogramma in guida: lungo la pista, coi conti di sopra su un numero solo.
    private func fotogrammaSullaPista(_ adesso: Double) -> Bool {
        let meta = metaPista(adesso)
        let vaAvanti = andando(adesso)
        if !mostrata || abs(meta - mostrataM) > MotoCarPlay.saltoM {
            salta(adesso)
            fermo = !vaAvanti
            return true
        }
        let dt = min(max(adesso - ultimo, 0), MotoCarPlay.fotogrammaAlPiu)
        ultimo = adesso
        let lungo = meta - mostrataM
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
            arrivata = true
        } else if lungo < 0 {
            velocitaMostrata = 0
            avanti = lungo * k
        } else {
            let voluta = lungo / MotoCarPlay.tauLungo * 2
            velocitaMostrata += (voluta - velocitaMostrata) * kv
            if velocitaMostrata < 0 { velocitaMostrata = 0 }
            avanti = min(velocitaMostrata * dt, lungo)
            arrivata = lungo - avanti < 0.3
            if arrivata { velocitaMostrata = 0 }
        }
        mostrataM = min(max(mostrataM + avanti, 0), pistaCum[pistaCum.count - 1])
        sullaPista(mostrataM)
        rottaMappa = MotoCarPlay.verso(rottaMappa, pRottaMappa, k)
        fermo = !vaAvanti && arrivata && abs(MotoCarPlay.giro(rottaMappa, pRottaMappa)) < 0.5
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
    private static let valoriIcona: [Double] = [0.6, 0.8, 1.15, 1.35]

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
