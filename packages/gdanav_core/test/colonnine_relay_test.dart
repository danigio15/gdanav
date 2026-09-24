import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> riquadro(int id, double lat, double lon) => {
      'elements': [
        {
          'type': 'node',
          'id': id,
          'lat': lat,
          'lon': lon,
          'tags': {'amenity': 'charging_station', 'socket:type2_combo': '2', 'socket:type2_combo:output': '150 kW'},
        },
      ],
    };

void main() {
  // Da Bologna verso nord-ovest, una cinquantina di km.
  const percorso = [Punto(44.49, 11.34), Punto(44.65, 10.92)];

  test('i riquadri coprono la striscia intorno al percorso', () {
    final r = ClienteColonnineRelay.riquadri(percorso, 3);
    expect(r, containsAll([(88, 22), (89, 21)]));
    expect(r.length, lessThan(8));
  });

  test('chiede i riquadri al relay e mette insieme le colonnine, senza doppioni', () async {
    final chiesti = <String>[];
    final client = MockClient((r) async {
      chiesti.add(r.url.path);
      // Una colonnina sta su due riquadri vicini: la stessa.
      return http.Response(jsonEncode(riquadro(r.url.path.endsWith('/22') ? 1 : 2, 44.5, 11.3)), 200);
    });
    final c = await ClienteColonnineRelay(Uri.parse('https://gdanav.gdahome.org/'), client: client).lungo(percorso);
    expect(chiesti, everyElement(startsWith('/v1/colonnine/')));
    expect(chiesti.toSet(), hasLength(chiesti.length));
    expect(c.map((x) => x.id).toSet(), {'osm-node-1', 'osm-node-2'});
    expect(c.first.potenzaPer({TipoConnettore.ccs2}), 150);
  });

  test('un riquadro che non arriva, dopo un secondo tentativo, è un errore', () async {
    var volte = 0;
    final client = MockClient((r) async {
      if (r.url.path.endsWith('/22')) {
        volte++;
        return http.Response('{"errore":"colonnine: overpass"}', 502);
      }
      return http.Response(jsonEncode(riquadro(2, 44.5, 11.3)), 200);
    });
    await expectLater(
      ClienteColonnineRelay(Uri.parse('https://gdanav.gdahome.org/'), client: client).lungo(percorso),
      throwsA(predicate((e) => '$e'.contains('colonnine'))),
    );
    expect(volte, greaterThanOrEqualTo(2));
  });
}
