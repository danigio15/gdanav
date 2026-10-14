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
        case 28, 29: return "ferry"
        // Rotonde, inversioni e svolte strette si disegnano a mano (`disegno`):
        // «arrow.triangle.2.circlepath» era il simbolo di «aggiorna», non una
        // rotonda.
        default: return "arrow.up"
        }
    }

    /// Il lato del simbolo della manovra, in punti: CarPlay lo vuole entro
    /// 50×50 (con 44 punti di carattere il simbolo usciva più grande).
    static let latoSimbolo: CGFloat = 50

    /// Il disegno della manovra, nelle due varianti: bianco sul fondo scuro
    /// (la scheda di guida, blu) e quasi nero sul fondo chiaro (il Dashboard
    /// e il quadro di giorno). CarPlay sceglie quella giusta dall'asset.
    /// [rotonda] è l'uscita da prendere, per disegnarla.
    static func immagine(_ valhalla: Int, rotonda: Int? = nil) -> UIImage? {
        guard let scuro = disegno(valhalla, rotonda: rotonda, colore: .white),
              let chiaro = disegno(valhalla, rotonda: rotonda, colore: UIColor(white: 0.12, alpha: 1))
        else { return nil }
        let scala = UITraitCollection(displayScale: scuro.scale)
        let asset = UIImageAsset()
        asset.register(chiaro, with: UITraitCollection(traitsFrom: [scala, UITraitCollection(userInterfaceStyle: .light)]))
        asset.register(scuro, with: UITraitCollection(traitsFrom: [scala, UITraitCollection(userInterfaceStyle: .dark)]))
        return asset.image(with: UITraitCollection(traitsFrom: [scala, UITraitCollection(userInterfaceStyle: .dark)]))
    }

    /// Una variante del disegno, nel colore [colore], in un quadrato di
    /// `latoSimbolo` punti.
    private static func disegno(_ valhalla: Int, rotonda: Int?, colore: UIColor) -> UIImage? {
        let lato = latoSimbolo
        let quadro = UIGraphicsImageRenderer(size: CGSize(width: lato, height: lato))
        switch valhalla {
        case 26:
            return quadro.image { _ in disegnaRotonda(lato, uscita: rotonda, colore: colore) }
        case 27:
            // Si esce dalla rotonda: la prima uscita, senza numero.
            return quadro.image { _ in disegnaRotonda(lato, uscita: 1, colore: colore) }
        case 12, 13:
            // 13 inversione a sinistra (in Italia), 12 a destra.
            return quadro.image { _ in disegnaInversione(lato, aSinistra: valhalla == 13, colore: colore) }
        case 11, 14:
            // «arrow.turn.down.right» scendeva e poi girava: non era una
            // svolta stretta. Qui sale, e torna indietro di 135 gradi.
            return quadro.image { _ in disegnaSvolta(lato, gradi: valhalla == 11 ? 135 : -135, colore: colore) }
        default:
            let conf = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
            guard let base = UIImage(systemName: simbolo(valhalla), withConfiguration: conf)
                ?? UIImage(systemName: "arrow.up", withConfiguration: conf)
            else { return nil }
            let tinta = base.withTintColor(colore, renderingMode: .alwaysOriginal)
            return quadro.image { contesto in
                // Il bivio a sinistra è quello a destra allo specchio.
                if valhalla == 24 {
                    contesto.cgContext.translateBy(x: lato, y: 0)
                    contesto.cgContext.scaleBy(x: -1, y: 1)
                }
                let s = tinta.size
                let r = min((lato * 0.9) / s.width, (lato * 0.9) / s.height, 1)
                let w = s.width * r, h = s.height * r
                tinta.draw(in: CGRect(x: (lato - w) / 2, y: (lato - h) / 2, width: w, height: h))
            }
        }
    }

    /// Un punto sul cerchio di centro [c] e raggio [r], a [gradi] come la
    /// bussola: 0 in alto, 90 a destra, 180 in basso.
    private static func sulCerchio(_ c: CGPoint, _ r: CGFloat, _ gradi: CGFloat) -> CGPoint {
        let a = gradi * .pi / 180
        return CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
    }

    /// La punta della freccia in [punta], rivolta a [gradi] (come la bussola).
    private static func punta(_ punta: CGPoint, gradi: CGFloat, lato: CGFloat, colore: UIColor) {
        let lunga = lato * 0.22, larga = lato * 0.32
        let base = sulCerchio(punta, lunga, gradi + 180)
        let p = UIBezierPath()
        p.move(to: punta)
        p.addLine(to: sulCerchio(base, larga / 2, gradi - 90))
        p.addLine(to: sulCerchio(base, larga / 2, gradi + 90))
        p.close()
        colore.setFill()
        p.fill()
    }

    private static func tratto(_ p: UIBezierPath, _ lato: CGFloat, _ colore: UIColor, spessore: CGFloat = 0.12) {
        p.lineWidth = lato * spessore
        p.lineCapStyle = .butt
        p.lineJoinStyle = .round
        colore.setStroke()
        p.stroke()
    }

    /// La rotonda come la disegna Mappe: l'anello, l'ingresso dal basso e il
    /// giro fino all'uscita, pieno; il resto dell'anello leggero. Si guida a
    /// destra: si gira in senso antiorario. L'uscita non sa quante strade ha
    /// la rotonda: la prima a destra, la seconda dritto, la terza a
    /// sinistra, dalla quarta quasi indietro; il numero giusto lo dice il
    /// testo («2ª uscita»).
    private static func disegnaRotonda(_ lato: CGFloat, uscita: Int?, colore: UIColor) {
        let c = CGPoint(x: lato * 0.5, y: lato * 0.52)
        let r = lato * 0.16
        let anello = UIBezierPath(arcCenter: c, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        tratto(anello, lato, colore.withAlphaComponent(0.4), spessore: 0.07)
        let n = max(uscita ?? 2, 1)
        let verso: CGFloat
        switch n {
        case 1: verso = 90
        case 2: verso = 0
        case 3: verso = -90
        default: verso = -120
        }
        let giro = UIBezierPath()
        giro.move(to: CGPoint(x: c.x, y: lato * 0.96))
        giro.addLine(to: sulCerchio(c, r, 180))
        // Dal basso (180) a destra (90), in alto (0), a sinistra (-90):
        // sullo schermo è il senso antiorario. Gli angoli di UIKit partono da
        // destra: quello della bussola meno 90.
        giro.addArc(
            withCenter: c,
            radius: r,
            startAngle: (180 - 90) * .pi / 180,
            endAngle: (verso - 90) * .pi / 180,
            clockwise: false
        )
        // Il braccio dell'uscita, che finisce sotto la punta.
        giro.addLine(to: sulCerchio(c, r + lato * 0.1, verso))
        tratto(giro, lato, colore)
        punta(sulCerchio(c, r + lato * 0.28, verso), gradi: verso, lato: lato, colore: colore)
    }

    /// L'inversione a U: si sale, si gira in alto e si torna giù.
    private static func disegnaInversione(_ lato: CGFloat, aSinistra: Bool, colore: UIColor) {
        let s: CGFloat = aSinistra ? 1 : -1
        let da = lato * 0.5 + s * lato * 0.16
        let a = lato * 0.5 - s * lato * 0.16
        let p = UIBezierPath()
        p.move(to: CGPoint(x: da, y: lato * 0.94))
        p.addLine(to: CGPoint(x: da, y: lato * 0.4))
        p.addArc(
            withCenter: CGPoint(x: lato * 0.5, y: lato * 0.4),
            radius: lato * 0.16,
            startAngle: aSinistra ? 0 : .pi,
            endAngle: aSinistra ? .pi : 0,
            clockwise: !aSinistra
        )
        p.addLine(to: CGPoint(x: a, y: lato * 0.6))
        tratto(p, lato, colore)
        punta(CGPoint(x: a, y: lato * 0.84), gradi: 180, lato: lato, colore: colore)
    }

    /// Una svolta di [gradi] (positivi a destra): si sale e si gira.
    private static func disegnaSvolta(_ lato: CGFloat, gradi: CGFloat, colore: UIColor) {
        // Il gambo spostato dal lato opposto, perché la freccia stia al centro.
        let x = lato * 0.5 - (gradi > 0 ? 1 : -1) * lato * 0.2
        let incrocio = CGPoint(x: x, y: lato * 0.3)
        let p = UIBezierPath()
        p.move(to: CGPoint(x: x, y: lato * 0.94))
        p.addLine(to: incrocio)
        p.addLine(to: sulCerchio(incrocio, lato * 0.4, gradi))
        tratto(p, lato, colore)
        punta(sulCerchio(incrocio, lato * 0.58, gradi), gradi: gradi, lato: lato, colore: colore)
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
