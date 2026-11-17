import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// La musica in guida sull'iPhone: il lettore di sistema, cioè la Musica di
/// Apple (`MPMusicPlayerController.systemMusicPlayer`). Un'app non può vedere
/// né comandare i lettori delle altre (Spotify, YouTube Music): quelli
/// arriveranno coi loro SDK, dietro la stessa interfaccia Dart
/// (`LettoreMusicale`, `lib/componenti/mini_lettore.dart`).
///
/// Per questo il brano e i tasti ci sono **solo quando è davvero la Musica
/// di Apple quella in ascolto**: suona adesso, oppure è stata messa in pausa
/// da questi tasti (e da allora nessun'altra app ha preso il suono). Il
/// lettore di sistema ricorda l'ultimo brano anche da fermo, per giorni:
/// mostrarlo con un ▶ mentre suona Spotify voleva dire far partire un brano
/// vecchio e zittire Spotify. Con un'altra app in ascolto qui non c'è
/// niente: il brano lo mostra la scheda «In riproduzione» di CarPlay.
///
/// Per leggere il brano serve il permesso della libreria musicale
/// (`NSAppleMusicUsageDescription` nell'Info.plist dell'app che ospita
/// GdANav). Senza, [permesso] è falso e il telefono mostra l'invito una volta
/// sola; dallo schermo dell'auto lo si chiede una volta sola in tutto
/// ([chiediDallAuto]). `MPNowPlayingInfoCenter` qui non serve: dice solo
/// quello che suona questa app, non le altre.
///
/// Lo usano il telefono (canale `gdanav/musica`, come su Android) e CarPlay
/// (`GdanavCarPlay`: ⏯ e ⏭ nella barra; il brano lo mostra la scheda «In
/// riproduzione» di CarPlay, non la mappa).
final class LettoreDiSistema {
    static let shared = LettoreDiSistema()

    struct Brano {
        let titolo: String
        let artista: String
        let suona: Bool
        let copertina: UIImage?
    }

    private(set) var acceso = false
    private(set) var permesso = false

    /// Il brano della Musica di Apple in ascolto; `nil` se non suona lei (e
    /// non l'abbiamo messa in pausa da qui), anche se ricorda un brano.
    private(set) var brano: Brano?

    /// Se c'è un brano da dire, e i tasti per comandarlo (sul telefono e
    /// nella barra di CarPlay): accesa, col permesso, e la Musica di Apple
    /// davvero in ascolto.
    var daMostrare: Bool { acceso && permesso && brano != nil }

    private let lettore = MPMusicPlayerController.systemMusicPlayer
    private var osservatori: [NSObjectProtocol] = []
    private var canali: [FlutterMethodChannel] = []
    private var vogliono = Set<ObjectIdentifier>()
    private var ascoltatori: [UUID: () -> Void] = [:]
    private var copertinaPng: Data?
    private weak var copertinaDi: UIImage?

    /// La Musica è stata messa in pausa da questi tasti, e quando (il tempo
    /// di sistema): finché resta così, il brano e ▶ restano.
    private var inPausaDaQui = false
    private var inPausaDa: TimeInterval = 0

    /// Da quando la musica è accesa (il tempo di sistema).
    private var accesoDa: TimeInterval = 0

    /// Dall'auto il permesso non si chiede (più): già chiesto una volta, già
    /// deciso, o l'invito sul telefono è stato visto.
    private var dallAutoNo = false

    /// Dopo una pausa fatta da qui, per un attimo il lettore dice ancora
    /// «suona» e il suono della Musica non si è ancora spento: prima di
    /// questo tempo non si tirano conclusioni.
    private static let assestamento: TimeInterval = 2

    /// Accesa la musica, quanto si aspetta prima di chiedere il permesso
    /// dall'auto: il telefono fa in tempo a dire se l'invito era già stato
    /// visto (`invitoVisto`, che arriva subito dopo `avvia`).
    private static let attesaPrimaDiChiedere: TimeInterval = 5

    /// Ricordato fra un avvio e l'altro: il permesso è già stato chiesto (o
    /// l'invito rifiutato), dall'auto non lo si chiede più.
    private static let chiaveChiesto = "gdanav.musica.permesso_chiesto"

    private static func adesso() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func collega(registrar: FlutterPluginRegistrar) {
        let c = FlutterMethodChannel(name: "gdanav/musica", binaryMessenger: registrar.messenger())
        canali.append(c)
        c.setMethodCallHandler { [weak self, weak c] chiamata, risposta in
            guard let self, let c else { return risposta(nil) }
            switch chiamata.method {
            case "avvia":
                self.vogliono.insert(ObjectIdentifier(c))
                self.accendi(true)
                risposta(self.stato())
            case "ferma":
                // «Musica nel navigatore» spenta: dall'auto il permesso non
                // lo si chiede più, nemmeno riaccendendola (come su Android).
                self.maiPiuDallAuto()
                self.vogliono.remove(ObjectIdentifier(c))
                if self.vogliono.isEmpty { self.accendi(false) }
                risposta(self.stato())
            case "chiediPermesso":
                self.chiediPermesso()
                risposta(self.stato())
            // L'invito sul telefono è stato visto o chiuso («Non ora»):
            // dall'auto non lo si chiede più.
            case "invitoVisto":
                self.maiPiuDallAuto()
                risposta(nil)
            case "comando":
                self.comando(chiamata.arguments as? String ?? "")
                risposta(nil)
            default:
                risposta(FlutterMethodNotImplemented)
            }
        }
        // Tornando dalle Impostazioni il permesso può essere cambiato.
        osservatori.append(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.acceso else { return }
                self.accendi(true)
            }
        )
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

    private var osservaIlLettore: [NSObjectProtocol] = []

    private func accendi(_ si: Bool) {
        let appenaAccesa = si && !acceso
        if appenaAccesa { accesoDa = LettoreDiSistema.adesso() }
        acceso = si
        permesso = MPMediaLibrary.authorizationStatus() == .authorized
        for o in osservaIlLettore { NotificationCenter.default.removeObserver(o) }
        osservaIlLettore = []
        guard si, permesso else {
            brano = nil
            inPausaDaQui = false
            avvisa()
            // Appena accesa e senza permesso: fra poco, se l'auto è lì e si
            // è fermi, lo può chiedere (`GdanavCarPlay` guarda a ogni
            // novità; questa è la novità, se non ne arrivano altre).
            if appenaAccesa, !dallAutoNo {
                let fra = LettoreDiSistema.attesaPrimaDiChiedere + 0.5
                DispatchQueue.main.asyncAfter(deadline: .now() + fra) { [weak self] in
                    guard let self, self.daChiedereDallAuto else { return }
                    for f in self.ascoltatori.values { f() }
                }
            }
            return
        }
        lettore.beginGeneratingPlaybackNotifications()
        let centro = NotificationCenter.default
        for nome in [
            Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
            Notification.Name.MPMusicPlayerControllerPlaybackStateDidChange,
        ] {
            osservaIlLettore.append(
                centro.addObserver(forName: nome, object: lettore, queue: .main) { [weak self] _ in self?.leggi() }
            )
        }
        leggi()
    }

    /// La prima volta la finestra del sistema; se è già stato detto di no,
    /// le Impostazioni dell'app (l'iPhone non lo richiede due volte).
    func chiediPermesso() {
        switch MPMediaLibrary.authorizationStatus() {
        case .notDetermined:
            // Chiesto dal telefono: dall'auto non lo si richiede.
            maiPiuDallAuto()
            chiediAlSistema()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            accendi(acceso)
        }
    }

    private func chiediAlSistema() {
        MPMediaLibrary.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.accendi(self.acceso)
            }
        }
    }

    /// Se dallo schermo dell'auto c'è da chiedere il permesso: la musica è
    /// accesa da un po', il permesso manca, e non è già stato chiesto.
    var daChiedereDallAuto: Bool {
        acceso && !permesso && !dallAutoNo
            && LettoreDiSistema.adesso() - accesoDa >= LettoreDiSistema.attesaPrimaDiChiedere
    }

    /// Il permesso chiesto dallo schermo dell'auto (CarPlay collegato, da
    /// fermi), dove l'invito del telefono non si vede: **una volta sola in
    /// tutto**, e solo se l'iPhone non l'ha ancora mai chiesto (la finestra
    /// esce sul telefono). Se è già stato negato non si insiste: resta la
    /// voce nelle impostazioni del navigatore.
    func chiediDallAuto() {
        guard daChiedereDallAuto else { return }
        dallAutoNo = true
        let preferenze = UserDefaults.standard
        guard MPMediaLibrary.authorizationStatus() == .notDetermined,
              !preferenze.bool(forKey: LettoreDiSistema.chiaveChiesto)
        else { return }
        preferenze.set(true, forKey: LettoreDiSistema.chiaveChiesto)
        chiediAlSistema()
    }

    private func maiPiuDallAuto() {
        dallAutoNo = true
        UserDefaults.standard.set(true, forKey: LettoreDiSistema.chiaveChiesto)
    }

    /// Se è la Musica di Apple quella in ascolto: `true` suona, `false` è in
    /// pausa perché l'abbiamo fermata da qui, `nil` non è lei (ferma per
    /// conto suo, o sta suonando un'altra app).
    private func inAscolto() -> Bool? {
        let ora = LettoreDiSistema.adesso()
        switch lettore.playbackState {
        case .playing, .seekingForward, .seekingBackward:
            // Subito dopo la nostra pausa il lettore può dire ancora «suona».
            if inPausaDaQui, ora - inPausaDa > LettoreDiSistema.assestamento { inPausaDaQui = false }
            return true
        case .paused, .interrupted:
            guard inPausaDaQui else { return nil }
            // Nel frattempo ha cominciato a suonare un'altra app (per noi lo
            // è anche la Musica, ma quella è in pausa): il ▶ la zittirebbe.
            if ora - inPausaDa > LettoreDiSistema.assestamento, AVAudioSession.sharedInstance().isOtherAudioPlaying {
                inPausaDaQui = false
                return nil
            }
            return false
        default:
            inPausaDaQui = false
            return nil
        }
    }

    func comando(_ quale: String) {
        guard permesso else { return }
        // I tasti valgono solo per la Musica di Apple in ascolto: mai un ▶
        // che fa partire un brano vecchio sopra un'altra app che suona.
        guard inAscolto() != nil, lettore.nowPlayingItem != nil else {
            leggi()
            return
        }
        switch quale {
        case "precedente": lettore.skipToPreviousItem()
        case "successivo": lettore.skipToNextItem()
        case "playPausa":
            if lettore.playbackState == .playing {
                inPausaDaQui = true
                inPausaDa = LettoreDiSistema.adesso()
                lettore.pause()
            } else {
                lettore.play()
            }
        default: break
        }
    }

    private func leggi() {
        guard let suona = inAscolto(), let item = lettore.nowPlayingItem else {
            brano = nil
            avvisa()
            return
        }
        brano = Brano(
            titolo: item.title ?? "",
            artista: item.artist ?? item.albumArtist ?? "",
            suona: suona,
            copertina: item.artwork?.image(at: CGSize(width: 256, height: 256))
        )
        avvisa()
    }

    /// Un tempo in secondi come millisecondi interi; `nil` se non è un tempo
    /// vero. Il lettore di sistema a volte dà «non un numero» (una radio, il
    /// cambio di brano), e in Swift `Int(Double.nan)` chiude l'app.
    static func millisecondi(_ secondi: TimeInterval) -> Int? {
        guard secondi.isFinite, secondi >= 0, secondi < 1_000_000_000 else { return nil }
        return Int(secondi * 1000)
    }

    /// Lo stato per il telefono, come lo legge `LettoreDelTelefono.leggi`.
    private func stato() -> [String: Any] {
        let b = brano
        if b?.copertina !== copertinaDi {
            copertinaDi = b?.copertina
            copertinaPng = b?.copertina?.pngData()
        }
        var s: [String: Any] = [
            "permesso": permesso,
            "suona": b?.suona == true,
        ]
        if let b {
            s["app"] = "Musica"
            s["titolo"] = b.titolo
            s["artista"] = b.artista
            if let png = copertinaPng { s["copertina"] = FlutterStandardTypedData(bytes: png) }
            if let item = lettore.nowPlayingItem, let ms = LettoreDiSistema.millisecondi(item.playbackDuration) {
                s["durata_ms"] = ms
            }
            if let ms = LettoreDiSistema.millisecondi(lettore.currentPlaybackTime) { s["posizione_ms"] = ms }
        }
        return s
    }

    private func avvisa() {
        let s = stato()
        for c in canali where vogliono.contains(ObjectIdentifier(c)) {
            c.invokeMethod("stato", arguments: s)
        }
        for f in ascoltatori.values { f() }
    }
}
