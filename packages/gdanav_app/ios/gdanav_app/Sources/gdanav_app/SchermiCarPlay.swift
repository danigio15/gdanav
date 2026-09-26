import CarPlay
import UIKit

/// Gli schermi di CarPlay sopra la mappa: la copia di `SchermoMenu.kt`,
/// `SchermoCerca.kt` e `SchermoDestinazioni.kt`. Si rifanno da soli quando il
/// telefono manda novità.
enum SchermiCarPlay {
    // MARK: - Pezzi comuni

    static func icona(_ simbolo: String, _ colore: UIColor? = nil) -> UIImage? {
        let i = UIImage(systemName: simbolo, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold))
        guard let colore else { return i }
        return i?.withTintColor(colore, renderingMode: .alwaysOriginal)
    }

    static func riga(
        _ titolo: String,
        _ testo: String? = nil,
        icona: UIImage? = nil,
        sfoglia: Bool = false,
        azione: @escaping () -> Void
    ) -> CPListItem {
        let r = CPListItem(text: titolo, detailText: testo?.isEmpty == false ? testo : nil, image: icona)
        if sfoglia { r.accessoryType = .disclosureIndicator }
        r.handler = { _, fatto in
            azione()
            fatto()
        }
        return r
    }

    /// Su CarPlay non ci sono gli interruttori: la riga dice com'è e si tocca.
    static func interruttore(
        _ titolo: String,
        _ acceso: Bool,
        _ testo: String? = nil,
        icona: UIImage? = nil,
        cambia: @escaping (Bool) -> Void
    ) -> CPListItem {
        let r = CPListItem(
            text: titolo,
            detailText: [acceso ? "Attivo" : "Spento", testo].compactMap { $0 }.joined(separator: " · "),
            image: icona,
            accessoryImage: UIImage(systemName: acceso ? "checkmark.circle.fill" : "circle"),
            accessoryType: .none
        )
        r.handler = { _, fatto in
            cambia(!acceso)
            fatto()
        }
        return r
    }

    /// Quante righe l'auto mostra.
    static var righeMassime: Int { CPListTemplate.maximumItemCount }

    /// Un elenco che si rifà quando cambia qualcosa che mostra.
    static func elenco(
        _ titolo: String,
        vuoto: String = "Niente da mostrare",
        sezioni: @escaping () -> [CPListSection]
    ) -> CPListTemplate {
        let t = CPListTemplate(title: titolo, sections: sezioni())
        t.emptyViewTitleVariants = [vuoto]
        var versione = PonteAuto.shared.versioneModello
        var ascolto: UUID?
        ascolto = PonteAuto.shared.ascolta { [weak t] in
            guard let t else {
                if let a = ascolto { PonteAuto.shared.smetti(a) }
                return
            }
            guard PonteAuto.shared.versioneModello != versione else { return }
            versione = PonteAuto.shared.versioneModello
            t.updateSections(sezioni())
        }
        return t
    }

    /// Un elenco che arriva dopo (colonnine, distributori): prima «Cerco…».
    static func inArrivo(
        _ titolo: String,
        vuoto: String,
        carica: (@escaping ([CPListItem]) -> Void) -> Void
    ) -> CPListTemplate {
        let t = CPListTemplate(title: titolo, sections: [])
        t.emptyViewTitleVariants = ["Cerco…"]
        carica { [weak t] righe in
            guard let t else { return }
            t.emptyViewTitleVariants = [vuoto]
            t.updateSections([CPListSection(items: Array(righe.prefix(righeMassime)))])
        }
        return t
    }

    private static func vai(_ l: LuogoAuto, _ c: CPInterfaceController?) {
        PonteAuto.shared.vai(l)
        c?.popToRootTemplate(animated: true, completion: nil)
    }

    private static let blu = UIColor.systemBlue
    private static let verde = UIColor.systemGreen
    private static let giallo = UIColor.systemYellow

    // MARK: - I dati dell'auto e il viaggio

    /// Il testo del tasto in alto a sinistra: «79% · 259 km» (con la termica
    /// il meteo). `nil` se non c'è niente da dire.
    static func testoCruscotto() -> String? {
        let c = PonteAuto.shared.cruscotto
        if c.elettrica, let b = c.batteria {
            if let km = c.autonomiaKm { return "\(Int(b.rounded()))% · \(Int(km.rounded())) km" }
            return "\(Int(b.rounded()))%"
        }
        if let t = c.meteoTemperatura { return "\(c.meteoEmoji ?? "") \(Int(t.rounded()))°".trimmingCharacters(in: .whitespaces) }
        return nil
    }

    private static func righeViaggio() -> [CPListSection] {
        let p = PonteAuto.shared
        let c = p.cruscotto
        var auto: [CPListItem] = []
        if c.elettrica, let b = c.batteria {
            let km = c.autonomiaKm.map { "\(Int($0.rounded())) km di autonomia" + (c.autonomiaAuto ? " (dall'auto)" : " (stima)") }
            auto.append(CPListItem(text: "Batteria \(Int(b.rounded()))%", detailText: km, image: icona("battery.75", verde)))
        }
        if c.elettrica, let a = c.arrivoBatteria {
            auto.append(CPListItem(text: "Alla meta \(Int(a.rounded()))%", detailText: "La batteria quando arrivi", image: icona("flag.fill", a < 10 ? .systemRed : verde)))
        }
        if let nome = c.sostaNome {
            var sotto: [String] = []
            if let km = c.sostaKm { sotto.append("tra \(Int(km.rounded())) km") }
            if let b = c.sostaBatteria { sotto.append("arrivi col \(Int(b.rounded()))%") }
            auto.append(CPListItem(text: "Prossima sosta: \(nome)", detailText: sotto.joined(separator: " · "), image: icona("bolt.car.fill", verde)))
        }
        if let t = c.meteoTemperatura {
            auto.append(CPListItem(
                text: "\(c.meteoEmoji ?? "") \(Int(t.rounded()))°".trimmingCharacters(in: .whitespaces),
                detailText: c.meteoDove.map { "Meteo \($0)" } ?? "Meteo",
                image: icona("cloud.sun.fill")
            ))
        }
        if let v = c.velocita {
            let limite = c.limite.map { "limite \($0) km/h" }
            let oltre = c.limite.map { v > Double($0) + 3 } ?? false
            auto.append(CPListItem(text: "\(Int(v.rounded())) km/h", detailText: limite, image: icona("speedometer", oltre ? .systemRed : nil)))
        }
        var viaggio: [CPListItem] = []
        if let g = p.guida {
            let ora = DateFormatter()
            ora.dateFormat = "HH:mm"
            let minuti = max(Int((g.restantiS + 30) / 60), 1)
            let durata = minuti < 60 ? "\(minuti) min" : "\(minuti / 60) h \(String(format: "%02d", minuti % 60))"
            let d = ManovreCarPlay.distanza(g.restantiM)
            let km = d.unit == .kilometers
                ? String(format: "%.0f km", d.value)
                : "\(Int(d.value)) m"
            viaggio.append(CPListItem(text: "Arrivo \(ora.string(from: g.arrivo))", detailText: "\(durata) · \(km) · \(g.destinazione)", image: icona("flag.checkered")))
        }
        return [
            CPListSection(items: auto, header: "L'auto", sectionIndexTitle: nil),
            CPListSection(items: viaggio, header: "Il viaggio", sectionIndexTitle: nil),
        ].filter { !$0.items.isEmpty }
    }

    /// Il viaggio: tutto quello che su Android Auto sta sopra la mappa, in un
    /// elenco che si rifà da solo (al massimo ogni due secondi).
    static func viaggio() -> CPListTemplate {
        let t = CPListTemplate(title: "Il viaggio", sections: righeViaggio())
        t.emptyViewTitleVariants = ["Ancora nessun dato dall'auto"]
        var ultima = Date.distantPast
        var ascolto: UUID?
        ascolto = PonteAuto.shared.ascolta { [weak t] in
            guard let t else {
                if let a = ascolto { PonteAuto.shared.smetti(a) }
                return
            }
            guard Date().timeIntervalSince(ultima) >= 2 else { return }
            ultima = Date()
            t.updateSections(righeViaggio())
        }
        return t
    }

    // MARK: - Il menu

    /// Il menu dell'auto, come Waze: Casa e Lavoro (un tocco e si parte),
    /// preferiti e recenti, colonnine vicine, segnala, impostazioni.
    static func menu(_ c: CPInterfaceController, mappa: MappaCarPlay) -> CPListTemplate {
        elenco("Menu") { [weak c, weak mappa] in
            let p = PonteAuto.shared
            var vaiA: [CPListItem] = []
            // Dentro gdahome: la casa, che in guida non ha il suo tasto sulla mappa.
            if let casa = GdanavCarPlay.casa {
                vaiA.append(riga("La tua casa", "Comandi rapidi e dispositivi", icona: icona("house.fill", .systemOrange), sfoglia: true) {
                    guard let c else { return }
                    c.pushTemplate(casa(c), animated: true, completion: nil)
                })
            }
            if let casa = p.casa() {
                vaiA.append(riga("Casa", casa.nome, icona: icona("house.fill", blu)) { vai(casa, c) })
            } else {
                vaiA.append(riga("Casa", "Tocca per impostarla", icona: icona("house.fill", blu), sfoglia: true) {
                    guard let c else { return }
                    c.pushTemplate(cerca(c, imposta: "casa"), animated: true, completion: nil)
                })
            }
            if let lavoro = p.lavoro() {
                vaiA.append(riga("Lavoro", lavoro.nome, icona: icona("briefcase.fill", blu)) { vai(lavoro, c) })
            } else {
                vaiA.append(riga("Lavoro", "Tocca per impostarlo", icona: icona("briefcase.fill", blu), sfoglia: true) {
                    guard let c else { return }
                    c.pushTemplate(cerca(c, imposta: "lavoro"), animated: true, completion: nil)
                })
            }
            vaiA.append(riga("Preferiti e recenti", icona: icona("star.fill", giallo), sfoglia: true) {
                guard let c else { return }
                c.pushTemplate(destinazioni(c), animated: true, completion: nil)
            })
            // Elettrica: le colonnine; termica: i distributori.
            var intorno: [CPListItem] = []
            if p.cruscotto.elettrica {
                intorno.append(riga("Colonnine vicine", "Le rapide intorno a te", icona: icona("bolt.car.fill", verde), sfoglia: true) {
                    guard let c else { return }
                    c.pushTemplate(colonnine(c), animated: true, completion: nil)
                })
            } else {
                intorno.append(riga("Distributori vicini", "Coi prezzi di oggi", icona: icona("fuelpump.fill", verde), sfoglia: true) {
                    guard let c else { return }
                    c.pushTemplate(distributori(c), animated: true, completion: nil)
                })
            }
            intorno.append(riga("Segnala", "Polizia, incidente, traffico, pericolo…", icona: icona("exclamationmark.bubble.fill", giallo), sfoglia: true) {
                    guard let c else { return }
                    c.pushTemplate(segnala(c), animated: true, completion: nil)
                })
            let impostazioni = riga(
                "Impostazioni",
                "Batteria all'arrivo, vista 3D, voce, percorso",
                icona: icona("gearshape.fill"),
                sfoglia: true
            ) {
                guard let c, let mappa else { return }
                c.pushTemplate(SchermiCarPlay.impostazioni(c, mappa: mappa), animated: true, completion: nil)
            }
            return [
                CPListSection(items: vaiA, header: "Vai a", sectionIndexTitle: nil),
                CPListSection(items: intorno, header: "Intorno a te", sectionIndexTitle: nil),
                CPListSection(items: [impostazioni], header: "Impostazioni", sectionIndexTitle: nil),
            ]
        }
    }

    /// Vista, voce, opzioni del percorso, e dove sono Casa e Lavoro.
    static func impostazioni(_ c: CPInterfaceController, mappa: MappaCarPlay) -> CPListTemplate {
        elenco("Impostazioni") { [weak c, weak mappa] in
            let o = PonteAuto.shared.opzioni
            let elettrica = (o["elettrica"] as? Bool) != false
            let arrivo = numero(o["arrivo"]).map { Int($0) }
            var righe: [CPListItem] = []
            if elettrica {
                righe.append(riga(
                    "Batteria all'arrivo: \(arrivo.map { "\($0)%" } ?? "—")",
                    "Con quanta carica arrivare: le soste si ricalcolano",
                    icona: icona("battery.75", verde),
                    sfoglia: true
                ) {
                    guard let c else { return }
                    c.pushTemplate(SchermiCarPlay.arrivo(c), animated: true, completion: nil)
                })
            }
            righe.append(interruttore(
                "Vista 3D",
                mappa?.tridimensionale ?? true,
                "Spenta: mappa dall'alto, nord in su",
                icona: icona("map.fill", blu)
            ) { acceso in
                guard let mappa, acceso != mappa.tridimensionale else { return }
                mappa.alternaVista()
                // La vista non passa dal telefono: l'elenco si rifà da qui.
                PonteAuto.shared.rinfresca()
            })
            righe.append(interruttore(
                "Voce",
                (o["muto"] as? Bool) != true,
                "Le indicazioni e gli avvisi a voce",
                icona: icona("speaker.wave.2.fill", blu)
            ) { _ in PonteAuto.shared.alternaVoce() })
            righe.append(riga(
                "Percorso",
                "\(o["modo_nome"] as? String ?? "Veloce") · pedaggi, autostrade, traghetti",
                icona: icona("point.topleft.down.curvedto.point.bottomright.up", blu),
                sfoglia: true
            ) {
                guard let c else { return }
                c.pushTemplate(SchermiCarPlay.opzioni(), animated: true, completion: nil)
            })
            righe.append(riga("Imposta Casa", PonteAuto.shared.casa()?.nome ?? "Non ancora impostata", icona: icona("house.fill"), sfoglia: true) {
                guard let c else { return }
                c.pushTemplate(cerca(c, imposta: "casa"), animated: true, completion: nil)
            })
            righe.append(riga("Imposta Lavoro", PonteAuto.shared.lavoro()?.nome ?? "Non ancora impostato", icona: icona("briefcase.fill"), sfoglia: true) {
                guard let c else { return }
                c.pushTemplate(cerca(c, imposta: "lavoro"), animated: true, completion: nil)
            })
            return [CPListSection(items: righe)]
        }
    }

    /// Con quanta batteria arrivare alla meta (e alle soste): si ricalcola subito.
    static func arrivo(_ c: CPInterfaceController) -> CPListTemplate {
        elenco("Batteria all'arrivo") { [weak c] in
            let ora = numero(PonteAuto.shared.opzioni["arrivo"]).map { Int($0) }
            let righe = [5, 10, 15, 20, 25, 30].map { v in
                riga(v == ora ? "✓  \(v)%" : "\(v)%", v == ora ? "Scelta adesso" : nil) {
                    PonteAuto.shared.cambiaOpzione("arrivo", v)
                    c?.popTemplate(animated: true, completion: nil)
                }
            }
            return [CPListSection(items: righe)]
        }
    }

    /// Come calcolare il percorso: guida e cosa evitare. Vale anche per il viaggio in corso.
    static func opzioni() -> CPListTemplate {
        let modi = [("veloce", "Veloce"), ("equilibrato", "Equilibrato"), ("risparmio", "Risparmio")]
        return elenco("Percorso") {
            let o = PonteAuto.shared.opzioni
            let modo = o["modo"] as? String ?? "veloce"
            let i = modi.firstIndex { $0.0 == modo } ?? 0
            let p = PonteAuto.shared
            return [CPListSection(items: [
                riga("Guida: \(modi[i].1)", "Tocca per cambiare: veloce, equilibrato (120), risparmio (100)") {
                    p.cambiaOpzione("modo", modi[(i + 1) % modi.count].0)
                },
                interruttore("Evita pedaggi", (o["pedaggi"] as? Bool) == true) { p.cambiaOpzione("pedaggi", $0) },
                interruttore("Evita autostrade", (o["autostrade"] as? Bool) == true) { p.cambiaOpzione("autostrade", $0) },
                interruttore("Evita traghetti", (o["traghetti"] as? Bool) == true) { p.cambiaOpzione("traghetti", $0) },
                interruttore(
                    "Ricalcolo automatico",
                    (o["ricalcolo"] as? Bool) != false,
                    "Se il consumo cambia, le soste si rifanno"
                ) { p.cambiaOpzione("ricalcolo", $0) },
            ])]
        }
    }

    // MARK: - Dove andare

    /// «Dove andiamo?»: Cerca, poi Casa, Lavoro, i preferiti e i recenti.
    static func destinazioni(_ c: CPInterfaceController) -> CPListTemplate {
        elenco("Dove andiamo?") { [weak c] in
            var righe: [CPListItem] = [
                riga("Cerca un indirizzo o un posto", icona: icona("magnifyingglass", blu), sfoglia: true) {
                    guard let c else { return }
                    c.pushTemplate(cerca(c), animated: true, completion: nil)
                },
            ]
            // L'auto decide quante righe si vedono: una è già «Cerca».
            for l in PonteAuto.shared.luoghi.prefix(righeMassime - 1) {
                let titolo: String
                let simbolo: UIImage?
                switch l.tipo {
                case "casa":
                    titolo = "Casa"
                    simbolo = icona("house.fill", blu)
                case "lavoro":
                    titolo = "Lavoro"
                    simbolo = icona("briefcase.fill", blu)
                case "recente":
                    titolo = l.etichetta
                    simbolo = icona("clock.arrow.circlepath")
                default:
                    titolo = l.etichetta
                    simbolo = icona("star.fill", giallo)
                }
                let sotto = l.tipo == "recente" ? l.descrizione : l.nome
                righe.append(riga(titolo, sotto, icona: simbolo) { vai(l, c) })
            }
            return [CPListSection(items: righe)]
        }
    }

    /// La ricerca sull'auto: si scrive (o si detta) e si sceglie. Con `imposta`
    /// («casa» o «lavoro») il posto scelto si salva invece di partire.
    static func cerca(_ c: CPInterfaceController, imposta: String? = nil) -> CPSearchTemplate {
        let t = CPSearchTemplate()
        let d = Ricerca(controllore: c, imposta: imposta)
        t.delegate = d
        // Il delegato CarPlay lo tiene debole: lo tiene il modello.
        t.userInfo = d
        return t
    }

    /// Le colonnine rapide vicine, adatte alla tua auto; con Premium libere e occupate.
    static func colonnine(_ c: CPInterfaceController) -> CPListTemplate {
        inArrivo("Colonnine vicine", vuoto: "Nessuna colonnina rapida qui intorno") { [weak c] fatto in
            PonteAuto.shared.colonnine { trovate in
                fatto(trovate.map { l in
                    riga(l.nome, l.descrizione, icona: icona("bolt.car.fill", verde)) { vai(l, c) }
                })
            }
        }
    }

    /// Auto termica: i distributori vicini. In guida ci si passa e si prosegue.
    static func distributori(_ c: CPInterfaceController) -> CPListTemplate {
        inArrivo("Distributori vicini", vuoto: "Nessun distributore qui intorno") { [weak c] fatto in
            PonteAuto.shared.distributori { trovati in
                fatto(trovati.map { l in
                    riga(l.nome, l.descrizione, icona: icona("fuelpump.fill", verde)) {
                        PonteAuto.shared.passa(l)
                        c?.popToRootTemplate(animated: true, completion: nil)
                    }
                })
            }
        }
    }

    /// Segnala dove sei, come in Waze.
    static func segnala(_ c: CPInterfaceController) -> CPGridTemplate {
        let tipi = [
            ("polizia", "Polizia", "shield.lefthalf.filled"),
            ("incidente", "Incidente", "car.2.fill"),
            ("traffico", "Traffico", "car.rear.waves.up.fill"),
            ("pericolo", "Pericolo", "exclamationmark.triangle.fill"),
            ("lavori", "Lavori", "cone.fill"),
            ("autovelox", "Autovelox", "camera.fill"),
        ]
        let tasti = tipi.map { voce -> CPGridButton in
            let (tipo, nome, simbolo) = voce
            let immagine = PonteAuto.shared.immagini["segnala-\(tipo)"]
                ?? icona(simbolo, giallo)
                ?? icona("exclamationmark.triangle.fill", giallo)
                ?? UIImage()
            return CPGridButton(titleVariants: [nome], image: immagine) { [weak c] _ in
                PonteAuto.shared.segnala(tipo) { frase in
                    GdanavCarPlay.attuale?.avvisa(frase)
                }
                c?.popTemplate(animated: true, completion: nil)
            }
        }
        return CPGridTemplate(title: "Segnala", gridButtons: tasti)
    }
}

/// Il delegato della ricerca: aspetta che si smetta di scrivere, chiede
/// all'app e mostra i risultati.
private final class Ricerca: NSObject, CPSearchTemplateDelegate {
    weak var controllore: CPInterfaceController?
    let imposta: String?
    private var attesa: DispatchWorkItem?
    private var inAttesa: (([CPListItem]) -> Void)?
    private var ultima = 0
    private var ultimi: [CPListItem] = []
    private var luoghi: [ObjectIdentifier: LuogoAuto] = [:]

    init(controllore: CPInterfaceController, imposta: String?) {
        self.controllore = controllore
        self.imposta = imposta
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        attesa?.cancel()
        // La risposta rimasta in sospeso resta quella di prima.
        inAttesa?(ultimi)
        inAttesa = nil
        ultima += 1
        let questa = ultima
        guard searchText.trimmingCharacters(in: .whitespaces).count >= 3 else {
            return completionHandler([])
        }
        inAttesa = completionHandler
        // Una richiesta quando si smette di scrivere, non una per lettera.
        let lavoro = DispatchWorkItem { [weak self] in
            PonteAuto.shared.cerca(searchText) { trovati in
                guard let self, questa == self.ultima, let fine = self.inAttesa else { return }
                self.inAttesa = nil
                self.luoghi.removeAll()
                self.ultimi = trovati.prefix(SchermiCarPlay.righeMassime).map { l in
                    let r = CPListItem(text: l.nome, detailText: l.descrizione.isEmpty ? nil : l.descrizione)
                    self.luoghi[ObjectIdentifier(r)] = l
                    return r
                }
                fine(self.ultimi)
            }
        }
        attesa = lavoro
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: lavoro)
    }

    func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let l = luoghi[ObjectIdentifier(item)] else { return }
        guard let tipo = imposta else {
            PonteAuto.shared.vai(l)
            controllore?.popToRootTemplate(animated: true, completion: nil)
            return
        }
        PonteAuto.shared.imposta(tipo, l) { [weak self] fatto in
            let nome = tipo == "casa" ? "Casa" : "Lavoro"
            self?.controllore?.popTemplate(animated: true, completion: nil)
            GdanavCarPlay.attuale?.avvisa(fatto ? "\(nome) salvato: \(l.nome)" : "Non si è potuto salvare \(nome)")
        }
    }

    func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {}
}
