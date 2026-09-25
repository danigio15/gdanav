import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final risposta = {
    'elements': [
      {
        'type': 'node',
        'id': 1,
        'lat': 45.001,
        'lon': 9.0,
        'tags': {
          'amenity': 'fuel',
          'name': 'Eni Viale Roma',
          'brand': 'Eni',
          'fuel:octane_95': 'yes',
          'fuel:diesel': 'yes',
          'fuel:lpg': 'yes',
          'opening_hours': '24/7',
          'self_service': 'yes',
        },
      },
      {
        'type': 'way',
        'id': 2,
        'center': {'lat': 45.02, 'lon': 9.0},
        'tags': {'amenity': 'fuel', 'brand': 'Q8', 'fuel:cng': 'yes'},
      },
      // Privato: non si mostra.
      {
        'type': 'node',
        'id': 3,
        'lat': 45.0005,
        'lon': 9.0,
        'tags': {'amenity': 'fuel', 'access': 'private'},
      },
      // Solo per le barche.
      {
        'type': 'node',
        'id': 4,
        'lat': 45.0002,
        'lon': 9.0,
        'tags': {'amenity': 'fuel', 'boat': 'yes'},
      },
    ],
  };

  test('da OpenStreetMap: nome, marca, carburanti, orari; niente privati né barche', () {
    final d = ClienteDistributori.leggi(risposta);
    expect(d, hasLength(2));
    final eni = d.first;
    expect(eni.nome, 'Eni Viale Roma');
    expect(eni.marca, 'Eni');
    expect(eni.carburanti, {Carburante.benzina, Carburante.diesel, Carburante.gpl});
    expect(eni.sempreAperto, isTrue);
    expect(eni.self, isTrue);
    final q8 = d.last;
    expect(q8.nome, 'Q8');
    expect(q8.carburanti, {Carburante.metano});
    expect(q8.posizione.lat, 45.02);
    expect(q8.self, isNull);
  });

  test('si chiedono intorno a te, dal più vicino; se un server sbaglia si prova il prossimo', () async {
    final chiesti = <String>[];
    final client = MockClient((r) async {
      chiesti.add(r.url.host);
      if (r.url.host == 'uno.esempio') return http.Response('occupato', 429);
      expect(r.bodyFields['data'], contains('around:5000,45.00000,9.00000'));
      return http.Response(jsonEncode(risposta), 200);
    });
    final c = ClienteDistributori(
      client: client,
      server: [Uri.parse('https://uno.esempio/api'), Uri.parse('https://due.esempio/api')],
    );
    final d = await c.vicino(const Punto(45, 9));
    expect(chiesti, ['uno.esempio', 'due.esempio']);
    expect(d.map((x) => x.nome), ['Eni Viale Roma', 'Q8']);
  });

  // Come risponde l'Osservaprezzi del Ministero (search/zone).
  final mimit = {
    'success': true,
    'center': {'lat': 45.0, 'lng': 9.0},
    'results': [
      {
        'id': 12345,
        'name': 'Stazione Viale Roma',
        'fuels': [
          {'id': 1, 'price': 1.799, 'name': 'Benzina', 'fuelId': 1, 'isSelf': true},
          {'id': 2, 'price': 1.949, 'name': 'Benzina', 'fuelId': 1, 'isSelf': false},
          {'id': 3, 'price': 1.699, 'name': 'Gasolio', 'fuelId': 2, 'isSelf': true},
          {'id': 4, 'price': 0.729, 'name': 'GPL', 'fuelId': 4, 'isSelf': false},
          {'id': 5, 'price': 1.889, 'name': 'Blue Diesel', 'fuelId': 13, 'isSelf': true},
          {'id': 6, 'price': 0, 'name': 'Metano', 'fuelId': 3, 'isSelf': false},
        ],
        'location': {'lat': 45.004, 'lng': 9.0},
        'insertDate': '2026-09-25T07:12:03Z',
        'address': 'Viale Roma 1',
        'brand': 'Agip Eni',
      },
      {
        'id': 777,
        'name': 'Rossi Carburanti',
        'fuels': [
          {'id': 9, 'price': 1.759, 'name': 'Benzina', 'fuelId': 1, 'isSelf': true},
        ],
        'location': {'lat': 45.001, 'lng': 9.0},
        'insertDate': '2026-09-24T18:00:00Z',
        'address': 'Via Verdi 3',
        'brand': 'Pompe Bianche',
      },
    ],
  };

  test('prezzi del Ministero: marca, prezzi self e serviti, tipo dal codice o dal nome, niente prezzi a zero', () {
    final d = ClientePrezziMimit.leggi(mimit);
    expect(d, hasLength(2));
    final eni = d.first;
    expect(eni.id, 'mimit-12345');
    expect(eni.nome, 'Agip Eni');
    expect(eni.indirizzo, 'Viale Roma 1');
    expect(eni.aggiornato, DateTime.utc(2026, 9, 25, 7, 12, 3));
    expect(eni.carburanti, {Carburante.benzina, Carburante.diesel, Carburante.gpl});
    expect(eni.prezzoDi(Carburante.benzina)!.euro, 1.799);
    expect(eni.prezzoDi(Carburante.benzina)!.self, isTrue);
    // Il Blue Diesel è un gasolio, ma più caro: vince il normale.
    expect(eni.prezzoDi(Carburante.diesel)!.euro, 1.699);
    expect(eni.prezzoDi(Carburante.metano), isNull);
    // Le «pompe bianche» si chiamano col loro nome.
    expect(d.last.nome, 'Rossi Carburanti');
  });

  test('in Italia si chiedono i prezzi al Ministero; se non risponde, OpenStreetMap', () async {
    Map<String, Object?>? corpo;
    final ministero = ClientePrezziMimit(
      client: MockClient((r) async {
        corpo = jsonDecode(r.body) as Map<String, Object?>;
        return http.Response(jsonEncode(mimit), 200);
      }),
    );
    final osm = ClienteDistributori(
      server: [Uri.parse('https://osm.esempio/api')],
      client: MockClient((_) async => http.Response(jsonEncode(risposta), 200)),
    );
    final fonte = DistributoriConPrezzi(prezzi: ministero, mappa: osm);
    final italia = await fonte.vicino(const Punto(45, 9));
    expect(corpo!['points'], [
      {'lat': 45, 'lng': 9},
    ]);
    expect(corpo!['fuelType'], '0-x');
    expect(italia.first.nome, 'Rossi Carburanti'); // il più vicino
    expect(italia.first.prezzi, isNotEmpty);

    // Fuori dall'Italia: OpenStreetMap, senza prezzi.
    final fuori = await fonte.vicino(const Punto(48.85, 2.35));
    expect(fuori.map((d) => d.nome), containsAll(['Eni Viale Roma', 'Q8']));
    expect(fuori.first.prezzi, isEmpty);

    // Ministero giù: OpenStreetMap.
    final giu = DistributoriConPrezzi(
      prezzi: ClientePrezziMimit(client: MockClient((_) async => http.Response('errore', 503))),
      mappa: osm,
    );
    expect((await giu.vicino(const Punto(45, 9))).first.prezzi, isEmpty);
  });
}
