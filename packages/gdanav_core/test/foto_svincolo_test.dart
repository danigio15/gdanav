import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  // Una strada dritta verso est; lo svincolo a 1000 m.
  final linea = Linea([for (var i = 0; i <= 20; i++) Punto(45.0, 9.0 + i * 0.001)]);
  final ora = DateTime.utc(2026, 9, 25);
  Map<String, Object?> foto(String id, double lon, double direzione, {double lat = 45.0, int anno = 2025}) => {
        'id': id,
        'thumb_1024_url': 'https://foto.esempio/$id.jpg',
        'computed_geometry': {
          'type': 'Point',
          'coordinates': [lon, lat],
        },
        'computed_compass_angle': direzione,
        'captured_at': DateTime.utc(anno, 6).millisecondsSinceEpoch,
        'creator': {'username': 'mario'},
      };
  // 1000 m lungo la linea: il punto di longitudine ~9.01272.
  final svincoloM = 1000.0;
  double lonA(double metri) => 9.0 + metri / (111320 * 0.7071);

  test('sceglie la foto giusta: prima dello svincolo, nel verso di marcia, sulla nostra strada', () {
    final m = ClienteMapillary('tok', orologio: () => ora);
    final elenco = [
      foto('dopo', lonA(1100), 90), // oltre lo svincolo
      foto('contromano', lonA(850), 270), // guarda indietro
      foto('lontana', lonA(850), 90, lat: 45.0005), // 55 m di lato: altra strada
      foto('vecchia', lonA(850), 90, anno: 2012),
      foto('troppo-prima', lonA(500), 90),
      foto('buona', lonA(840), 92),
      foto('meno-buona', lonA(920), 110),
    ].map(FotoStrada.daJson).whereType<FotoStrada>().toList();
    expect(m.migliore(elenco, linea, svincoloM)!.id, 'buona');
    expect(m.migliore(elenco.where((f) => f.id != 'buona' && f.id != 'meno-buona').toList(), linea, svincoloM), isNull);
    final b = elenco.firstWhere((f) => f.id == 'buona');
    expect(b.citazione, '© mario, Mapillary · 2025 · CC BY-SA');
  });

  test('chiede le foto intorno al punto e scarica quella scelta', () async {
    final chieste = <Uri>[];
    final client = MockClient((r) async {
      chieste.add(r.url);
      if (r.url.host == 'graph.mapillary.com') {
        return http.Response(
            jsonEncode({
              'data': [foto('buona', lonA(850), 90)]
            }),
            200);
      }
      return http.Response.bytes([0xff, 0xd8, 0xff], 200);
    });
    final m = ClienteMapillary('MLY|tok', client: client, orologio: () => ora);
    final r = await m.fotoSvincolo(linea, svincoloM);
    expect(r!.$1.id, 'buona');
    expect(r.$2, [0xff, 0xd8, 0xff]);
    final q = chieste.first.queryParameters;
    expect(q['access_token'], 'MLY|tok');
    expect(q['is_pano'], 'false');
    final bbox = q['bbox']!.split(',').map(double.parse).toList();
    // Un riquadro piccolo intorno a 150 m prima dello svincolo.
    expect((bbox[2] - bbox[0]) * (bbox[3] - bbox[1]), lessThan(0.01));
    expect((bbox[0] + bbox[2]) / 2, closeTo(lonA(850), 0.0005));
    expect(chieste.last.toString(), 'https://foto.esempio/buona.jpg');
  });

  test('nessuna foto adatta: null, senza scaricare niente', () async {
    var scaricate = 0;
    final client = MockClient((r) async {
      if (r.url.host != 'graph.mapillary.com') scaricate++;
      return http.Response(jsonEncode({'data': []}), 200);
    });
    expect(await ClienteMapillary('t', client: client).fotoSvincolo(linea, svincoloM), isNull);
    expect(scaricate, 0);
  });
}
