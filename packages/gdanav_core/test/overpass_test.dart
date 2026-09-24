import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  // Tre colonnine come le scrivono i mappatori di OpenStreetMap.
  const risposta = {
    'elements': [
      {
        'type': 'node',
        'id': 1,
        'lat': 44.5,
        'lon': 11.3,
        'tags': {
          'amenity': 'charging_station',
          'name': 'Ionity Bologna',
          'operator': 'Ionity',
          'socket:type2_combo': '4',
          'socket:type2_combo:output': '350 kW',
        },
      },
      {
        'type': 'way',
        'id': 2,
        'center': {'lat': 44.6, 'lon': 11.4},
        'tags': {
          'amenity': 'charging_station',
          'brand': 'Enel X',
          'socket:type2': '2',
          'socket:type2:output': '22kW',
          'socket:type2_combo': 'yes',
          'socket:type2_combo:output': '50000 W',
        },
      },
      {
        'type': 'node',
        'id': 3,
        'lat': 44.7,
        'lon': 11.5,
        'tags': {'amenity': 'charging_station', 'bicycle': 'yes'},
      },
      {
        'type': 'node',
        'id': 4,
        'lat': 44.8,
        'lon': 11.6,
        'tags': {'amenity': 'charging_station', 'access': 'private'},
      },
    ],
  };

  test('le colonnine di OpenStreetMap: prese, potenze, nomi; niente bici né private', () {
    final c = ClienteOverpass.leggi(risposta);
    expect(c, hasLength(2));
    expect(c[0].id, 'osm-node-1');
    expect(c[0].nome, 'Ionity Bologna');
    expect(c[0].connettori, hasLength(4));
    expect(c[0].potenzaPer({TipoConnettore.ccs2}), 350);
    expect(c[0].fonte, 'osm');
    expect(c[1].nome, 'Enel X');
    expect(c[1].posizione, const Punto(44.6, 11.4));
    expect(c[1].potenzaPer({TipoConnettore.ccs2}), 50);
    expect(c[1].potenzaPer({TipoConnettore.tipo2}), 22);
  });

  test('la richiesta segue il percorso, anche lungo, con pochi punti', () {
    final lungo = [for (var i = 0; i <= 800; i++) Punto(40.8 + i * 0.009, 14.2)]; // ~800 km
    final q = ClienteOverpass.richiesta(lungo, 3);
    expect(q, contains('nwr["amenity"="charging_station"](around:3000,'));
    expect(RegExp(r'\d+\.\d+,\d+\.\d+').allMatches(q).length, lessThanOrEqualTo(350));
  });

  test('se il primo server è giù si prova il secondo', () async {
    final chiesti = <String>[];
    final client = MockClient((r) async {
      chiesti.add(r.url.host);
      if (r.url.host == 'uno.esempio') return http.Response('troppo occupato', 429);
      expect(r.bodyFields['data'], startsWith('[out:json]'));
      return http.Response(jsonEncode(risposta), 200);
    });
    final o = ClienteOverpass(
      client: client,
      server: [Uri.parse('https://uno.esempio/api'), Uri.parse('https://due.esempio/api')],
    );
    final c = await o.lungo(const [Punto(44.5, 11.3), Punto(44.8, 11.6)]);
    expect(c, hasLength(2));
    expect(chiesti, ['uno.esempio', 'due.esempio']);
  });

  test('la riserva: se Open Charge Map non risponde, OpenStreetMap', () async {
    final ocm = ClienteOpenChargeMap(
      chiave: '',
      client: MockClient((_) async => http.Response('chiave mancante', 403)),
    );
    final osm = ClienteOverpass(client: MockClient((_) async => http.Response(jsonEncode(risposta), 200)));
    final c = await FonteColonnineConRiserva([ocm, osm]).lungo(const [Punto(44.5, 11.3), Punto(44.8, 11.6)]);
    expect(c.map((x) => x.fonte).toSet(), {'osm'});
    final giu = FonteColonnineConRiserva([ocm]);
    expect(giu.lungo(const [Punto(44.5, 11.3)]), throwsA(predicate((e) => '$e'.contains('colonnine'))));
  });
}
