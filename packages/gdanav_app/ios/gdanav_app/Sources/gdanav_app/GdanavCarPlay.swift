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
        guard let io = attuale, let t = io.modello else { return }
        let alert = CPNavigationAlert(
            titleVariants: [titolo],
            subtitleVariants: [sotto],
            image: immagine,
            primaryAction: CPAlertAction(title: si, style: .default) { _ in azione() },
            secondaryAction: CPAlertAction(title: no, style: .cancel) { _ in },
            duration: 15
        )
        io.metti(alert, in: t)
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

    /// Le strade mostrate prima di partire (le anteprime di CarPlay), e il
    /// loro viaggio.
    private var stradeMostrate: StradeAuto?
    private var viaggioStrade: CPTrip?

    /// La strada a risparmio già proposta, e il suo avviso finché si vede.
    private var stradaMostrata: String?
    private weak var avvisoStrada: CPNavigationAlert?

    /// La scena di CarPlay, per sapere se è davanti (non il Dashboard, non
    /// un'altra app sullo schermo dell'auto).
    private weak var scena: CPTemplateApplicationScene?

    /// L'ultimo avviso dato a CarPlay e non ancora confermato (`didShow`), e
    /// quando: due dati insieme, e il secondo non farebbe niente ([metti]).
    private weak var inVolo: CPNavigationAlert?
    private var inVoloDa: TimeInterval = 0

    // L'avviso di casa su CarPlay ([mostraAvvisoCasa]).

    /// Di quale avviso ci si sta occupando (`AvvisoCasaAuto.chiave`), e da
    /// quando lo si conosce.
    private var casaVoluta: String?
    private var casaVistaDa: TimeInterval = 0

    /// Il suo avviso di CarPlay: dato a CarPlay, in vista o in attesa che
    /// CarPlay lo confermi. Coi dati di quando è stato dato.
    private var avvisoCasa: CPNavigationAlert?
    private var casaDati: AvvisoCasaAuto?

    /// CarPlay ha detto che si vede (`didShow`), e quando.
    private var casaConfermata = false
    private var casaConfermatoA: TimeInterval = 0

    /// Quando è stato dato a CarPlay, per quanto, e fino a quando CarPlay lo
    /// tiene.
    private var casaDatoA: TimeInterval = 0
    private var casaDurata: TimeInterval = 0
    private var casaFinoA: TimeInterval = 0

    /// Da quando CarPlay non lo tiene più sullo schermo senza averlo detto.
    private var casaSparitoDa: TimeInterval?

    /// Il titolo e il testo che mostra.
    private var casaTitolo = ""
    private var casaTesto = ""

    /// Se è stato chiuso da un suo tasto (uno per ogni avviso dato).
    private var casaTocco = Tocco()

    /// Per questo avviso su CarPlay non c'è più niente da fare: toccato,
    /// scaduto, o ci si è arresi.
    private var casaFinita = false

    /// Si è visto almeno una volta; quante volte CarPlay non l'ha mostrato
    /// di fila; quante volte un altro avviso l'ha tolto.
    private var casaVistoMai = false
    private var casaTentativi = 0
    private var casaScalzate = 0

    /// Un nostro avviso di casa che non serve più si sta togliendo, e da quando.
    private var casaRitiroDa: TimeInterval?

    /// Uno ritirato prima che CarPlay lo mettesse: se arriva, si toglie.
    private weak var casaRitirato: CPNavigationAlert?

    /// Quando è in programma la prossima occhiata all'avviso di casa (0: mai).
    private var casaSveglia: TimeInterval = 0

    /// La musica (il lettore di sistema): a ogni cambio si rifanno i tasti.
    private var ascoltoMusica: UUID?

    // MARK: - La scena

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        GdanavCarPlay.attuale = self
        scena = templateApplicationScene
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
        ascoltoMusica = LettoreDiSistema.shared.ascolta { PonteAuto.shared.rinfresca() }
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
        if let m = ascoltoMusica { LettoreDiSistema.shared.smetti(m) }
        ascoltoMusica = nil
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
        scena = nil
        // L'avviso di casa finisce con la sessione: alla prossima il telefono
        // rimanda quello di allora, se c'è (`in_auto`).
        dimenticaAvvisoCasa()
        PonteAuto.shared.fineSessione()
        if GdanavCarPlay.attuale === self { GdanavCarPlay.attuale = nil }
        PonteAuto.shared.chiedi("in_auto", ["si": false])
        GdanavCarPlay.alCollegamento?(false)
    }

    /// La mappa di GdANav torna davanti sullo schermo dell'auto (dal
    /// Dashboard, da un'altra app): un avviso di casa dato mentre era dietro
    /// si guarda adesso se c'è.
    public func sceneDidBecomeActive(_ scene: UIScene) {
        mostraAvvisoCasa()
    }

    // MARK: - Le novità dal telefono

    private func novita() {
        guard let m = mappa else { return }
        m.aggiorna()
        // Prima via le anteprime delle strade, poi la guida: partiti dal
        // telefono, CarPlay non deve avere le due cose insieme.
        mostraStrade()
        sincronizzaGuida()
        mostraAvviso()
        mostraStrada()
        mostraAvvisoCasa()
        if !GdanavCarPlay.pannelliSullaMappa { avvisaLaSosta() }
        chiediLaMusica()
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
        } else if LettoreDiSistema.shared.daMostrare, let brano = LettoreDiSistema.shared.brano {
            // Con la Musica di Apple in ascolto, in guida e a mappa libera: ⏯
            // e ⏭, come la barra di Mappe. Solo se è davvero lei a suonare (o
            // l'abbiamo messa in pausa da qui): con un'altra app in ascolto
            // (Spotify), o con la Musica ferma da prima, restano «Cerca» e la
            // casa — un ▶ farebbe partire un brano vecchio e zittirebbe
            // l'altra. Apple non vuole tasti disegnati sulla mappa, e il brano
            // lo mostra la scheda «In riproduzione» di CarPlay. In guida la
            // lente passa nel Menu; a mappa libera la lente e la casa restano
            // nei tasti di lato (`mapButtons`).
            sinistra = [
                tasto(brano.suona ? "pause.fill" : "play.fill") { LettoreDiSistema.shared.comando("playPausa") },
                tasto("forward.fill") { LettoreDiSistema.shared.comando("successivo") },
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
        } else if ponte.strade != nil {
            // Con le strade in vista: niente viaggio, come «Fine» sul telefono.
            destra.append(tasto(titolo: "Annulla") { [weak self] in self?.fine() })
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

    // MARK: - Le strade prima di partire

    /// «Quando c'è il calcolo percorso questo non esce su CarPlay»: calcolato
    /// il viaggio (dall'auto o dal telefono), le strade fra cui scegliere
    /// nelle anteprime di CarPlay — più rapida, risparmia energia, tempo
    /// simile, più lenta — con la durata, il consumo, il pedaggio, da dove
    /// passa e la batteria all'arrivo; «Avvia» parte con quella scelta.
    /// Toccandone una la si sceglie anche sul telefono. Partiti, o cambiato
    /// il viaggio, le anteprime se ne vanno.
    private func mostraStrade() {
        guard let t = modello else { return }
        let ponte = PonteAuto.shared
        let ora = ponte.guida == nil && ponte.guidaInAuto ? ponte.strade : nil
        if ora == stradeMostrate { return }
        // Lo stesso viaggio con un'altra strada scelta (qui o sul telefono):
        // l'anteprima resta, cambiano i tempi.
        if let o = ora, let prima = stradeMostrate, let v = viaggioStrade, o.id == prima.id,
           o.voci.map(\.nome) == prima.voci.map(\.nome)
        {
            stradeMostrate = o
            stime(o, per: v)
            return
        }
        stradeMostrate = ora
        if viaggioStrade != nil {
            t.hideTripPreviews()
            viaggioStrade = nil
        }
        guard let s = ora else { return }
        let qui = ponte.qui.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let arrivo = CLLocationCoordinate2D(latitude: s.lat ?? qui?.latitude ?? 0, longitude: s.lon ?? qui?.longitude ?? 0)
        let da = MKMapItem(placemark: MKPlacemark(coordinate: qui ?? arrivo))
        let a = MKMapItem(placemark: MKPlacemark(coordinate: arrivo))
        a.name = s.meta
        // Dentro ogni pezzo lo spazio non va a capo («+7 / min traffico»):
        // CarPlay manda a capo solo fra un pezzo e l'altro.
        func intero(_ t: String?) -> String? { t?.replacingOccurrences(of: " ", with: "\u{00A0}") }
        let scelte = s.voci.enumerated().map { i, v -> CPRouteChoice in
            // Dal più lungo al più corto: CarPlay prende quello che ci sta.
            let durata = ManovreCarPlay.durata(v.durataS)
            let costi = [v.consumo, v.pedaggio].compactMap { $0 }.joined(separator: " · ")
            let c = CPRouteChoice(
                summaryVariants: [
                    [durata, v.nome, costi].filter { !$0.isEmpty }.compactMap { intero($0) }.joined(separator: " · "),
                    "\(intero(durata) ?? durata) · \(v.nome)",
                    v.nome,
                ],
                additionalInformationVariants: [
                    [v.via.isEmpty ? nil : v.via, v.km, v.arrivo.map { "arrivi con il \($0)%" }, v.traffico]
                        .compactMap { intero($0) }.joined(separator: " · "),
                    [v.km, v.arrivo.map { "arrivi con il \($0)%" }].compactMap { intero($0) }.joined(separator: " · "),
                ],
                selectionSummaryVariants: [v.via.isEmpty ? v.nome : v.via]
            )
            c.userInfo = i
            return c
        }
        let v = CPTrip(origin: da, destination: a, routeChoices: scelte)
        viaggioStrade = v
        t.showTripPreviews(
            [v],
            textConfiguration: CPTripPreviewTextConfiguration(
                startButtonTitle: "Avvia",
                additionalRoutesButtonTitle: "Altre strade",
                overviewButtonTitle: "Panoramica"
            )
        )
        stime(s, per: v)
    }

    /// I tempi della strada scelta, sotto l'anteprima.
    private func stime(_ s: StradeAuto, per v: CPTrip) {
        guard let t = modello, s.voci.indices.contains(s.scelta) else { return }
        let voce = s.voci[s.scelta]
        t.update(
            CPTravelEstimates(distanceRemaining: ManovreCarPlay.distanza(voce.metri), timeRemaining: voce.durataS),
            for: v,
            with: .default
        )
    }

    public func mapTemplate(_ mapTemplate: CPMapTemplate, selectedPreviewFor trip: CPTrip, using routeChoice: CPRouteChoice) {
        guard let s = stradeMostrate, let i = routeChoice.userInfo as? Int, i != s.scelta else { return }
        stradeMostrate?.scelta = i
        if let v = viaggioStrade, let ora = stradeMostrate { stime(ora, per: v) }
        PonteAuto.shared.scegliStrada(s.id, indice: i)
    }

    public func mapTemplate(_ mapTemplate: CPMapTemplate, startedTrip trip: CPTrip, using routeChoice: CPRouteChoice) {
        guard let s = stradeMostrate else { return }
        let i = routeChoice.userInfo as? Int ?? s.scelta
        mapTemplate.hideTripPreviews()
        viaggioStrade = nil
        PonteAuto.shared.avvia(s.id, indice: i)
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
        metti(alert, in: t)
    }

    // MARK: - L'avviso di casa

    /// Dopo quanto, senza un `didShow`, un avviso dato a CarPlay non si è visto.
    private static let attesaConferma: TimeInterval = 2.5

    /// Quanto si lascia a CarPlay per mettere un avviso prima di dargliene un altro.
    private static let attesaVolo: TimeInterval = 0.8

    /// Quanto si aspetta che CarPlay tolga un avviso ritirato.
    private static let attesaRitiro: TimeInterval = 1.5

    /// Un avviso che CarPlay non tiene più, senza averlo detto: lo si crede dopo questo tempo.
    private static let attesaSparito: TimeInterval = 1

    /// Meno di così CarPlay non tiene un avviso (`CPNavigationAlertMinimumDuration`).
    private static let durataMinima: TimeInterval = 5

    /// Con meno tempo di così davanti non vale la pena mostrarlo.
    private static let restoMinimo: TimeInterval = 1.5

    /// Quanto si aspetta CarPlay oltre la durata, prima di darlo per finito.
    private static let margineFine: TimeInterval = 3

    /// Quante volte di fila si riprova se CarPlay non lo mostra, e quante
    /// volte si rimette dopo che un altro avviso l'ha tolto.
    private static let tentativiAlPiu = 3
    private static let scalzateAlPiu = 3

    /// Quanto CarPlay tiene un avviso che sul telefono non ha un tempo suo:
    /// l'urgente dieci minuti, la domanda «Sì / No» mezzo minuto, come su
    /// Android Auto (`SchermoNavigazione.mostraAvvisoCasa`).
    private static let durataUrgente: TimeInterval = 600
    private static let durataDomanda: TimeInterval = 30

    /// Ogni quanto si riguarda, mentre si aspetta che la mappa torni in cima
    /// o che l'avviso di un altro finisca.
    private static let ogniTanto: TimeInterval = 2

    private static func adesso() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Se la mappa è lo schermo in cima, senza niente sopra (il Menu, la
    /// ricerca, la casa, un avviso a tutto schermo): solo lì un avviso di
    /// navigazione si vede.
    private var mappaInCima: Bool {
        guard let c = controllore, let t = modello else { return false }
        return c.topTemplate === t && c.presentedTemplate == nil
    }

    /// Se la mappa di GdANav è davanti sullo schermo dell'auto (non il
    /// Dashboard, non un'altra app).
    private var scenaDavanti: Bool { scena?.activationState == .foregroundActive }

    /// Dà un avviso a CarPlay. CarPlay ne tiene uno alla volta, e un `present`
    /// con un altro avviso in vista non fa niente: prima via quello che c'è
    /// (se è l'avviso di casa, torna quando questo finisce:
    /// [mostraAvvisoCasa]). Se un altro è stato dato un attimo fa e CarPlay
    /// non l'ha ancora messo, questo aspetta quell'attimo: dati insieme, il
    /// secondo si perderebbe.
    private func metti(_ alert: CPNavigationAlert, in t: CPMapTemplate) {
        let ora = GdanavCarPlay.adesso()
        if t.currentNavigationAlert == nil, let altro = inVolo, altro !== alert,
           ora - inVoloDa < GdanavCarPlay.attesaVolo
        {
            DispatchQueue.main.asyncAfter(deadline: .now() + GdanavCarPlay.attesaVolo) { [weak self, weak t] in
                guard let self, let t, self.modello === t else { return }
                self.metti(alert, in: t)
            }
            return
        }
        inVolo = alert
        inVoloDa = ora
        if t.currentNavigationAlert != nil {
            t.dismissNavigationAlert(animated: false) { _ in t.present(navigationAlert: alert, animated: true) }
        } else {
            t.present(navigationAlert: alert, animated: true)
        }
    }

    /// Un avviso di casa (dentro GdAHome): un avviso di navigazione, come
    /// quelli di Mappe, coi tasti scelti dal telefono (al più due). Il tasto
    /// torna al telefono, che fa la domanda «Sì / No» se serve e poi lo passa
    /// a GdAHome.
    ///
    /// Qui si confronta quello che il telefono vuole in vista
    /// (`PonteAuto.avvisoCasa`) con quello che CarPlay ha davvero sullo
    /// schermo, e si fa quel che manca. Si richiama a ogni novità, quando
    /// CarPlay mostra o toglie un avviso, e da sé finché aspetta qualcosa.
    ///
    /// - **Mostrato solo se CarPlay lo conferma** (`didShow`). Se non lo
    ///   conferma si riprova, al più tre volte; con un altro schermo sopra la
    ///   mappa (il Menu, la casa) non si prova nemmeno, e lo si dà quando la
    ///   mappa torna in cima.
    /// - **Lo stesso avviso, uguale, non si ripresenta**: il telefono lo
    ///   rimanda a ogni `in_auto`. Con un altro titolo o testo (il gruppo «3
    ///   notifiche» che diventa 4) si aggiorna quello in vista.
    /// - **Uno alla volta.** Un altro avviso (un messaggio, la strada
    ///   proposta, «Quasi a casa») toglie quello di casa, che **torna** quando
    ///   l'altro finisce, col tempo che gli resta. Arrivando con un altro
    ///   avviso in vista, l'urgente gli passa davanti; gli altri aspettano
    ///   che finisca. Tornando non scalza mai nessuno, e dopo tre volte di
    ///   fila ci si arrende: niente giri.
    /// - **Il tempo.** `secondi` è quello che resta sul telefono. L'urgente e
    ///   la domanda, che sul telefono non scadono, qui durano dieci minuti e
    ///   mezzo minuto.
    /// - **Quando se ne va da solo.** Chi ha un tempo suo sparisce e basta:
    ///   ci pensa il telefono. Per l'urgente e la domanda — scaduti qui, mai
    ///   mostrati dopo tre prove, tolti troppe volte — lo si dice al telefono
    ///   (`_scaduto`, [PonteAuto.casaScaduta]), una volta sola: l'urgente va
    ///   da parte e passano quelli dopo, la domanda torna all'avviso. Da lì
    ///   in poi per quell'avviso qui non si fa più niente ([casaFinita]),
    ///   finché il telefono non ne manda un altro.
    private func mostraAvvisoCasa() {
        guard let t = modello else { return }
        let ora = GdanavCarPlay.adesso()
        guard let a = PonteAuto.shared.avvisoCasa else {
            // Il telefono non ne ha più: via anche da qui.
            casaVoluta = nil
            ritiraAvvisoCasa(da: t)
            return
        }
        if a.chiave != casaVoluta {
            // Un altro avviso (o lo stesso diventato la domanda): via quello
            // di prima, e questo da capo.
            ritiraAvvisoCasa(da: t)
            casaVoluta = a.chiave
            casaVistaDa = ora
            casaFinita = false
            casaVistoMai = false
            casaTentativi = 0
            casaScalzate = 0
        }
        guard !casaFinita else { return }
        if let v = avvisoCasa {
            // Già dato a CarPlay. Lo stesso con un altro testo si aggiorna.
            if a.titolo != casaTitolo || a.testo != casaTesto {
                casaTitolo = a.titolo
                casaTesto = a.testo
                v.updateTitleVariants([a.titolo], subtitleVariants: a.testo.isEmpty ? [] : [a.testo])
            }
            let sulloSchermo = t.currentNavigationAlert === v
            if sulloSchermo, !casaConfermata { casaConfermato() }
            if casaConfermata {
                if ora > casaFinoA + GdanavCarPlay.margineFine {
                    // CarPlay doveva averlo già tolto, e non ha detto niente:
                    // finito, come allo scadere.
                    finisciCasa(a)
                    ritiraAvvisoCasa(da: t)
                    return
                }
                if sulloSchermo {
                    casaSparitoDa = nil
                    return
                }
                // Dietro (il Dashboard, un altro schermo sopra) non si giudica.
                guard scenaDavanti, mappaInCima else { return }
                // CarPlay non lo tiene più. Di solito lo sta per dire
                // (`didDismiss`): gli si lascia un attimo.
                guard let da = casaSparitoDa else {
                    casaSparitoDa = ora
                    rivediCasa(tra: GdanavCarPlay.attesaSparito)
                    return
                }
                let manca = da + GdanavCarPlay.attesaSparito - ora
                if manca > 0 {
                    rivediCasa(tra: manca)
                    return
                }
                // Tolto senza dirlo: come scalzato da un altro avviso.
                casaScalzato()
            } else {
                // In attesa che CarPlay dica che si vede.
                let manca = casaDatoA + GdanavCarPlay.attesaConferma - ora
                if manca > 0 {
                    rivediCasa(tra: manca)
                    return
                }
                // Dato mentre la mappa era dietro, magari è uscito come
                // notifica: si guarda quando torna davanti.
                guard scenaDavanti else { return }
                // CarPlay non l'ha mostrato.
                avvisoCasa = nil
                casaDati = nil
                casaRitirato = v
                casaTentativi += 1
            }
        }
        // Da dare a CarPlay: la prima volta, o di nuovo.
        if let da = casaRitiroDa {
            let manca = da + GdanavCarPlay.attesaRitiro - ora
            if manca > 0 {
                rivediCasa(tra: manca)
                return
            }
            casaRitiroDa = nil
        }
        let scade: TimeInterval
        if let secondi = a.secondi {
            scade = a.arrivato + TimeInterval(secondi)
        } else {
            scade = casaVistaDa + (a.conferma ? GdanavCarPlay.durataDomanda : GdanavCarPlay.durataUrgente)
        }
        let resta = scade - ora
        guard resta >= GdanavCarPlay.restoMinimo,
              casaTentativi < GdanavCarPlay.tentativiAlPiu,
              casaScalzate <= GdanavCarPlay.scalzateAlPiu
        else {
            // Il suo tempo è passato, o CarPlay non lo vuole: ci si arrende.
            finisciCasa(a)
            return
        }
        guard mappaInCima else {
            rivediCasa(tra: GdanavCarPlay.ogniTanto)
            return
        }
        if t.currentNavigationAlert != nil {
            // Sullo schermo c'è l'avviso di un altro. L'urgente che non si è
            // ancora visto gli passa davanti; chi torna, e chi non è urgente,
            // aspetta che finisca (`didDismiss`).
            guard a.urgente, !casaVistoMai, casaScalzate == 0 else {
                rivediCasa(tra: GdanavCarPlay.ogniTanto)
                return
            }
        } else if inVolo != nil, ora - inVoloDa < GdanavCarPlay.attesaVolo {
            // Un altro è appena stato dato a CarPlay: prima quello.
            rivediCasa(tra: GdanavCarPlay.attesaVolo)
            return
        }
        daiACarPlay(a, per: resta, in: t)
    }

    private func daiACarPlay(_ a: AvvisoCasaAuto, per resta: TimeInterval, in t: CPMapTemplate) {
        let tocco = Tocco()
        func azione(_ x: AvvisoCasaAuto.Tasto) -> CPAlertAction {
            let stile: CPAlertAction.Style = x.principale ? .default : .cancel
            return CPAlertAction(title: x.etichetta, style: stile) { _ in
                tocco.fatto = true
                PonteAuto.shared.tastoCasa(a.id, x.id)
            }
        }
        let primo = a.tasti.first.map(azione) ?? CPAlertAction(title: "Chiudi", style: .cancel) { _ in
            tocco.fatto = true
            PonteAuto.shared.tastoCasa(a.id, "_chiudi")
        }
        let durata = max(resta, GdanavCarPlay.durataMinima)
        let alert = CPNavigationAlert(
            titleVariants: [a.titolo],
            subtitleVariants: a.testo.isEmpty ? [] : [a.testo],
            image: a.icona,
            primaryAction: primo,
            secondaryAction: a.tasti.count > 1 ? azione(a.tasti[1]) : nil,
            duration: durata
        )
        let ora = GdanavCarPlay.adesso()
        avvisoCasa = alert
        casaDati = a
        casaTocco = tocco
        casaConfermata = false
        casaSparitoDa = nil
        casaDatoA = ora
        casaDurata = durata
        casaFinoA = ora + durata
        casaTitolo = a.titolo
        casaTesto = a.testo
        metti(alert, in: t)
        rivediCasa(tra: GdanavCarPlay.attesaConferma + 0.1)
    }

    /// CarPlay ha il nostro avviso di casa sullo schermo.
    private func casaConfermato() {
        let ora = GdanavCarPlay.adesso()
        casaConfermata = true
        casaConfermatoA = ora
        casaVistoMai = true
        casaTentativi = 0
        casaFinoA = ora + casaDurata
    }

    /// L'avviso di casa non è più sullo schermo e nessuno l'ha chiuso: un
    /// altro avviso gli ha preso il posto, o CarPlay l'ha tolto. Resta da
    /// mostrare, e torna quando si può ([mostraAvvisoCasa]). Si contano le
    /// volte una dietro l'altra: se era rimasto in vista un po', da capo.
    private func casaScalzato() {
        let rimasto = casaConfermata && GdanavCarPlay.adesso() - casaConfermatoA >= GdanavCarPlay.durataMinima
        casaScalzate = rimasto ? 1 : casaScalzate + 1
        avvisoCasa = nil
        casaDati = nil
        casaConfermata = false
        casaSparitoDa = nil
    }

    /// Su CarPlay questo avviso è finito senza che nessuno lo toccasse. Chi
    /// sul telefono non ha un tempo suo (l'urgente, la domanda) lo si dice al
    /// telefono, che non lo aspetta più; gli altri se ne vanno col loro tempo.
    private func finisciCasa(_ a: AvvisoCasaAuto) {
        casaFinita = true
        if a.secondi == nil { PonteAuto.shared.casaScaduta(a.id, conferma: a.conferma) }
    }

    /// Toglie dallo schermo il nostro avviso di casa, che non serve più. Da
    /// qui quello che CarPlay dice di lui non conta.
    private func ritiraAvvisoCasa(da t: CPMapTemplate) {
        guard let v = avvisoCasa else { return }
        avvisoCasa = nil
        casaDati = nil
        casaConfermata = false
        casaSparitoDa = nil
        guard t.currentNavigationAlert === v else {
            // Non è (ancora) sullo schermo: se CarPlay lo mette adesso, lo si
            // toglie (`didShow`).
            casaRitirato = v
            return
        }
        casaRitiroDa = GdanavCarPlay.adesso()
        t.dismissNavigationAlert(animated: PonteAuto.shared.avvisoCasa == nil) { [weak self] _ in
            guard let self else { return }
            self.casaRitiroDa = nil
            self.mostraAvvisoCasa()
        }
    }

    /// CarPlay si è scollegato: dell'avviso di casa non resta niente.
    private func dimenticaAvvisoCasa() {
        casaVoluta = nil
        avvisoCasa = nil
        casaDati = nil
        casaConfermata = false
        casaFinita = false
        casaSparitoDa = nil
        casaRitiroDa = nil
        casaRitirato = nil
        casaSveglia = 0
        inVolo = nil
    }

    /// Un'altra occhiata all'avviso di casa fra [secondi]; se ce n'è già una
    /// in programma prima, basta quella.
    private func rivediCasa(tra secondi: TimeInterval) {
        let fra = max(secondi, 0.05)
        let ora = GdanavCarPlay.adesso()
        if casaSveglia > ora, casaSveglia <= ora + fra { return }
        casaSveglia = ora + fra
        DispatchQueue.main.asyncAfter(deadline: .now() + fra) { [weak self] in
            guard let self else { return }
            if self.casaSveglia <= GdanavCarPlay.adesso() + 0.02 { self.casaSveglia = 0 }
            self.mostraAvvisoCasa()
        }
    }

    /// CarPlay ha messo un avviso sullo schermo: solo adesso quello di casa è
    /// «mostrato».
    public func mapTemplate(_ mapTemplate: CPMapTemplate, didShow navigationAlert: CPNavigationAlert) {
        if navigationAlert === inVolo { inVolo = nil }
        if navigationAlert === avvisoCasa {
            casaConfermato()
        } else if navigationAlert === casaRitirato {
            // Ritirato prima che CarPlay lo mettesse: non serve più.
            casaRitirato = nil
            casaRitiroDa = GdanavCarPlay.adesso()
            mapTemplate.dismissNavigationAlert(animated: false) { [weak self] _ in
                guard let self else { return }
                self.casaRitiroDa = nil
                self.mostraAvvisoCasa()
            }
        }
    }

    /// CarPlay ha tolto un avviso. Se era quello di casa: chiuso a mano (non
    /// da un suo tasto), via anche dal telefono; scaduto, finito; tolto per
    /// far posto a un altro, torna quando l'altro finisce. In ogni caso lo
    /// schermo è cambiato: si riguarda se tocca all'avviso di casa.
    public func mapTemplate(
        _ mapTemplate: CPMapTemplate,
        didDismiss navigationAlert: CPNavigationAlert,
        dismissalContext: CPNavigationAlert.DismissalContext
    ) {
        if navigationAlert === inVolo { inVolo = nil }
        if navigationAlert === avvisoCasa {
            let dati = casaDati
            let tocco = casaTocco
            switch dismissalContext {
            case .userDismissed:
                casaFinita = true
                // Il tasto toccato lo dice da sé al telefono, e può dirlo un
                // attimo dopo: solo se non è stato un tasto, «chiudi».
                if let id = dati?.id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if !tocco.fatto { PonteAuto.shared.tastoCasa(id, "_chiudi") }
                    }
                }
            case .timeout:
                if let dati {
                    finisciCasa(dati)
                } else {
                    casaFinita = true
                }
            default:
                // Tolto per far posto a un altro avviso (`systemDismissed`):
                // tornerà.
                casaScalzato()
            }
            avvisoCasa = nil
            casaDati = nil
            casaConfermata = false
            casaSparitoDa = nil
        }
        mostraAvvisoCasa()
    }

    /// Con la mappa di GdANav dietro (il Dashboard, un'altra app sullo
    /// schermo dell'auto) CarPlay chiede se l'avviso va mostrato come
    /// notifica: sì per l'avviso di casa e per la strada proposta, che
    /// altrimenti non si vedrebbero; gli altri (un messaggio, una
    /// segnalazione) valgono solo sulla mappa.
    public func mapTemplate(
        _ mapTemplate: CPMapTemplate,
        shouldShowNotificationFor navigationAlert: CPNavigationAlert
    ) -> Bool {
        navigationAlert === avvisoCasa || navigationAlert === avvisoStrada
    }

    /// Il permesso della Musica chiesto dall'auto: l'invito del telefono qui
    /// non si vede. Da fermi, con la musica accesa, e una volta sola in tutto
    /// (`LettoreDiSistema.chiediDallAuto`): la finestra esce sul telefono. Se
    /// è già stato negato non si dice niente.
    private func chiediLaMusica() {
        let musica = LettoreDiSistema.shared
        guard musica.daChiedereDallAuto, PonteAuto.shared.daFermi else { return }
        musica.chiediDallAuto()
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
        metti(alert, in: t)
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
        metti(alert, in: t)
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
        metti(alert, in: t)
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

/// Se un avviso di casa è stato chiuso da un suo tasto: uno per ogni avviso
/// dato a CarPlay, così quello che arriva in ritardo da un avviso di prima
/// non si confonde con quello in vista.
private final class Tocco {
    var fatto = false
}
