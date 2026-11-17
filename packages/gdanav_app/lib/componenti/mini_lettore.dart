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
/// sistema). Col permesso ma senza un lettore aperto resta ⏯, che riprende
/// l'ultima app che suonava.
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

/// Un lettore finto, per le prove e le fotografie.
class LettoreFinto extends ChangeNotifier implements LettoreMusicale, ComandiDelLettore {
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
  });

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
}

/// Il lettore del telefono, dal canale `gdanav/musica`: su Android quello di
/// qualunque app che suona (MediaSession), sull'iPhone quello di sistema.
///
/// Il lato nativo manda `stato` a ogni cambio (brano, play/pausa, copertina,
/// permesso): `{permesso, app, titolo, artista, suona, copertina, durata_ms,
/// posizione_ms, puo_precedente, puo_successivo, puo_play}`. Gli ultimi tre
/// li manda solo Android; se mancano, i tasti restano accesi. Senza il canale
/// (nelle prove, sul web) resta muto.
class LettoreDelTelefono extends ChangeNotifier implements LettoreMusicale, ComandiDelLettore {
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

  Uint8List? _copertina;

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
}

/// Il riquadro in guida. [inMovimento]: niente playlist (si sceglie da
/// fermi); i tre tasti restano, grandi.
///
/// Senza nessun lettore aperto sul telefono (né brano né app) non c'è.
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.lettore,
    builder: (context, _) {
      final l = widget.lettore;
      if (!l.permesso || (l.brano == null && l.app == null)) return const SizedBox.shrink();
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
