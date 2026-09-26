import UIKit

/// Dal tipo di manovra di Valhalla al disegno per CarPlay, come fa
/// `IconeManovra.kt` per Android Auto. Si guida a destra: le rotonde girano in
/// senso antiorario.
enum ManovreCarPlay {
    static func simbolo(_ valhalla: Int) -> String {
        switch valhalla {
        case 4, 5, 6: return "flag.checkered"
        case 9: return "arrow.up.right"
        case 2, 10: return "arrow.turn.up.right"
        case 11: return "arrow.turn.down.right"
        case 12, 13: return "arrow.uturn.left"
        case 14: return "arrow.turn.down.left"
        case 3, 15: return "arrow.turn.up.left"
        case 16: return "arrow.up.left"
        case 18, 20: return "arrow.up.right"
        case 19, 21: return "arrow.up.left"
        case 23: return "arrow.triangle.branch"
        case 24: return "arrow.triangle.branch"
        case 25, 37, 38: return "arrow.triangle.merge"
        case 26, 27: return "arrow.triangle.2.circlepath"
        case 28, 29: return "ferry"
        default: return "arrow.up"
        }
    }

    /// Il disegno della manovra: bianco, sul fondo della scheda di guida.
    static func immagine(_ valhalla: Int) -> UIImage? {
        let conf = UIImage.SymbolConfiguration(pointSize: 44, weight: .bold)
        let nome = simbolo(valhalla)
        let base = UIImage(systemName: nome, withConfiguration: conf) ?? UIImage(systemName: "arrow.up", withConfiguration: conf)
        // Il bivio a sinistra è quello a destra allo specchio.
        let giusta = valhalla == 24 ? base?.withHorizontallyFlippedOrientation() : base
        return giusta?.withTintColor(.white, renderingMode: .alwaysOriginal)
    }

    /// La freccia di una corsia, come la manda l'app.
    private static func simboloCorsia(_ direzione: String) -> String {
        switch direzione {
        case "leggeraDestra": return "arrow.up.right"
        case "destra", "destraStretta": return "arrow.turn.up.right"
        case "leggeraSinistra": return "arrow.up.left"
        case "sinistra", "sinistraStretta": return "arrow.turn.up.left"
        case "inversioneSinistra", "inversioneDestra": return "arrow.uturn.left"
        default: return "arrow.up"
        }
    }

    /// Le corsie prima dello svincolo, disegnate in una striscia (come
    /// `ImmagineCorsie.kt`): quelle giuste bianche, le altre spente. CarPlay la
    /// mostra sotto la manovra, al posto della vista dello svincolo.
    static func corsie(_ corsie: [CorsiaAuto]) -> UIImage? {
        guard !corsie.isEmpty else { return nil }
        let lato: CGFloat = 36
        let spazio: CGFloat = 6
        let dimensione = CGSize(
            width: CGFloat(corsie.count) * lato + CGFloat(corsie.count - 1) * spazio,
            height: lato
        )
        let conf = UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        let disegno = UIGraphicsImageRenderer(size: dimensione)
        return disegno.image { _ in
            for (i, c) in corsie.enumerated() {
                let x = CGFloat(i) * (lato + spazio)
                let riquadro = CGRect(x: x, y: 0, width: lato, height: lato)
                UIColor(white: 1, alpha: c.giusta ? 0.18 : 0.06).setFill()
                UIBezierPath(roundedRect: riquadro, cornerRadius: 6).fill()
                let direzione = c.consigliata ?? c.direzioni.first ?? "dritto"
                guard let freccia = UIImage(systemName: simboloCorsia(direzione), withConfiguration: conf)?
                    .withTintColor(UIColor(white: 1, alpha: c.giusta ? 1 : 0.35), renderingMode: .alwaysOriginal)
                else { continue }
                let dove = CGRect(
                    x: riquadro.midX - freccia.size.width / 2,
                    y: riquadro.midY - freccia.size.height / 2,
                    width: freccia.size.width,
                    height: freccia.size.height
                )
                let specchio = direzione == "inversioneDestra"
                (specchio ? freccia.withHorizontallyFlippedOrientation() : freccia).draw(in: dove)
            }
        }
    }

    /// Un'immagine riportata dentro `massimo` punti, per le schede di CarPlay.
    static func dentro(_ immagine: UIImage, _ massimo: CGSize) -> UIImage {
        let s = immagine.size
        let r = min(massimo.width / s.width, massimo.height / s.height, 1)
        if r >= 1 { return immagine }
        let nuova = CGSize(width: s.width * r, height: s.height * r)
        return UIGraphicsImageRenderer(size: nuova).image { _ in immagine.draw(in: CGRect(origin: .zero, size: nuova)) }
    }

    /// Da che parte va la manovra: 1 destra, -1 sinistra, 0 dritto (come `PannelloAuto.kt`).
    static func lato(_ tipo: Int) -> Int {
        switch tipo {
        case 9, 10, 11, 18, 20, 23, 37: return 1
        case 14, 15, 16, 19, 21, 24, 38: return -1
        default: return 0
        }
    }

    /// Il testo della scheda, come su Android Auto: «Uscita 43 · A14 · Bologna,
    /// Ravenna», o la strada, o l'istruzione.
    static func testo(_ g: GuidaAuto) -> String {
        let cartello = [g.uscita.isEmpty ? nil : "Uscita \(g.uscita)", g.verso.isEmpty ? nil : g.verso]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !cartello.isEmpty { return cartello }
        return g.strada.isEmpty ? g.istruzione : g.strada
    }

    /// La vista dello svincolo col cartello dell'uscita disegnato nel cielo dal
    /// lato giusto e piantato coi suoi pali, come `svincoloConCartello` in
    /// `PannelloAuto.kt`.
    static func svincoloConCartello(_ vista: UIImage, _ g: GuidaAuto) -> UIImage {
        guard !g.uscita.isEmpty || !g.verso.isEmpty else { return vista }
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = vista.scale
        return UIGraphicsImageRenderer(size: vista.size, format: formato).image { _ in
            vista.draw(at: .zero)
            // Le misure sono pensate per una vista larga 500 punti.
            let k = vista.size.width / 500
            let m = 10 * k
            cartelloUscita(
                sinistra: m,
                destra: vista.size.width - m,
                y: m,
                larghezzaMassima: vista.size.width * 0.38,
                g: g,
                pali: vista.size.height * 0.52,
                righe: 2,
                k: k
            )
        }
    }

    /// Il cartello dell'uscita come in autostrada: verde, bordo bianco, in
    /// alto «USCITA» col numero e le sigle (A14, E45), sotto le direzioni con la
    /// freccia. Blu se non è un'uscita numerata. Si disegna nel contesto attuale.
    private static func cartelloUscita(
        sinistra: CGFloat,
        destra: CGFloat,
        y: CGFloat,
        larghezzaMassima: CGFloat,
        g: GuidaAuto,
        pali: CGFloat,
        righe: Int,
        k: CGFloat
    ) {
        func dp(_ v: CGFloat) -> CGFloat { v * k }
        let autostrada = !g.uscita.isEmpty || (18...21).contains(g.tipo)
            || g.verso.range(of: "^[AE] ?\\d", options: .regularExpression) != nil
        let colore = autostrada
            ? UIColor(red: 0, green: 122 / 255, blue: 61 / 255, alpha: 1)
            : UIColor(red: 21 / 255, green: 88 / 255, blue: 176 / 255, alpha: 1)
        let parti = g.verso
            .components(separatedBy: CharacterSet(charactersIn: ";"))
            .flatMap { $0.components(separatedBy: " · ") }
            .flatMap { $0.components(separatedBy: ", ") }
            .flatMap { $0.components(separatedBy: "/") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let sigle = Array(parti.filter { $0.range(of: "^[AESTR]{1,2} ?\\d+[a-z]?$", options: .regularExpression) != nil }.prefix(3))
        var luoghi = Array(parti.filter { !sigle.contains($0) }.prefix(righe))
        if luoghi.isEmpty { luoghi = [g.strada.isEmpty ? g.istruzione : g.strada].filter { !$0.isEmpty } }

        func carattere(_ t: CGFloat, _ c: UIColor = .white) -> [NSAttributedString.Key: Any] {
            [.font: UIFont.systemFont(ofSize: dp(t), weight: .bold), .foregroundColor: c]
        }
        var nome = carattere(22)
        let etichetta = carattere(13)
        let sigla = carattere(16)
        func larghezza(_ t: String, _ a: [NSAttributedString.Key: Any]) -> CGFloat { (t as NSString).size(withAttributes: a).width }

        let interno = dp(14)
        let hTesta: CGFloat = g.uscita.isEmpty ? 0 : dp(34)
        let hSigle: CGFloat = !sigle.isEmpty && g.uscita.isEmpty ? dp(32) : 0
        let hRiga = dp(28)
        // Nomi lunghi: prima si rimpicciolisce un po' il testo, poi si taglia.
        let spazioNomi = larghezzaMassima - interno * 2 - dp(36)
        let piuLungo = luoghi.map { larghezza($0, nome) }.max() ?? 0
        if piuLungo > spazioNomi && spazioNomi > 0 { nome = carattere(22 * max(0.7, spazioNomi / piuLungo)) }
        let larghezzaTesto = max(
            luoghi.map { larghezza($0, nome) }.max() ?? 0,
            sigle.reduce(0) { $0 + larghezza($1, sigla) + dp(22) } + (g.uscita.isEmpty ? 0 : larghezza("USCITA", etichetta) + dp(60))
        )
        let w = min(max(larghezzaTesto + interno * 2 + dp(36), dp(180)), max(larghezzaMassima, dp(180)))
        let h = interno + hTesta + hSigle + hRiga * CGFloat(max(luoghi.count, 1)) + interno - dp(6)
        let x: CGFloat
        switch lato(g.tipo) {
        case 1: x = destra - w
        case -1: x = sinistra
        default: x = (sinistra + destra - w) / 2
        }
        let box = CGRect(x: x, y: y, width: w, height: h)
        // Due pali grigi sotto il cartello, fino alla strada.
        UIColor(red: 120 / 255, green: 126 / 255, blue: 134 / 255, alpha: 1).setFill()
        for f in [0.22, 0.78] as [CGFloat] {
            let px = box.minX + box.width * f
            UIRectFill(CGRect(x: px - dp(3), y: box.maxY - dp(4), width: dp(6), height: max(pali, box.maxY) - box.maxY + dp(4)))
        }
        colore.setFill()
        UIBezierPath(roundedRect: box, cornerRadius: dp(10)).fill()
        UIColor.white.setStroke()
        let bordo = UIBezierPath(roundedRect: box.insetBy(dx: dp(4), dy: dp(4)), cornerRadius: dp(7))
        bordo.lineWidth = dp(2.5)
        bordo.stroke()

        var riga = box.minY + interno
        var inizioSigle = box.minX + interno
        if !g.uscita.isEmpty {
            // «USCITA 43» in un riquadro bianco col numero verde.
            ("USCITA" as NSString).draw(at: CGPoint(x: box.minX + interno, y: riga + dp(5)), withAttributes: etichetta)
            let n = String(g.uscita.prefix(6))
            let nw = larghezza(n, sigla) + dp(16)
            let xn = box.minX + interno + larghezza("USCITA", etichetta) + dp(8)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: xn, y: riga, width: nw, height: dp(26)), cornerRadius: dp(5)).fill()
            (n as NSString).draw(at: CGPoint(x: xn + dp(8), y: riga + dp(3)), withAttributes: carattere(16, colore))
            inizioSigle = xn + nw + dp(10)
        }
        var xs = inizioSigle
        let y0 = g.uscita.isEmpty ? riga : riga + dp(1)
        for s in sigle {
            // Autostrade: riquadro bianco; strade europee: verde.
            let europea = s.hasPrefix("E")
            let sw = larghezza(s, sigla) + dp(14)
            (europea ? UIColor(red: 0, green: 150 / 255, blue: 70 / 255, alpha: 1) : UIColor.white).setFill()
            UIBezierPath(roundedRect: CGRect(x: xs, y: y0, width: sw, height: dp(24)), cornerRadius: dp(5)).fill()
            (s as NSString).draw(at: CGPoint(x: xs + dp(7), y: y0 + dp(3)), withAttributes: carattere(16, europea ? .white : colore))
            xs += sw + dp(8)
        }
        riga += hTesta + hSigle
        // Le direzioni, con la freccia verso l'uscita.
        let freccia: String
        switch lato(g.tipo) {
        case 1: freccia = "↗"
        case -1: freccia = "↖"
        default: freccia = "↑"
        }
        let spazio = box.width - interno * 2 - dp(30)
        for (i, l) in luoghi.enumerated() {
            var t = l
            while larghezza(t, nome) > spazio && t.count > 4 { t = String(t.dropLast(2)) + "…" }
            (t as NSString).draw(at: CGPoint(x: box.minX + interno, y: riga + dp(2)), withAttributes: nome)
            if i == 0 {
                let f = carattere(26)
                (freccia as NSString).draw(at: CGPoint(x: box.maxX - interno - larghezza(freccia, f), y: riga), withAttributes: f)
            }
            riga += hRiga
        }
    }

    /// «600 m», «1,2 km»: come le distanze sul telefono.
    static func distanza(_ metri: Double) -> Measurement<UnitLength> {
        if metri >= 1000 {
            return Measurement(value: (metri / 100).rounded() / 10, unit: .kilometers)
        }
        let passo: Double = metri > 300 ? 50 : 10
        return Measurement(value: (metri / passo).rounded() * passo, unit: .meters)
    }
}
