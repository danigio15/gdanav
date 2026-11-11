/// I messaggi fra l'app e la mappa 3D (la pagina di `assets/web3d`, nella
/// WebView). Solo dati, niente WebView: così si provano da soli.
///
/// Verso la mappa: un oggetto `{v: 1, tipo, …}` passato a
/// `gdanav3d.ricevi(…)` (vedi [chiamata3d]). Dalla mappa: una stringa JSON
/// `{tipo, …}` sul canale `Gdanav3d` (vedi [MessaggioDalla3d]). Lo stesso
/// formato lo controlla `web3d/src/messaggi.js`, con le sue prove.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gdanav_core/gdanav_core.dart';

import 'controllo_mappa.dart';
import 'dati_viaggio.dart' show trattoManovraM;
import 'segnaposto.dart';

/// La versione dei messaggi: la pagina scarta quelli di un'altra.
const versionePonte3d = 1;

/// Il canale su cui la pagina risponde.
const canale3d = 'Gdanav3d';

/// La pagina della mappa 3D, fra le risorse del pacchetto.
const paginaMappa3d = 'packages/gdanav_app/assets/web3d/index.html';

/// Il JavaScript che consegna [m] alla pagina. Il JSON è anche JavaScript
/// valido: niente da sfuggire.
String chiamata3d(Map<String, Object?> m) => 'window.gdanav3d&&window.gdanav3d.ricevi(${jsonEncode(m)});';

Map<String, Object?> _m(String tipo, Map<String, Object?> dati) => {'v': versionePonte3d, 'tipo': tipo, ...dati};

/// Sei decimali: dieci centimetri, e il JSON di un percorso lungo resta piccolo.
double _sei(double x) => (x * 1e6).roundToDouble() / 1e6;

/// Giorno o notte, la vista, il colore dell'auto e il segnaposto (per la
/// mappa vista da lontano, dove l'auto 3D non si vede).
///
/// [edifici]: l'app sa dare gli edifici di Overture ([msgEdifici]); la
/// pagina li chiede per ogni tessera che costruisce.
Map<String, Object?> msgOpzioni({
  required bool notte,
  required VistaMappa vista,
  required Segnaposto segnaposto,
  bool edifici = false,
}) => _m('opzioni', {
  'notte': notte,
  'vista': vista == VistaMappa.immersiva ? 'immersiva' : 'inclinata',
  'auto': coloreAuto3d(segnaposto),
  'icona': segnaposto.immagine,
  if (edifici) 'edifici': true,
});

/// Gli edifici di Overture della tessera [z]/[x]/[y] (una tessera vettoriale
/// col solo livello `building`), o `null` se non ci sono: la pagina usa
/// allora quelli di sempre.
Map<String, Object?> msgEdifici(int z, int x, int y, Uint8List? dati) =>
    _m('edifici', {'z': z, 'x': x, 'y': y, 'dati': dati == null ? null : base64Encode(dati)});

/// Lo stile di sempre (`stileMappa`): la pagina lo adatta al 3D da sé.
Map<String, Object?> msgStile(Map<String, Object> stile) => _m('stile', {'stile': stile});

/// Un'immagine dello stile (icone, bandiera, autovelox), come PNG.
Map<String, Object?> msgImmagine(String nome, Uint8List png, {double ratio = 3}) =>
    _m('immagine', {'nome': nome, 'png': base64Encode(png), 'ratio': ratio});

/// I dati di una sorgente GeoJSON dello stile (colonnine, meta, segnalazioni…).
Map<String, Object?> msgSorgente(String id, Map<String, Object?> dati) => _m('sorgente', {'id': id, 'dati': dati});

/// Il percorso: i punti (longitudine, latitudine), i loro metri dalla
/// partenza e le code, in metri lungo il percorso come [Coda]. Senza
/// viaggio, `punti: null`.
Map<String, Object?> msgPercorso(Viaggio? v) {
  final punti = v?.percorso.punti ?? const <Punto>[];
  final buoni = [
    for (final p in punti)
      if (p.lat.isFinite && p.lon.isFinite) p,
  ];
  if (buoni.length < 2) return _m('percorso', {'punti': null});
  // I metri di ogni punto come li conta la guida: la posizione, le code e la
  // freccia arrivano in questi metri, e in pianta (Mercatore) un percorso
  // lungo da nord a sud li sbaglierebbe di qualche per cento.
  final cumulate = Linea(buoni).cumulate;
  return _m('percorso', {
    'punti': [
      for (final p in buoni) ...[_sei(p.lon), _sei(p.lat)],
    ],
    'metri': [for (final m in cumulate) (m * 10).roundToDouble() / 10],
    'code': [
      for (final c in v!.percorso.code)
        if (c.daM.isFinite && c.aM.isFinite && c.aM > c.daM) [c.daM.roundToDouble(), c.aM.roundToDouble(), c.livello],
    ],
  });
}

/// La freccia della prossima manovra: da dove a dove (metri lungo il
/// percorso), come `datiManovra`; o niente.
Map<String, Object?> msgManovra(Viaggio? v, Manovra? m) {
  final t = trattoManovraM(v, m);
  return _m('manovra', {'da': t?.$1, 'a': t?.$2});
}

/// La strada proposta in guida (verde), o niente.
Map<String, Object?> msgRisparmio(PropostaStrada? p) {
  final punti = p?.percorso.punti ?? const <Punto>[];
  if (punti.length < 2) return _m('risparmio', {'punti': null});
  return _m('risparmio', {
    'punti': [
      for (final q in punti)
        if (q.lat.isFinite && q.lon.isFinite) ...[_sei(q.lon), _sei(q.lat)],
    ],
  });
}

/// Dove si è: il punto, la rotta, i metri lungo il percorso (o `null` fuori
/// dal percorso), la velocità in m/s, lo zoom voluto e quando è stata letta
/// (ms dall'epoca: la pagina la porta avanti fino ad adesso).
///
/// [lettura] è il GPS com'era (`GestoreGuida.letturaSulPercorso`): con lei
/// la pagina fa da sé, col suo filtro, dove sta l'auto adesso.
Map<String, Object?> msgPosizione({
  required Punto qui,
  required double rotta,
  required double? metri,
  required double velocitaMs,
  required double zoom,
  required DateTime quando,
  ({double metri, DateTime alle, double? velocitaMs, double? precisioneM})? lettura,
  bool zoomSubito = false,
}) => _m('posizione', {
  'lat': _sei(qui.lat),
  'lon': _sei(qui.lon),
  'rotta': ((rotta % 360) * 10).roundToDouble() / 10,
  'metri': metri == null || !metri.isFinite ? null : (metri * 10).roundToDouble() / 10,
  'velocita': velocitaMs.isFinite ? math.max(0.0, (velocitaMs * 10).roundToDouble() / 10) : 0.0,
  'zoom': (zoom * 100).roundToDouble() / 100,
  // Lo zoom l'ha appena scelto chi guida, coi tasti: la pagina ci va subito.
  if (zoomSubito) 'zoomSubito': true,
  'quando': quando.millisecondsSinceEpoch,
  if (lettura != null && lettura.metri.isFinite)
    'lettura': {
      'metri': (lettura.metri * 10).roundToDouble() / 10,
      'alle': lettura.alle.millisecondsSinceEpoch,
      if (lettura.velocitaMs case final v? when v.isFinite) 'v': (math.max(0.0, v) * 100).roundToDouble() / 100,
      if (lettura.precisioneM case final p? when p.isFinite && p > 0) 'precisione': (p * 10).roundToDouble() / 10,
    },
});

/// La velocità dell'auto dal cruscotto (Android Auto, il dongle, Home
/// Assistant), [ms] m/s letta [alle]: più volte al secondo e senza il
/// ritardo del GPS, muove la freccia in partenza e in frenata.
///
/// Il campo è `ms` e non `v`: `v` è la versione del messaggio ([_m]).
Map<String, Object?> msgVelocita({required double ms, required DateTime alle}) =>
    _m('velocita', {'ms': (math.max(0.0, ms) * 100).roundToDouble() / 100, 'alle': alle.millisecondsSinceEpoch});

/// Come si muove la telecamera.
enum ModoCamera3d { segui, libera, panoramica }

/// La telecamera: segue l'auto, è libera (un dito l'ha spostata), o mostra
/// tutta la strada ([riquadro]: sud, ovest, nord, est). [sopra]: quanto alto
/// copre un popup (in punti).
Map<String, Object?> msgCamera(
  ModoCamera3d modo, {
  double sopra = 0,
  double sinistra = 0,
  double destra = 0,
  double? pitch,
  (Punto, Punto)? riquadro,
}) => _m('camera', {
  'modo': modo.name,
  'sopra': sopra,
  if (sinistra > 0) 'sinistra': sinistra,
  if (destra > 0) 'destra': destra,
  'pitch': ?pitch,
  if (riquadro case (final so, final ne)?) 'riquadro': [so.lat, so.lon, ne.lat, ne.lon],
});

/// L'app va in secondo piano (o torna): la mappa smette di disegnare.
Map<String, Object?> msgPausa(bool si) => _m('pausa', {'si': si});

/// Il colore dell'auto 3D. La freccia (la scelta di partenza) è l'auto rossa:
/// «crea un colore che vada in contrasto con la linea del percorso». Le
/// altre auto hanno il loro colore, la blu un blu più scuro del percorso.
String coloreAuto3d(Segnaposto s) => switch (s) {
  Segnaposto.freccia || Segnaposto.autoRossa => '#d62a26',
  Segnaposto.autoBlu => '#1e3a8a',
  Segnaposto.autoBianca => '#f1f3f5',
  Segnaposto.autoNera => '#22252b',
  Segnaposto.autoGrigia => '#8a9099',
};

/// Lo zoom della mappa 3D in guida: vicino come il prototipo approvato, più
/// lontano su una strada veloce con la prossima manovra lontana
/// ([zoomLontanoInGuida], lo stesso della mappa di sempre e dell'auto).
double zoom3d(VistaMappa vista, {required double velocitaStradaKmh, required double allaProssimaM}) =>
    (vista == VistaMappa.immersiva ? 18.3 : 17.9) +
    zoomLontanoInGuida(velocitaStradaKmh: velocitaStradaKmh, allaProssimaM: allaProssimaM);

/// Un messaggio dalla pagina.
sealed class MessaggioDalla3d {
  const MessaggioDalla3d();

  /// Il messaggio in [testo]; `null` se non si capisce.
  static MessaggioDalla3d? leggi(String testo) {
    final Object? j;
    try {
      j = jsonDecode(testo);
    } on FormatException {
      return null;
    }
    if (j is! Map) return null;
    return switch (j['tipo']) {
      'caricata' => const Caricata3d(),
      'pronto' => const Pronta3d(),
      'errore' => Errore3d('${j['motivo'] ?? 'sconosciuto'}', gpu: j['gpu'] as String?),
      'prestazioni' => Prestazioni3d(
        fps: (j['fps'] as num?)?.toDouble() ?? 0,
        lento: j['lento'] == true,
        triangoli: (j['triangoli'] as num?)?.toInt() ?? 0,
      ),
      'toccata' => const Toccata3d(),
      'edifici?' => switch ((j['z'], j['x'], j['y'])) {
        (final int z, final int x, final int y) => ChiestiEdifici3d(z, x, y),
        _ => null,
      },
      'tocco' => Tocco3d([
        for (final e in (j['elementi'] as List?) ?? const [])
          if (e is Map) e.cast<Object?, Object?>(),
      ]),
      _ => null,
    };
  }
}

/// Se un messaggio della pagina vuol dire che il 3D aumentato non va: il
/// perché, e se ricordarlo (il telefono non ce la fa: WebGL 2 che manca,
/// solo in software, troppo lento) o no (un intoppo di questa volta).
/// `null`: va.
(String, bool)? nonVaPer(MessaggioDalla3d m) => switch (m) {
  Errore3d(:final motivo) => (motivo, motiviDaRicordare.contains(motivo)),
  Prestazioni3d(lento: true) => ('lento', true),
  _ => null,
};

/// I motivi per cui il 3D aumentato su questo telefono non andrà mai.
const motiviDaRicordare = {'webgl2', 'software', 'trame', 'memoria', 'mappa', 'webview', 'lento'};

/// La pagina è caricata: si può mandare lo stile.
class Caricata3d extends MessaggioDalla3d {
  const Caricata3d();
}

/// Lo stile è pronto: la mappa disegna.
class Pronta3d extends MessaggioDalla3d {
  const Pronta3d();
}

/// Il 3D non parte ([motivo]: `webgl2`, `software`, `trame`, `memoria`,
/// `contesto`, `mappa`, `script`…): si torna alla mappa di sempre.
class Errore3d extends MessaggioDalla3d {
  const Errore3d(this.motivo, {this.gpu});
  final String motivo;
  final String? gpu;
}

/// Quanti fotogrammi al secondo fa davvero, nei primi secondi di guida.
class Prestazioni3d extends MessaggioDalla3d {
  const Prestazioni3d({required this.fps, required this.lento, required this.triangoli});
  final double fps;
  final bool lento;
  final int triangoli;
}

/// Un dito ha spostato la mappa.
class Toccata3d extends MessaggioDalla3d {
  const Toccata3d();
}

/// Un tocco su qualcosa (colonnina, distributore, punto): gli elementi come
/// li dà MapLibre (`properties`, `geometry`).
/// La pagina chiede gli edifici di Overture della tessera [z]/[x]/[y].
class ChiestiEdifici3d extends MessaggioDalla3d {
  const ChiestiEdifici3d(this.z, this.x, this.y);
  final int z, x, y;
}

class Tocco3d extends MessaggioDalla3d {
  const Tocco3d(this.elementi);
  final List<Map<Object?, Object?>> elementi;
}
