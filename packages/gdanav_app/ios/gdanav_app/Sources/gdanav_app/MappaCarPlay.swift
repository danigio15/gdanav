import Flutter
import MapLibre
import UIKit

/// La mappa di GdANav sullo schermo di CarPlay: la copia di `RendererMappa.kt`.
/// Stesso stile, stessi dati e stesso segnaposto del telefono. Si sposta col
/// dito o con la manopola (tramite CarPlay): dopo un po' torna da sola
/// sull'auto. Sopra niente: CarPlay vuole la mappa pulita, e la manovra, i
/// tempi e gli avvisi li mostra lui.
final class MappaCarPlay: UIViewController, MLNMapViewDelegate {
    private var mappa: MLNMapView!
    private let pannello = PannelloCarPlay(frame: .zero)
    /// Il segnaposto, sopra la mappa: vedi «L'auto che scorre».
    private let freccia = UIImageView(frame: .zero)
    private var immaginiSegnaposto: [String: UIImage] = [:]
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

    /// Lo zoom quando segue l'auto in guida: i tasti + e − lo cambiano.
    private var zoomGuida: Double
    /// Senza percorso lo zoom lo dà la velocità (`MotoCarPlay.zoomLibero`): i
    /// tasti + e − lo spostano di qualche livello. Lo zoom fisso di prima
    /// (`auto_zoom_fermo`, 15,5) non si legge più: teneva la mappa lontana.
    private var scartoLibero: Double

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
        scartoLibero = p.object(forKey: "gdanav.auto_zoom_libero_scarto") as? Double ?? 0
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
        freccia.isUserInteractionEnabled = false
        freccia.isHidden = true
        contenitore.addSubview(m)
        contenitore.addSubview(freccia)
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
            scartoLibero = min(max(scartoLibero + passo, -4), 2)
            preferenze.set(scartoLibero, forKey: "gdanav.auto_zoom_libero_scarto")
        }
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
        aggiorna()
    }

    private func liberaPerUnPo() {
        torna?.invalidate()
        torna = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.segui() }
        if !libera {
            // I fotogrammi continuano: la telecamera resta dov'è il dito, il
            // segnaposto va avanti sulla mappa.
            libera = true
            alCambio()
        }
    }

    /// La mappa spostata (col dito o in volo): il segnaposto la segue.
    func mapViewRegionIsChanging(_ mapView: MLNMapView) {
        if libera || inVolo { mettiFreccia() }
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
        // In 3D anche senza percorso, come su Android Auto: la vista scelta è una.
        let inclinata = tridimensionale
        if inclinata != inclinataOra {
            inclinataOra = inclinata
            s.layer(withIdentifier: "edifici")?.isVisible = !inclinata
            s.layer(withIdentifier: "edifici-3d")?.isVisible = inclinata
        }
        muovi()
    }

    // MARK: - L'auto che scorre

    /* Dal campo, due volte: «la freccia sulla mappa non è fluida, prende pause
     * e poi cammina», e poi «ha ancora dei piccoli frame lag, deve essere
     * continuo con il movimento dell'auto».
     *
     * Il conto è quello di `MotoFluido` (gdanav_core, con le sue prove), in
     * `MotoCarPlay`: fra una posizione e l'altra l'auto va avanti da sola, e la
     * freccia ha una velocità sua che cambia piano: andando non si ferma più a
     * ogni posizione un poco indietro (le piccole pause), e non torna indietro.
     *
     * Il segnaposto non è più un punto della sorgente `gdanav-io` riscritto a
     * ogni fotogramma: MapLibre lo rilegge per conto suo e lo mostra qualche
     * fotogramma dopo la telecamera, e seguendo l'auto la freccia ballava
     * avanti e indietro. Adesso è un'immagine sopra la mappa (`freccia`), dove
     * la telecamera mette l'auto; schiacciata come la mappa inclinata. */

    private let moto = MotoCarPlay()

    /// La telecamera che si vuole (dall'ultima novità) e quella che si vede.
    private var zoomVoluto = 16.5
    private var inclinazioneVoluta = 0.0
    private var bussolaInclinata = false
    private var marginiVoluti = UIEdgeInsets.zero
    private var zoomMostrato = 16.5
    private var inclinazioneMostrata = 0.0
    private var bussolaMostrata = 0.0
    private var marginiMostrati = UIEdgeInsets.zero
    private var cameraPronta = false

    private var ultimoFotogramma: CFTimeInterval = 0
    private var collegamento: CADisplayLink?
    /// Quando lo schermo dell'auto non si sa ancora: vedi [accendiFotogrammi].
    private var orologio: Timer?
    private var eraLibera = false
    private var inVolo = false

    private static let inclinazione = 55.0
    private static let tauZoom = 0.8
    private static let tauCamera = 0.3

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

    /// Una novità dal telefono: la posizione, e la telecamera che si vuole.
    private func muovi() {
        let ponte = PonteAuto.shared
        guard let qui = ponte.qui else {
            fermaAnimazione()
            moto.dimentica()
            freccia.isHidden = true
            return
        }
        let guida = ponte.guida != nil
        let inclinata = tridimensionale
        let a = areaSicura
        let libero = Double(mappa.bounds.height - a.top - a.bottom)
        /* Senza percorso, come in guida: vicina, in 3D, con l'auto più in
         * basso. Prima era a 15,5 col nord in su e l'auto in mezzo. */
        let sopra: Double
        if guida {
            zoomVoluto = zoomGuida + MappaCarPlay.zoomInSvolta(ponte.guida)
            sopra = 0.3
        } else {
            zoomVoluto = MotoCarPlay.zoomLibero(velocita: ponte.velocita, scarto: scartoLibero)
            sopra = inclinata ? 0.3 : 0
        }
        inclinazioneVoluta = inclinata ? MappaCarPlay.inclinazione : 0
        bussolaInclinata = inclinata
        marginiVoluti = UIEdgeInsets(top: a.top + CGFloat(libero * sopra), left: a.left, bottom: a.bottom, right: a.right)
        let ora = CACurrentMediaTime()
        if !moto.stessaPosizione(qui.lat, qui.lon) {
            moto.posizione(lat: qui.lat, lon: qui.lon, rotta: ponte.rottaIo, rottaMappa: ponte.rotta, velocita: ponte.velocita, alle: ora)
        }
        // Tornando a seguire l'auto dopo averla spostata col dito: un volo.
        if eraLibera && !libera {
            eraLibera = false
            moto.salta(ora + 0.7)
            prendiVoluta()
            inVolo = true
            disegna(animata: true)
            accendi()
            return
        }
        eraLibera = libera
        accendi()
    }

    private func accendi() {
        if collegamento == nil && orologio == nil {
            ultimoFotogramma = 0
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
            // Al più trenta al secondo: di più scalda e basta.
            c.preferredFramesPerSecond = 30
            c.add(to: .main, forMode: .common)
            collegamento = c
            return
        }
        let o = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.fotogramma() }
        RunLoop.main.add(o, forMode: .common)
        orologio = o
    }

    /// La telecamera mostrata diventa subito quella voluta.
    private func prendiVoluta() {
        zoomMostrato = zoomVoluto
        inclinazioneMostrata = inclinazioneVoluta
        bussolaMostrata = bussolaInclinata ? moto.rottaMappa : 0
        marginiMostrati = marginiVoluti
        cameraPronta = true
    }

    @objc private func fotogramma() {
        // L'ora del fotogramma che si sta preparando, se lo schermo la dice.
        let ora = collegamento?.targetTimestamp ?? CACurrentMediaTime()
        let dt = ultimoFotogramma == 0 ? 0 : min(max(ora - ultimoFotogramma, 0), MotoCarPlay.fotogrammaAlPiu)
        ultimoFotogramma = ora
        let primo = !moto.mostrata
        guard moto.fotogramma(ora) else { return fermaAnimazione() }
        if primo || !cameraPronta {
            prendiVoluta()
        } else {
            let kz = 1 - exp(-dt / MappaCarPlay.tauZoom)
            let kc = 1 - exp(-dt / MappaCarPlay.tauCamera)
            zoomMostrato += (zoomVoluto - zoomMostrato) * kz
            inclinazioneMostrata += (inclinazioneVoluta - inclinazioneMostrata) * kc
            let c = CGFloat(kc)
            marginiMostrati = UIEdgeInsets(
                top: marginiMostrati.top + (marginiVoluti.top - marginiMostrati.top) * c,
                left: marginiMostrati.left + (marginiVoluti.left - marginiMostrati.left) * c,
                bottom: marginiMostrati.bottom + (marginiVoluti.bottom - marginiMostrati.bottom) * c,
                right: marginiMostrati.right + (marginiVoluti.right - marginiMostrati.right) * c
            )
            bussolaMostrata = MotoCarPlay.verso(bussolaMostrata, bussolaInclinata ? moto.rottaMappa : 0, kc)
        }
        disegna()
        if moto.fermo && cameraArrivata() && !inVolo { fermaAnimazione() }
    }

    private func cameraArrivata() -> Bool {
        if abs(zoomVoluto - zoomMostrato) > 0.01 || abs(inclinazioneVoluta - inclinazioneMostrata) > 0.1 { return false }
        let m = marginiVoluti, n = marginiMostrati
        if abs(m.top - n.top) > 0.5 || abs(m.left - n.left) > 0.5 || abs(m.bottom - n.bottom) > 0.5 || abs(m.right - n.right) > 0.5 {
            return false
        }
        return abs(MotoCarPlay.giro(bussolaMostrata, bussolaInclinata ? moto.rottaMappa : 0)) < 0.1
    }

    private func fermaAnimazione() {
        collegamento?.invalidate()
        collegamento = nil
        orologio?.invalidate()
        orologio = nil
    }

    private func disegna(animata: Bool = false) {
        guard mappa.style != nil, moto.mostrata else { return }
        if !libera && (!inVolo || animata) {
            let margini = marginiMostrati
            if mappa.contentInset != margini {
                mappa.setContentInset(margini, animated: false, completionHandler: nil)
            }
            // Prima l'inclinazione, poi centro, zoom e rotta: `setCenter` la lascia com'è.
            if abs(Double(mappa.camera.pitch) - inclinazioneMostrata) > 0.1 {
                let camera = mappa.camera
                camera.pitch = CGFloat(inclinazioneMostrata)
                mappa.setCamera(camera, animated: false)
            }
            let centro = CLLocationCoordinate2D(latitude: moto.lat, longitude: moto.lon)
            if animata {
                mappa.setCenter(centro, zoomLevel: zoomMostrato, direction: bussolaMostrata, animated: true) { [weak self] in
                    self?.inVolo = false
                }
            } else {
                mappa.setCenter(centro, zoomLevel: zoomMostrato, direction: bussolaMostrata, animated: false)
            }
        }
        mettiFreccia()
    }

    /// Il segnaposto dove la mappa mette l'auto.
    private func mettiFreccia() {
        guard moto.mostrata, let immagine = immaginiSegnaposto[PonteAuto.shared.icona] ?? immaginiSegnaposto["freccia"] else {
            freccia.isHidden = true
            return
        }
        let punto: CGPoint
        let bussola: Double, zoom: Double, inclinazione: Double
        if !libera && !inVolo {
            // Seguendo l'auto, la telecamera la mette nel mezzo dell'area dentro i margini.
            let m = marginiMostrati
            let b = mappa.bounds
            punto = CGPoint(x: m.left + (b.width - m.left - m.right) / 2, y: m.top + (b.height - m.top - m.bottom) / 2)
            bussola = bussolaMostrata
            zoom = zoomMostrato
            inclinazione = inclinazioneMostrata
        } else {
            punto = mappa.convert(CLLocationCoordinate2D(latitude: moto.lat, longitude: moto.lon), toPointTo: mappa)
            bussola = mappa.direction
            zoom = mappa.zoomLevel
            inclinazione = Double(mappa.camera.pitch)
        }
        if freccia.image !== immagine {
            freccia.image = immagine
            freccia.bounds = CGRect(origin: .zero, size: immagine.size)
        }
        let scala = CGFloat(MotoCarPlay.dimensioneIcona(zoom))
        let angolo = CGFloat(MotoCarPlay.giro(bussola, moto.rotta) * .pi / 180)
        freccia.transform = CGAffineTransform(scaleX: scala, y: scala)
            .concatenating(CGAffineTransform(rotationAngle: angolo))
            .concatenating(CGAffineTransform(scaleX: 1, y: CGFloat(cos(inclinazione * .pi / 180))))
        freccia.center = punto
        freccia.isHidden = false
    }

    /// Le immagini del segnaposto, prese dalle risorse dell'app Flutter.
    private func caricaSegnaposto(_ s: MLNStyle) {
        // Il segnaposto lo disegna `freccia`, sopra la mappa: la sorgente resta vuota.
        (s.source(withIdentifier: "gdanav-io") as? MLNShapeSource)?.shape = nil
        guard immaginiSegnaposto.isEmpty else { return }
        for nome in ["freccia", "auto_blu", "auto_bianca", "auto_rossa", "auto_nera", "auto_grigia"] {
            let chiave = FlutterDartProject.lookupKey(forAsset: "assets/segnaposto/\(nome).png", fromPackage: "gdanav_app")
            guard let percorso = Bundle.main.path(forResource: chiave, ofType: nil),
                  let dati = FileManager.default.contents(atPath: percorso),
                  let immagine = UIImage(data: dati, scale: 3)
            else { continue }
            immaginiSegnaposto[nome] = immagine
        }
    }
}
