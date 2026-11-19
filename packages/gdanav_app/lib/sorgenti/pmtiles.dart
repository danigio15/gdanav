import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Da dove si leggono i byte di un pacchetto: [lunghezza] byte da [inizio].
typedef LeggiByte = Future<Uint8List> Function(int inizio, int lunghezza);

/// Un pacchetto PMTiles (versione 3): le tessere si leggono quando servono,
/// senza caricarlo tutto. Dal file sul telefono ([apri]) o, un pezzo alla
/// volta, dal server che lo tiene ([inRete]).
///
/// Serve agli edifici di Overture per la scena 3D ([GestoreEdifici]): un
/// pacchetto per zona, scaricato una volta. Il formato è quello di
/// https://github.com/protomaps/PMTiles (v3): un'intestazione di 127 byte, le
/// cartelle compresse con gli indirizzi delle tessere (numerate lungo la curva
/// di Hilbert), e le tessere.
class LettorePmtiles {
  LettorePmtiles._(this._leggiByte, this._h, this._chiudi, [this._testa]);

  final LeggiByte _leggiByte;
  final _Intestazione _h;
  final Future<void> Function() _chiudi;

  /// I primi byte del pacchetto, già letti all'apertura (in rete: l'intestazione
  /// e la cartella principale con una richiesta sola).
  final Uint8List? _testa;

  /// Le cartelle già lette, per non rileggerle a ogni tessera.
  final _cartelle = <int, List<_Voce>>{};

  /// Quanti byte si leggono all'apertura di un pacchetto in rete: l'intestazione
  /// e, quasi sempre, la cartella principale (il formato la vuole entro i
  /// primi 16 KiB).
  static const testaInRete = 16384;

  /// Apre [percorso]; solleva [FormatException] se non è un PMTiles v3.
  static Future<LettorePmtiles> apri(String percorso) async {
    final f = await File(percorso).open();
    try {
      final h = _Intestazione.leggi(await _leggi(f, 0, 127));
      return LettorePmtiles._((i, n) => _leggi(f, i, n), h, f.close);
    } catch (_) {
      await f.close();
      rethrow;
    }
  }

  /// Apre un pacchetto che non è sul telefono, leggendolo a pezzi ([leggi]:
  /// per esempio [SorgenteHttp.leggi]). La prima lettura prende
  /// [testaInRete] byte (o meno, se il pacchetto è più corto: [lunghezza]).
  static Future<LettorePmtiles> daSorgente(LeggiByte leggi, {int? lunghezza}) async {
    final n = lunghezza == null ? testaInRete : lunghezza.clamp(127, testaInRete);
    final testa = await leggi(0, n);
    final h = _Intestazione.leggi(testa);
    return LettorePmtiles._(leggi, h, () async {}, testa);
  }

  /// Zoom minimo e massimo delle tessere dentro.
  int get zoomMinimo => _h.zoomMinimo;
  int get zoomMassimo => _h.zoomMassimo;

  /// La tessera [z]/[x]/[y] così com'è nel file (decompressa se era gzip);
  /// `null` se non c'è.
  Future<Uint8List?> tessera(int z, int x, int y) async {
    if (z < _h.zoomMinimo || z > _h.zoomMassimo) return null;
    final id = idTessera(z, x, y);
    var inizio = _h.radiceInizio, lunghezza = _h.radiceLunghezza;
    // Al più quattro livelli di cartelle, come dice il formato.
    for (var livello = 0; livello < 4; livello++) {
      final voci = await _cartella(inizio, lunghezza);
      final v = _cerca(voci, id);
      if (v == null) return null;
      if (v.ripetute > 0) {
        if (id >= v.id + v.ripetute) return null;
        final dati = await _byte(_h.datiInizio + v.posizione, v.lunghezza);
        return _h.compressioneTessere == _gzip ? Uint8List.fromList(gzip.decode(dati)) : dati;
      }
      // Una cartella foglia.
      inizio = _h.fogliaInizio + v.posizione;
      lunghezza = v.lunghezza;
    }
    return null;
  }

  Future<void> chiudi() => _chiudi();

  /// [lunghezza] byte da [inizio]: dalla testa già letta, se ci sono.
  Future<Uint8List> _byte(int inizio, int lunghezza) {
    final t = _testa;
    if (t != null && inizio + lunghezza <= t.length) {
      return Future.value(Uint8List.sublistView(t, inizio, inizio + lunghezza));
    }
    return _leggiByte(inizio, lunghezza);
  }

  Future<List<_Voce>> _cartella(int inizio, int lunghezza) async {
    final gia = _cartelle[inizio];
    if (gia != null) return gia;
    var dati = await _byte(inizio, lunghezza);
    if (_h.compressioneInterna == _gzip) dati = Uint8List.fromList(gzip.decode(dati));
    final voci = _leggiCartella(dati);
    if (_cartelle.length > 64) _cartelle.remove(_cartelle.keys.first);
    _cartelle[inizio] = voci;
    return voci;
  }

  static Future<Uint8List> _leggi(RandomAccessFile f, int inizio, int lunghezza) async {
    await f.setPosition(inizio);
    final b = await f.read(lunghezza);
    if (b.length != lunghezza) throw const FormatException('PMTiles: file troncato');
    return b;
  }
}

const _gzip = 2;

/// I byte di un pacchetto sul server, a pezzi (richieste HTTP «Range»).
///
/// I pacchetti degli edifici stanno nella release di GitHub, che risponde
/// con un rinvio (302) a un indirizzo firmato per mezz'ora: lo si chiede una
/// volta e lo si tiene per [validitaRinvio], così ogni tessera è una
/// richiesta sola. Un server che non dà pezzi (risponde 200 col pacchetto
/// intero) è un errore: si scaricherebbero decine di megabyte per una
/// tessera.
class SorgenteHttp {
  SorgenteHttp(
    this._http,
    this.indirizzo, {
    this.validitaRinvio = const Duration(minutes: 20),
    this.attesa = const Duration(seconds: 12),
    this.letti,
  });

  final http.Client _http;

  /// Dove sta il pacchetto (quello pubblico, prima del rinvio).
  final Uri indirizzo;

  /// Quanto si tiene l'indirizzo firmato del rinvio.
  final Duration validitaRinvio;

  /// Quanto si aspetta una risposta.
  final Duration attesa;

  /// Chi conta i byte arrivati (per il limite sui dati a consumo).
  final void Function(int byte)? letti;

  Uri? _vero;
  DateTime? _veroDal;

  Future<Uint8List> leggi(int inizio, int lunghezza) async {
    try {
      return await _leggi(inizio, lunghezza, rinvioNuovo: false);
    } on _RinvioScaduto {
      // L'indirizzo firmato è scaduto prima del previsto: se ne chiede un altro.
      return _leggi(inizio, lunghezza, rinvioNuovo: true);
    }
  }

  Future<Uint8List> _leggi(int inizio, int lunghezza, {required bool rinvioNuovo}) async {
    if (lunghezza <= 0) return Uint8List(0);
    final dal = _veroDal;
    final usaVero = !rinvioNuovo && _vero != null && dal != null && DateTime.now().difference(dal) < validitaRinvio;
    final r = http.Request('GET', usaVero ? _vero! : indirizzo)
      ..followRedirects = false
      ..headers['Range'] = 'bytes=$inizio-${inizio + lunghezza - 1}';
    var risposta = await _http.send(r).timeout(attesa);
    if (!usaVero && (risposta.statusCode == 301 || risposta.statusCode == 302 || risposta.statusCode == 307)) {
      final dove = risposta.headers['location'];
      await risposta.stream.drain<void>();
      if (dove == null) throw const HttpException('rinvio senza indirizzo');
      _vero = indirizzo.resolve(dove);
      _veroDal = DateTime.now();
      final r2 = http.Request('GET', _vero!)
        ..followRedirects = false
        ..headers['Range'] = r.headers['Range']!;
      risposta = await _http.send(r2).timeout(attesa);
    } else if (!usaVero && risposta.statusCode == 206) {
      // Nessun rinvio: il server dà i pezzi da sé.
      _vero = indirizzo;
      _veroDal = DateTime.now();
    }
    if (usaVero && (risposta.statusCode == 401 || risposta.statusCode == 403)) {
      await risposta.stream.drain<void>();
      _vero = null;
      throw const _RinvioScaduto();
    }
    if (risposta.statusCode != 206) {
      // Niente pezzi (200: il pacchetto intero): non lo si legge.
      unawaited(risposta.stream.drain<void>().catchError((Object _) {}));
      throw HttpException('pacchetto in rete: risposta ${risposta.statusCode}');
    }
    final b = await risposta.stream.toBytes().timeout(attesa);
    letti?.call(b.length);
    if (b.length != lunghezza) throw const FormatException('PMTiles in rete: pezzo troncato');
    return b;
  }
}

class _RinvioScaduto implements Exception {
  const _RinvioScaduto();
}

/// Il numero della tessera [z]/[x]/[y] lungo la curva di Hilbert, come nel
/// formato PMTiles: prima tutte quelle degli zoom più bassi.
int idTessera(int z, int x, int y) {
  if (z < 0 || z > 26) throw RangeError.range(z, 0, 26, 'z');
  final n = 1 << z;
  if (x < 0 || y < 0 || x >= n || y >= n) throw RangeError('tessera fuori: $z/$x/$y');
  var prima = 0;
  for (var i = 0; i < z; i++) {
    prima += 1 << (2 * i);
  }
  var px = x, py = y, d = 0;
  for (var s = n >> 1; s > 0; s >>= 1) {
    final rx = (px & s) > 0 ? 1 : 0;
    final ry = (py & s) > 0 ? 1 : 0;
    d += s * s * ((3 * rx) ^ ry);
    if (ry == 0) {
      if (rx == 1) {
        px = s - 1 - px;
        py = s - 1 - py;
      }
      final t = px;
      px = py;
      py = t;
    }
  }
  return prima + d;
}

class _Intestazione {
  const _Intestazione({
    required this.radiceInizio,
    required this.radiceLunghezza,
    required this.fogliaInizio,
    required this.datiInizio,
    required this.compressioneInterna,
    required this.compressioneTessere,
    required this.zoomMinimo,
    required this.zoomMassimo,
  });

  factory _Intestazione.leggi(Uint8List b) {
    if (b.length < 127 || String.fromCharCodes(b.sublist(0, 7)) != 'PMTiles' || b[7] != 3) {
      throw const FormatException('non è un PMTiles v3');
    }
    final d = ByteData.sublistView(b);
    int u64(int o) => d.getUint64(o, Endian.little);
    return _Intestazione(
      radiceInizio: u64(8),
      radiceLunghezza: u64(16),
      fogliaInizio: u64(40),
      datiInizio: u64(56),
      compressioneInterna: b[97],
      compressioneTessere: b[98],
      zoomMinimo: b[100],
      zoomMassimo: b[101],
    );
  }

  final int radiceInizio, radiceLunghezza, fogliaInizio, datiInizio;
  final int compressioneInterna, compressioneTessere, zoomMinimo, zoomMassimo;
}

class _Voce {
  _Voce(this.id);
  final int id;
  int ripetute = 0, lunghezza = 0, posizione = 0;
}

List<_Voce> _leggiCartella(Uint8List b) {
  var i = 0;
  int varint() {
    var v = 0, s = 0;
    while (true) {
      if (i >= b.length) throw const FormatException('PMTiles: cartella troncata');
      final c = b[i++];
      v |= (c & 0x7f) << s;
      if (c < 0x80) return v;
      s += 7;
    }
  }

  final n = varint();
  final voci = <_Voce>[];
  var id = 0;
  for (var k = 0; k < n; k++) {
    id += varint();
    voci.add(_Voce(id));
  }
  for (final v in voci) {
    v.ripetute = varint();
  }
  for (final v in voci) {
    v.lunghezza = varint();
  }
  for (var k = 0; k < n; k++) {
    final o = varint();
    voci[k].posizione = o == 0 && k > 0 ? voci[k - 1].posizione + voci[k - 1].lunghezza : o - 1;
  }
  return voci;
}

/// La voce con l'id più grande non oltre [id].
_Voce? _cerca(List<_Voce> voci, int id) {
  var lo = 0, hi = voci.length - 1;
  while (lo <= hi) {
    final m = (lo + hi) >> 1;
    final c = voci[m].id;
    if (c == id) return voci[m];
    if (c < id) {
      lo = m + 1;
    } else {
      hi = m - 1;
    }
  }
  if (hi >= 0) {
    final v = voci[hi];
    // Una cartella foglia copre tutto quello che viene dopo il suo id.
    if (v.ripetute == 0 || id - v.id < v.ripetute) return v;
  }
  return null;
}
