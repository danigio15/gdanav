import Flutter
import UIKit

/// Un posto da scegliere in auto: Casa, Lavoro, un preferito, un recente o un risultato.
struct LuogoAuto {
    let etichetta: String
    let nome: String
    let descrizione: String
    let lat: Double
    let lon: Double
    let tipo: String

    var comeMappa: [String: Any] {
        ["nome": nome, "descrizione": descrizione, "lat": lat, "lon": lon]
    }

    init?(_ m: [String: Any], tipo predefinito: String = "risultato") {
        guard let lat = numero(m["lat"]), let lon = numero(m["lon"]), let nome = m["nome"] as? String else {
            return nil
        }
        self.nome = nome
        self.lat = lat
        self.lon = lon
        etichetta = m["etichetta"] as? String ?? nome
        descrizione = m["descrizione"] as? String ?? ""
        tipo = m["tipo"] as? String ?? predefinito
    }
}

/// Una corsia prima dello svincolo: le frecce, se è giusta, quale seguire.
struct CorsiaAuto {
    let direzioni: [String]
    let giusta: Bool
    let consigliata: String?
}

/// La prossima manovra e il viaggio, mentre si guida.
struct GuidaAuto {
    let tipo: Int
    let distanzaM: Double
    let strada: String
    let istruzione: String
    let restantiM: Double
    let restantiS: Double
    let arrivo: Date
    let destinazione: String
    let destinazioneLat: Double?
    let destinazioneLon: Double?
    let arrivoBatteria: Double?
    let uscita: String
    let verso: String
    let rotonda: Int?
    let corsie: [CorsiaAuto]
    let dopoTipo: Int?
    let dopoStrada: String
    /// La vista dello svincolo da mostrare, se pronta (vedi `svincoli`).
    let svincolo: Int?
}

/// Batteria, velocità e limite, arrivo, sosta, meteo.
struct CruscottoAuto {
    /// Auto termica: niente batteria né colonnine.
    var elettrica = true
    var batteria: Double?
    var autonomiaKm: Double?
    var velocita: Double?
    var limite: Int?
    var arrivoBatteria: Double?
    var sostaNome: String?
    var sostaKm: Double?
    var sostaBatteria: Double?
    var meteoTemperatura: Double?
    var meteoEmoji: String?
    var meteoDove: String?
}

/// La segnalazione che si avvicina, e quella appena passata.
struct AvvisoAuto {
    var titolo: String?
    var tipo: String?
    var metri: Double?
    var limite: Int?
    var ancoraId: String?
    var ancoraTesto: String?
}

func numero(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

/// Quello che il telefono sa e CarPlay mostra: la copia di `PonteAuto.kt`.
/// L'app Flutter lo aggiorna sul canale `gdanav/schermo_auto`, e dall'auto
/// tornano la ricerca, la meta scelta, le opzioni, le segnalazioni e «fine».
/// Tutto sul filo principale, come i canali di Flutter.
final class PonteAuto {
    static let shared = PonteAuto()

    var stileChiaro: String?
    var stileScuro: String?

    /// I GeoJSON delle sorgenti dello stile, come li usa la mappa del telefono.
    private(set) var sorgenti: [String: String] = [:]

    /// Dove sei: centro della mappa, e la rotta in gradi.
    private(set) var qui: (lat: Double, lon: Double)?
    private(set) var rotta = 0.0

    /// La rotta del segnaposto (la mappa guarda un po' avanti) e la sua immagine.
    private(set) var rottaIo = 0.0
    private(set) var icona = "freccia"
    private(set) var guida: GuidaAuto?
    private(set) var luoghi: [LuogoAuto] = []
    private(set) var cruscotto = CruscottoAuto()
    private(set) var avviso = AvvisoAuto()

    /// Le opzioni del percorso e la voce, per il menu.
    private(set) var opzioni: [String: Any] = [:]

    /// Le viste degli svincoli, disegnate dall'app: le ultime, per manovra.
    private(set) var svincoli: [Int: UIImage] = [:]

    /// Le icone delle segnalazioni e dei punti, disegnate dall'app.
    private(set) var immagini: [String: UIImage] = [:]

    /// Cosa dire quando non si guida: «Calcolo il percorso…», o cosa non va.
    private(set) var messaggio: String?

    /// Cresce quando cambia qualcosa dei modelli di CarPlay (manovra, messaggi,
    /// luoghi, opzioni): il resto (posizione, cruscotto) ridisegna solo la mappa.
    private(set) var versioneModello = 0

    /// gdanav Premium: l'app lo dice, l'auto lo ricorda anche a telefono spento.
    var premium: Bool { UserDefaults.standard.bool(forKey: "gdanav.premium") }

    func casa() -> LuogoAuto? { luoghi.first { $0.tipo == "casa" } }
    func lavoro() -> LuogoAuto? { luoghi.first { $0.tipo == "lavoro" } }

    private var canale: FlutterMethodChannel?
    private var ascoltatori: [UUID: () -> Void] = [:]
    private var avvisoInArrivo = false

    private static let soloMappa: Set<String> = ["posizione", "sorgenti", "cruscotto", "immagini", "stili"]

    /// Le icone disegnate dall'app sono a 3×, come sul telefono.
    private static let scalaImmagini: CGFloat = 3

    func collega(registrar: FlutterPluginRegistrar) {
        let c = FlutterMethodChannel(name: "gdanav/schermo_auto", binaryMessenger: registrar.messenger())
        c.setMethodCallHandler { [weak self] call, risultato in
            self?.gestisci(call)
            risultato(nil)
        }
        canale = c
    }

    @discardableResult
    func ascolta(_ f: @escaping () -> Void) -> UUID {
        let id = UUID()
        ascoltatori[id] = f
        return id
    }

    func smetti(_ id: UUID) {
        ascoltatori.removeValue(forKey: id)
    }

    private func gestisci(_ call: FlutterMethodCall) {
        let a = call.arguments as? [String: Any] ?? [:]
        let prima = avviso.ancoraId
        switch call.method {
        case "stili":
            stileChiaro = a["chiaro"] as? String
            stileScuro = a["scuro"] as? String
        case "sorgenti":
            if let dati = a["dati"] as? [String: String] {
                sorgenti.merge(dati) { _, nuovo in nuovo }
            }
        case "posizione":
            if let lat = numero(a["lat"]), let lon = numero(a["lon"]) {
                qui = (lat, lon)
            } else {
                qui = nil
            }
            rotta = numero(a["rotta"]) ?? 0
            rottaIo = numero(a["rotta_io"]) ?? rotta
            if let i = a["icona"] as? String { icona = i }
        case "luoghi":
            luoghi = (a["elenco"] as? [[String: Any]] ?? []).compactMap { LuogoAuto($0) }
        case "messaggio":
            messaggio = a["testo"] as? String
        case "cruscotto":
            cruscotto = CruscottoAuto(
                elettrica: (a["elettrica"] as? Bool) != false,
                batteria: numero(a["batteria"]),
                autonomiaKm: numero(a["autonomia_km"]),
                velocita: numero(a["velocita"]),
                limite: numero(a["limite"]).map { Int($0) },
                arrivoBatteria: numero(a["arrivo_batteria"]),
                sostaNome: a["sosta_nome"] as? String,
                sostaKm: numero(a["sosta_km"]),
                sostaBatteria: numero(a["sosta_batteria"]),
                meteoTemperatura: numero(a["meteo_temperatura"]),
                meteoEmoji: a["meteo_emoji"] as? String,
                meteoDove: a["meteo_dove"] as? String
            )
        case "avviso":
            let prossimo = AvvisoAuto(
                titolo: a["titolo"] as? String,
                tipo: a["tipo"] as? String,
                metri: numero(a["metri"]),
                limite: numero(a["limite"]).map { Int($0) },
                ancoraId: a["ancora_id"] as? String,
                ancoraTesto: a["ancora_testo"] as? String
            )
            // Un avviso nuovo (non la stessa segnalazione un po' più vicina):
            // CarPlay lo mostra come avviso di navigazione.
            avvisoInArrivo = prossimo.titolo != nil && (prossimo.tipo != avviso.tipo || avviso.titolo == nil)
            avviso = prossimo
        case "opzioni":
            opzioni = a
        case "svincolo":
            if let id = numero(a["id"]).map({ Int($0) }),
               let png = (a["png"] as? FlutterStandardTypedData)?.data,
               let immagine = UIImage(data: png, scale: 2)
            {
                // Solo le ultime: una vista pesa.
                let tenute = svincoli.keys.sorted().suffix(2)
                svincoli = svincoli.filter { tenute.contains($0.key) }
                svincoli[id] = immagine
            }
        case "immagini":
            for (nome, dati) in a["png"] as? [String: FlutterStandardTypedData] ?? [:] {
                if let immagine = UIImage(data: dati.data, scale: PonteAuto.scalaImmagini) {
                    immagini[nome] = immagine
                }
            }
        case "premium":
            UserDefaults.standard.set((a["sbloccato"] as? Bool) == true, forKey: "gdanav.premium")
        case "guida":
            guida = (a["attiva"] as? Bool) == true ? guidaDa(a) : nil
        default:
            return
        }
        if !PonteAuto.soloMappa.contains(call.method) && (call.method != "avviso" || avviso.ancoraId != prima) {
            versioneModello += 1
        }
        avvisa()
    }

    private func guidaDa(_ a: [String: Any]) -> GuidaAuto {
        let arrivoMs = numero(a["arrivo"]) ?? Date().timeIntervalSince1970 * 1000
        return GuidaAuto(
            tipo: numero(a["tipo"]).map { Int($0) } ?? 8,
            distanzaM: numero(a["distanza"]) ?? 0,
            strada: a["strada"] as? String ?? "",
            istruzione: a["istruzione"] as? String ?? "",
            restantiM: numero(a["restanti"]) ?? 0,
            restantiS: numero(a["secondi"]) ?? 0,
            arrivo: Date(timeIntervalSince1970: arrivoMs / 1000),
            destinazione: a["destinazione"] as? String ?? "",
            destinazioneLat: numero(a["destinazione_lat"]),
            destinazioneLon: numero(a["destinazione_lon"]),
            arrivoBatteria: numero(a["arrivo_batteria"]),
            uscita: a["uscita"] as? String ?? "",
            verso: a["verso"] as? String ?? "",
            rotonda: numero(a["rotonda"]).map { Int($0) },
            corsie: (a["corsie"] as? [[String: Any]] ?? []).map { c in
                CorsiaAuto(
                    direzioni: (c["direzioni"] as? [Any] ?? []).map { "\($0)" },
                    giusta: (c["giusta"] as? Bool) == true,
                    consigliata: c["consigliata"] as? String
                )
            },
            dopoTipo: numero(a["dopo_tipo"]).map { Int($0) },
            dopoStrada: a["dopo_strada"] as? String ?? "",
            svincolo: numero(a["svincolo"]).map { Int($0) }
        )
    }

    /// L'avviso nuovo da mostrare, una volta sola.
    func prendiAvvisoNuovo() -> AvvisoAuto? {
        guard avvisoInArrivo else { return nil }
        avvisoInArrivo = false
        return avviso
    }

    /// Qualcosa è cambiato sull'auto senza passare dal telefono (la vista 3D):
    /// gli schermi aperti si rifanno.
    func rinfresca() {
        versioneModello += 1
        avvisa()
    }

    private func avvisa() {
        for f in ascoltatori.values { f() }
    }

    // MARK: - Le domande all'app

    /// Una domanda all'app, con la risposta sul filo principale.
    func chiedi(_ metodo: String, _ argomenti: Any? = nil, risposta: @escaping (Any?) -> Void = { _ in }) {
        guard let c = canale else { return risposta(nil) }
        c.invokeMethod(metodo, arguments: argomenti) { r in
            if r is FlutterError || (r as? NSObject) === FlutterMethodNotImplemented {
                risposta(nil)
            } else {
                risposta(r)
            }
        }
    }

    /// La ricerca fatta sull'auto, con Photon come sul telefono.
    func cerca(_ testo: String, risultati: @escaping ([LuogoAuto]) -> Void) {
        chiedi("cerca", ["testo": testo]) { r in
            risultati((r as? [[String: Any]] ?? []).compactMap { LuogoAuto($0) })
        }
    }

    /// Una meta scelta sull'auto: il telefono calcola e parte la guida.
    func vai(_ l: LuogoAuto) {
        messaggio = "Calcolo il percorso per \(l.etichetta)…"
        versioneModello += 1
        avvisa()
        chiedi("vai", l.comeMappa)
    }

    /// In guida si passa dal distributore e poi si prosegue; fermi, ci si va.
    func passa(_ l: LuogoAuto) {
        messaggio = "Passo da \(l.etichetta)…"
        versioneModello += 1
        avvisa()
        chiedi("passa", l.comeMappa)
    }

    /// Casa o Lavoro scelti dalla ricerca sull'auto.
    func imposta(_ tipo: String, _ l: LuogoAuto, fatto: @escaping (Bool) -> Void) {
        chiedi("imposta", ["tipo": tipo, "luogo": l.comeMappa]) { fatto(($0 as? Bool) == true) }
    }

    func cambiaOpzione(_ chiave: String, _ valore: Any) {
        chiedi("opzioni", [chiave: valore])
    }

    func alternaVoce() {
        chiedi("voce")
    }

    /// Segnala dove sei; la risposta è la frase da mostrare.
    func segnala(_ tipo: String, risposta: @escaping (String) -> Void) {
        chiedi("segnala", ["tipo": tipo]) { risposta($0 as? String ?? "Non è partita.") }
    }

    func ancora(_ id: String, si: Bool) {
        chiedi("ancora", ["id": id, "si": si])
    }

    /// Le colonnine rapide vicine, come luoghi da raggiungere.
    func colonnine(risultati: @escaping ([LuogoAuto]) -> Void) {
        chiedi("colonnine") { r in
            risultati((r as? [[String: Any]] ?? []).compactMap { LuogoAuto($0, tipo: "colonnina") })
        }
    }

    /// Auto termica: i distributori intorno.
    func distributori(risultati: @escaping ([LuogoAuto]) -> Void) {
        chiedi("distributori") { r in
            risultati((r as? [[String: Any]] ?? []).compactMap { LuogoAuto($0, tipo: "distributore") })
        }
    }

    /// L'auto ha chiesto di finire la guida.
    func fermaDallAuto() {
        chiedi("ferma")
    }
}
