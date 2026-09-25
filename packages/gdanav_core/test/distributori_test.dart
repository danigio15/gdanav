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
}
