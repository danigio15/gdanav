import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/gestore_edifici.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory cartella;
  late List<int> pacchetto;

  setUp(() async {
    cartella = await Directory.systemTemp.createTemp('edifici');
    pacchetto = await File('test/dati/edifici-prova.pmtiles').readAsBytes();
  });
  tearDown(() => cartella.delete(recursive: true));

  /// Un server con l'indice e il pacchetto della cella di via Torretta.
  ({MockClient client, List<String> chieste}) server({int? byteNellIndice, List<int>? corpo}) {
    final chieste = <String>[];
    final client = MockClient((r) async {
      chieste.add(r.url.pathSegments.last);
      if (r.url.path.endsWith('indice.json')) {
        return http.Response(
          jsonEncode({
            'celle': {
              '8/138/96': {'file': 'edifici-8-138-96.pmtiles', 'byte': byteNellIndice ?? pacchetto.length},
            },
          }),
          200,
        );
      }
      if (r.url.path.endsWith('edifici-8-138-96.pmtiles')) return http.Response.bytes(corpo ?? pacchetto, 200);
      return http.Response('', 404);
    });
    return (client: client, chieste: chieste);
  }

  test('la cella di una tessera', () {
    expect(GestoreEdifici.cellaDi(14, 8838, 6144), '8/138/96');
    expect(GestoreEdifici.fileDi('8/138/96'), 'edifici-8-138-96.pmtiles');
  });

  test('senza pacchetto: niente, intanto lo si scarica; poi gli edifici ci sono', () async {
    final s = server();
    final g = GestoreEdifici(client: s.client, cartella: () async => cartella, aConsumo: () async => false);
    expect(await g.tessera(14, 8838, 6144), isNull);
    expect(await g.scarica('8/138/96'), isTrue);
    expect(utf8.decode((await g.tessera(14, 8838, 6144))!), 'edifici di via Torretta');
    expect(File('${cartella.path}/edifici-8-138-96.pmtiles').existsSync(), isTrue);
    // Già lì: non si riscarica.
    final prima = s.chieste.length;
    expect(await g.scarica('8/138/96'), isTrue);
    expect(s.chieste.length, prima);
  });

  test('sui dati a consumo non si scarica niente', () async {
    final s = server();
    final g = GestoreEdifici(client: s.client, cartella: () async => cartella, aConsumo: () async => true);
    expect(await g.scarica('8/138/96'), isFalse);
    expect(s.chieste.where((c) => c.endsWith('.pmtiles')), isEmpty);
  });

  test('una zona che non ha pacchetto non si chiede', () async {
    final s = server();
    final g = GestoreEdifici(client: s.client, cartella: () async => cartella, aConsumo: () async => false);
    expect(await g.scarica('8/1/1'), isFalse);
    expect(s.chieste.where((c) => c.endsWith('.pmtiles')), isEmpty);
  });

  test('un pacchetto arrivato a metà non resta sul telefono', () async {
    final s = server(corpo: pacchetto.sublist(0, 100));
    final g = GestoreEdifici(client: s.client, cartella: () async => cartella, aConsumo: () async => false);
    expect(await g.scarica('8/138/96'), isFalse);
    expect(cartella.listSync(), isEmpty);
  });
}
