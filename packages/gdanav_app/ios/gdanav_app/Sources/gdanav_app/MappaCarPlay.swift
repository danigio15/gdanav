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
        didSet { aggiorna() }
    }

    init() {
        tridimensionale = preferenze.object(forKey: "gdanav.auto_3d") as? Bool ?? true
        zoomGuida = preferenze.object(forKey: "gdanav.auto_zoom_guida") as? Double ?? 16.5
        zoomFermo = preferenze.object(forKey: "gdanav.auto_zoom_fermo") as? Double ?? 15.5
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
        view = m
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
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        aggiorna()
    }

    deinit {
        torna?.invalidate()
        collegamento?.invalidate()
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

    /// Latitudine, longitudine, rotta della mappa, rotta del segnaposto, zoom,
    /// inclinazione e i quattro margini. Fra una posizione e l'altra (dal
    /// telefono ogni 300 ms circa) segnaposto e mappa scorrono a ogni
    /// fotogramma, invece di saltare.
    private var mostrata: [Double]?
    private var obiettivo: [Double]?
    private var partenza: [Double] = []
    private var inizio: CFTimeInterval = 0
    private var durata: CFTimeInterval = 0
    private var collegamento: CADisplayLink?
    private var ultimaPosizione: CFTimeInterval = 0
    private var eraLibera = false

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
            guida ? zoomGuida : zoomFermo,
            inclinata ? 55 : 0,
            Double(a.left), Double(a.top) + sopra, Double(a.right), Double(a.bottom),
        ]
        // Tornando a seguire l'auto dopo averla spostata col dito: un volo.
        if eraLibera && !libera {
            eraLibera = false
            fermaAnimazione()
            mostrata = nuovo
            obiettivo = nuovo
            disegna(nuovo, animata: true)
            return
        }
        eraLibera = libera
        let prima = obiettivo
        if let p = prima, p == nuovo { return }
        obiettivo = nuovo
        let ora = CACurrentMediaTime()
        let spostata = prima == nil || prima![0] != nuovo[0] || prima![1] != nuovo[1]
        let passo = ora - ultimaPosizione
        if spostata { ultimaPosizione = ora }
        // Troppo lontano (prima volta, salto del GPS): subito lì.
        guard let da = mostrata, abs(da[0] - nuovo[0]) <= 0.01, abs(da[1] - nuovo[1]) <= 0.01 else {
            fermaAnimazione()
            mostrata = nuovo
            disegna(nuovo)
            return
        }
        // Dura quanto l'intervallo fra due posizioni: si arriva quando arriva
        // la prossima, e il moto resta continuo.
        partenza = da
        inizio = ora
        durata = spostata ? min(max(passo, 0.25), 1.1) : 0.45
        if collegamento == nil {
            let c = CADisplayLink(target: self, selector: #selector(fotogramma))
            c.add(to: .main, forMode: .common)
            collegamento = c
        }
    }

    @objc private func fotogramma() {
        guard let arrivo = obiettivo, partenza.count == arrivo.count else { return fermaAnimazione() }
        let t = min((CACurrentMediaTime() - inizio) / max(durata, 0.001), 1)
        var v = arrivo
        for i in 0..<arrivo.count {
            v[i] = (i == 2 || i == 3) ? angolo(partenza[i], arrivo[i], t) : partenza[i] + (arrivo[i] - partenza[i]) * t
        }
        mostrata = v
        disegna(v)
        if t >= 1 { fermaAnimazione() }
    }

    private func fermaAnimazione() {
        collegamento?.invalidate()
        collegamento = nil
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
