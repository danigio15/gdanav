import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';

/// Una foto della strada, scattata da chi ci è passato (Mapillary).
class FotoStrada {
  const FotoStrada({
    required this.id,
    required this.url,
    required this.punto,
    required this.direzione,
    required this.scattata,
    this.autore = '',
  });

  final String id;

  /// L'immagine larga 1024 pixel.
  final String url;
  final Punto punto;

  /// Verso dove guarda la fotocamera, in gradi da nord.
  final double direzione;
  final DateTime scattata;
  final String autore;

  /// La citazione che la licenza (CC BY-SA 4.0) chiede.
  String get citazione => '© ${autore.isEmpty ? 'Mapillary' : '$autore, Mapillary'} · ${scattata.year} · CC BY-SA';

  static FotoStrada? daJson(Object? j) {
    if (j is! Map) return null;
    final url = j['thumb_1024_url'], id = j['id'];
    final geo = (j['computed_geometry'] ?? j['geometry']) as Map?;
    final c = geo?['coordinates'] as List?;
    final dir = (j['computed_compass_angle'] ?? j['compass_angle']) as num?;
    final quando = j['captured_at'] as num?;
    if (url is! String || id == null || c == null || c.length < 2 || dir == null || quando == null) return null;
    return FotoStrada(
      id: '$id',
      url: url,
      punto: Punto((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      direzione: dir.toDouble(),
      scattata: DateTime.fromMillisecondsSinceEpoch(quando.toInt(), isUtc: true),
      autore: '${(j['creator'] as Map?)?['username'] ?? ''}',
    );
  }
}

/// Le foto delle strade di Mapillary: gratuite anche per uso commerciale,
/// con la citazione. Serve un «client token» (gratuito) dello sviluppatore.
class ClienteMapillary {
  ClienteMapillary(this.token, {http.Client? client, DateTime Function()? orologio})
      : _http = client ?? http.Client(),
        _ora = orologio ?? DateTime.now;

  final String token;
  final http.Client _http;
  final DateTime Function() _ora;

  /// Le foto (non panoramiche) entro [raggioM] da [centro]. Mapillary vuole
  /// un riquadro piccolo: il raggio si tiene sotto i 300 metri.
  Future<List<FotoStrada>> vicine(Punto centro, {double raggioM = 200}) async {
    final r = math.min(raggioM, 300.0);
    final dLat = r / 110540, dLon = r / (111320 * math.cos(centro.lat * math.pi / 180));
    final risposta = await _http
        .get(
          Uri.https('graph.mapillary.com', '/images', {
            'access_token': token,
            'fields': 'id,thumb_1024_url,computed_geometry,computed_compass_angle,compass_angle,captured_at,creator',
            'bbox': [
              centro.lon - dLon,
              centro.lat - dLat,
              centro.lon + dLon,
              centro.lat + dLat,
            ].map((v) => v.toStringAsFixed(6)).join(','),
            'is_pano': 'false',
            'limit': '200',
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (risposta.statusCode != 200) throw Exception('mapillary: ${risposta.statusCode}');
    final j = jsonDecode(utf8.decode(risposta.bodyBytes)) as Map;
    return ((j['data'] as List?) ?? const []).map(FotoStrada.daJson).whereType<FotoStrada>().toList();
  }

  /// Fra [foto], quella che mostra meglio lo svincolo a [svincoloM] metri
  /// lungo [linea]: scattata sulla strada del percorso (non su quella
  /// accanto), fra 60 e 300 metri prima, guardando nella direzione di
  /// marcia; a pari merito la più vicina ai 150 metri e la più recente.
  /// `null` se nessuna va bene.
  FotoStrada? migliore(List<FotoStrada> foto, Linea linea, double svincoloM) {
    FotoStrada? scelta;
    var punteggio = double.infinity;
    for (final f in foto) {
      final p = linea.proietta(f.punto);
      if (p.lontanoM > 15) continue;
      final prima = svincoloM - p.lungoM;
      if (prima < 60 || prima > 300) continue;
      final i = p.segmento.clamp(0, linea.punti.length - 2);
      final rotta = rottaGradi(linea.punti[i], linea.punti[i + 1]);
      final scarto = ((f.direzione - rotta + 540) % 360 - 180).abs();
      if (scarto > 30) continue;
      final anni = _ora().difference(f.scattata).inDays / 365;
      if (anni > 8) continue;
      // Metri dai 150 ideali, gradi fuori asse e anni pesano insieme.
      final v = (prima - 150).abs() + scarto * 3 + anni * 20;
      if (v < punteggio) {
        punteggio = v;
        scelta = f;
      }
    }
    return scelta;
  }

  Future<Uint8List> scarica(FotoStrada f) async {
    final r = await _http.get(Uri.parse(f.url)).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('mapillary foto: ${r.statusCode}');
    return r.bodyBytes;
  }

  /// La foto dello svincolo a [svincoloM] metri lungo [linea], già
  /// scaricata; `null` se Mapillary lì non ne ha di adatte.
  Future<(FotoStrada, Uint8List)?> fotoSvincolo(Linea linea, double svincoloM) async {
    final centro = _lungo(linea, math.max(0, svincoloM - 150));
    final scelta = migliore(await vicine(centro, raggioM: 220), linea, svincoloM);
    if (scelta == null) return null;
    return (scelta, await scarica(scelta));
  }

  static Punto _lungo(Linea l, double m) {
    var i = 1;
    while (i < l.punti.length - 1 && l.cumulate[i] < m) {
      i++;
    }
    final a = l.punti[i - 1], b = l.punti[i];
    final tratto = l.cumulate[i] - l.cumulate[i - 1];
    final t = tratto <= 0 ? 0.0 : ((m - l.cumulate[i - 1]) / tratto).clamp(0.0, 1.0);
    return Punto(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  }

  void chiudi() => _http.close();
}
