import Flutter
import MapLibre
import UIKit

/// La mappa di gdanav sullo schermo di CarPlay: la copia di `RendererMappa.kt`.
/// Stesso stile, stessi dati e stesso segnaposto del telefono. Si sposta col
/// dito o con la manopola (tramite CarPlay): dopo un po' torna da sola
/// sull'auto. Sopra niente: CarPlay vuole la mappa pulita, e la manovra, i
/// tempi e gli avvisi li mostra lui.
final class MappaCarPlay: UIViewController, MLNMapViewDelegate {
    private var mappa: MLNMapView!
    private let pannello = PannelloCarPlay(frame: .zero)
    private var stileCaricato: String?
    private var stilePronto = false
    private var inclinataOra: Bool?
    private var immaginiCaricate = 0
    private var sorgentiCaricate: [String: String] = [:]
    private let preferenze = UserDefaults.standard

    /// Spostata col dito: non segue l'auto finché non si torna.
    private(set) var libera = false

    /// Chiamata quando `libera` cambia, per mostrare «Centra».
    var alCambio: () -> Void = {}

    /// 3D (inclinata, girata come vai) o 2D (dall'alto, nord in su): si ricorda.
    private(set) var tridimensionale: Bool

    /// Lo zoom quando segue l'auto: i tasti + e − lo cambiano.
    private var zoomGuida: Double
    private var zoomFermo: Double

    private var torna: Timer?

    /// L'area non coperta dai tasti e dai pannelli di CarPlay.
    var areaSicura: UIEdgeInsets = .zero {
        didSet {
            pannello.area = areaSicura
            aggiorna()
        }
    }

    /// Nel riquadro del Dashboard di CarPlay: la mappa e basta, senza i
    /// dati sopra — il riquadro è piccolo, e la manovra la scrive CarPlay
    /// accanto.
    let soloMappa: Bool

    init(soloMappa: Bool = false) {
        self.soloMappa = soloMappa
        let p = UserDefaults.standard
        tridimensionale = p.object(forKey: "gdanav.auto_3d") as? Bool ?? true
        zoomGuida = p.object(forKey: "gdanav.auto_zoom_guida") as? Double ?? 16.5
        zoomFermo = p.object(forKey: "gdanav.auto_zoom_fermo") as? Double ?? 15.5
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non si usa") }

    override func loadView() {
        let m = MLNMapView(frame: .zero)
        m.delegate = self
        // Su CarPlay la mappa non si tocca direttamente: la muove il template.
        m.isUserInteractionEnabled = false
        m.automaticallyAdjustsContentInset = false
        m.logoView.isHidden = true
        m.attributionButton.isHidden = true
        m.compassView.isHidden = true
        m.showsScale = false
        m.showsUserLocation = false
        mappa = m
        // Sopra la mappa il pannello coi dati, come su Android Auto.
        let contenitore = UIView(frame: .zero)
        m.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pannello.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contenitore.addSubview(m)
        contenitore.addSubview(pannello)
        view = contenitore
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        aggiorna()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        aggiorna()
    }

    /// CarPlay stringe l'area sicura quando mostra la scheda di guida o i tasti.
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        areaSicura = view.safeAreaInsets
        /* Il percorso rientra subito nell'area libera: aspettare la prossima
         * posizione voleva dire, fermi al semaforo, l'auto sotto la scheda
         * appena aperta (o a lato, se l'area si è stretta). */
        if isViewLoaded, stilePronto, !libera { muovi() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        aggiorna()
    }

    deinit {
        torna?.invalidate()
        collegamento?.invalidate()
        orologio?.invalidate()
    }

    // MARK: - Col dito o con la manopola

    /// Le frecce del pannello di spostamento di CarPlay.
    func sposta(verso: CGPoint) {
        guard isViewLoaded else { return }
        liberaPerUnPo()
        let centro = CGPoint(x: mappa.bounds.midX + verso.x, y: mappa.bounds.midY + verso.y)
        let dove = mappa.convert(centro, toCoordinateFrom: mappa)
        mappa.setCenter(dove, animated: true)
    }

    /// Il dito che trascina sullo schermo (auto col touch).
    func trascina(di spostamento: CGPoint) {
        guard isViewLoaded else { return }
        liberaPerUnPo()
        let centro = CGPoint(x: mappa.bounds.midX - spostamento.x, y: mappa.bounds.midY - spostamento.y)
        mappa.setCenter(mappa.convert(centro, toCoordinateFrom: mappa), animated: false)
    }

    /// I tasti + e −: seguendo l'auto cambiano lo zoom della guida (e si ricorda).
    func zoom(_ passo: Double) {
        guard isViewLoaded else { return }
        if libera {
            liberaPerUnPo()
            mappa.setZoomLevel(mappa.zoomLevel + passo, animated: true)
            return
        }
        if PonteAuto.shared.guida != nil {
            zoomGuida = min(max(zoomGuida + passo, 12), 19)
            preferenze.set(zoomGuida, forKey: "gdanav.auto_zoom_guida")
        } else {
            zoomFermo = min(max(zoomFermo + passo, 8), 19)
            preferenze.set(zoomFermo, forKey: "gdanav.auto_zoom_fermo")
        }
        obiettivo = nil
        aggiorna()
    }

    func alternaVista() {
        tridimensionale.toggle()
        preferenze.set(tridimensionale, forKey: "gdanav.auto_3d")
        segui()
    }

    /// «Centra»: di nuovo sull'auto.
    func segui() {
        torna?.invalidate()
        torna = nil
        if libera {
            libera = false
            alCambio()
        }
        obiettivo = nil
        aggiorna()
    }

    private func liberaPerUnPo() {
        torna?.invalidate()
        torna = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.segui() }
        if !libera {
            libera = true
            fermaAnimazione()
            alCambio()
        }
    }

    // MARK: - I dati dal telefono

    private var scuro: Bool { traitCollection.userInterfaceStyle == .dark }

    /// Chiamata a ogni novità dal telefono.
    func aggiorna() {
        guard isViewLoaded else { return }
        pannello.isHidden = soloMappa || !GdanavCarPlay.pannelliSullaMappa
        pannello.aggiorna()
        let ponte = PonteAuto.shared
        guard let json = (scuro ? ponte.stileScuro : ponte.stileChiaro) ?? ponte.stileChiaro else { return }
        if json != stileCaricato {
            stileCaricato = json
            stilePronto = false
            inclinataOra = nil
            immaginiCaricate = 0
            sorgentiCaricate.removeAll()
            mappa.styleJSON = json
            return
        }
        if stilePronto { aggiornaDati() }
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        stilePronto = true
        caricaSegnaposto(style)
        aggiornaDati()
    }

    private func aggiornaDati() {
        guard let s = mappa.style else { return }
        let ponte = PonteAuto.shared
        // Solo le sorgenti cambiate: rileggere il percorso a ogni novità del
        // cruscotto fa perdere fotogrammi.
        for (id, dati) in ponte.sorgenti where sorgentiCaricate[id] != dati {
            if let sorgente = s.source(withIdentifier: id) as? MLNShapeSource,
               let d = dati.data(using: .utf8)
            {
                sorgente.shape = try? MLNShape(data: d, encoding: String.Encoding.utf8.rawValue)
            }
            sorgentiCaricate[id] = dati
        }
        if ponte.immagini.count != immaginiCaricate {
            immaginiCaricate = ponte.immagini.count
            for (nome, immagine) in ponte.immagini { s.setImage(immagine, forName: nome) }
        }
        let inclinata = ponte.guida != nil && tridimensionale
        if inclinata != inclinataOra {
            inclinataOra = inclinata
            s.layer(withIdentifier: "edifici")?.isVisible = !inclinata
            s.layer(withIdentifier: "edifici-3d")?.isVisible = inclinata
        }
        muovi()
    }

    // MARK: - L'auto che scorre

    /* Dal campo: «la freccia sulla mappa non è fluida, prende pause e poi
     * cammina». A ogni posizione dal telefono si partiva da dov'era la
     * freccia verso la posizione nuova, in un tempo pari all'intervallo di
     * prima, e lì ci si fermava ad aspettare la prossima.
     *
     * Adesso è il conto di `MotoFluido` (gdanav_core, con le sue prove), come
     * su Android Auto (`RendererMappa`): fra una posizione e l'altra l'auto va
     * avanti da sola con la velocità che manda il telefono (`velocita_ms`) e
     * girando come stava girando, al più per un secondo e mezzo; quello che si
     * disegna la insegue a ogni fotogramma, mai indietro lungo la strada; da
     * fermi, arrivata, i fotogrammi si spengono fino alla posizione dopo. */

    /// Latitudine, longitudine, rotta della mappa, rotta del segnaposto, zoom,
    /// inclinazione e i quattro margini: quello che si vede adesso.
    private var mostrata: [Double]?
    /// L'ultima posizione dal telefono, con zoom e margini di adesso.
    private var obiettivo: [Double]?
    /// Quando è arrivata l'ultima posizione, a che velocità (m/s) e quanto si
    /// girava (gradi al secondo).
    private var fixAlle: CFTimeInterval = 0
    private var fixVelocita = 0.0
    private var fixGira = 0.0
    private var ultimoFotogramma: CFTimeInterval = 0
    private var collegamento: CADisplayLink?
    /// Quando lo schermo dell'auto non si sa ancora: vedi [accendiFotogrammi].
    private var orologio: Timer?
    private var eraLibera = false

    /// I numeri di `MotoFluido` (gdanav_core).
    private static let tau = 0.2
    private static let oltreAlPiu = 1.5
    private static let saltoM = 120.0
    private static let fermoSotto = 0.5
    private static let giraAlPiu = 45.0
    private static let metriPerGrado = 111195.08

    /// Quanto si avvicina la mappa arrivando a una svolta, un'uscita, una
    /// rotonda: da 600 metri si comincia, a 150 si è vicini di un livello e
    /// mezzo, e passata la manovra si torna allo zoom di prima. Come su
    /// Android Auto (`RendererMappa.zoomInSvolta`).
    static func zoomInSvolta(_ g: GuidaAuto?) -> Double {
        guard let g else { return 0 }
        guard (9...27).contains(g.tipo) || g.tipo == 37 || g.tipo == 38 else { return 0 }
        let inizio = 600.0, vicino = 150.0
        return 1.5 * min(max((inizio - g.distanzaM) / (inizio - vicino), 0), 1)
    }

    private func muovi() {
        let ponte = PonteAuto.shared
        guard let qui = ponte.qui else {
            fermaAnimazione()
            mostrata = nil
            obiettivo = nil
            (mappa.style?.source(withIdentifier: "gdanav-io") as? MLNShapeSource)?.shape = nil
            return
        }
        let guida = ponte.guida != nil
        let inclinata = guida && tridimensionale
        // L'auto al centro dell'area libera; in guida più in basso, per
        // vedere la strada davanti.
        let a = areaSicura
        let libero = mappa.bounds.height - a.top - a.bottom
        let sopra = guida ? Double(libero) * 0.3 : 0
        let nuovo: [Double] = [
            qui.lat, qui.lon,
            inclinata ? ponte.rotta : 0,
            ponte.rottaIo,
            guida ? zoomGuida + MappaCarPlay.zoomInSvolta(ponte.guida) : zoomFermo,
            inclinata ? 55 : 0,
            Double(a.left), Double(a.top) + sopra, Double(a.right), Double(a.bottom),
        ]
        let ora = CACurrentMediaTime()
        // Tornando a seguire l'auto dopo averla spostata col dito: un volo.
        if eraLibera && !libera {
            eraLibera = false
            fermaAnimazione()
            mostrata = nuovo
            obiettivo = nuovo
            fixAlle = ora
            fixVelocita = 0
            fixGira = 0
            disegna(nuovo, animata: true)
            return
        }
        eraLibera = libera
        let prima = obiettivo
        if let p = prima, p == nuovo { return }
        // Una posizione nuova (non solo zoom o margini, che cambiano di
        // continuo avvicinandosi a una svolta): da qui riparte la previsione.
        if prima == nil || prima![0] != nuovo[0] || prima![1] != nuovo[1] {
            let passo = ora - fixAlle
            let v = ponte.velocita
            if let p = prima, v >= 2, passo >= 0.2, passo <= 3 {
                fixGira = min(max(MappaCarPlay.giro(p[3], nuovo[3]) / passo, -MappaCarPlay.giraAlPiu), MappaCarPlay.giraAlPiu)
            } else if prima == nil || passo > 0.2 {
                fixGira = 0
            }
            fixAlle = ora
            fixVelocita = v.isFinite && v > 0 ? v : 0
        }
        obiettivo = nuovo
        // Troppo lontano (prima volta, salto del GPS, ricalcolo): subito lì.
        guard let da = mostrata, MappaCarPlay.distanzaM(da[0], da[1], nuovo[0], nuovo[1]) <= MappaCarPlay.saltoM else {
            mostrata = nuovo
            disegna(nuovo)
            ultimoFotogramma = ora
            if fixVelocita >= MappaCarPlay.fermoSotto { accendi() }
            return
        }
        accendi()
    }

    private func accendi() {
        if collegamento == nil && orologio == nil {
            ultimoFotogramma = CACurrentMediaTime()
            accendiFotogrammi()
        }
    }

    /* I fotogrammi li da' lo schermo dell'auto, non quello del telefono.
     *
     * «Col telefono sbloccato la posizione va avanti, bloccato resta ferma.»
     * Un `CADisplayLink(target:selector:)` segue lo schermo principale, cioe'
     * quello dell'iPhone: col telefono bloccato quello schermo e' spento e i
     * fotogrammi non arrivano piu'. Le posizioni continuavano ad arrivare, ma
     * il segnaposto restava fermo (e saltava avanti solo dopo un chilometro).
     * Adesso il ritmo e' quello dello schermo dell'auto; se la finestra non
     * c'e' ancora, un orologio a 30 al secondo, che non dipende da nessuno
     * schermo. */
    private func accendiFotogrammi() {
        if let schermo = view.window?.windowScene?.screen ?? view.window?.screen,
           schermo !== UIScreen.main,
           let c = schermo.displayLink(withTarget: self, selector: #selector(fotogramma)) {
            c.add(to: .main, forMode: .common)
            collegamento = c
            return
        }
        let o = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.fotogramma() }
        RunLoop.main.add(o, forMode: .common)
        orologio = o
    }

    /// Dove l'auto dovrebbe essere adesso: l'ultima posizione portata avanti.
    private func previsione(_ o: [Double], _ ora: CFTimeInterval) -> [Double] {
        var v = o
        if fixVelocita < MappaCarPlay.fermoSotto { return v }
        let t = min(max(ora - fixAlle, 0), MappaCarPlay.oltreAlPiu)
        let r0 = o[3] * .pi / 180
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
        v[0] = o[0] + nord / MappaCarPlay.metriPerGrado
        v[1] = o[1] + est / (MappaCarPlay.metriPerGrado * cos(o[0] * .pi / 180))
        v[3] = ((o[3] + fixGira * t).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return v
    }

    @objc private func fotogramma() {
        guard let o = obiettivo, let da = mostrata, da.count == o.count else { return fermaAnimazione() }
        let ora = CACurrentMediaTime()
        // Un fotogramma saltato non diventa un salto: al più un decimo di secondo.
        let dt = min(max(ora - ultimoFotogramma, 0), 0.1)
        ultimoFotogramma = ora
        let p = previsione(o, ora)
        let k = 1 - exp(-dt / MappaCarPlay.tau)
        let coslat = cos(da[0] * .pi / 180)
        var est = (p[1] - da[1]) * MappaCarPlay.metriPerGrado * coslat * k
        var nord = (p[0] - da[0]) * MappaCarPlay.metriPerGrado * k
        if fixVelocita >= MappaCarPlay.fermoSotto {
            // Mai indietro lungo la strada: quella parte del passo si toglie.
            let r = p[3] * .pi / 180
            let lungo = est * sin(r) + nord * cos(r)
            if lungo < 0 {
                est -= lungo * sin(r)
                nord -= lungo * cos(r)
            }
        }
        var v = da
        v[0] = da[0] + nord / MappaCarPlay.metriPerGrado
        v[1] = da[1] + est / (MappaCarPlay.metriPerGrado * coslat)
        var arrivata = MappaCarPlay.distanzaM(v[0], v[1], p[0], p[1]) < 0.3
        for i in 2..<o.count {
            v[i] = (i == 2 || i == 3) ? angolo(da[i], p[i], k) : da[i] + (p[i] - da[i]) * k
            let scarto = (i == 2 || i == 3) ? abs(MappaCarPlay.giro(v[i], p[i])) : abs(v[i] - p[i])
            if scarto > 0.05 { arrivata = false }
        }
        mostrata = v
        disegna(v)
        let ferma = fixVelocita < MappaCarPlay.fermoSotto || ora - fixAlle >= MappaCarPlay.oltreAlPiu
        if arrivata && ferma { fermaAnimazione() }
    }

    private func fermaAnimazione() {
        collegamento?.invalidate()
        collegamento = nil
        orologio?.invalidate()
        orologio = nil
    }

    /// Di quanto si gira da `da` ad `a`, fra -180 e 180.
    private static func giro(_ da: Double, _ a: Double) -> Double {
        ((a - da + 540).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180
    }

    /// Metri fra due punti vicini.
    private static func distanzaM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let nord = (lat2 - lat1) * metriPerGrado
        let est = (lon2 - lon1) * metriPerGrado * cos(lat1 * .pi / 180)
        return (nord * nord + est * est).squareRoot()
    }

    private func disegna(_ v: [Double], animata: Bool = false) {
        guard let s = mappa.style else { return }
        let segnaposto = MLNPointFeature()
        segnaposto.coordinate = CLLocationCoordinate2D(latitude: v[0], longitude: v[1])
        segnaposto.attributes = ["icona": PonteAuto.shared.icona, "rotta": v[3]]
        (s.source(withIdentifier: "gdanav-io") as? MLNShapeSource)?.shape = segnaposto
        guard !libera else { return }
        let margini = UIEdgeInsets(top: v[7], left: v[6], bottom: v[9], right: v[8])
        if mappa.contentInset != margini {
            mappa.setContentInset(margini, animated: false, completionHandler: nil)
        }
        // Prima l'inclinazione, poi centro, zoom e rotta: `setCenter` la lascia com'è.
        if abs(Double(mappa.camera.pitch) - v[5]) > 0.1 {
            let camera = mappa.camera
            camera.pitch = CGFloat(v[5])
            mappa.setCamera(camera, animated: false)
        }
        mappa.setCenter(
            CLLocationCoordinate2D(latitude: v[0], longitude: v[1]),
            zoomLevel: v[4],
            direction: v[2],
            animated: animata
        )
    }

    /// Da un angolo all'altro per la via più corta.
    private func angolo(_ da: Double, _ a: Double, _ t: Double) -> Double {
        var d = (a - da).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return ((da + d * t).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Le immagini del segnaposto, prese dalle risorse dell'app Flutter.
    private func caricaSegnaposto(_ s: MLNStyle) {
        for nome in ["freccia", "auto_blu", "auto_bianca", "auto_rossa", "auto_nera", "auto_grigia"] {
            let chiave = FlutterDartProject.lookupKey(forAsset: "assets/segnaposto/\(nome).png", fromPackage: "gdanav_app")
            guard let percorso = Bundle.main.path(forResource: chiave, ofType: nil),
                  let dati = FileManager.default.contents(atPath: percorso),
                  let immagine = UIImage(data: dati, scale: 3)
            else { continue }
            s.setImage(immagine, forName: nome)
        }
    }
}
