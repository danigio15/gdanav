import CarPlay
import MapKit
import UIKit

/// GdANav su CarPlay: la scena di un'app di navigazione, come la sessione di
/// Android Auto (`SessioneGdanav.kt` e `SchermoNavigazione.kt`).
///
/// Sotto la mappa di GdANav; sopra la scheda della manovra, i tempi e gli
/// avvisi, disegnati da CarPlay. In alto Cerca e Menu (in guida anche Fine); a
/// lato +, −, 2D/3D o Centra, e sposta.
///
/// Chi porta GdANav dentro la mette nell'Info.plist come delegato della scena
/// `CPTemplateApplicationSceneSessionRoleApplication`, col nome
/// `GdanavCarPlay`. Il motore Flutter lo accende l'app all'avvio: CarPlay può
/// aprirla senza la schermata del telefono.
@objc(GdanavCarPlay)
public final class GdanavCarPlay: UIResponder, CPTemplateApplicationSceneDelegate, CPMapTemplateDelegate {
    /// Lo schermo della casa, se chi ospita GdANav ne ha uno (GdAHome): un
    /// tasto in alto sulla mappa, e sull'avviso del Premium.
    public static var casa: ((CPInterfaceController) -> CPTemplate)?

    /// La scena di CarPlay aperta adesso, per chi deve mostrare qualcosa.
    public private(set) static weak var attuale: GdanavCarPlay?

    /// Chiamata quando CarPlay si collega (`true`) o si scollega (`false`):
    /// GdAHome ci accende GdANav anche se la sua sezione non si è mai aperta.
    public static var alCollegamento: ((Bool) -> Void)?

    /// I dati sopra la mappa come su Android Auto (batteria, km, meta,
    /// meteo, sosta, tachimetro col limite, avvisi piccoli). Le regole di
    /// Apple per i navigatori chiedono la mappa pulita: se la revisione li
    /// rifiuta, qui si spengono, e i dati passano agli avvisi di CarPlay.
    public static var pannelliSullaMappa = true

    /// Se CarPlay è collegato adesso.
    public static var collegato: Bool { attuale != nil }

    /// Dove si è, come lo sa GdANav.
    public static var posizione: CLLocationCoordinate2D? {
        PonteAuto.shared.qui.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// Dov'è Casa, fra i luoghi di GdANav.
    public static var casaSalvata: CLLocationCoordinate2D? {
        PonteAuto.shared.casa().map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// «Ehi Siri, naviga con GdANav»: [testo] è quello che si è detto (un
    /// indirizzo, un posto), [tappa] per aggiungerlo al viaggio in corso.
    /// Come «Ok Google, naviga verso…» su Android Auto: il telefono cerca e
    /// parte, anche con l'app ancora spenta. [fatto] dice se l'app ha
    /// risposto.
    public static func naviga(_ testo: String, tappa: Bool = false, fatto: @escaping (Bool) -> Void = { _ in }) {
        var c = URLComponents()
        c.queryItems = [URLQueryItem(name: "q", value: testo)] + (tappa ? [URLQueryItem(name: "intent", value: "add_a_stop")] : [])
        // Il «+» in una domanda vale uno spazio: quello vero va scritto.
        let q = (c.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        PonteAuto.shared.naviga("geo:0,0?" + q, fatto: fatto)
    }

    /// «Portami a casa» o «al lavoro» (`casa`, `lavoro`): [fatto] è `false`
    /// se il posto non è ancora impostato.
    public static func vaiA(_ tipo: String, fatto: @escaping (Bool) -> Void = { _ in }) {
        PonteAuto.shared.vaiA({ PonteAuto.shared.luoghi.first { $0.tipo == tipo } }, fatto: fatto)
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
    /// L'ultima proposta dell'auto termica vista, e se è sopra la mappa.
    private var termicaVista: String?
    private var termicaSopra = false
    private var spostamentoPrima: CGPoint = .zero
    private var sostaAvvisata: String?

    /// La strada a risparmio già proposta, e il suo avviso finché si vede.
    private var stradaMostrata: String?
    private weak var avvisoStrada: CPNavigationAlert?

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
        // La scheda di guida col blu di GdANav: la freccia è bianca.
        t.guidanceBackgroundColor = UIColor(red: 0.08, green: 0.36, blue: 0.75, alpha: 1)
        t.tripEstimateStyle = .dark
        modello = t
        // Col blocco di fine anche qui: senza, un «no» di CarPlay chiude l'app.
        interfaceController.setRootTemplate(t, animated: false) { ok, errore in
            if !ok { NSLog("gdanav CarPlay: setRootTemplate non riuscito: \(errore?.localizedDescription ?? "")") }
        }

        ascolto = PonteAuto.shared.ascolta { [weak self] in self?.novita() }
        novita()
        // Come Android Auto: lo schermo dell'auto si è acceso. Il telefono
        // rilegge i dati dell'auto e i viaggi pianificati.
        PonteAuto.shared.chiedi("in_auto", ["si": true])
        GdanavCarPlay.alCollegamento?(true)
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        if let a = ascolto { PonteAuto.shared.smetti(a) }
        ascolto = nil
        // Come su Android Auto: la prova di guida finisce con l'auto.
        PonteAuto.shared.prova(false)
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
        PonteAuto.shared.chiedi("in_auto", ["si": false])
        GdanavCarPlay.alCollegamento?(false)
    }

    // MARK: - Le novità dal telefono

    private func novita() {
        guard let m = mappa else { return }
        m.aggiorna()
        sincronizzaGuida()
        mostraAvviso()
        mostraStrada()
        if !GdanavCarPlay.pannelliSullaMappa { avvisaLaSosta() }
        // I tasti si rifanno solo se cambia qualcosa che mostrano.
        if PonteAuto.shared.versioneModello != versione {
            versione = PonteAuto.shared.versioneModello
            aggiornaTasti()
            mostraMessaggio()
            proponiTermica()
            controllaPremium()
        }
    }

    // MARK: - I tasti

    private func tasto(_ simbolo: String, _ azione: @escaping () -> Void) -> CPBarButton {
        CPBarButton(image: UIImage(systemName: simbolo) ?? UIImage()) { _ in azione() }
    }

    /// Da fermi «Cerca» con la lente; in guida, dove c'è meno posto, solo la lente.
    private func tasto(titolo: String, simbolo: String, _ azione: @escaping () -> Void) -> CPBarButton {
        titolo.isEmpty ? tasto(simbolo, azione) : tasto(titolo: titolo, azione)
    }

    private func tasto(titolo: String, _ azione: @escaping () -> Void) -> CPBarButton {
        CPBarButton(title: titolo) { _ in azione() }
    }

    private func tastoMappa(_ simbolo: String, _ azione: @escaping () -> Void) -> CPMapButton {
        let b = CPMapButton { _ in azione() }
        b.image = UIImage(systemName: simbolo, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        return b
    }

    /// In alto: Cerca, la casa (dentro GdAHome) e Menu (in guida anche Fine);
    /// appena passata una segnalazione, «C'è ancora?» Sì / No arriva come avviso.
    private func aggiornaTasti() {
        guard let t = modello, let m = mappa else { return }
        let ponte = PonteAuto.shared
        // A sinistra i dati dell'auto (quelli che Android Auto disegna sulla
        // mappa: CarPlay vuole la mappa pulita, e li tiene in un tasto che
        // apre il viaggio) e la lente. A destra la casa (dentro GdAHome) e il
        // Menu; in guida Menu e Fine, e la casa passa nel Menu.
        // Come su Android Auto: la lente e la casa (dentro GdAHome) a
        // sinistra, Menu e (in guida) Fine a destra. Appena passata una
        // segnalazione, a sinistra «C'è ancora» e «No».
        var sinistra: [CPBarButton] = []
        if let id = ponte.avviso.ancoraId, GdanavCarPlay.pannelliSullaMappa {
            sinistra = [
                tasto(titolo: "C'è ancora") { PonteAuto.shared.ancora(id, si: true) },
                tasto(titolo: "No") { PonteAuto.shared.ancora(id, si: false) },
            ]
        } else {
            sinistra.append(tasto(titolo: ponte.guida == nil ? "Cerca" : "", simbolo: "magnifyingglass") { [weak self] in self?.apriCerca() })
            if GdanavCarPlay.casa != nil {
                sinistra.append(tasto("house.fill") { [weak self] in self?.apriCasa() })
            }
        }
        var destra = [tasto(titolo: "Menu") { [weak self] in self?.apriMenu() }]
        if ponte.guida != nil {
            destra.append(tasto(titolo: "Fine") { [weak self] in self?.fine() })
        }
        t.leadingNavigationBarButtons = sinistra
        t.trailingNavigationBarButtons = destra
        // A lato della mappa: + e −, la vista (o Centra se la si è spostata), sposta;
        // da fermi prima la lente e la casa.
        let vista: CPMapButton
        if m.libera {
            vista = tastoMappa("location.fill") { [weak m] in m?.segui() }
        } else {
            // Il tasto mostra la vista dopo: 3D → immersiva → 2D → 3D.
            let simbolo: String
            switch m.vista.dopo {
            case .piatta: simbolo = "view.2d"
            case .inclinata: simbolo = "view.3d"
            case .immersiva: simbolo = "road.lanes"
            }
            vista = tastoMappa(simbolo) { [weak self, weak m] in
                m?.alternaVista()
                self?.aggiornaTasti()
            }
        }
        var tasti = [
            tastoMappa("plus") { [weak m] in m?.zoom(1) },
            tastoMappa("minus") { [weak m] in m?.zoom(-1) },
            vista,
            tastoMappa("arrow.up.and.down.and.arrow.left.and.right") { [weak t] in
                t?.showPanningInterface(animated: true)
            },
        ]
        /* Da fermi la lente e la casa anche di lato, prima di tutto.
         *
         * «Sullo schermo piccolo non fa più selezionare niente»: su certe
         * autoradio piccole la barra in alto (Cerca, casa, Menu) non si vede, e
         * la mappa restava senza un modo di scegliere dove andare. I tasti di
         * lato si vedono sempre; CarPlay ne tiene quattro, quindi da fermi
         * cedono il posto 2D/3D e «sposta» (la mappa si sposta anche col dito).
         * In guida restano quelli di prima: la meta c'e' gia'. */
        if ponte.guida == nil {
            var davanti = [tastoMappa("magnifyingglass") { [weak self] in self?.apriCerca() }]
            if GdanavCarPlay.casa != nil {
                davanti.append(tastoMappa("house.fill") { [weak self] in self?.apriCasa() })
            }
            tasti = Array((davanti + tasti).prefix(4))
        }
        t.mapButtons = tasti
    }

    private func fine() {
        PonteAuto.shared.fermaDallAuto()
    }

    private func apriCerca() {
        guard let c = controllore else { return }
        c.spingi(SchermiCarPlay.cerca(c))
    }

    private func apriMenu() {
        guard let c = controllore, let m = mappa else { return }
        c.spingi(SchermiCarPlay.menu(c, mappa: m))
    }

    private func apriCasa() {
        guard let c = controllore, let casa = GdanavCarPlay.casa else { return }
        c.spingi(casa(c))
    }

    // MARK: - Premium

    /// Senza GdANav Premium la mappa c'è, ma la navigazione no: lo si dice, e
    /// basta — niente «fallo dal telefono», che guidando non si fa (come su
    /// Android Auto, dove Google ha rifiutato l'app per questo). Appena l'app
    /// lo sblocca, l'avviso se ne va da solo.
    ///
    /// Conta [PonteAuto.guidaInAuto], non Premium da solo: dentro GdAHome,
    /// senza una casa abbinata, si guida base anche senza Premium (come su
    /// Android Auto). Apre e chiude coi blocchi di fine («I passi fra gli
    /// schermi», in `SchermiCarPlay.swift`): se CarPlay non lo mostra — c'è
    /// già un altro avviso sopra — si riprova alla novità dopo, invece di
    /// far chiudere l'app.
    private func controllaPremium() {
        // Finché l'app non ha parlato (niente stile) non si sa ancora niente.
        guard let c = controllore, PonteAuto.shared.stileChiaro != nil else { return }
        let siGuida = PonteAuto.shared.guidaInAuto
        if siGuida && premiumMostrato {
            premiumMostrato = false
            c.chiudiSopra()
        } else if !siGuida && !premiumMostrato {
            premiumMostrato = true
            var azioni = [
                CPAlertAction(title: "Riprova", style: .default) { [weak self] _ in
                    guard let self else { return }
                    if PonteAuto.shared.guidaInAuto {
                        self.premiumMostrato = false
                        self.controllore?.chiudiSopra()
                    }
                },
            ]
            // Dentro GdAHome la casa non è Premium: ci si arriva anche da qui.
            if GdanavCarPlay.casa != nil {
                azioni.append(CPAlertAction(title: "Casa", style: .default) { [weak self] _ in
                    guard let self else { return }
                    self.premiumMostrato = false
                    self.controllore?.chiudiSopra { _ in self.apriCasa() }
                })
            }
            // Dentro GdAHome Premium si attiva lì, non nel negozio di GdANav.
            // Una versione troppo vecchia va prima aggiornata.
            let avviso = CPAlertTemplate(
                titleVariants: PonteAuto.shared.aggiorna
                    ? [
                        "C'è una versione nuova di GdANav: questa non è più attiva.",
                        "Serve un aggiornamento.",
                    ]
                    : PonteAuto.shared.premiumOspite
                    ? [
                        "La navigazione in auto è inclusa in GdAHome Premium.",
                        "Inclusa in GdAHome Premium.",
                    ]
                    : [
                        "La navigazione in auto è inclusa in GdANav Premium.",
                        "Inclusa in GdANav Premium.",
                    ],
                actions: azioni
            )
            c.mostraSopra(avviso) { [weak self] ok in
                if !ok { self?.premiumMostrato = false }
            }
        }
    }

    // MARK: - La guida

    /// CarPlay vuole sapere quando si naviga, per le altre app e Siri; e la
    /// manovra, i tempi e le corsie li disegna lui.
    private func sincronizzaGuida() {
        guard let t = modello else { return }
        let ponte = PonteAuto.shared
        // Come l'avviso del Premium: conta se in auto si guida, non Premium da
        // solo (dentro GdAHome senza casa abbinata si guida base).
        guard let g = ponte.guida, ponte.guidaInAuto else {
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
            // Il pedaggio, come le informazioni in più di una strada.
            let scelta = CPRouteChoice(
                summaryVariants: riepilogo,
                additionalInformationVariants: g.pedaggio.map { [$0] } ?? [],
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
            + "|\(g.rotonda ?? -1)|\(g.frasi.joined(separator: "¦"))|\(g.dopoFrasi.joined(separator: "¦"))"
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
        // Le frasi le scrive l'app (`frasiManovra`), dalla più lunga alla più
        // corta: CarPlay prende la prima che ci sta. Su uno schermo piccolo
        // (800×480, 400×240 punti) è «2ª uscita», non tre righe con
        // «/SP253». Un'app di prima non le manda: il testo di sempre.
        if !g.frasi.isEmpty {
            m.instructionVariants = g.frasi
        } else {
            let testo = ManovreCarPlay.testo(g)
            var righe = [testo]
            if !g.strada.isEmpty && g.strada != testo { righe.append(g.strada) }
            if !g.istruzione.isEmpty && !righe.contains(g.istruzione) { righe.append(g.istruzione) }
            m.instructionVariants = righe
        }
        // La rotonda disegnata con la sua uscita, non il simbolo di «aggiorna».
        m.symbolImage = ManovreCarPlay.immagine(g.tipo, rotonda: g.rotonda)
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
        // Il «poi» arriva solo se la manovra dopo è vicina (entro 150 m,
        // `poiVicino`), come in Mappe: lontana era una riga in più sulla mappa.
        guard let dopo = g.dopoTipo else { return [m] }
        let poi = CPManeuver()
        if !g.dopoFrasi.isEmpty {
            poi.instructionVariants = g.dopoFrasi
        } else {
            poi.instructionVariants = g.dopoStrada.isEmpty ? ["Poi"] : ["Poi \(g.dopoStrada)", "Poi"]
        }
        poi.symbolImage = ManovreCarPlay.immagine(dopo, rotonda: g.dopoRotonda)
        return [m, poi]
    }

    // MARK: - Avvisi e messaggi

    /// Una segnalazione davanti, o «C'è ancora?» dopo averla passata: un
    /// avviso di navigazione, come quelli di Mappe.
    private func mostraAvviso() {
        // Coi pannelli l'avviso è la capsula piccola sulla mappa, e «c'è
        // ancora?» si risponde coi tasti in alto, come su Android Auto.
        guard let t = modello, let a = PonteAuto.shared.prendiAvvisoNuovo() else { return }
        guard !GdanavCarPlay.pannelliSullaMappa else { return }
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
            if let testo = a.testo {
                sotto.append(testo)
            } else if let metri = a.metri {
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

    /// La strada a risparmio (o più rapida) proposta dal telefono: un avviso di
    /// navigazione coi due tasti, come Mappe quando propone un'altra strada.
    /// Sparisce da solo dopo venti secondi, come sul telefono; presa,
    /// rifiutata o scaduta là, sparisce anche qui.
    private func mostraStrada() {
        guard let t = modello else { return }
        let s = PonteAuto.shared.strada
        guard s.id != stradaMostrata else { return }
        stradaMostrata = s.id
        guard let id = s.id else {
            if let a = avvisoStrada, t.currentNavigationAlert === a {
                t.dismissNavigationAlert(animated: true) { _ in }
            }
            avvisoStrada = nil
            return
        }
        let alert = CPNavigationAlert(
            titleVariants: [s.titolo ?? "Strada a risparmio"],
            subtitleVariants: [s.testo ?? ""],
            image: UIImage(systemName: "leaf.fill")?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal),
            primaryAction: CPAlertAction(title: "Prendila", style: .default) { _ in
                PonteAuto.shared.rispondiStrada(id, si: true)
            },
            secondaryAction: CPAlertAction(title: "Resto qui", style: .cancel) { _ in
                PonteAuto.shared.rispondiStrada(id, si: false)
            },
            duration: 20
        )
        avvisoStrada = alert
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

    /// Manca la batteria: l'avviso breve sparirebbe senza lasciare niente da
    /// fare, e in auto la batteria non si scrive. Un avviso sopra la mappa
    /// (`CPAlertTemplate`) col tasto per passare all'auto termica, come
    /// `SchermoTermica.kt`; se il telefono risolve da sé, se ne va.
    private func proponiTermica() {
        guard let c = controllore, !premiumMostrato else { return }
        let id = PonteAuto.shared.guida == nil ? PonteAuto.shared.termica.id : nil
        // Una proposta per volta, e una volta sola: «Annulla» non la fa tornare.
        guard id != termicaVista else { return }
        termicaVista = id
        if termicaSopra {
            termicaSopra = false
            c.chiudiSopra { [weak self] _ in
                if let id { self?.mostraTermica(id) }
            }
        } else if let id {
            mostraTermica(id)
        }
    }

    private func mostraTermica(_ id: String) {
        guard let c = controllore else { return }
        let t = PonteAuto.shared.termica
        let testo = PonteAuto.shared.messaggio ?? "Passiamo all'auto termica?"
        let avviso = CPAlertTemplate(
            titleVariants: [testo, t.titolo ?? "Passiamo all'auto termica?"],
            actions: [
                // Senza auto elettrica la termica è la proposta; altrimenti una via d'uscita.
                CPAlertAction(title: "Usa auto termica", style: t.primaria ? .default : .cancel) { [weak self] _ in
                    self?.termicaSopra = false
                    self?.controllore?.chiudiSopra()
                    PonteAuto.shared.usaTermica(id)
                },
                CPAlertAction(title: "Annulla", style: t.primaria ? .cancel : .default) { [weak self] _ in
                    self?.termicaSopra = false
                    self?.controllore?.chiudiSopra()
                },
            ]
        )
        termicaSopra = true
        c.mostraSopra(avviso) { [weak self] ok in
            if !ok { self?.termicaSopra = false }
        }
    }

    /// «Calcolo il percorso…» o cosa non va, da fermi: un avviso breve.
    private func mostraMessaggio() {
        let testo = PonteAuto.shared.guida == nil && PonteAuto.shared.termica.id == nil ? PonteAuto.shared.messaggio : nil
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
