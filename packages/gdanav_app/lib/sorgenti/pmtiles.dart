import 'dart:io';
import 'dart:typed_data';

/// Un pacchetto PMTiles (versione 3) sul telefono: le tessere si leggono dal
/// file quando servono, senza caricarlo tutto.
///
/// Serve agli edifici di Overture per la scena 3D ([GestoreEdifici]): un
/// pacchetto per zona, scaricato una volta. Il formato è quello di
/// https://github.com/protomaps/PMTiles (v3): un'intestazione di 127 byte, le
/// cartelle compresse con gli indirizzi delle tessere (numerate lungo la curva
/// di Hilbert), e le tessere.
class LettorePmtiles {
  LettorePmtiles._(this._file, this._h);

  final RandomAccessFile _file;
  final _Intestazione _h;

  /// Le cartelle già lette, per non rileggerle a ogni tessera.
  final _cartelle = <int, List<_Voce>>{};

  /// Apre [percorso]; solleva [FormatException] se non è un PMTiles v3.
  static Future<LettorePmtiles> apri(String percorso) async {
    final f = await File(percorso).open();
    try {
      final h = _Intestazione.leggi(await _leggi(f, 0, 127));
      return LettorePmtiles._(f, h);
    } catch (_) {
      await f.close();
      rethrow;
    }
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
        final dati = await _leggi(_file, _h.datiInizio + v.posizione, v.lunghezza);
        return _h.compressioneTessere == _gzip ? Uint8List.fromList(gzip.decode(dati)) : dati;
      }
      // Una cartella foglia.
      inizio = _h.fogliaInizio + v.posizione;
      lunghezza = v.lunghezza;
    }
    return null;
  }

  Future<void> chiudi() => _file.close();

  Future<List<_Voce>> _cartella(int inizio, int lunghezza) async {
    final gia = _cartelle[inizio];
    if (gia != null) return gia;
    var dati = await _leggi(_file, inizio, lunghezza);
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
