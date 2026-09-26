import UIKit

/// Sopra la mappa di CarPlay, come su Android Auto (`PannelloAuto.kt`): poco
/// e in basso, perché la mappa si veda. In basso a sinistra, dal lato di chi
/// guida, la capsula con velocità e limite, e sopra una barra sottile coi dati
/// dell'auto (batteria, km, alla meta), il meteo e la prossima sosta; in alto,
/// piccolo, l'avviso della segnalazione che si avvicina, finché serve.
///
/// La scheda della manovra e arrivo/durata/km li disegna CarPlay: qui non si
/// ripetono. Tutto sta dentro l'area sicura che CarPlay lascia libera.
final class PannelloCarPlay: UIView {
    /// L'area non coperta dai tasti e dalle schede di CarPlay.
    var area: UIEdgeInsets = .zero {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non si usa") }

    func aggiorna() { setNeedsDisplay() }

    // Le misure di Android Auto, un po' più piccole: lo schermo di CarPlay è
    // più stretto.
    private func dp(_ v: CGFloat) -> CGFloat { v * 0.85 }

    private let fondoScheda = UIColor(red: 32 / 255, green: 33 / 255, blue: 36 / 255, alpha: 0.92)
    private let muto = UIColor(white: 1, alpha: 185 / 255)

    private func font(_ pt: CGFloat, grassetto: Bool = true, colore: UIColor = .white) -> [NSAttributedString.Key: Any] {
        [.font: UIFont.systemFont(ofSize: dp(pt), weight: grassetto ? .bold : .regular), .foregroundColor: colore]
    }

    private func larghezza(_ t: String, _ a: [NSAttributedString.Key: Any]) -> CGFloat {
        (t as NSString).size(withAttributes: a).width
    }

    /// Scrive [t] con la linea di base a [y], come `drawText` di Android.
    private func scrivi(_ t: String, _ x: CGFloat, _ y: CGFloat, _ a: [NSAttributedString.Key: Any]) {
        let f = a[.font] as? UIFont ?? .systemFont(ofSize: 14)
        (t as NSString).draw(at: CGPoint(x: x, y: y - f.ascender), withAttributes: a)
    }

    private func taglia(_ t: String, _ a: [NSAttributedString.Key: Any], _ spazio: CGFloat) -> String {
        var s = t
        while larghezza(s, a) > spazio && s.count > 3 { s = String(s.dropLast(2)) + "…" }
        return s
    }

    override func draw(_ rect: CGRect) {
        let a = bounds.inset(by: area)
        guard a.width > 0, a.height > 0 else { return }
        let c = PonteAuto.shared.cruscotto
        let margine = dp(10)
        avviso(sinistra: a.minX + margine, destra: a.maxX - margine, alto: a.minY + margine)
        let tachimetro = velocita(a, c)
        barra(a, tachimetro, c)
    }

    // MARK: - La barra dei dati

    /// Batteria (icona e %), km che restano, batteria alla meta, meteo; sopra,
    /// piccola, la prossima sosta. Con la termica solo il meteo.
    private func barra(_ a: CGRect, _ tachimetro: CGRect?, _ c: CruscottoAuto) {
        let b = c.elettrica ? c.batteria : nil
        let meteo = c.meteoTemperatura
        if b == nil && meteo == nil && c.sostaNome == nil { return }
        let margine = dp(10)
        let forte = font(20)
        let piccolo = font(13, grassetto: false, colore: muto)
        let p = dp(14)
        let spazio = dp(9)

        // I pezzi della riga: larghezza e come disegnarli da x, alla linea y.
        var pezzi: [(CGFloat, (CGFloat, CGFloat) -> Void)] = []
        if let b {
            let colore: UIColor = b < 20
                ? UIColor(red: 239 / 255, green: 83 / 255, blue: 80 / 255, alpha: 1)
                : b < 50 ? UIColor(red: 1, green: 193 / 255, blue: 7 / 255, alpha: 1)
                : UIColor(red: 102 / 255, green: 187 / 255, blue: 106 / 255, alpha: 1)
            let t = "\(Int(b.rounded()))%"
            pezzi.append((dp(32) + larghezza(t, forte), { x, y in
                let corpo = CGRect(x: x, y: y - self.dp(15), width: self.dp(24), height: self.dp(13))
                UIColor.white.setStroke()
                let contorno = UIBezierPath(roundedRect: corpo, cornerRadius: self.dp(3))
                contorno.lineWidth = self.dp(2)
                contorno.stroke()
                UIColor.white.setFill()
                UIRectFill(CGRect(x: corpo.maxX + self.dp(1), y: y - self.dp(11), width: self.dp(2), height: self.dp(5)))
                colore.setFill()
                let livello = CGFloat(min(max(b / 100, 0.06), 1))
                UIRectFill(CGRect(
                    x: corpo.minX + self.dp(3),
                    y: corpo.minY + self.dp(3),
                    width: (corpo.width - self.dp(6)) * livello,
                    height: corpo.height - self.dp(6)
                ))
                self.scrivi(t, x + self.dp(32), y, forte)
            }))
            if let km = c.autonomiaKm {
                let t = "\(Int(km.rounded())) km"
                pezzi.append((larghezza(t, forte), { x, y in self.scrivi(t, x, y, forte) }))
            }
            if let v = c.arrivoBatteria {
                let t = "\(Int(v.rounded()))%"
                let valore = font(20, colore: v < 10
                    ? UIColor(red: 239 / 255, green: 83 / 255, blue: 80 / 255, alpha: 1)
                    : UIColor(red: 102 / 255, green: 187 / 255, blue: 106 / 255, alpha: 1))
                let etichetta = font(14, grassetto: false, colore: muto)
                let spazioEtichetta = larghezza("meta", etichetta) + dp(6)
                pezzi.append((spazioEtichetta + larghezza(t, valore), { x, y in
                    self.scrivi("meta", x, y, etichetta)
                    self.scrivi(t, x + spazioEtichetta, y, valore)
                }))
            }
        }
        if let m = meteo {
            let t = "\(c.meteoEmoji ?? "") \(Int(m.rounded()))°".trimmingCharacters(in: .whitespaces)
            pezzi.append((larghezza(t, forte), { x, y in self.scrivi(t, x, y, forte) }))
        }
        let larghezzaRiga = pezzi.reduce(0) { $0 + $1.0 } + spazio * 2 * CGFloat(max(pezzi.count - 1, 0))
        var sosta: String?
        if let nome = c.sostaNome {
            sosta = [
                "⚡ \(nome)",
                c.sostaKm.map { "\(Int($0.rounded())) km" },
                c.sostaBatteria.map { "arrivi col \(Int($0.rounded()))%" },
            ].compactMap { $0 }.joined(separator: " · ")
        }
        // Larga quanto la riga; la sosta, se è più lunga, si accorcia.
        let w = min((pezzi.isEmpty ? dp(220) : larghezzaRiga) + p * 2, a.width - margine * 2)
        let hRiga = dp(54)
        let hSosta: CGFloat = sosta != nil ? dp(24) : 0
        let h = hRiga + hSosta
        // In basso a sinistra, sopra la capsula del tachimetro.
        let basso = tachimetro.map { $0.minY - dp(8) } ?? (a.maxY - margine)
        let box = CGRect(x: a.minX + margine, y: basso - h, width: w, height: h)
        fondoScheda.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: dp(18)).fill()
        if let sosta {
            scrivi(taglia(sosta, piccolo, w - p * 2), box.minX + p, box.minY + dp(19), piccolo)
        }
        let linea = box.maxY - hRiga / 2 + dp(7)
        var cx = box.minX + p + max(w - p * 2 - larghezzaRiga, 0) / 2
        for (i, pezzo) in pezzi.enumerated() {
            if i > 0 {
                UIColor(white: 1, alpha: 60 / 255).setFill()
                UIRectFill(CGRect(x: cx + spazio - dp(0.5), y: linea - dp(17), width: dp(1), height: dp(20)))
                cx += spazio * 2
            }
            pezzo.1(cx, linea)
            cx += pezzo.0
        }
    }

    // MARK: - Il tachimetro

    /// In basso a sinistra, in una capsula: la velocità (rossa oltre il
    /// limite) e il cartello del limite. Arrivo, durata e km stanno già nella
    /// scheda dei tempi di CarPlay. Restituisce dove sta.
    private func velocita(_ a: CGRect, _ c: CruscottoAuto) -> CGRect? {
        guard let v = c.velocita else { return nil }
        let margine = dp(10)
        let h = dp(54)
        let r = dp(22)
        let basso = a.maxY - margine
        let cy = basso - h / 2
        var x = a.minX + margine + dp(5)
        let cxVelocita = x + r
        x += r * 2 + dp(6)
        var cxLimite: CGFloat?
        if c.limite != nil {
            cxLimite = x + r * 0.9
            x += r * 1.8 + dp(5)
        }
        let box = CGRect(x: a.minX + margine, y: basso - h, width: x - a.minX - margine + dp(4), height: h)
        fondoScheda.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: h / 2).fill()
        if let cxLimite, let l = c.limite { cartello(cxLimite, cy, r * 0.9, l) }
        let oltre = c.limite.map { v > Double($0) + 3 } ?? false
        (oltre ? UIColor(red: 229 / 255, green: 57 / 255, blue: 53 / 255, alpha: 1) : .white).setFill()
        UIBezierPath(ovalIn: CGRect(x: cxVelocita - r, y: cy - r, width: r * 2, height: r * 2)).fill()
        let colore: UIColor = oltre ? .white : UIColor(red: 32 / 255, green: 38 / 255, blue: 51 / 255, alpha: 1)
        centrato("\(Int(v.rounded()))", cxVelocita, cy + dp(4), font(19, colore: colore))
        centrato("km/h", cxVelocita, cy + dp(15), font(8.5, colore: colore))
        return box
    }

    private func centrato(_ t: String, _ cx: CGFloat, _ y: CGFloat, _ a: [NSAttributedString.Key: Any]) {
        scrivi(t, cx - larghezza(t, a) / 2, y, a)
    }

    /// Il cartello del limite: cerchio bianco col bordo rosso.
    private func cartello(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ limite: Int) {
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()
        let spessore = r * 0.2
        let bordo = UIBezierPath(ovalIn: CGRect(x: cx - r + spessore / 2, y: cy - r + spessore / 2, width: r * 2 - spessore, height: r * 2 - spessore))
        UIColor(red: 211 / 255, green: 47 / 255, blue: 47 / 255, alpha: 1).setStroke()
        bordo.lineWidth = spessore
        bordo.stroke()
        let dimensione = r * (limite >= 100 ? 0.72 : 0.85)
        let a: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: dimensione, weight: .bold), .foregroundColor: UIColor.black]
        centrato("\(limite)", cx, cy + dimensione * 0.35, a)
    }

    // MARK: - L'avviso

    /// La segnalazione che si avvicina (autovelox, polizia, incidente…) o
    /// quella appena passata («c'è ancora?», si risponde coi tasti in alto):
    /// una capsula piccola in alto al centro, finché serve.
    private func avviso(sinistra: CGFloat, destra: CGFloat, alto: CGFloat) {
        let av = PonteAuto.shared.avviso
        let riga1: String
        let riga2: String?
        let colore: UIColor
        if let titolo = av.titolo {
            riga1 = titolo
            riga2 = av.metri.map { "tra \(distanza($0))" }
            switch av.tipo {
            case "autovelox": colore = UIColor(red: 245 / 255, green: 124 / 255, blue: 0, alpha: 1)
            case "polizia": colore = UIColor(red: 30 / 255, green: 136 / 255, blue: 229 / 255, alpha: 1)
            case "incidente", "chiusura": colore = UIColor(red: 229 / 255, green: 57 / 255, blue: 53 / 255, alpha: 1)
            default: colore = UIColor(red: 251 / 255, green: 140 / 255, blue: 0, alpha: 1)
            }
        } else if let ancora = av.ancoraTesto {
            riga1 = ancora
            riga2 = "Rispondi coi tasti in alto"
            colore = UIColor(red: 32 / 255, green: 38 / 255, blue: 51 / 255, alpha: 0.92)
        } else {
            return
        }
        let testo = font(19)
        let testoPiccolo = font(14, grassetto: false, colore: UIColor(white: 1, alpha: 225 / 255))
        let icona = av.tipo.flatMap { PonteAuto.shared.immagini["segnala-\($0)"] }
        let spazioIcona: CGFloat = icona != nil ? dp(44) : 0
        let spazioLimite: CGFloat = av.limite != nil ? dp(48) : 0
        let w = min(
            max(larghezza(riga1, testo), riga2.map { larghezza($0, testoPiccolo) } ?? 0) + dp(30) + spazioIcona + spazioLimite,
            destra - sinistra
        )
        let cx = (sinistra + destra) / 2
        let box = CGRect(x: cx - w / 2, y: alto, width: w, height: dp(58))
        colore.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: dp(18)).fill()
        if let icona {
            let lato = dp(36)
            icona.draw(in: CGRect(x: box.minX + dp(10), y: box.midY - lato / 2, width: lato, height: lato))
        }
        let x = box.minX + dp(15) + spazioIcona
        let spazioTesto = box.maxX - spazioLimite - dp(12) - x
        scrivi(taglia(riga1, testo, spazioTesto), x, box.minY + dp(26), testo)
        if let riga2 { scrivi(taglia(riga2, testoPiccolo, spazioTesto), x, box.minY + dp(46), testoPiccolo) }
        if let l = av.limite { cartello(box.maxX - dp(30), box.midY, dp(21), l) }
    }

    private func distanza(_ m: Double) -> String {
        m < 1000 ? "\(Int((m / 10).rounded()) * 10) m" : String(format: "%.1f km", m / 1000).replacingOccurrences(of: ".", with: ",")
    }
}
