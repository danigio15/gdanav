import CarPlay
import MapKit
import UIKit

/// gdanav su CarPlay: la scena di un'app di navigazione, come la sessione di
/// Android Auto (`SessioneGdanav.kt` e `SchermoNavigazione.kt`).
///
/// Sotto la mappa di gdanav; sopra la scheda della manovra, i tempi e gli
/// avvisi, disegnati da CarPlay. In alto Cerca e Menu (in guida anche Fine); a
/// lato +, −, 2D/3D o Centra, e sposta.
///
/// Chi porta gdanav dentro la mette nell'Info.plist come delegato della scena
/// `CPTemplateApplicationSceneSessionRoleApplication`, col nome
/// `GdanavCarPlay`. Il motore Flutter lo accende l'app all'avvio: CarPlay può
/// aprirla senza la schermata del telefono.
@objc(GdanavCarPlay)
public final class GdanavCarPlay: UIResponder, CPTemplateApplicationSceneDelegate, CPMapTemplateDelegate {
    /// Lo schermo della casa, se chi ospita gdanav ne ha uno (gdahome): un
    /// tasto in alto sulla mappa, e sull'avviso del Premium.
    public static var casa: ((CPInterfaceController) -> CPTemplate)?

    /// La scena di CarPlay aperta adesso, per chi deve mostrare qualcosa.
    public private(set) static weak var attuale: GdanavCarPlay?

    /// Chiamata quando CarPlay si collega (`true`) o si scollega (`false`):
    /// gdahome ci accende gdanav anche se la sua sezione non si è mai aperta.
    public static var alCollegamento: ((Bool) -> Void)?

    /// Se CarPlay è collegato adesso.
    public static var collegato: Bool { attuale != nil }

    /// Dove si è, come lo sa gdanav.
    public static var posizione: CLLocationCoordinate2D? {
        PonteAuto.shared.qui.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Dov'è Casa, fra i luoghi di gdanav.
    public static var casaSalvata: CLLocationCoordinate2D? {
        PonteAuto.shared.casa().map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Un messaggio breve sopra la mappa, come i toast di Android Auto.
    public static func mostra(_ testo: String) {
        attuale?.avvisa(testo)
    }

    /// Una proposta sopra la mappa con due tasti («Quasi a casa: Fallo / Non ora»).
    public static func proponi(
        _ titolo: String,
        sotto: String,
        immagine: UIImage?,
        si: String,
        no: String,
        azione: @escaping () -> Void
    ) {
        guard let t = attuale?.modello else { return }
        let alert = CPNavigationAlert(
            titleVariants: [titolo],
            subtitleVariants: [sotto],
            image: immagine,
            primaryAction: CPAlertAction(title: si, style: .default) { _ in azione() },
            secondaryAction: CPAlertAction(title: no, style: .cancel) { _ in },
            duration: 15
        )
        if t.currentNavigationAlert != nil {
            t.dismissNavigationAlert(animated: false) { _ in t.present(navigationAlert: alert, animated: true) }
        } else {
            t.present(navigationAlert: alert, animated: true)
        }
    }

    private var controllore: CPInterfaceController?
    private var finestra: CPWindow?
    private var mappa: MappaCarPlay?
    private var modello: CPMapTemplate?
    private var sessione: CPNavigationSession?
    private var viaggio: CPTrip?
    private var ascolto: UUID?
    private var versione = -1
    private var chiaveManovra: String?
    private var manovre: [CPManeuver] = []
    private var messaggioMostrato: String?
    private var premiumMostrato = false
    private var spostamentoPrima: CGPoint = .zero
    private var cruscottoMostrato: String?
    private var sostaAvvisata: String?

    // MARK: - La scena

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        GdanavCarPlay.attuale = self
        controllore = interfaceController
        finestra = window
        let m = MappaCarPlay()
        m.alCambio = { [weak self] in self?.aggiornaTasti() }
        window.rootViewController = m
        mappa = m

        let t = CPMapTemplate()
        t.mapDelegate = self
        t.automaticallyHidesNavigationBar = false
        // La scheda di guida col blu di gdanav: la freccia è bianca.
        t.guidanceBackgroundColor = UIColor(red: 0.08, green: 0.36, blue: 0.75, alpha: 1)
        t.tripEstimateStyle = .dark
        modello = t
        interfaceController.setRootTemplate(t, animated: false, completion: nil)

        ascolto = PonteAuto.shared.ascolta { [weak self] in self?.novita() }
        novita()
        GdanavCarPlay.alCollegamento?(true)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        if let a = ascolto { PonteAuto.shared.smetti(a) }
        ascolto = nil
        sessione?.finishTrip()
        sessione = nil
        viaggio = nil
        manovre = []
        chiaveManovra = nil
        window.rootViewController = nil
        mappa = nil
        modello = nil
        controllore = nil
        finestra = nil
        if GdanavCarPlay.attuale === self { GdanavCarPlay.attuale = nil }
        GdanavCarPlay.alCollegamento?(false)
    }

    // MARK: - Le novità dal telefono

    private func novita() {
        guard let m = mappa else { return }
        m.aggiorna()
        sincronizzaGuida()
        mostraAvviso()
        avvisaLaSosta()
        // Il tasto coi dati dell'auto cambia con la batteria e i km, che non
        // toccano il resto dei tasti.
        if SchermiCarPlay.testoCruscotto() != cruscottoMostrato { aggiornaTasti() }
        // I tasti si rifanno solo se cambia qualcosa che mostrano.
        if PonteAuto.shared.versioneModello != versione {
            versione = PonteAuto.shared.versioneModello
            aggiornaTasti()
            mostraMessaggio()
            controllaPremium()
        }
    }

    // MARK: - I tasti

    private func tasto(_ simbolo: String, _ azione: @escaping () -> Void) -> CPBarButton {
        CPBarButton(image: UIImage(systemName: simbolo) ?? UIImage()) { _ in azione() }
    }

    private func tasto(titolo: String, _ azione: @escaping () -> Void) -> CPBarButton {
        CPBarButton(title: titolo) { _ in azione() }
    }

    private func tastoMappa(_ simbolo: String, _ azione: @escaping () -> Void) -> CPMapButton {
        let b = CPMapButton { _ in azione() }
        b.image = UIImage(systemName: simbolo, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        return b
    }

    /// In alto: Cerca, la casa (dentro gdahome) e Menu (in guida anche Fine);
    /// appena passata una segnalazione, «C'è ancora?» Sì / No arriva come avviso.
    private func aggiornaTasti() {
        guard let t = modello, let m = mappa else { return }
        let ponte = PonteAuto.shared
        // A sinistra i dati dell'auto (quelli che Android Auto disegna sulla
        // mappa: CarPlay vuole la mappa pulita, e li tiene in un tasto che
        // apre il viaggio) e la lente. A destra la casa (dentro gdahome) e il
        // Menu; in guida Menu e Fine, e la casa passa nel Menu.
        var sinistra: [CPBarButton] = []
        cruscottoMostrato = SchermiCarPlay.testoCruscotto()
        if let dati = cruscottoMostrato {
            sinistra.append(tasto(titolo: dati) { [weak self] in self?.apriViaggio() })
        }
        sinistra.append(tasto("magnifyingglass") { [weak self] in self?.apriCerca() })
        var destra: [CPBarButton] = []
        if ponte.guida != nil {
            destra = [
                tasto(titolo: "Menu") { [weak self] in self?.apriMenu() },
                tasto(titolo: "Fine") { [weak self] in self?.fine() },
            ]
        } else {
            if GdanavCarPlay.casa != nil {
                destra.append(tasto("house.fill") { [weak self] in self?.apriCasa() })
            }
            destra.append(tasto(titolo: "Menu") { [weak self] in self?.apriMenu() })
        }
        t.leadingNavigationBarButtons = sinistra
        t.trailingNavigationBarButtons = destra
        // A lato della mappa: + e −, 2D/3D (o Centra se la si è spostata), sposta.
        let vista: CPMapButton
        if m.libera {
            vista = tastoMappa("location.fill") { [weak m] in m?.segui() }
        } else {
            vista = tastoMappa(m.tridimensionale ? "view.2d" : "view.3d") { [weak self, weak m] in
                m?.alternaVista()
                self?.aggiornaTasti()
            }
        }
        t.mapButtons = [
            tastoMappa("plus") { [weak m] in m?.zoom(1) },
            tastoMappa("minus") { [weak m] in m?.zoom(-1) },
            vista,
            tastoMappa("arrow.up.and.down.and.arrow.left.and.right") { [weak t] in
                t?.showPanningInterface(animated: true)
            },
        ]
    }

    private func fine() {
        PonteAuto.shared.fermaDallAuto()
    }

    private func apriCerca() {
        guard let c = controllore else { return }
        c.pushTemplate(SchermiCarPlay.cerca(c), animated: true, completion: nil)
    }

    private func apriMenu() {
        guard let c = controllore, let m = mappa else { return }
        c.pushTemplate(SchermiCarPlay.menu(c, mappa: m), animated: true, completion: nil)
    }

    private func apriViaggio() {
        guard let c = controllore else { return }
        c.pushTemplate(SchermiCarPlay.viaggio(), animated: true, completion: nil)
    }

    private func apriCasa() {
        guard let c = controllore, let casa = GdanavCarPlay.casa else { return }
        c.pushTemplate(casa(c), animated: true, completion: nil)
    }

    // MARK: - Premium

    /// Senza gdanav Premium la mappa c'è, ma la navigazione no: si dice come
    /// sbloccarlo dal telefono. Appena l'app lo sblocca, l'avviso se ne va.
    private func controllaPremium() {
        // Finché l'app non ha parlato (niente stile) non si sa ancora niente.
        guard let c = controllore, PonteAuto.shared.stileChiaro != nil else { return }
        let premium = PonteAuto.shared.premium
        if premium && premiumMostrato {
            premiumMostrato = false
            c.dismissTemplate(animated: true, completion: nil)
        } else if !premium && !premiumMostrato {
            premiumMostrato = true
            var azioni = [
                CPAlertAction(title: "Ho sbloccato", style: .default) { [weak self] _ in
                    guard let self else { return }
                    if PonteAuto.shared.premium {
                        self.premiumMostrato = false
                        self.controllore?.dismissTemplate(animated: true, completion: nil)
                    }
                },
            ]
            // Dentro gdahome la casa non è Premium: ci si arriva anche da qui.
            if GdanavCarPlay.casa != nil {
                azioni.append(CPAlertAction(title: "Casa", style: .default) { [weak self] _ in
                    guard let self else { return }
                    self.premiumMostrato = false
                    self.controllore?.dismissTemplate(animated: true) { _, _ in self.apriCasa() }
                })
            }
            let avviso = CPAlertTemplate(
                titleVariants: [
                    "La navigazione in auto fa parte di gdanav Premium. Sbloccalo dall'app sul telefono: menu → Premium.",
                    "gdanav Premium: sbloccalo dal telefono.",
                ],
                actions: azioni
            )
            c.presentTemplate(avviso, animated: true, completion: nil)
        }
    }

    // MARK: - La guida

    /// CarPlay vuole sapere quando si naviga, per le altre app e Siri; e la
    /// manovra, i tempi e le corsie li disegna lui.
    private func sincronizzaGuida() {
        guard let t = modello else { return }
        let ponte = PonteAuto.shared
        guard let g = ponte.guida, ponte.premium else {
            if let s = sessione {
                s.finishTrip()
                sessione = nil
                viaggio = nil
                manovre = []
                chiaveManovra = nil
            }
            return
        }
        if sessione == nil {
            let partenza = ponte.qui.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
                ?? CLLocationCoordinate2D(latitude: g.destinazioneLat ?? 0, longitude: g.destinazioneLon ?? 0)
            let arrivo = CLLocationCoordinate2D(
                latitude: g.destinazioneLat ?? partenza.latitude,
                longitude: g.destinazioneLon ?? partenza.longitude
            )
            let da = MKMapItem(placemark: MKPlacemark(coordinate: partenza))
            let a = MKMapItem(placemark: MKPlacemark(coordinate: arrivo))
            a.name = g.destinazione
            var riepilogo = [g.destinazione]
            if let b = g.arrivoBatteria { riepilogo.insert("Arrivi con il \(Int(b.rounded()))%", at: 0) }
            let scelta = CPRouteChoice(
                summaryVariants: riepilogo,
                additionalInformationVariants: [],
                selectionSummaryVariants: []
            )
            let v = CPTrip(origin: da, destination: a, routeChoices: [scelta])
            viaggio = v
            sessione = t.startNavigationSession(for: v)
        }
        guard let s = sessione, let v = viaggio else { return }
        // Una manovra nuova si dà solo quando cambia: aggiornarla a ogni metro
        // fa sfarfallare la scheda. La distanza si aggiorna a parte.
        let chiave = "\(g.tipo)|\(g.istruzione)|\(g.strada)|\(g.svincolo ?? -1)|\(g.corsie.count)|\(g.dopoTipo ?? -1)|\(g.dopoStrada)"
        if chiave != chiaveManovra {
            chiaveManovra = chiave
            manovre = manovreDa(g)
            s.upcomingManeuvers = manovre
        }
        if let prima = manovre.first {
            s.updateEstimates(
                CPTravelEstimates(distanceRemaining: ManovreCarPlay.distanza(g.distanzaM), timeRemaining: 0),
                for: prima
            )
        }
        t.update(
            CPTravelEstimates(
                distanceRemaining: ManovreCarPlay.distanza(g.restantiM),
                timeRemaining: g.restantiS
            ),
            for: v,
            with: .default
        )
    }

    private func manovreDa(_ g: GuidaAuto) -> [CPManeuver] {
        let ponte = PonteAuto.shared
        let m = CPManeuver()
        // Lo stesso testo della scheda di Android Auto; CarPlay sceglie la
        // variante che ci sta, dalla più lunga.
        let testo = ManovreCarPlay.testo(g)
        var righe = [testo]
        if !g.strada.isEmpty && g.strada != testo { righe.append(g.strada) }
        if !g.istruzione.isEmpty && !righe.contains(g.istruzione) { righe.append(g.istruzione) }
        m.instructionVariants = righe
        m.symbolImage = ManovreCarPlay.immagine(g.tipo)
        m.initialTravelEstimates = CPTravelEstimates(
            distanceRemaining: ManovreCarPlay.distanza(g.distanzaM),
            timeRemaining: 0
        )
        // La vista dello svincolo, o le corsie da tenere.
        if let id = g.svincolo, let vista = ponte.svincoli[id] {
            // Col cartello verde dell'uscita, come su Android Auto.
            m.junctionImage = ManovreCarPlay.dentro(ManovreCarPlay.svincoloConCartello(vista, g), CGSize(width: 140, height: 100))
        } else if let strisce = ManovreCarPlay.corsie(g.corsie) {
            m.junctionImage = ManovreCarPlay.dentro(strisce, CGSize(width: 140, height: 100))
        }
        guard let dopo = g.dopoTipo else { return [m] }
        let poi = CPManeuver()
        poi.instructionVariants = g.dopoStrada.isEmpty ? ["Poi"] : ["Poi \(g.dopoStrada)"]
        poi.symbolImage = ManovreCarPlay.immagine(dopo)
        return [m, poi]
    }

    // MARK: - Avvisi e messaggi

    /// Una segnalazione davanti, o «C'è ancora?» dopo averla passata: un
    /// avviso di navigazione, come quelli di Mappe.
    private func mostraAvviso() {
        guard let t = modello, let a = PonteAuto.shared.prendiAvvisoNuovo() else { return }
        let immagine = a.tipo.flatMap { PonteAuto.shared.immagini["segnala-\($0)"] }
        let alert: CPNavigationAlert
        if let id = a.ancoraId {
            alert = CPNavigationAlert(
                titleVariants: [a.ancoraTesto ?? "C'è ancora?"],
                subtitleVariants: [],
                image: immagine,
                primaryAction: CPAlertAction(title: "Sì", style: .default) { _ in PonteAuto.shared.ancora(id, si: true) },
                secondaryAction: CPAlertAction(title: "No", style: .cancel) { _ in PonteAuto.shared.ancora(id, si: false) },
                duration: 10
            )
        } else {
            var sotto: [String] = []
            if let metri = a.metri {
                let d = ManovreCarPlay.distanza(metri)
                sotto.append("Fra \(Int(d.value)) \(d.unit == .kilometers ? "km" : "m")")
            }
            if let l = a.limite { sotto.append("Limite \(l) km/h") }
            alert = CPNavigationAlert(
                titleVariants: [a.titolo ?? "Attenzione"],
                subtitleVariants: [sotto.joined(separator: " · ")],
                image: immagine,
                primaryAction: CPAlertAction(title: "OK", style: .cancel) { _ in },
                secondaryAction: nil,
                duration: 8
            )
        }
        if t.currentNavigationAlert != nil {
            t.dismissNavigationAlert(animated: false) { _ in t.present(navigationAlert: alert, animated: true) }
        } else {
            t.present(navigationAlert: alert, animated: true)
        }
    }

    /// La prossima sosta di ricarica, avvicinandosi (a 15 km): quello che su
    /// Android Auto sta nella riga «⚡ Area 180 · 176 km · arrivi col 21%».
    private func avvisaLaSosta() {
        let c = PonteAuto.shared.cruscotto
        guard PonteAuto.shared.guida != nil, let nome = c.sostaNome, let km = c.sostaKm else { return }
        guard km <= 15, sostaAvvisata != nome, let t = modello else { return }
        sostaAvvisata = nome
        var sotto = ["tra \(Int(km.rounded())) km"]
        if let b = c.sostaBatteria { sotto.append("arrivi col \(Int(b.rounded()))%") }
        let alert = CPNavigationAlert(
            titleVariants: ["Prossima sosta: \(nome)", "Sosta: \(nome)"],
            subtitleVariants: [sotto.joined(separator: " · ")],
            image: UIImage(systemName: "bolt.car.fill")?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal),
            primaryAction: CPAlertAction(title: "OK", style: .cancel) { _ in },
            secondaryAction: nil,
            duration: 10
        )
        if t.currentNavigationAlert != nil {
            t.dismissNavigationAlert(animated: false) { _ in t.present(navigationAlert: alert, animated: true) }
        } else {
            t.present(navigationAlert: alert, animated: true)
        }
    }

    /// «Calcolo il percorso…» o cosa non va, da fermi: un avviso breve.
    private func mostraMessaggio() {
        let testo = PonteAuto.shared.guida == nil ? PonteAuto.shared.messaggio : nil
        guard testo != messaggioMostrato else { return }
        messaggioMostrato = testo
        guard let t = modello, let testo, !testo.isEmpty else { return }
        mostra(testo, in: t)
    }

    /// Un messaggio che sparisce da solo, come i toast di Android Auto.
    func avvisa(_ testo: String) {
        guard let t = modello else { return }
        controllore?.popToRootTemplate(animated: true) { _, _ in self.mostra(testo, in: t) }
    }

    private func mostra(_ testo: String, in t: CPMapTemplate) {
        let alert = CPNavigationAlert(
            titleVariants: [testo],
            subtitleVariants: [],
            image: nil,
            primaryAction: CPAlertAction(title: "OK", style: .cancel) { _ in },
            secondaryAction: nil,
            duration: 5
        )
        if t.currentNavigationAlert != nil {
            t.dismissNavigationAlert(animated: false) { _ in t.present(navigationAlert: alert, animated: true) }
        } else {
            t.present(navigationAlert: alert, animated: true)
        }
    }

    // MARK: - Spostare la mappa

    public func mapTemplate(_ mapTemplate: CPMapTemplate, panWith direction: CPMapTemplate.PanDirection) {
        let passo: CGFloat = 120
        var verso = CGPoint.zero
        if direction.contains(.left) { verso.x -= passo }
        if direction.contains(.right) { verso.x += passo }
        if direction.contains(.up) { verso.y -= passo }
        if direction.contains(.down) { verso.y += passo }
        mappa?.sposta(verso: verso)
    }

    public func mapTemplateDidBeginPanGesture(_ mapTemplate: CPMapTemplate) {
        spostamentoPrima = .zero
    }

    public func mapTemplate(
        _ mapTemplate: CPMapTemplate,
        didUpdatePanGestureWithTranslation translation: CGPoint,
        velocity: CGPoint
    ) {
        // CarPlay dà lo spostamento dall'inizio del gesto: si muove della differenza.
        let delta = CGPoint(x: translation.x - spostamentoPrima.x, y: translation.y - spostamentoPrima.y)
        spostamentoPrima = translation
        mappa?.trascina(di: delta)
    }

    public func mapTemplateDidDismissPanningInterface(_ mapTemplate: CPMapTemplate) {
        mappa?.segui()
    }
}
