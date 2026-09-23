import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Una risposta vera di Valhalla 3 (pyvalhalla, mappa di prova di Utrecht,
/// senza modello del terreno: quote a -500).
Map<String, Object?> utrecht() =>
    jsonDecode(File('test/dati/valhalla_utrecht.json').readAsStringSync()) as Map<String, Object?>;

void main() {
  group('lettura della risposta', () {
    test('lunghezza e durata tornano con il riepilogo di Valhalla', () {
      final json = utrecht();
      final riepilogo = (json['trip'] as Map)['summary'] as Map;
      final p = PercorsoCalcolato.daValhalla(json);
      expect(p.lunghezzaM, closeTo((riepilogo['length'] as num) * 1000, 1));
      expect(p.durata.inSeconds, closeTo(riepilogo['time'] as num, 1));
      expect(p.manovre, hasLength(14));
      expect(p.manovre.first.istruzione, 'Guida verso nord su Domplein.');
      expect(p.manovre.last.istruzione, isNotEmpty);
    });

    test('senza modello del terreno il percorso è piatto, non un burrone', () {
      final p = PercorsoCalcolato.daValhalla(utrecht());
      expect(p.tratti.every((t) => t.dislivelloM == 0), isTrue);
    });

    test('le manovre puntano dentro il tracciato', () {
      final p = PercorsoCalcolato.daValhalla(utrecht());
      expect(p.manovre.every((m) => m.inizio >= 0 && m.inizio < p.punti.length), isTrue);
      expect(p.punti.first.lat, closeTo(52.0907, 0.001));
    });

    test('con le quote il dislivello segue il profilo', () {
      // 2 km in salita di 100 m: tracciato di 3 punti, quote ogni 1000 m.
      final forma = codificaPolyline(const [Punto(45, 9), Punto(45.009, 9), Punto(45.018, 9)], precisione: 6);
      final p = PercorsoCalcolato.daValhalla({
        'trip': {
          'legs': [
            {
              'shape': forma,
              'elevation_interval': 1000,
              'elevation': [100, 150, 200],
              'maneuvers': [
                {'instruction': 'Parti', 'length': 2.0, 'time': 120, 'begin_shape_index': 0, 'end_shape_index': 2},
              ],
            },
          ],
        },
      });
      expect(p.tratti, hasLength(2));
      expect(p.tratti.fold<double>(0, (s, t) => s + t.dislivelloM), closeTo(100, 1));
      expect(p.tratti.first.velocitaKmh, closeTo(60, 1e-9));
    });
  });

  group('client', () {
    test('manda le tappe e legge il percorso', () async {
      late Map<String, Object?> chiesto;
      final client = MockClient((r) async {
        expect(r.url.toString(), 'https://valhalla.esempio.dev/route');
        expect(r.headers['x-gdanav-chiave'], 'segreto');
        chiesto = jsonDecode(r.body) as Map<String, Object?>;
        return http.Response(jsonEncode(utrecht()), 200, headers: {'content-type': 'application/json'});
      });
      final v = ClienteValhalla(Uri.parse('https://valhalla.esempio.dev/'), client: client, chiave: 'segreto');
      final p = await v.calcola(const [Punto(52.0907, 5.1214), Punto(52.064, 5.19)]);
      expect(chiesto['costing'], 'auto');
      expect(chiesto['elevation_interval'], 30);
      expect((chiesto['locations'] as List).first, {'lat': 52.0907, 'lon': 5.1214});
      expect(p.manovre, hasLength(14));
    });

    test("un errore di Valhalla diventa un'eccezione leggibile", () async {
      final client = MockClient((_) async => http.Response('{"error_code":442,"error":"No path could be found"}', 400));
      final v = ClienteValhalla(Uri.parse('https://valhalla.esempio.dev/'), client: client);
      expect(
        v.calcola(const [Punto(0, 0), Punto(1, 1)]),
        throwsA(isA<ErroreValhalla>().having((e) => e.messaggio, 'messaggio', 'No path could be found')),
      );
    });
  });

  // Contro un Valhalla vero: GDANAV_VALHALLA=http://127.0.0.1:8002/
  final vero = Platform.environment['GDANAV_VALHALLA'];
  test('Valhalla vero', () async {
    final v = ClienteValhalla(Uri.parse(vero!));
    final p = await v.calcola(const [Punto(52.0907, 5.1214), Punto(52.064, 5.19)]);
    expect(p.lunghezzaM, greaterThan(1000));
    expect(p.tratti, isNotEmpty);
    v.chiudi();
  }, skip: vero == null ? 'serve GDANAV_VALHALLA' : false);
}
