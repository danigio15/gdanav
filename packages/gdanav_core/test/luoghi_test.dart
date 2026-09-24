import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// Scritto sul formato GeoJSON documentato di Photon: da qui il servizio vero
// non si raggiunge.
Map<String, Object?> esempio() =>
    jsonDecode(File('test/dati/photon_esempio.json').readAsStringSync()) as Map<String, Object?>;

void main() {
  test('legge nome, descrizione e posizione', () {
    final l = ClientePhoton.leggi(esempio());
    expect(l.map((x) => x.nome), ['Bologna', 'Stazione di ricarica Piazza Maggiore', 'Via Torino 12']);
    expect(l.first.descrizione, 'Emilia-Romagna');
    expect(l.first.posizione, const Punto(44.4938, 11.3426));
    expect(l[1].descrizione, 'Piazza Maggiore 6, Bologna, Emilia-Romagna');
    expect(l[2].descrizione, 'Milano, Lombardia');
  });

  test('cerca vicino alla posizione, e non per meno di tre lettere', () async {
    final chieste = <Uri>[];
    final client = MockClient((r) async {
      chieste.add(r.url);
      return http.Response(jsonEncode(esempio()), 200);
    });
    final p = ClientePhoton(client: client);
    expect(await p.cerca('bo'), isEmpty);
    expect(chieste, isEmpty);
    final l = await p.cerca(' bologna ', vicinoA: const Punto(45, 9));
    expect(l, hasLength(3));
    expect(chieste.single.queryParameters, {'q': 'bologna', 'limit': '10', 'lat': '45.0', 'lon': '9.0'});
  });
}
