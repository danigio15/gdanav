/// Il mini-lettore musicale, come in Waze, in guida e a mappa libera: la
/// copertina, il titolo, l'artista e ⏮ ⏯ ⏭, in un riquadro basso (in guida
/// sopra la barra dell'arrivo, a mappa libera sopra il pannello di partenza),
/// che non copre la manovra e si richiude in un bottone tondo.
///
/// Chi suona lo dice un [LettoreMusicale]:
///
/// - **Android, qualsiasi app** (Spotify, YouTube Music, Amazon Music…):
///   [LettoreDelTelefono], che dall'altra parte del canale `gdanav/musica` usa
///   `MediaSessionManager.getActiveSessions` con un `NotificationListenerService`
///   abilitato dall'utente («Accesso alle notifiche»), e `MediaController` per
///   il brano e i comandi (`android/.../musica/LettoreTelefono.kt`). Niente
///   account sviluppatore;
/// - **iPhone**: un'app non può comandare le altre. Si comanda il lettore di
///   sistema, cioè la Musica di Apple, con
///   `MPMusicPlayerController.systemMusicPlayer` e il permesso della libreria
///   musicale (`ios/.../LettoreDiSistema.swift`);
/// - **Spotify, per le playlist** (Android e iOS), dopo: Spotify App Remote
///   SDK, con un Client ID registrato e l'app Spotify installata. Basta un
///   altro [LettoreMusicale] con `fonte: FonteMusica.spotify`; il riquadro e
///   l'auto non cambiano.
///
/// In auto lo stesso lettore nativo dà, con o senza percorso: su Android Auto
/// un lettore disegnato in alto a destra sulla mappa, che si comanda col dito
/// (copertina, titolo, artista, la barra del brano e ⏮ ⏯ ⏭; si richiude in
/// una pillola: `android/.../auto/PannelloAuto.kt`), e solo sulle auto che non
/// mandano i tocchi ⏯ nell'`ActionStrip` del template col brano da guardare;
/// su CarPlay ⏯ ⏭ come `CPBarButton`, e niente disegnato sulla mappa (Apple
/// la vuole solo mappa: il brano lo mostra la scheda «In riproduzione» di
/// sistema). Col permesso ma senza un lettore aperto resta ▶.
///
/// **Far partire la musica da zero** (solo Android, [AvvioDellaMusica]): con
/// niente che suona, sul telefono e sull'auto c'è la pillola «▶ Spotify» con
/// l'icona e il nome dell'app che partirà (quella scelta in «App della
/// musica», Spotify di serie, l'ultima che ha suonato). Il lato nativo
/// (`android/.../musica/AvvioMusica.kt`) prova il `MediaBrowserService`
/// dell'app, poi il tasto ▶ mandato all'app, e sul telefono da fermi alla fine
/// la apre; intanto «Avvio Spotify…», e se dopo qualche secondo non suona
/// niente lo dice. Sull'iPhone un'app non può far partire le altre: lì niente
/// pillola.
///
/// Qui e sull'auto lo stesso aspetto: la barra sottile del brano sotto i
/// testi, e i tasti che l'app che suona non accetta ([ComandiDelLettore]:
/// una radio in diretta non ha ⏮ e ⏭) spenti.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'vetro.dart';

/// Il brano che suona adesso.
@immutable
class BranoInAscolto {
  const BranoInAscolto({
    required this.titolo,
    this.artista = '',
    this.copertina,
    this.durata,
    this.posizione,
    this.alle,
  });

  final String titolo;
  final String artista;
  final ImageProvider? copertina;
  final Duration? durata;

  /// A che punto era il brano [alle]: se suona, da allora è andato avanti.
  final Duration? posizione;

  /// Quando è stata letta la [posizione].
  final DateTime? alle;

  /// Quanta parte del brano è passata [adesso], da 0 a 1: la [posizione],
  /// più il tempo trascorso da quando è stata letta se [suona]. `null` se il
  /// lettore non dice quanto dura (una radio in diretta).
  double? avanzamento({required bool suona, required DateTime adesso}) {
    final durata = this.durata;
    if (durata == null || durata.inMilliseconds <= 0) return null;
    var ms = (posizione ?? Duration.zero).inMilliseconds;
    final alle = this.alle;
    if (suona && alle != null) {
      final passati = adesso.difference(alle).inMilliseconds;
      if (passati > 0) ms += passati;
    }
    return (ms / durata.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Una playlist da riprendere con un tocco (solo da fermi): «Riprendi».
@immutable
class PlaylistPreferita {
  const PlaylistPreferita({required this.id, required this.nome, this.copertina});

  final String id;
  final String nome;
  final ImageProvider? copertina;
}

/// Da dove arriva la musica.
enum FonteMusica {
  /// Il lettore che suona sul telefono, qualunque app (Android).
  telefono,

  /// Il lettore di sistema dell'iPhone (la Musica di Apple).
  sistema,

  /// Spotify collegato con App Remote: anche le playlist (dopo).
  spotify,
}

/// Il lettore che il mini-lettore comanda.
abstract class LettoreMusicale implements Listenable {
  /// Il nome dell'app che suona, sotto il titolo: «Spotify», «YouTube Music».
  /// `null`: nessuna app ha un lettore aperto.
  String? get app;

  FonteMusica get fonte;

  /// `null`: niente in ascolto.
  BranoInAscolto? get brano;

  bool get suona;

  /// Se il telefono lascia vedere e comandare la musica: su Android
  /// l'«Accesso alle notifiche», sull'iPhone la libreria musicale.
  bool get permesso;

  /// Le playlist da riprendere; vuote se la fonte non le sa dare (il
  /// lettore del telefono via MediaSession non sfoglia).
  List<PlaylistPreferita> get preferite;

  /// Comincia ([si]) o smette di seguire la musica: spento non ascolta
  /// niente e non chiede niente al telefono.
  Future<void> accendi(bool si);

  /// Apre la pagina del permesso (Android) o lo chiede (iPhone).
  Future<void> chiediPermesso();

  /// L'invito al permesso è stato visto o chiuso («Non ora») sul telefono:
  /// chi lo ripeteva altrove (il messaggio sullo schermo dell'auto, la
  /// notifica) smette.
  Future<void> invitoVisto();

  Future<void> precedente();
  Future<void> playPausa();
  Future<void> successivo();
  Future<void> riprendi(PlaylistPreferita playlist);
}

/// I comandi che il lettore accetta adesso. Su Android lo dichiara l'app che
/// suona (`PlaybackState.actions`): una radio in diretta non ha «precedente»
/// né «successivo». Un [LettoreMusicale] che non lo sa dire li accetta tutti.
abstract interface class ComandiDelLettore {
  bool get puoPrecedente;
  bool get puoPlayPausa;
  bool get puoSuccessivo;
}

/// Un'app della musica che si può far partire: «Spotify», con la sua icona.
@immutable
class AppDellaMusica {
  const AppDellaMusica({required this.pacchetto, required this.nome, this.icona});

  /// Il pacchetto Android (`com.spotify.music`).
  final String pacchetto;
  final String nome;
  final ImageProvider? icona;
}

/// Le app della musica per «App della musica» nelle impostazioni.
@immutable
class ElencoAppMusica {
  const ElencoAppMusica({this.app = const [], this.scelta, this.ultima, this.effettiva, this.ultimoAvvio});

  /// Le app installate che offrono un `MediaBrowserService`, Spotify per prima.
  final List<AppDellaMusica> app;

  /// La scelta salvata: un pacchetto, [ultimaUsata], o `null` (di serie).
  final String? scelta;

  /// L'ultima app che ha suonato, se se ne sa una.
  final String? ultima;

  /// Quella che parte davvero con ▶; `null`: nessuna.
  final String? effettiva;

  /// Le strade provate l'ultima volta e com'è finita (per chi prova).
  final String? ultimoAvvio;

  /// La scelta «l'ultima che ha suonato».
  static const ultimaUsata = 'ultima';

  /// Spotify, proposta di serie se c'è.
  static const spotify = 'com.spotify.music';

  /// Il punto acceso nell'elenco: la scelta, se vale ancora; se no quella di
  /// serie (Spotify se c'è, se no «l'ultima»).
  String get selezionata {
    final s = scelta;
    if (s != null && (s == ultimaUsata || app.any((a) => a.pacchetto == s))) return s;
    return app.any((a) => a.pacchetto == spotify) ? spotify : ultimaUsata;
  }

  /// Il nome di un'app nell'elenco, o il pacchetto.
  String? nomeDi(String? pacchetto) {
    if (pacchetto == null) return null;
    for (final a in app) {
      if (a.pacchetto == pacchetto) return a.nome;
    }
    return null;
  }
}

/// Far partire la musica quando nessuna app ha un lettore aperto. Lo sa
/// fare Android (`android/.../musica/AvvioMusica.kt`); l'iPhone no, e
/// [puoAvviare] è falso.
abstract interface class AvvioDellaMusica {
  /// Se qui la musica si fa partire da zero.
  bool get puoAvviare;

  /// L'app che ▶ fa partire («Spotify»); `null` se non se ne sa nessuna:
  /// allora ▶ propone la scelta.
  AppDellaMusica? get prossima;

  /// Sta partendo: «Avvio Spotify…».
  bool get inAvvio;

  /// Il nome dell'app che sta partendo.
  String? get nomeInAvvio;

  /// Non è partita: il messaggio, per qualche secondo; poi `null`.
  String? get esito;

  /// ▶ con niente che suona. [daFermi]: chi tocca è fermo (alla fine, se
  /// niente parte, si può aprire l'app).
  Future<void> parti({required bool daFermi});

  /// Le app della musica sul telefono, per sceglierne una.
  Future<ElencoAppMusica> elencoApp();

  /// Sceglie l'app di ▶: un pacchetto, [ElencoAppMusica.ultimaUsata], o
  /// `null` per quella di serie.
  Future<ElencoAppMusica> scegliApp(String? scelta);
}

/// Un lettore finto, per le prove e le fotografie.
class LettoreFinto extends ChangeNotifier implements LettoreMusicale, ComandiDelLettore, AvvioDellaMusica {
  LettoreFinto({
    this.brani = const [],
    this.preferite = const [],
    this.app = 'Spotify',
    this.fonte = FonteMusica.telefono,
    this.suona = true,
    this.permesso = true,
    this.puoPrecedente = true,
    this.puoPlayPausa = true,
    this.puoSuccessivo = true,
    bool? puoAvviare,
    this.prossima,
    this.appInstallate = const [],
    this.scelta,
    this.ultima,
  }) : puoAvviare = puoAvviare ?? fonte == FonteMusica.telefono;

  @override
  bool puoAvviare;
  @override
  AppDellaMusica? prossima;
  @override
  bool inAvvio = false;
  @override
  String? nomeInAvvio;
  @override
  String? esito;

  /// Le app che offre [elencoApp], e la scelta fatta.
  List<AppDellaMusica> appInstallate;
  String? scelta;
  String? ultima;

  @override
  bool puoPrecedente;
  @override
  bool puoPlayPausa;
  @override
  bool puoSuccessivo;

  final List<BranoInAscolto> brani;
  @override
  final List<PlaylistPreferita> preferite;
  @override
  String? app;
  @override
  final FonteMusica fonte;
  @override
  bool suona;
  @override
  bool permesso;
  bool acceso = false;
  int _i = 0;
  final comandi = <String>[];

  @override
  BranoInAscolto? get brano => brani.isEmpty ? null : brani[_i % brani.length];

  @override
  Future<void> accendi(bool si) async {
    comandi.add(si ? 'accendi' : 'spegni');
    acceso = si;
  }

  @override
  Future<void> chiediPermesso() async {
    comandi.add('permesso');
    permesso = true;
    notifyListeners();
  }

  /// Quante volte gli è stato detto che l'invito è stato visto.
  int invitiVisti = 0;

  @override
  Future<void> invitoVisto() async => invitiVisti++;

  @override
  Future<void> precedente() async {
    comandi.add('precedente');
    _i = (_i - 1) % (brani.isEmpty ? 1 : brani.length);
    notifyListeners();
  }

  @override
  Future<void> playPausa() async {
    comandi.add('playPausa');
    suona = !suona;
    notifyListeners();
  }

  @override
  Future<void> successivo() async {
    comandi.add('successivo');
    _i++;
    notifyListeners();
  }

  @override
  Future<void> riprendi(PlaylistPreferita playlist) async {
    comandi.add('riprendi:${playlist.id}');
    suona = true;
    notifyListeners();
  }

  @override
  Future<void> parti({required bool daFermi}) async {
    comandi.add(daFermi ? 'parti:fermo' : 'parti');
    inAvvio = true;
    nomeInAvvio = prossima?.nome;
    notifyListeners();
  }

  ElencoAppMusica get _elenco {
    String? effettiva = scelta == ElencoAppMusica.ultimaUsata ? ultima : scelta;
    if (effettiva == null || !appInstallate.any((a) => a.pacchetto == effettiva)) {
      effettiva = appInstallate.any((a) => a.pacchetto == ElencoAppMusica.spotify) ? ElencoAppMusica.spotify : ultima;
    }
    return ElencoAppMusica(app: appInstallate, scelta: scelta, ultima: ultima, effettiva: effettiva);
  }

  @override
  Future<ElencoAppMusica> elencoApp() async => _elenco;

  @override
  Future<ElencoAppMusica> scegliApp(String? scelta) async {
    comandi.add('scegli:$scelta');
    this.scelta = scelta;
    final e = _elenco;
    prossima = appInstallate.where((a) => a.pacchetto == e.effettiva).firstOrNull;
    notifyListeners();
    return e;
  }
}

/// Il lettore del telefono, dal canale `gdanav/musica`: su Android quello di
/// qualunque app che suona (MediaSession), sull'iPhone quello di sistema.
///
/// Il lato nativo manda `stato` a ogni cambio (brano, play/pausa, copertina,
/// permesso): `{permesso, app, titolo, artista, suona, copertina, durata_ms,
/// posizione_ms, puo_precedente, puo_successivo, puo_play}`. Gli ultimi tre
/// li manda solo Android; se mancano, i tasti restano accesi. Solo Android
/// manda anche come far partire la musica da zero ([AvvioDellaMusica]):
/// `avviabile`, `prossima` (`{pacchetto, nome, icona}`), `in_avvio`,
/// `nome_in_avvio`, `esito` ed `esito_id`. Senza il canale (nelle prove, sul
/// web) resta muto.
class LettoreDelTelefono extends ChangeNotifier implements LettoreMusicale, ComandiDelLettore, AvvioDellaMusica {
  LettoreDelTelefono({MethodChannel? canale, FonteMusica? fonte})
    : _canale = canale ?? const MethodChannel('gdanav/musica'),
      fonte = fonte ?? (defaultTargetPlatform == TargetPlatform.iOS ? FonteMusica.sistema : FonteMusica.telefono) {
    _canale.setMethodCallHandler((c) async {
      if (c.method == 'stato') leggi(c.arguments);
      return null;
    });
  }

  final MethodChannel _canale;
  @override
  final FonteMusica fonte;

  @override
  String? app;
  @override
  BranoInAscolto? brano;
  @override
  bool suona = false;
  @override
  bool permesso = false;
  @override
  List<PlaylistPreferita> get preferite => const [];
  @override
  bool puoPrecedente = true;
  @override
  bool puoPlayPausa = true;
  @override
  bool puoSuccessivo = true;

  @override
  bool puoAvviare = false;
  @override
  AppDellaMusica? prossima;
  @override
  bool inAvvio = false;
  @override
  String? nomeInAvvio;
  @override
  String? esito;

  Uint8List? _copertina;
  Uint8List? _icona;
  ImageProvider? _immagineIcona;
  int? _esitoId;
  Timer? _finoAllEsito;

  /// Per quanto resta il messaggio di un avvio non partito.
  static const durataEsito = Duration(seconds: 6);

  /// Lo stato come lo manda il lato nativo. Pubblico per le prove.
  @visibleForTesting
  void leggi(Object? grezzo) {
    if (grezzo is! Map) return;
    permesso = grezzo['permesso'] == true;
    app = switch (grezzo['app']) {
      final String a when a.isNotEmpty => a,
      _ => null,
    };
    suona = grezzo['suona'] == true;
    // Solo un «no» detto spegne un tasto: chi non lo dice (l'iPhone) li ha tutti.
    puoPrecedente = grezzo['puo_precedente'] != false;
    puoPlayPausa = grezzo['puo_play'] != false;
    puoSuccessivo = grezzo['puo_successivo'] != false;
    final titolo = '${grezzo['titolo'] ?? ''}'.trim();
    final byte = grezzo['copertina'];
    // La stessa copertina non si rifà: l'immagine non lampeggia.
    if (byte is Uint8List && !listEquals(byte, _copertina)) _copertina = byte;
    if (byte == null) _copertina = null;
    Duration? ms(Object? v) => v is num && v > 0 ? Duration(milliseconds: v.toInt()) : null;
    puoAvviare = grezzo['avviabile'] == true;
    inAvvio = grezzo['in_avvio'] == true;
    nomeInAvvio = switch (grezzo['nome_in_avvio']) {
      final String n when n.isNotEmpty => n,
      _ => null,
    };
    prossima = switch (grezzo['prossima']) {
      {'pacchetto': final String p, 'nome': final String n} && final Map m => AppDellaMusica(
        pacchetto: p,
        nome: n,
        icona: _iconaDa(m['icona']),
      ),
      _ => null,
    };
    // Un avvio non partito: si dice una volta, per qualche secondo.
    final id = grezzo['esito_id'];
    final testo = grezzo['esito'];
    if (id is int && id != _esitoId && testo is String && testo.isNotEmpty) {
      _esitoId = id;
      esito = testo;
      _finoAllEsito?.cancel();
      _finoAllEsito = Timer(durataEsito, () {
        esito = null;
        notifyListeners();
      });
      unawaited(_chiama('esitoDetto', id));
    }
    brano = titolo.isEmpty
        ? null
        : BranoInAscolto(
            titolo: titolo,
            artista: '${grezzo['artista'] ?? ''}'.trim(),
            copertina: _copertina == null ? null : MemoryImage(_copertina!),
            durata: ms(grezzo['durata_ms']),
            posizione: ms(grezzo['posizione_ms']),
            alle: DateTime.now(),
          );
    notifyListeners();
  }

  /// L'icona dell'app: la stessa non si rifà (non lampeggia).
  ImageProvider? _iconaDa(Object? byte) {
    if (byte is! Uint8List) return null;
    if (!listEquals(byte, _icona)) {
      _icona = byte;
      _immagineIcona = MemoryImage(byte);
    }
    return _immagineIcona;
  }

  Future<void> _chiama(String metodo, [Object? argomenti]) async {
    try {
      final r = await _canale.invokeMethod<Object?>(metodo, argomenti);
      if (r is Map) leggi(r);
    } on MissingPluginException {
      // Nessun lettore qui: il riquadro resta vuoto.
    } on PlatformException {
      // Il lettore dell'altra app non risponde: si riprova al tocco dopo.
    }
  }

  @override
  Future<void> accendi(bool si) => _chiama(si ? 'avvia' : 'ferma');

  @override
  Future<void> chiediPermesso() => _chiama('chiediPermesso');

  /// Al lato nativo (`invitoVisto`, senza argomenti): su Android l'auto non
  /// ripete più l'invito. Un lato nativo che non lo conosce risponde «non
  /// c'è», e va bene così.
  @override
  Future<void> invitoVisto() => _chiama('invitoVisto');

  @override
  Future<void> precedente() => _chiama('comando', 'precedente');

  @override
  Future<void> playPausa() => _chiama('comando', 'playPausa');

  @override
  Future<void> successivo() => _chiama('comando', 'successivo');

  @override
  Future<void> riprendi(PlaylistPreferita playlist) async {}

  @override
  Future<void> parti({required bool daFermi}) => _chiama('parti', {'da_fermi': daFermi});

  /// L'elenco come lo manda il lato nativo. Pubblico per le prove.
  @visibleForTesting
  static ElencoAppMusica leggiElenco(Object? grezzo) {
    if (grezzo is! Map) return const ElencoAppMusica();
    String? testo(Object? v) => v is String && v.isNotEmpty ? v : null;
    return ElencoAppMusica(
      app: [
        for (final a in grezzo['app'] is List ? grezzo['app'] as List : const [])
          if (a case {'pacchetto': final String p, 'nome': final String n})
            AppDellaMusica(
              pacchetto: p,
              nome: n,
              icona: switch (a['icona']) {
                final Uint8List b => MemoryImage(b),
                _ => null,
              },
            ),
      ],
      scelta: testo(grezzo['scelta']),
      ultima: testo(grezzo['ultima']),
      effettiva: testo(grezzo['effettiva']),
      ultimoAvvio: testo(grezzo['ultimo_avvio']),
    );
  }

  Future<ElencoAppMusica> _elenco(String metodo, [Object? argomenti]) async {
    try {
      return leggiElenco(await _canale.invokeMethod<Object?>(metodo, argomenti));
    } on MissingPluginException {
      return const ElencoAppMusica();
    } on PlatformException {
      return const ElencoAppMusica();
    }
  }

  @override
  Future<ElencoAppMusica> elencoApp() => _elenco('appDellaMusica');

  @override
  Future<ElencoAppMusica> scegliApp(String? scelta) => _elenco('scegliApp', scelta);

  @override
  void dispose() {
    _finoAllEsito?.cancel();
    super.dispose();
  }
}

/// Il riquadro in guida. [inMovimento]: niente playlist (si sceglie da
/// fermi); i tre tasti restano, grandi.
///
/// Senza nessun lettore aperto sul telefono (né brano né app) è la pillola
/// «▶ Spotify», dove la musica si fa partire da zero ([AvvioDellaMusica]:
/// Android); dove non si può (l'iPhone) non c'è.
class MiniLettore extends StatefulWidget {
  const MiniLettore({
    super.key,
    required this.lettore,
    this.inMovimento = true,
    this.chiuso = false,
    this.conPreferite = true,
  });

  final LettoreMusicale lettore;
  final bool inMovimento;

  /// Le playlist da fermi: di traverso no, non ci stanno senza coprire il
  /// «Poi».
  final bool conPreferite;

  /// Come parte: chiuso (il bottone tondo) o aperto.
  final bool chiuso;

  @override
  State<MiniLettore> createState() => _MiniLettoreState();
}

class _MiniLettoreState extends State<MiniLettore> {
  late bool _chiuso = widget.chiuso;

  /// Un messaggio della pillola detto da qui («Scegli l'app da fermo»).
  String? _avviso;
  Timer? _finoAllAvviso;

  @override
  void dispose() {
    _finoAllAvviso?.cancel();
    super.dispose();
  }

  void _dici(String testo) {
    _finoAllAvviso?.cancel();
    setState(() => _avviso = testo);
    _finoAllAvviso = Timer(LettoreDelTelefono.durataEsito, () {
      if (mounted) setState(() => _avviso = null);
    });
  }

  /// ▶ nella pillola, con niente che suona: parte l'app della musica; se
  /// non se ne sa nessuna, da fermi la scelta (in marcia lo si dice).
  Future<void> _parti(AvvioDellaMusica a) async {
    if (a.inAvvio) return;
    if (a.prossima == null) {
      if (widget.inMovimento) {
        _dici('Scegli l\'app della musica da fermo');
        return;
      }
      final scelta = await mostraSceltaAppMusica(context, a);
      if (scelta == null || !mounted) return;
    }
    await a.parti(daFermi: !widget.inMovimento);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.lettore,
    builder: (context, _) {
      final l = widget.lettore;
      if (!l.permesso) return const SizedBox.shrink();
      if (l.brano == null && l.app == null) {
        // Niente che suona: «▶ Spotify», dove si può far partire.
        final a = l is AvvioDellaMusica ? l as AvvioDellaMusica : null;
        if (a == null || !a.puoAvviare) return const SizedBox.shrink();
        return _PillolaAvvio(avvio: a, avviso: _avviso, onTap: () => unawaited(_parti(a)));
      }
      return AnimatedSize(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.bottomLeft,
        child: _chiuso ? _bottone(context) : _riquadro(context),
      );
    },
  );

  Widget _bottone(BuildContext context) {
    final l = widget.lettore;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Vetro(
          key: const Key('lettore-chiuso'),
          raggio: 28,
          onTap: () => setState(() => _chiuso = false),
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 6),
                _Copertina(brano: l.brano, lato: 44, raggio: 22),
                const SizedBox(width: 6),
                Icon(l.suona ? Icons.graphic_eq_rounded : Icons.pause_rounded, size: 26),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _riquadro(BuildContext context) {
    final l = widget.lettore;
    final t = Theme.of(context).textTheme;
    final tenue = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
    final brano = l.brano;
    final preferite = widget.inMovimento || !widget.conPreferite
        ? const <PlaylistPreferita>[]
        : l.preferite.take(5).toList();
    // I tasti che l'app che suona non accetta restano spenti, come sull'auto.
    final comandi = l is ComandiDelLettore ? l as ComandiDelLettore : null;
    Widget tasto(
      IconData icona,
      String chiave,
      String nome,
      Future<void> Function() fai, {
      bool grande = false,
      bool acceso = true,
    }) => SizedBox(
      width: grande ? 52 : 44,
      height: 56,
      child: IconButton(
        key: Key('lettore-$chiave'),
        tooltip: nome,
        onPressed: acceso ? fai : null,
        iconSize: grande ? 34 : 30,
        style: grande
            ? IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              )
            : null,
        icon: Icon(icona),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Vetro(
        key: const Key('mini-lettore'),
        raggio: 22,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Copertina(brano: brano, lato: 52, raggio: 12),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (l.app case final app?)
                          Text(
                            app,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelSmall?.copyWith(color: tenue, fontWeight: FontWeight.w700),
                          ),
                        Text(
                          brano?.titolo ?? 'Niente in ascolto',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (brano != null && brano.artista.isNotEmpty)
                          Text(
                            brano.artista,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(color: tenue),
                          ),
                      ],
                    ),
                  ),
                  tasto(
                    Icons.skip_previous_rounded,
                    'precedente',
                    'Precedente',
                    l.precedente,
                    acceso: comandi?.puoPrecedente ?? true,
                  ),
                  tasto(
                    l.suona ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    'play',
                    l.suona ? 'Pausa' : 'Riproduci',
                    l.playPausa,
                    grande: true,
                    acceso: comandi?.puoPlayPausa ?? true,
                  ),
                  tasto(
                    Icons.skip_next_rounded,
                    'successivo',
                    'Successivo',
                    l.successivo,
                    acceso: comandi?.puoSuccessivo ?? true,
                  ),
                  SizedBox(
                    width: 28,
                    height: 56,
                    child: IconButton(
                      key: const Key('lettore-richiudi'),
                      tooltip: 'Richiudi',
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() => _chiuso = true),
                      icon: Icon(Icons.expand_more_rounded, color: tenue),
                    ),
                  ),
                ],
              ),
              // La barra sottile del brano, come sull'auto: solo se il
              // lettore dice quanto dura.
              if (brano != null && brano.durata != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 8, 8, 0),
                  child: _Avanzamento(brano: brano, suona: l.suona),
                ),
              // Da fermi: le playlist da riprendere, con un tocco.
              if (preferite.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final (i, p) in preferite.indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        ActionChip(
                          key: Key('lettore-preferita-${p.id}'),
                          avatar: const Icon(Icons.playlist_play_rounded),
                          label: Text(p.nome),
                          onPressed: () => l.riprendi(p),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// La pillola «▶ Spotify», quando nessuna app ha un lettore aperto: l'icona
/// e il nome dell'app che partirà, e ▶; tutta la pillola è il tasto. Mentre
/// parte «Avvio Spotify…» coi tre puntini; se non parte, il messaggio per
/// qualche secondo. Senza un'app da far partire «Scegli la musica».
class _PillolaAvvio extends StatelessWidget {
  const _PillolaAvvio({required this.avvio, required this.onTap, this.avviso});

  final AvvioDellaMusica avvio;
  final VoidCallback onTap;
  final String? avviso;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final colori = Theme.of(context).colorScheme;
    final app = avvio.prossima;
    final messaggio = avvio.esito ?? avviso;
    final nomeInAvvio = avvio.nomeInAvvio ?? app?.nome;
    final testo = avvio.inAvvio
        ? (nomeInAvvio == null ? 'Avvio…' : 'Avvio $nomeInAvvio…')
        : messaggio ?? app?.nome ?? 'Scegli la musica';
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Semantics(
          button: true,
          label: avvio.inAvvio ? testo : (app == null ? 'Scegli l\'app della musica' : 'Fai partire ${app.nome}'),
          excludeSemantics: true,
          child: Vetro(
            key: const Key('lettore-avvio'),
            raggio: 28,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 6),
                  ClipOval(
                    child: SizedBox.square(
                      dimension: 44,
                      child: app?.icona != null
                          ? Image(image: app!.icona!, fit: BoxFit.cover, gaplessPlayback: true)
                          : ColoredBox(
                              color: colori.primaryContainer,
                              child: Icon(Icons.music_note_rounded, color: colori.onPrimaryContainer),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        testo,
                        key: const Key('lettore-avvio-testo'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: (messaggio != null && !avvio.inAvvio ? t.bodyMedium : t.titleSmall)?.copyWith(
                          fontWeight: messaggio != null && !avvio.inAvvio ? FontWeight.w600 : FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox.square(
                    dimension: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: colori.primary, shape: BoxShape.circle),
                      // Mentre parte tre puntini, come sull'auto: un altro
                      // tocco non fa niente.
                      child: Icon(
                        avvio.inAvvio ? Icons.more_horiz_rounded : Icons.play_arrow_rounded,
                        key: Key(avvio.inAvvio ? 'lettore-avvio-in-corso' : 'lettore-avvio-play'),
                        size: 30,
                        color: colori.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// La scelta dell'app della musica, da fermi, quando ▶ non sa chi far
/// partire: un foglio dal basso con l'elenco ([SceltaAppDellaMusica]). Dà la
/// scelta fatta, `null` se chiuso senza scegliere.
Future<String?> mostraSceltaAppMusica(BuildContext context, AvvioDellaMusica avvio) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Quale musica far partire?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Col tasto play del navigatore, quando niente suona, partirà questa app anche se è chiusa. '
            'La cambi in «Casa e musica in guida».',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SceltaAppDellaMusica(avvio: avvio, onScelta: (s) => Navigator.of(context).pop(s)),
        ],
      ),
    ),
  ),
);

/// «App della musica»: le app installate che si possono far partire, con
/// la loro icona, e «L'ultima che ha suonato». Di serie Spotify, se c'è. Lo
/// usano le impostazioni e il foglio di [mostraSceltaAppMusica].
class SceltaAppDellaMusica extends StatefulWidget {
  const SceltaAppDellaMusica({super.key, required this.avvio, this.onScelta, this.conDettagli = false});

  final AvvioDellaMusica avvio;

  /// Scelta fatta (e salvata).
  final ValueChanged<String>? onScelta;

  /// Sotto l'elenco, le strade provate l'ultima volta (le impostazioni).
  final bool conDettagli;

  @override
  State<SceltaAppDellaMusica> createState() => _SceltaAppDellaMusicaState();
}

class _SceltaAppDellaMusicaState extends State<SceltaAppDellaMusica> {
  ElencoAppMusica? _elenco;

  @override
  void initState() {
    super.initState();
    unawaited(_leggi(widget.avvio.elencoApp()));
  }

  Future<void> _leggi(Future<ElencoAppMusica> f) async {
    final e = await f;
    if (mounted) setState(() => _elenco = e);
  }

  Future<void> _scegli(String? s) async {
    if (s == null) return;
    await _leggi(widget.avvio.scegliApp(s));
    widget.onScelta?.call(s);
  }

  @override
  Widget build(BuildContext context) {
    final e = _elenco;
    final tema = Theme.of(context);
    if (e == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3))),
      );
    }
    Widget icona(AppDellaMusica a) => ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox.square(
        dimension: 40,
        child: a.icona != null
            ? Image(image: a.icona!, fit: BoxFit.cover)
            : ColoredBox(color: tema.colorScheme.primaryContainer, child: const Icon(Icons.music_note_rounded)),
      ),
    );
    final nomeUltima = e.nomeDi(e.ultima);
    final dettagli = e.ultimoAvvio;
    return RadioGroup<String>(
      groupValue: e.selezionata,
      onChanged: (s) => unawaited(_scegli(s)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (e.app.isEmpty)
            Padding(
              key: const Key('app-musica-nessuna'),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Sul telefono non c\'è un\'app della musica che GdANav possa far partire. Falla partire tu: '
                'qui compariranno il brano e i tasti.',
                style: tema.textTheme.bodyMedium,
              ),
            ),
          for (final a in e.app)
            RadioListTile<String>(
              key: Key('app-musica-${a.pacchetto}'),
              value: a.pacchetto,
              secondary: icona(a),
              title: Text(a.nome),
              subtitle: a.pacchetto == ElencoAppMusica.spotify && e.scelta == null ? const Text('Di serie') : null,
            ),
          RadioListTile<String>(
            key: const Key('app-musica-ultima'),
            value: ElencoAppMusica.ultimaUsata,
            secondary: const SizedBox.square(dimension: 40, child: Icon(Icons.history_rounded)),
            title: const Text('L\'ultima che ha suonato'),
            subtitle: Text(nomeUltima ?? (e.ultima == null ? 'Nessuna ancora' : 'Quella di prima')),
          ),
          if (widget.conDettagli && dettagli != null)
            Padding(
              key: const Key('app-musica-ultimo-avvio'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'L\'ultima volta: $dettagli',
                style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// L'invito, una volta sola, a dare il permesso per la musica: al posto del
/// riquadro, da fermi, in guida e a mappa libera. «Consenti» apre la pagina
/// del sistema, «Non ora» lo chiude; in tutti e due i casi (e se se ne va da
/// solo dopo essere rimasto in vista una decina di secondi) non torna più: lo
/// dice [onVisto]. Le impostazioni del navigatore lo ripropongono a chi lo
/// cerca.
class InvitoMusica extends StatefulWidget {
  const InvitoMusica({super.key, required this.lettore, required this.onVisto});

  final LettoreMusicale lettore;
  final VoidCallback onVisto;

  @override
  State<InvitoMusica> createState() => _InvitoMusicaState();
}

class _InvitoMusicaState extends State<InvitoMusica> {
  var _detto = false;

  /// Da quando è in vista: se se ne va dopo un'occhiata (si riparte), torna
  /// la prossima volta da fermi; se è rimasto lì a lungo, è visto.
  final _dal = DateTime.now();

  /// Quanto deve restare in vista, senza un tocco, per non tornare più.
  static const abbastanza = Duration(seconds: 10);

  void _visto() {
    if (_detto) return;
    _detto = true;
    widget.onVisto();
  }

  @override
  void dispose() {
    // Se ne va senza un tocco dopo essere rimasto in vista abbastanza: visto
    // anche così. Sparito subito (si è ripartiti) no: dal campo, chi usa
    // l'auto lo perdeva così senza averlo mai letto. Dopo, non durante lo
    // smontaggio, che non si cambia chi sta ascoltando.
    if (!_detto && DateTime.now().difference(_dal) >= abbastanza) {
      _detto = true;
      scheduleMicrotask(widget.onVisto);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final iPhone = widget.lettore.fonte == FonteMusica.sistema;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Vetro(
        key: const Key('invito-musica'),
        raggio: 22,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.music_note_rounded, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Musica nel navigatore',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          iPhone ? 'Serve l\'accesso a Musica' : 'Serve l\'accesso alle notifiche',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Di lato non ci stanno sempre in riga (a mappa libera c'è
              // «Segnala» accanto): vanno a capo.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: const Key('invito-musica-no'),
                    style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                    onPressed: () => setState(_visto),
                    child: const Text('Non ora'),
                  ),
                  FilledButton(
                    key: const Key('invito-musica-si'),
                    style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                    onPressed: () {
                      _visto();
                      unawaited(widget.lettore.chiediPermesso());
                    },
                    child: const Text('Consenti'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La barra del brano: va avanti da sola, una volta al secondo, solo mentre
/// suona. Ferma (in pausa, o chiuso il riquadro) non fa lavorare niente.
class _Avanzamento extends StatefulWidget {
  const _Avanzamento({required this.brano, required this.suona});

  final BranoInAscolto brano;
  final bool suona;

  @override
  State<_Avanzamento> createState() => _AvanzamentoState();
}

class _AvanzamentoState extends State<_Avanzamento> {
  Timer? _battito;

  @override
  void initState() {
    super.initState();
    _regola();
  }

  @override
  void didUpdateWidget(_Avanzamento prima) {
    super.didUpdateWidget(prima);
    _regola();
  }

  void _regola() {
    if (widget.suona) {
      _battito ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else {
      _battito?.cancel();
      _battito = null;
    }
  }

  @override
  void dispose() {
    _battito?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colori = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        key: const Key('lettore-avanzamento'),
        value: widget.brano.avanzamento(suona: widget.suona, adesso: DateTime.now()) ?? 0,
        minHeight: 4,
        backgroundColor: colori.onSurface.withValues(alpha: 0.14),
        color: colori.primary,
      ),
    );
  }
}

class _Copertina extends StatelessWidget {
  const _Copertina({required this.brano, required this.lato, required this.raggio});

  final BranoInAscolto? brano;
  final double lato;
  final double raggio;

  @override
  Widget build(BuildContext context) {
    final img = brano?.copertina;
    return ClipRRect(
      borderRadius: BorderRadius.circular(raggio),
      child: SizedBox.square(
        dimension: lato,
        child: img != null
            ? Image(image: img, fit: BoxFit.cover, gaplessPlayback: true)
            : ColoredBox(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(Icons.music_note_rounded, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
      ),
    );
  }
}
