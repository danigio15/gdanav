import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// La musica di casa **in auto**, sull'iPhone: le radio preferite della casa
/// (e i brani di Home Assistant raggiungibili da fuori) suonano qui, nel
/// telefono, quindi nelle casse dell'auto; non sui lettori di casa.
///
/// Suona `AVPlayer` (una coda: ⏮ ⏭ passano alla radio preferita prima o
/// dopo), con la sessione audio `.playback` (continua a schermo spento:
/// l'app che porta GdANav dichiara `audio` in `UIBackgroundModes`). Il brano
/// lo dice `MPNowPlayingInfoCenter` e i tasti li prende
/// `MPRemoteCommandCenter`: così compare in «In riproduzione» di CarPlay, sul
/// blocco schermo, e risponde ai tasti del volante e delle cuffie. Una radio
/// che dice cosa trasmette (i metadati ICY) lo mostra al posto di «In
/// diretta».
///
/// In CarPlay non c'è un elenco delle radio: un'app di navigazione mostra
/// solo i modelli della navigazione, e le radio si scelgono sul telefono. Il
/// brano lo mostra «In riproduzione»; ⏯ e ⏭ stanno nella barra del
/// navigatore (`GdanavCarPlay`, da [LettoreDiSistema]).
///
/// Solo indirizzi `https` (la regola di iOS, App Transport Security): la casa
/// manda solo quelli. Si tocca dal filo principale.
final class LettoreDiCasa: NSObject {
    static let shared = LettoreDiCasa()

    struct Flusso {
        let id: String
        let titolo: String
        let sotto: String
        let url: URL
        let immagine: UIImage?
        let immagineByte: Data?
    }

    private(set) var voci: [Flusso] = []
    private(set) var indice = 0
    private(set) var nome: String?
    private(set) var radio = false
    private(set) var suona = false
    private(set) var inOnda: String?
    private(set) var errore: String?

    var attivo: Bool { !voci.isEmpty }
    var attuale: Flusso? { voci.indices.contains(indice) ? voci[indice] : nil }

    private var lettore: AVPlayer?
    private var osservaStato: NSKeyValueObservation?
    private var osservaFine: NSObjectProtocol?
    private var metadati: AVPlayerItemMetadataOutput?
    private var ascoltatori: [UUID: () -> Void] = [:]
    private var comandiPronti = false

    @discardableResult
    func ascolta(_ f: @escaping () -> Void) -> UUID {
        let id = UUID()
        ascoltatori[id] = f
        return id
    }

    func smetti(_ id: UUID) {
        ascoltatori.removeValue(forKey: id)
    }

    private func avvisa() {
        aggiornaInRiproduzione()
        for f in ascoltatori.values { f() }
    }

    /// I flussi come li manda il telefono (`suonaFlussi`): `{voci: [{id,
    /// titolo, sotto, url, immagine}], da, nome, radio}`. Torna il messaggio
    /// se non c'è niente da suonare.
    func suona(argomenti: [String: Any]) -> String? {
        let grezze = argomenti["voci"] as? [[String: Any]] ?? []
        let flussi: [Flusso] = grezze.compactMap { v in
            guard let testo = v["url"] as? String, testo.hasPrefix("https://"), let url = URL(string: testo) else { return nil }
            let byte = (v["immagine"] as? FlutterStandardTypedData)?.data
            return Flusso(
                id: v["id"] as? String ?? testo,
                titolo: v["titolo"] as? String ?? "",
                sotto: v["sotto"] as? String ?? "",
                url: url,
                immagine: byte.flatMap { UIImage(data: $0) },
                immagineByte: byte
            )
        }
        guard !flussi.isEmpty else { return "Niente da suonare" }
        voci = flussi
        indice = min(max(argomenti["da"] as? Int ?? 0, 0), flussi.count - 1)
        nome = argomenti["nome"] as? String
        radio = argomenti["radio"] as? Bool ?? false
        preparaComandi()
        do {
            let sessione = AVAudioSession.sharedInstance()
            try sessione.setCategory(.playback, mode: .default)
            try sessione.setActive(true)
        } catch {
            // Senza la sessione suona lo stesso, ma si ferma a schermo spento.
        }
        carica()
        return nil
    }

    private func carica() {
        guard let f = attuale else { return }
        inOnda = nil
        errore = nil
        let elemento = AVPlayerItem(url: f.url)
        // Cosa trasmette la radio (ICY), quando lo dice.
        let uscita = AVPlayerItemMetadataOutput(identifiers: nil)
        uscita.setDelegate(self, queue: .main)
        elemento.add(uscita)
        metadati = uscita
        if let l = lettore {
            l.replaceCurrentItem(with: elemento)
        } else {
            lettore = AVPlayer(playerItem: elemento)
        }
        osservaStato = lettore?.observe(\.timeControlStatus, options: [.new]) { [weak self] l, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.suona = l.timeControlStatus != .paused
                if l.currentItem?.status == .failed {
                    self.errore = "«\(self.attuale?.titolo ?? "La radio")» non si sente adesso"
                    self.suona = false
                }
                self.avvisa()
            }
        }
        if let o = osservaFine { NotificationCenter.default.removeObserver(o) }
        // Un brano di una playlist finito: il prossimo.
        osservaFine = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: elemento, queue: .main
        ) { [weak self] _ in
            guard let self, !self.radio, self.indice + 1 < self.voci.count else { return }
            self.indice += 1
            self.carica()
        }
        lettore?.play()
        suona = true
        avvisa()
    }

    func comando(_ quale: String) {
        guard attivo else { return }
        switch quale {
        case "playPausa":
            if suona { lettore?.pause() } else if lettore?.currentItem == nil { carica() } else { lettore?.play() }
        case "successivo":
            guard voci.count > 1 else { return }
            indice = (indice + 1) % voci.count
            carica()
        case "precedente":
            guard voci.count > 1 else { return }
            indice = (indice - 1 + voci.count) % voci.count
            carica()
        default:
            break
        }
    }

    func ferma() {
        lettore?.pause()
        lettore?.replaceCurrentItem(with: nil)
        voci = []
        indice = 0
        suona = false
        inOnda = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        avvisa()
    }

    func erroreDetto() {
        errore = nil
    }

    /// I tasti del sistema: il volante, le cuffie, «In riproduzione».
    private func preparaComandi() {
        guard !comandiPronti else { return }
        comandiPronti = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            guard let self, self.attivo else { return .noActionableNowPlayingItem }
            if !self.suona { self.comando("playPausa") }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.attivo else { return .noActionableNowPlayingItem }
            if self.suona { self.comando("playPausa") }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.attivo else { return .noActionableNowPlayingItem }
            self.comando("playPausa")
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.voci.count > 1 else { return .noActionableNowPlayingItem }
            self.comando("successivo")
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.voci.count > 1 else { return .noActionableNowPlayingItem }
            self.comando("precedente")
            return .success
        }
    }

    /// Quello che mostrano «In riproduzione» di CarPlay e il blocco schermo.
    private func aggiornaInRiproduzione() {
        guard let f = attuale else { return }
        MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = voci.count > 1
        MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = voci.count > 1
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: f.titolo,
            MPMediaItemPropertyArtist: inOnda ?? nome ?? f.sotto,
            MPNowPlayingInfoPropertyIsLiveStream: radio,
            MPNowPlayingInfoPropertyPlaybackRate: suona ? 1.0 : 0.0,
        ]
        if radio { info[MPMediaItemPropertyAlbumTitle] = "Radio di casa" }
        if let img = f.immagine {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension LettoreDiCasa: AVPlayerItemMetadataOutputPushDelegate {
    func metadataOutput(
        _ output: AVPlayerItemMetadataOutput,
        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
        from track: AVPlayerItemTrack?
    ) {
        // «StreamTitle» delle radio: il primo titolo che non è la stazione.
        let titolo = groups.flatMap { $0.items }.first { $0.commonKey == .commonKeyTitle || $0.identifier?.rawValue == "icy/StreamTitle" }
        let testo = (titolo?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let nuovo = testo.isEmpty || testo == attuale?.titolo ? nil : testo
        guard nuovo != inOnda else { return }
        inOnda = nuovo
        avvisa()
    }
}
