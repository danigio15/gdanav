/// La musica di casa in auto: le radio preferite e le playlist che si vedono
/// nella pagina Musica della plancia di GdAHome, da far suonare **in auto**
/// (sul telefono, quindi nelle casse dell'auto), non sui lettori di casa.
///
/// L'elenco lo dà la casa (`ponte/musica/della-casa`, il ponte di GdAHome):
/// per ogni voce il titolo, l'immagine (già letta dal ponte: niente rete
/// in chiaro sul telefono), da dove viene e **come si suona fuori casa**
/// ([ComeSiSuona]). Qui si decide, per questo telefono, dove suona davvero
/// ([DoveSuona], [riproduzione]):
///
/// - una radio (un flusso internet già risolto da Home Assistant) e un file
///   di Home Assistant raggiungibile da fuori: col lettore **nativo** del
///   navigatore ([SuonaDallaCasa]: su Android ExoPlayer con la sua sessione,
///   sull'iPhone AVPlayer), che compare nel lettore sulla mappa, nella scheda
///   della musica dell'auto e risponde ai tasti del volante;
/// - una playlist di Spotify (o un preferito di Alexa con un servizio che sul
///   telefono ha la sua app): nell'app del telefono, **senza aprirla** in auto
///   (solo Android; sull'iPhone un'app non fa partire le altre, e Spotify si
///   apre solo sul telefono, da fermi);
/// - tutto il resto (Sonos, la libreria di Music Assistant, Chromecast):
///   **solo sui lettori di casa**. Si mostra lo stesso, lo si dice, e si
///   propone di farla partire in casa ([GestoreMusicaDiCasa.avviaInCasa]).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../stato/archivio.dart';
import 'vetro.dart';

/// Radio o playlist.
enum TipoDiCasa { radio, playlist }

/// Come la casa dice che una voce si suona fuori casa.
enum ComeSiSuona {
  /// Un flusso audio (una radio, un file di Home Assistant): il lettore nativo.
  flusso,

  /// Una playlist di Spotify (`spotify:playlist:…`): nell'app Spotify.
  spotify,

  /// Un preferito di Alexa («Hit della settimana» su Spotify): la si cerca
  /// nell'app di quel servizio, se il telefono ce l'ha.
  cerca,

  /// Solo sui lettori di casa.
  casa,
}

/// Dove suona davvero, da questo telefono.
enum DoveSuona {
  /// In auto, col lettore del navigatore.
  inAuto,

  /// In auto, nell'app della musica del telefono (Spotify), senza aprirla.
  nellApp,

  /// Sul telefono si può solo aprire l'app, da fermi (l'iPhone con Spotify).
  apriDaFermo,

  /// Solo sui lettori di casa.
  soloInCasa,
}

/// Una radio o una playlist della casa.
@immutable
class VoceDiCasa {
  const VoceDiCasa({
    required this.id,
    required this.tipo,
    required this.titolo,
    this.provenienza = '',
    this.lettore,
    this.immagine,
    this.come = ComeSiSuona.casa,
    this.flusso,
    this.mime,
    this.uri,
    this.servizio,
    this.cerca,
    this.inCasa = false,
    this.perche,
  });

  /// L'identificativo che dà la casa: stabile, serve a «suonate per ultime».
  final String id;
  final TipoDiCasa tipo;
  final String titolo;

  /// Da dove viene: «Spotify», «Music Assistant», «Sonos», «Alexa · Spotify».
  final String provenienza;

  /// Il lettore di casa su cui c'è («Sonos Soggiorno»), se ce n'è uno.
  final String? lettore;

  /// Il logo o la copertina, già letti dal ponte.
  final Uint8List? immagine;

  final ComeSiSuona come;

  /// L'indirizzo del flusso, se la casa l'ha già risolto (le radio); `null`
  /// per un flusso che si chiede al momento (un file con la firma a tempo).
  final String? flusso;
  final String? mime;

  /// L'URI per l'app (`spotify:playlist:…`).
  final String? uri;

  /// Il servizio di un preferito di Alexa: `spotify`, `amazon`, `apple`, `deezer`.
  final String? servizio;

  /// Cosa cercare nell'app di quel servizio.
  final String? cerca;

  /// Se la casa la sa far partire su un suo lettore.
  final bool inCasa;

  /// Perché non suona fuori casa, se la casa lo sa: `solo-http` (la radio
  /// trasmette solo in chiaro), `non-trovata` (una radio di Alexa che Radio
  /// Browser non ha).
  final String? perche;

  /// La voce com'è nella risposta della casa; `null` se non ha id o titolo.
  static VoceDiCasa? daJson(Object? grezzo, TipoDiCasa tipo) {
    if (grezzo is! Map) return null;
    String? testo(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    final id = testo(grezzo['id']);
    final titolo = testo(grezzo['titolo']);
    if (id == null || titolo == null) return null;
    final come = switch (grezzo['come']) {
      'flusso' => ComeSiSuona.flusso,
      'spotify' => ComeSiSuona.spotify,
      'cerca' => ComeSiSuona.cerca,
      _ => ComeSiSuona.casa,
    };
    final flusso = testo(grezzo['flusso']);
    return VoceDiCasa(
      id: id,
      tipo: tipo,
      titolo: titolo,
      provenienza: testo(grezzo['provenienza']) ?? '',
      lettore: testo(grezzo['lettore']),
      immagine: _immagine(grezzo['immagine']),
      come: come,
      // Solo indirizzi sicuri, o di casa firmati: niente rete in chiaro.
      flusso: flusso != null && flusso.startsWith('https://') ? flusso : null,
      mime: testo(grezzo['mime']),
      uri: testo(grezzo['uri']),
      servizio: testo(grezzo['servizio'])?.toLowerCase(),
      cerca: testo(grezzo['cerca']),
      inCasa: grezzo['in_casa'] == true,
      perche: testo(grezzo['perche']),
    );
  }

  static Uint8List? _immagine(Object? grezzo) {
    if (grezzo is! Map || grezzo['dati'] is! String) return null;
    try {
      final b = base64Decode(grezzo['dati'] as String);
      return b.isEmpty ? null : b;
    } on FormatException {
      return null;
    }
  }

  /// Per il lato nativo (l'auto): solo quello che serve a disegnarla e suonarla.
  Map<String, Object?> perIlNativo({required DoveSuona dove, String? app}) => {
    'id': id,
    'tipo': tipo.name,
    'titolo': titolo,
    'provenienza': provenienza,
    'lettore': lettore,
    'immagine': immagine,
    'dove': dove.name,
    'flusso': flusso,
    'mime': mime,
    'uri': uri,
    'cerca': cerca,
    'app': app,
  };

  @override
  bool operator ==(Object other) => other is VoceDiCasa && other.id == id && other.titolo == titolo;

  @override
  int get hashCode => Object.hash(id, titolo);
}

/// Quello che la casa ha da suonare.
@immutable
class ElencoDiCasa {
  const ElencoDiCasa({this.radio = const [], this.playlist = const [], this.letto});

  final List<VoceDiCasa> radio;
  final List<VoceDiCasa> playlist;

  /// Quando la casa l'ha messo insieme.
  final DateTime? letto;

  bool get vuoto => radio.isEmpty && playlist.isEmpty;

  /// La risposta di `ponte/musica/della-casa`.
  static ElencoDiCasa daRisposta(Object? r) {
    if (r is! Map) return const ElencoDiCasa();
    List<VoceDiCasa> voci(Object? l, TipoDiCasa t) => [
      for (final v in l is List ? l : const []) ?VoceDiCasa.daJson(v, t),
    ];
    final ms = r['letto'];
    return ElencoDiCasa(
      radio: voci(r['radio'], TipoDiCasa.radio),
      playlist: voci(r['playlist'], TipoDiCasa.playlist),
      letto: ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }
}

/// Dove suona una voce, detto per chi guarda: l'etichetta corta (sulla
/// scheda) e la spiegazione (quando non suona in auto).
@immutable
class Riproduzione {
  const Riproduzione(this.dove, this.etichetta, {this.spiegazione, this.app});

  final DoveSuona dove;
  final String etichetta;
  final String? spiegazione;

  /// Il pacchetto dell'app che la suona ([DoveSuona.nellApp]).
  final String? app;

  bool get suonaInAuto => dove == DoveSuona.inAuto || dove == DoveSuona.nellApp;
}

/// I pacchetti Android dei servizi di musica che la casa nomina.
const pacchettiDeiServizi = {
  'spotify': 'com.spotify.music',
  'amazon': 'com.amazon.mp3',
  'apple': 'com.apple.android.music',
  'deezer': 'deezer.android.app',
  'youtube': 'com.google.android.apps.youtube.music',
};

const _nomiDeiServizi = {
  'spotify': 'Spotify',
  'amazon': 'Amazon Music',
  'apple': 'Apple Music',
  'deezer': 'Deezer',
  'youtube': 'YouTube Music',
};

/// Dove suona [v] da questo telefono. [android]: Android (le app si fanno
/// partire senza aprirle) o l'iPhone. [installate]: i pacchetti delle app
/// della musica sul telefono (`null`: non si sa, si suppone di sì).
Riproduzione riproduzione(VoceDiCasa v, {required bool android, Set<String>? installate}) {
  String inCasa(String perche) =>
      v.inCasa ? '$perche Puoi farla partire in casa${v.lettore != null ? ', su ${v.lettore}' : ''}.' : perche;
  switch (v.come) {
    case ComeSiSuona.flusso:
      return const Riproduzione(DoveSuona.inAuto, 'In auto');
    case ComeSiSuona.spotify:
    case ComeSiSuona.cerca:
      final servizio = v.come == ComeSiSuona.spotify ? 'spotify' : (v.servizio ?? '');
      final pacchetto = pacchettiDeiServizi[servizio];
      final nome = _nomiDeiServizi[servizio] ?? 'l\'app';
      if (pacchetto == null) {
        return Riproduzione(DoveSuona.soloInCasa, 'Solo in casa', spiegazione: inCasa('Si suona sui lettori di casa.'));
      }
      if (installate != null && !installate.contains(pacchetto)) {
        return Riproduzione(DoveSuona.soloInCasa, 'Solo in casa', spiegazione: inCasa('Sul telefono non c\'è $nome.'));
      }
      if (!android) {
        // Sull'iPhone un'app non fa partire le altre: Spotify si apre, da fermi.
        return v.come == ComeSiSuona.spotify
            ? Riproduzione(
                DoveSuona.apriDaFermo,
                'Apri $nome',
                spiegazione: 'Sull\'iPhone si apre $nome sulla playlist, da fermo: il play lo dai tu.',
                app: pacchetto,
              )
            : Riproduzione(
                DoveSuona.soloInCasa,
                'Solo in casa',
                spiegazione: inCasa('Sull\'iPhone un\'app non può far partire $nome.'),
              );
      }
      return Riproduzione(DoveSuona.nellApp, 'Su $nome', app: pacchetto);
    case ComeSiSuona.casa when v.tipo == TipoDiCasa.radio:
      return Riproduzione(
        DoveSuona.soloInCasa,
        'Solo in casa',
        spiegazione: switch (v.perche) {
          'solo-http' =>
            '«${v.titolo}» trasmette solo senza cifratura (http), che il telefono per sicurezza non apre: '
                'si ascolta sui lettori di casa.',
          'non-trovata' => '«${v.titolo}» non c\'è fra le radio di Radio Browser: si ascolta sugli Echo di casa.',
          _ => '«${v.titolo}» adesso non si riesce ad ascoltare fuori casa.',
        },
      );
    case ComeSiSuona.casa:
      return Riproduzione(
        DoveSuona.soloInCasa,
        'Solo in casa',
        spiegazione: inCasa(
          '«${v.titolo}» si suona solo sui lettori di casa${v.provenienza.isNotEmpty ? ' (${v.provenienza})' : ''}: '
          'al telefono non arriva.',
        ),
      );
  }
}

/// Chi sa suonare in auto la musica di casa: il lettore del telefono
/// ([LettoreDelTelefono] col lato nativo), quello finto nelle prove.
abstract interface class SuonaDallaCasa {
  /// Fa suonare in auto, col lettore nativo, una delle [voci] (dalla
  /// [da]-esima): le radio preferite (⏮ ⏭ passano all'altra radio) o i brani
  /// di una playlist. [nome]: il nome della playlist, sotto il brano. Torna il
  /// messaggio se non parte.
  Future<String?> suonaFlussi(List<VoceDiCasa> voci, {int da = 0, String? nome});

  /// Fa partire [v] nell'app [app] del telefono, senza aprirla; da fermi
  /// ([daFermi]), se non parte, l'app si apre. Torna il messaggio se non parte.
  Future<String?> suonaNellApp(VoceDiCasa v, {required String app, required bool daFermi});

  /// Ferma la musica di casa.
  Future<void> fermaCasa();

  /// L'elenco, per lo schermo dell'auto (Android Auto: Menu › Musica di casa).
  /// [ultima]: l'id dell'ultima suonata («Riprendi»).
  Future<void> elencoPerLAuto(List<Map<String, Object?>> radio, List<Map<String, Object?>> playlist, {String? ultima});

  /// Una voce toccata sullo schermo dell'auto che il lato nativo non sa
  /// suonare da solo (chiede alla casa): la si passa qui.
  set toccataDallAuto(Future<String?> Function(String id)? f);
}

/// Una voce di una playlist da suonare col lettore nativo, come la dà
/// `ponte/musica/flusso`: i brani con il loro indirizzo.
@immutable
class BranoDiCasa {
  const BranoDiCasa({required this.titolo, required this.url, this.mime});

  final String titolo;
  final String url;
  final String? mime;
}

/// La musica di casa per il navigatore: l'elenco chiesto alla casa (tenuto
/// qualche minuto), le ultime suonate per prime, e il tocco su una voce.
class GestoreMusicaDiCasa extends ChangeNotifier {
  GestoreMusicaDiCasa({
    required this.chiedi,
    this.lettore,
    this.archivio,
    bool? android,
    this.installate,
    DateTime Function()? adesso,
  }) : android = android ?? defaultTargetPlatform == TargetPlatform.android,
       _adesso = adesso ?? DateTime.now {
    lettore?.toccataDallAuto = _toccataDallAuto;
  }

  /// Come si manda un comando alla casa (`SorgenteGdahome.chiedi`); `null`
  /// finché GdAHome non ha una casa.
  final Future<Object?> Function(Map<String, Object?> comando)? Function() chiedi;
  final SuonaDallaCasa? lettore;
  final Archivio? archivio;
  final bool android;

  /// Le app della musica sul telefono, se si sanno.
  Future<Set<String>> Function()? installate;
  Set<String>? _installate;

  final DateTime Function() _adesso;

  /// Per quanto vale l'elenco letto: poi si richiede.
  static const valido = Duration(minutes: 10);

  ElencoDiCasa? _elenco;
  DateTime? _lettoIl;
  bool _caricando = false;
  String? _errore;
  List<String> _ultime = const [];
  bool _ultimeLette = false;

  /// Quello che si sta facendo partire adesso (l'id), per la scheda.
  String? inAvvio;

  ElencoDiCasa? get elenco => _elenco;
  bool get caricando => _caricando;
  String? get errore => _errore;

  /// Se c'è una casa a cui chiedere.
  bool get disponibile => chiedi() != null;

  /// Le radio, prima le ultime suonate.
  List<VoceDiCasa> get radio => _inOrdine(_elenco?.radio ?? const []);

  /// Le playlist: prima le ultime suonate, poi quelle che suonano in auto,
  /// poi quelle solo di casa.
  List<VoceDiCasa> get playlist {
    final tutte = _inOrdine(_elenco?.playlist ?? const []);
    final ultime = tutte.where((v) => _ultime.contains(v.id)).toList();
    final resto = tutte.where((v) => !_ultime.contains(v.id));
    return [...ultime, ...resto.where((v) => come(v).suonaInAuto), ...resto.where((v) => !come(v).suonaInAuto)];
  }

  /// L'ultima suonata, se c'è ancora: «Riprendi».
  VoceDiCasa? get ultima {
    for (final id in _ultime) {
      for (final v in [...?_elenco?.radio, ...?_elenco?.playlist]) {
        if (v.id == id) return v;
      }
    }
    return null;
  }

  List<VoceDiCasa> _inOrdine(List<VoceDiCasa> voci) {
    if (_ultime.isEmpty) return voci;
    final ordine = {for (final (i, id) in _ultime.indexed) id: i};
    final copia = [...voci];
    // Stabile: a parità (non suonate), l'ordine della casa.
    final indici = {for (final (i, v) in voci.indexed) v.id: i};
    copia.sort((a, b) {
      final x = ordine[a.id] ?? 1000 + indici[a.id]!;
      final y = ordine[b.id] ?? 1000 + indici[b.id]!;
      return x.compareTo(y);
    });
    return copia;
  }

  /// Dove suona [v] da questo telefono.
  Riproduzione come(VoceDiCasa v) => riproduzione(v, android: android, installate: _installate);

  /// Chiede l'elenco alla casa, se non è fresco ([forza]: comunque).
  Future<void> aggiorna({bool forza = false}) async {
    if (!_ultimeLette) {
      _ultimeLette = true;
      try {
        _ultime = await archivio?.ultimeDallaCasa() ?? const [];
      } catch (_) {}
    }
    if (installate case final f? when _installate == null) {
      try {
        _installate = await f();
      } catch (_) {}
    }
    final c = chiedi();
    if (c == null) {
      _errore = 'La casa non è collegata';
      notifyListeners();
      return;
    }
    final letto = _lettoIl;
    if (!forza && letto != null && _adesso().difference(letto) < valido) return;
    if (_caricando) return;
    _caricando = true;
    _errore = null;
    notifyListeners();
    try {
      final r = await c({'type': 'ponte/musica/della-casa'}).timeout(const Duration(seconds: 20));
      _elenco = ElencoDiCasa.daRisposta(r);
      _lettoIl = _adesso();
      unawaited(_allAuto());
    } catch (e) {
      _errore = _parola(e);
    } finally {
      _caricando = false;
      notifyListeners();
    }
  }

  static String _parola(Object e) {
    final s = '$e';
    if (s.contains('unauthorized')) return 'Per la musica di casa serve un utente: riabbina il telefono';
    if (s.contains('unknown_command')) return 'La casa non sa ancora dare la sua musica: aggiorna GdAHome';
    if (e is TimeoutException) return 'La casa non ha risposto';
    return 'Non si riesce a leggere la musica di casa';
  }

  /// L'elenco allo schermo dell'auto, con dove suona ogni voce.
  Future<void> _allAuto() async {
    final l = lettore;
    if (l == null) return;
    Map<String, Object?> nativo(VoceDiCasa v) {
      final r = come(v);
      return v.perIlNativo(dove: r.dove, app: r.app);
    }

    try {
      await l.elencoPerLAuto(
        [for (final v in radio) nativo(v)],
        [for (final v in playlist) nativo(v)],
        ultima: ultima?.id,
      );
    } catch (_) {}
  }

  Future<void> _suonata(VoceDiCasa v) async {
    _ultime = [v.id, ..._ultime.where((id) => id != v.id)].take(12).toList();
    notifyListeners();
    unawaited(_allAuto());
    try {
      await archivio?.salvaUltimeDallaCasa(_ultime);
    } catch (_) {}
  }

  /// Fa suonare [v] in auto. Torna il messaggio da dire se non si è potuto
  /// (anche «si suona solo in casa»), `null` se è partita.
  Future<String?> suona(VoceDiCasa v, {required bool daFermi}) async {
    final r = come(v);
    final l = lettore;
    if (l == null) return 'Qui non c\'è un lettore';
    if (!r.suonaInAuto && r.dove != DoveSuona.apriDaFermo) return r.spiegazione;
    if (r.dove == DoveSuona.apriDaFermo && !daFermi) return 'Si apre sul telefono, da fermo';
    inAvvio = v.id;
    notifyListeners();
    try {
      String? esito;
      if (r.dove == DoveSuona.inAuto) {
        esito = await _suonaFlusso(v, l);
      } else {
        esito = await l.suonaNellApp(v, app: r.app!, daFermi: daFermi);
      }
      if (esito == null) await _suonata(v);
      return esito;
    } finally {
      inAvvio = null;
      notifyListeners();
    }
  }

  Future<String?> _suonaFlusso(VoceDiCasa v, SuonaDallaCasa l) async {
    if (v.tipo == TipoDiCasa.radio && v.flusso != null) {
      // Le radio insieme: ⏮ ⏭ passano all'altra preferita.
      final radio = this.radio.where((r) => r.flusso != null).toList();
      return l.suonaFlussi(radio, da: radio.indexWhere((r) => r.id == v.id).clamp(0, radio.length));
    }
    if (v.flusso != null) return l.suonaFlussi([v]);
    // Un flusso con la firma a tempo: lo si chiede adesso alla casa.
    final brani = await flussoDi(v);
    if (brani == null || brani.isEmpty) return 'La casa non ha dato il brano: riprova';
    return l.suonaFlussi([
      for (final (i, b) in brani.indexed)
        VoceDiCasa(
          id: '${v.id}#$i',
          tipo: TipoDiCasa.playlist,
          titolo: b.titolo,
          provenienza: v.titolo,
          immagine: v.immagine,
          come: ComeSiSuona.flusso,
          flusso: b.url,
          mime: b.mime,
        ),
    ], nome: v.titolo);
  }

  /// I brani di una voce da suonare col lettore nativo, chiesti alla casa
  /// adesso (`ponte/musica/flusso`); `null` se non risponde.
  Future<List<BranoDiCasa>?> flussoDi(VoceDiCasa v) async {
    final c = chiedi();
    if (c == null) return null;
    try {
      final r = await c({'type': 'ponte/musica/flusso', 'voce': v.id}).timeout(const Duration(seconds: 15));
      if (r is! Map) return null;
      return [
        for (final b in r['brani'] is List ? r['brani'] as List : const [])
          if (b case {'titolo': final String t, 'url': final String u} when u.startsWith('https://'))
            BranoDiCasa(titolo: t, url: u, mime: b['mime'] is String ? b['mime'] as String : null),
      ];
    } catch (_) {
      return null;
    }
  }

  /// La fa partire su un lettore di casa (il suo). Torna il messaggio da dire.
  Future<String> avviaInCasa(VoceDiCasa v) async {
    final c = chiedi();
    if (c == null || !v.inCasa) return 'Non si può far partire in casa';
    try {
      final r = await c({'type': 'ponte/musica/in-casa', 'voce': v.id}).timeout(const Duration(seconds: 15));
      final dove = r is Map && r['lettore'] is String ? r['lettore'] as String : v.lettore;
      return dove == null ? 'Parte in casa' : 'Parte in casa, su $dove';
    } catch (_) {
      return 'La casa non è riuscita a farla partire';
    }
  }

  /// Dallo schermo dell'auto, una voce che il lato nativo non suona da solo.
  Future<String?> _toccataDallAuto(String id) async {
    // L'auto chiede l'elenco fresco (ha aperto «Musica di casa»).
    if (id.isEmpty) {
      await aggiorna(forza: true);
      return null;
    }
    await aggiorna();
    final v = [...?_elenco?.radio, ...?_elenco?.playlist].where((x) => x.id == id).firstOrNull;
    if (v == null) return 'Non c\'è più: riapri l\'elenco';
    final r = come(v);
    // In auto: «solo in casa» vuol dire farla partire in casa (la riga lo dice).
    if (r.dove == DoveSuona.soloInCasa) return v.inCasa ? avviaInCasa(v) : r.spiegazione;
    return suona(v, daFermi: false);
  }
}

/// La scheda «Dalla casa», dal basso: due righe, «Radio» (le preferite, col
/// logo) e «Playlist» (con la copertina e da dove viene). Un tocco e parte in
/// auto; una «solo in casa» lo spiega e propone di farla partire in casa.
Future<void> mostraDallaCasa(BuildContext context, GestoreMusicaDiCasa gestore, {bool daFermi = true}) {
  unawaited(gestore.aggiorna());
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SchedaDallaCasa(gestore: gestore, daFermi: daFermi),
    ),
  );
}

/// Il contenuto della scheda «Dalla casa».
class SchedaDallaCasa extends StatefulWidget {
  const SchedaDallaCasa({super.key, required this.gestore, this.daFermi = true, this.chiudi = true});

  final GestoreMusicaDiCasa gestore;
  final bool daFermi;

  /// Partita una voce, la scheda si chiude (sta in un foglio).
  final bool chiudi;

  @override
  State<SchedaDallaCasa> createState() => _SchedaDallaCasaState();
}

class _SchedaDallaCasaState extends State<SchedaDallaCasa> {
  String? _messaggio;

  Future<void> _tocca(VoceDiCasa v) async {
    final g = widget.gestore;
    final r = g.come(v);
    if (r.dove == DoveSuona.soloInCasa) {
      await _soloInCasa(v, r);
      return;
    }
    final esito = await g.suona(v, daFermi: widget.daFermi);
    if (!mounted) return;
    if (esito == null) {
      if (widget.chiudi) Navigator.of(context).maybePop();
    } else {
      setState(() => _messaggio = esito);
    }
  }

  Future<void> _soloInCasa(VoceDiCasa v, Riproduzione r) async {
    final g = widget.gestore;
    final avvia = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('solo-in-casa'),
        icon: const Icon(Icons.speaker_group_rounded),
        title: Text(v.titolo),
        content: Text(r.spiegazione ?? 'Si suona solo sui lettori di casa.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annulla')),
          if (v.inCasa)
            FilledButton(
              key: const Key('avvia-in-casa'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Avvia in casa'),
            ),
        ],
      ),
    );
    if (avvia != true) return;
    final detto = await g.avviaInCasa(v);
    if (mounted) setState(() => _messaggio = detto);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.gestore,
    builder: (context, _) {
      final g = widget.gestore;
      final tema = Theme.of(context);
      final t = tema.textTheme;
      final tenue = tema.colorScheme.onSurfaceVariant;
      final radio = g.radio;
      final playlist = g.playlist;
      Widget sezione(String titolo, String sotto) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(titolo, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sotto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(color: tenue),
              ),
            ),
          ],
        ),
      );
      final vuota = g.elenco?.vuoto ?? false;
      // Di traverso non ci sta tutta: si scorre.
      return SingleChildScrollView(
        child: Column(
          key: const Key('scheda-dalla-casa'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.home_rounded, color: tema.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Dalla casa', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  if (g.caricando)
                    const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  else
                    IconButton(
                      tooltip: 'Aggiorna',
                      onPressed: () => g.aggiorna(forza: true),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
              child: Text(
                'Le radio e le playlist della plancia, da ascoltare qui in auto.',
                style: t.bodySmall?.copyWith(color: tenue),
              ),
            ),
            if (g.errore case final e? when g.elenco == null)
              Padding(
                key: const Key('dalla-casa-errore'),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Text(e, style: t.bodyMedium),
              )
            else if (vuota)
              Padding(
                key: const Key('dalla-casa-vuota'),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Text(
                  'Nella plancia non ci sono ancora radio preferite né playlist: le radio si scelgono in Config › '
                  'Musica › Radio, le playlist sono quelle dei lettori della pagina Musica.',
                  style: t.bodyMedium,
                ),
              )
            else ...[
              sezione('Radio', radio.isEmpty ? 'Nessuna preferita' : 'Le preferite della casa'),
              _Riga(
                altezza: 128,
                voci: radio,
                gestore: g,
                onTap: _tocca,
                disegna: (v) => _Radio(voce: v, come: g.come(v), inAvvio: g.inAvvio == v.id),
              ),
              sezione('Playlist', 'Dai lettori della pagina Musica'),
              _Riga(
                altezza: 186,
                voci: playlist,
                gestore: g,
                onTap: _tocca,
                disegna: (v) => _Playlist(voce: v, come: g.come(v), inAvvio: g.inAvvio == v.id),
              ),
            ],
            if (_messaggio case final m?)
              Padding(
                key: const Key('dalla-casa-messaggio'),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(m, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

class _Riga extends StatelessWidget {
  const _Riga({
    required this.altezza,
    required this.voci,
    required this.gestore,
    required this.onTap,
    required this.disegna,
  });

  final double altezza;
  final List<VoceDiCasa> voci;
  final GestoreMusicaDiCasa gestore;
  final void Function(VoceDiCasa) onTap;
  final Widget Function(VoceDiCasa) disegna;

  @override
  Widget build(BuildContext context) {
    if (voci.isEmpty) {
      return SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(gestore.caricando ? 'Chiedo alla casa…' : '—', style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }
    return SizedBox(
      height: altezza,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: voci.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => InkWell(
          key: Key('dalla-casa-${voci[i].id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTap(voci[i]),
          child: disegna(voci[i]),
        ),
      ),
    );
  }
}

/// L'immagine di una voce, o un segno al suo posto.
class _Immagine extends StatelessWidget {
  const _Immagine({required this.voce, required this.lato, required this.tondo});

  final VoceDiCasa voce;
  final double lato;
  final bool tondo;

  @override
  Widget build(BuildContext context) {
    final colori = Theme.of(context).colorScheme;
    final img = voce.immagine;
    final dentro = img != null
        ? Image.memory(img, fit: BoxFit.cover, gaplessPlayback: true)
        : ColoredBox(
            color: colori.primaryContainer,
            child: Icon(
              voce.tipo == TipoDiCasa.radio ? Icons.radio_rounded : Icons.queue_music_rounded,
              size: lato * 0.42,
              color: colori.onPrimaryContainer,
            ),
          );
    return SizedBox.square(
      dimension: lato,
      child: tondo ? ClipOval(child: dentro) : ClipRRect(borderRadius: BorderRadius.circular(14), child: dentro),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.voce, required this.come, required this.inAvvio});

  final VoceDiCasa voce;
  final Riproduzione come;
  final bool inAvvio;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: come.suonaInAuto ? 1 : 0.45,
                child: _Immagine(voce: voce, lato: 76, tondo: true),
              ),
              if (!come.suonaInAuto)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.black.withValues(alpha: 0.75),
                    child: const Icon(Icons.home_rounded, size: 16, color: Colors.white),
                  ),
                ),
              if (inAvvio) const SizedBox.square(dimension: 80, child: CircularProgressIndicator(strokeWidth: 3)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            voce.titolo,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.15),
          ),
        ],
      ),
    );
  }
}

class _Playlist extends StatelessWidget {
  const _Playlist({required this.voce, required this.come, required this.inAvvio});

  final VoceDiCasa voce;
  final Riproduzione come;
  final bool inAvvio;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final inAuto = come.suonaInAuto;
    final colore = inAuto ? tema.colorScheme.primary : tema.colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Opacity(
                opacity: inAuto ? 1 : 0.55,
                child: _Immagine(voce: voce, lato: 120, tondo: false),
              ),
              if (inAvvio) const Positioned.fill(child: Center(child: CircularProgressIndicator(strokeWidth: 3))),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: inAuto ? tema.colorScheme.primary : Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        inAuto ? Icons.directions_car_rounded : Icons.home_rounded,
                        size: 13,
                        color: inAuto ? tema.colorScheme.onPrimary : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        come.etichetta,
                        style: t.labelSmall?.copyWith(
                          color: inAuto ? tema.colorScheme.onPrimary : Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            voce.titolo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            voce.provenienza,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: colore),
          ),
        ],
      ),
    );
  }
}

/// Il tasto «Dalla casa» accanto al lettore: un tondo con la casa e la nota.
class TastoDallaCasa extends StatelessWidget {
  const TastoDallaCasa({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Musica dalla casa',
    excludeSemantics: true,
    child: Vetro(
      key: const Key('lettore-dalla-casa'),
      forma: BoxShape.circle,
      onTap: onTap,
      child: const SizedBox.square(
        dimension: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.home_rounded, size: 30),
            Positioned(right: 10, bottom: 10, child: Icon(Icons.music_note_rounded, size: 16)),
          ],
        ),
      ),
    ),
  );
}
