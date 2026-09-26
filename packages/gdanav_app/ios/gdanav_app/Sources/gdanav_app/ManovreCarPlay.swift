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

    /// «600 m», «1,2 km»: come le distanze sul telefono.
    static func distanza(_ metri: Double) -> Measurement<UnitLength> {
        if metri >= 1000 {
            return Measurement(value: (metri / 100).rounded() / 10, unit: .kilometers)
        }
        let passo: Double = metri > 300 ? 50 : 10
        return Measurement(value: (metri / passo).rounded() * passo, unit: .meters)
    }
}
