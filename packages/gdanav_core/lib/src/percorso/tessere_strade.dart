import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../geo/geo.dart';
import '../guida/aggancio_strada.dart';

/* ─── Le strade di OpenStreetMap da una tessera vettoriale ──────────────────
 *
 * Per sapere dove una strada è a senso unico ([correggiContromano]) servono
 * le strade vere, coi loro sensi: le stesse che la mappa disegna, dalle
 * tessere vettoriali di OpenFreeMap (schema OpenMapTiles, livello
 * `transportation`, attributo `oneway`: 1 nel verso della linea, -1 al
 * contrario). Una tessera a zoom 14 copre un paio di chilometri; qui la si
 * legge da sé (Mapbox Vector Tile, protobuf), senza pacchetti: servono solo
 * le linee delle strade per le auto. */

/// Lo zoom delle tessere da cui si leggono le strade: il più fitto di
/// OpenMapTiles, dove ci sono tutte e coi loro sensi unici.
const zoomTessereStrade = 14;

/// Le classi di OpenMapTiles su cui va un'auto.
const classiStradeAuto = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'service'};

/// La tessera [z] che contiene [p].
({int x, int y}) tesseraDi(Punto p, [int z = zoomTessereStrade]) {
  final n = 1 << z;
  final x = ((p.lon + 180) / 360 * n).floor().clamp(0, n - 1);
  final lat = p.lat.clamp(-85.0511, 85.0511) * math.pi / 180;
  final y = ((1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * n).floor().clamp(0, n - 1);
  return (x: x, y: y);
}

/// Le tessere [z] che coprono i [punti], allargate di [marginiM] metri
/// attorno a ognuno (un bivio sul bordo di una tessera ha l'altro ramo in
/// quella accanto).
Set<({int x, int y})> tessereAttorno(Iterable<Punto> punti, {double marginiM = 150, int z = zoomTessereStrade}) {
  final out = <({int x, int y})>{};
  for (final p in punti) {
    final dLat = marginiM / 111195.0, dLon = marginiM / (111195.0 * math.cos(p.lat * math.pi / 180));
    for (final q in [
      p,
      Punto(p.lat + dLat, p.lon + dLon),
      Punto(p.lat + dLat, p.lon - dLon),
      Punto(p.lat - dLat, p.lon + dLon),
      Punto(p.lat - dLat, p.lon - dLon),
    ]) {
      out.add(tesseraDi(q, z));
    }
  }
  return out;
}

/// Le strade per le auto della tessera [z]/[x]/[y] ([dati]: la tessera così
/// com'è, già senza gzip), coi loro sensi unici e la loro classe. Una
/// tessera rotta o di un altro schema dà una lista vuota.
List<TrattoStrada> stradeDaTessera(Uint8List dati, int z, int x, int y) {
  try {
    return _leggi(dati, z, x, y);
  } on Object {
    return const [];
  }
}

List<TrattoStrada> _leggi(Uint8List dati, int z, int x, int y) {
  final out = <TrattoStrada>[];
  final t = _Protobuf(dati);
  while (t.resta) {
    final (campo, tipo) = t.chiave();
    if (campo == 3 && tipo == 2) {
      out.addAll(_livello(t.sotto(), z, x, y));
    } else {
      t.salta(tipo);
    }
  }
  return out;
}

List<TrattoStrada> _livello(_Protobuf l, int z, int x, int y) {
  var nome = '';
  var estensione = 4096;
  final chiavi = <String>[];
  final valori = <Object?>[];
  final elementi = <_Protobuf>[];
  while (l.resta) {
    final (campo, tipo) = l.chiave();
    switch ((campo, tipo)) {
      case (1, 2):
        nome = l.testo();
      case (2, 2):
        elementi.add(l.sotto());
      case (3, 2):
        chiavi.add(l.testo());
      case (4, 2):
        valori.add(_valore(l.sotto()));
      case (5, 0):
        estensione = l.varint();
      default:
        l.salta(tipo);
    }
    // Il nome arriva per primo: un livello che non è quello delle strade si
    // salta senza leggerne gli elementi.
    if (campo == 1 && nome != 'transportation') return const [];
  }
  if (nome != 'transportation') return const [];
  final out = <TrattoStrada>[];
  final n = 1 << z;
  Punto punto(int px, int py) {
    final lon = (x + px / estensione) / n * 360 - 180;
    final yy = (y + py / estensione) / n;
    final lat = math.atan(_sinh(math.pi * (1 - 2 * yy))) * 180 / math.pi;
    return Punto(lat, lon);
  }

  for (final e in elementi) {
    var tipoGeometria = 0;
    var etichette = const <int>[];
    var geometria = const <int>[];
    while (e.resta) {
      final (campo, tipo) = e.chiave();
      switch ((campo, tipo)) {
        case (2, 2):
          etichette = e.impacchettati();
        case (3, 0):
          tipoGeometria = e.varint();
        case (4, 2):
          geometria = e.impacchettati();
        default:
          e.salta(tipo);
      }
    }
    if (tipoGeometria != 2) continue;
    final props = <String, Object?>{};
    for (var i = 0; i + 1 < etichette.length; i += 2) {
      final k = etichette[i], v = etichette[i + 1];
      if (k < chiavi.length && v < valori.length) props[chiavi[k]] = valori[v];
    }
    final classe = '${props['class'] ?? ''}';
    if (!classiStradeAuto.contains(classe)) continue;
    final senso = switch (props['oneway']) {
      final num v when v > 0 => 1,
      final num v when v < 0 => -1,
      _ => 0,
    };
    final rampa = props['ramp'] == 1 || props['ramp'] == true;
    final ponte = '${props['brunnel'] ?? ''}';
    // Le linee: MoveTo comincia una linea nuova, LineTo la allunga.
    var cx = 0, cy = 0;
    var linea = <Punto>[];
    void chiudi() {
      if (linea.length >= 2) {
        out.add(TrattoStrada(linea, senso: senso, classe: classe, rampa: rampa, ponte: ponte));
      }
      linea = <Punto>[];
    }

    var i = 0;
    while (i < geometria.length) {
      final comando = geometria[i] & 7, quanti = geometria[i] >> 3;
      i++;
      if (comando == 7) continue;
      if (comando == 1) chiudi();
      for (var k = 0; k < quanti && i + 1 < geometria.length; k++) {
        cx += _zigzag(geometria[i]);
        cy += _zigzag(geometria[i + 1]);
        i += 2;
        linea.add(punto(cx, cy));
      }
    }
    chiudi();
  }
  return out;
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

int _zigzag(int n) => (n >> 1) ^ -(n & 1);

Object? _valore(_Protobuf v) {
  Object? out;
  while (v.resta) {
    final (campo, tipo) = v.chiave();
    switch ((campo, tipo)) {
      case (1, 2):
        out = v.testo();
      case (2, 5):
        out = v.float32();
      case (3, 1):
        out = v.float64();
      case (4, 0):
        out = v.varint();
      case (5, 0):
        out = v.varint();
      case (6, 0):
        out = _zigzag(v.varint());
      case (7, 0):
        out = v.varint() != 0;
      default:
        v.salta(tipo);
    }
  }
  return out;
}

/// Un lettore di protobuf ridotto all'osso: quanto serve alle tessere.
class _Protobuf {
  _Protobuf(this._b, [int da = 0, int? a])
      : _i = da,
        _fine = a ?? _b.length;

  final Uint8List _b;
  int _i;
  final int _fine;

  bool get resta => _i < _fine;

  int varint() {
    var out = 0, scala = 1;
    while (true) {
      if (_i >= _fine) throw const FormatException('tessera troncata');
      final b = _b[_i++];
      out += (b & 0x7f) * scala;
      if (b < 0x80) return out;
      scala *= 128;
    }
  }

  (int, int) chiave() {
    final k = varint();
    return (k >> 3, k & 7);
  }

  _Protobuf sotto() {
    final n = varint();
    if (_i + n > _fine) throw const FormatException('tessera troncata');
    final s = _Protobuf(_b, _i, _i + n);
    _i += n;
    return s;
  }

  String testo() {
    final s = sotto();
    return utf8.decode(Uint8List.sublistView(_b, s._i, s._fine), allowMalformed: true);
  }

  List<int> impacchettati() {
    final s = sotto();
    final out = <int>[];
    while (s.resta) {
      out.add(s.varint());
    }
    return out;
  }

  double float32() {
    final v = ByteData.sublistView(_b, _i, _i + 4).getFloat32(0, Endian.little);
    _i += 4;
    return v;
  }

  double float64() {
    final v = ByteData.sublistView(_b, _i, _i + 8).getFloat64(0, Endian.little);
    _i += 8;
    return v;
  }

  void salta(int tipo) {
    switch (tipo) {
      case 0:
        varint();
      case 1:
        _i += 8;
      case 2:
        _i += varint();
      case 5:
        _i += 4;
      default:
        throw FormatException('tipo protobuf $tipo');
    }
    if (_i > _fine) throw const FormatException('tessera troncata');
  }
}
