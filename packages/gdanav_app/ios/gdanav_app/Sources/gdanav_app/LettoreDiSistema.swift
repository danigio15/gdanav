import Flutter
import MediaPlayer
import UIKit

/// La musica in guida sull'iPhone: il lettore di sistema, cioè la Musica di
/// Apple (`MPMusicPlayerController.systemMusicPlayer`). Un'app non può vedere
/// né comandare i lettori delle altre (Spotify, YouTube Music): quelli
/// arriveranno coi loro SDK, dietro la stessa interfaccia Dart
/// (`LettoreMusicale`, `lib/componenti/mini_lettore.dart`).
///
/// Per leggere il brano serve il permesso della libreria musicale
/// (`NSAppleMusicUsageDescription` nell'Info.plist dell'app che ospita
/// GdANav). Senza, [permesso] è falso e il telefono mostra l'invito una volta
/// sola. `MPNowPlayingInfoCenter` qui non serve: dice solo quello che suona
/// questa app, non le altre.
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
    private(set) var brano: Brano?

    /// Se CarPlay deve mostrare i comandi: accesa, col permesso, e un brano.
    var daMostrare: Bool { acceso && permesso && brano != nil }

    private let lettore = MPMusicPlayerController.systemMusicPlayer
    private var osservatori: [NSObjectProtocol] = []
    private var canali: [FlutterMethodChannel] = []
    private var vogliono = Set<ObjectIdentifier>()
    private var ascoltatori: [UUID: () -> Void] = [:]
    private var copertinaPng: Data?
    private weak var copertinaDi: UIImage?

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
                self.vogliono.remove(ObjectIdentifier(c))
                if self.vogliono.isEmpty { self.accendi(false) }
                risposta(self.stato())
            case "chiediPermesso":
                self.chiediPermesso()
                risposta(self.stato())
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
        acceso = si
        permesso = MPMediaLibrary.authorizationStatus() == .authorized
        for o in osservaIlLettore { NotificationCenter.default.removeObserver(o) }
        osservaIlLettore = []
        guard si, permesso else {
            brano = nil
            avvisa()
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
            MPMediaLibrary.requestAuthorization { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.accendi(self.acceso)
                }
            }
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            accendi(acceso)
        }
    }

    func comando(_ quale: String) {
        guard permesso else { return }
        switch quale {
        case "precedente": lettore.skipToPreviousItem()
        case "successivo": lettore.skipToNextItem()
        case "playPausa":
            if lettore.playbackState == .playing { lettore.pause() } else { lettore.play() }
        default: break
        }
    }

    private func leggi() {
        guard let item = lettore.nowPlayingItem else {
            brano = nil
            avvisa()
            return
        }
        brano = Brano(
            titolo: item.title ?? "",
            artista: item.artist ?? item.albumArtist ?? "",
            suona: lettore.playbackState == .playing,
            copertina: item.artwork?.image(at: CGSize(width: 256, height: 256))
        )
        avvisa()
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
            if let item = lettore.nowPlayingItem {
                s["durata_ms"] = Int(item.playbackDuration * 1000)
            }
            s["posizione_ms"] = Int(lettore.currentPlaybackTime * 1000)
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
