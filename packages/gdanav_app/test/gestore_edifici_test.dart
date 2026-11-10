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
  /// [rilascio] si può cambiare fra una richiesta e l'altra (un mese dopo).
  ({MockClient client, List<String> chieste, void Function(String) nuovoRilascio, void Function(int) indiceRisponde})
  server({int? byteNellIndice, List<int>? corpo}) {
    final chieste = <String>[];
    var rilascio = '2026-10-21.0';
    var statoIndice = 200;
    final client = MockClient((r) async {
      chieste.add(r.url.pathSegments.last);
      if (r.url.path.endsWith('indice.json')) {
        if (statoIndice != 200) return http.Response('', statoIndice);
        return http.Response(
          jsonEncode({
            'rilascio_overture': rilascio,
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
    return (
      client: client,
      chieste: chieste,
      nuovoRilascio: (String r) => rilascio = r,
      indiceRisponde: (int s) => statoIndice = s,
    );
  }

  int pacchettiChiesti(List<String> chieste) => chieste.where((c) => c.endsWith('.pmtiles')).length;
  File versione() => File('${cartella.path}/edifici-8-138-96.pmtiles.versione');

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

  test('ogni pacchetto si ricorda la sua versione', () async {
    final s = server();
    final g = GestoreEdifici(client: s.client, cartella: () async => cartella, aConsumo: () async => false);
    expect(await g.scarica('8/138/96'), isTrue);
    expect(versione().readAsStringSync(), '2026-10-21.0/${pacchetto.length}');
  });

  test('un pacchetto nuovo nell\'indice si riscarica, e intanto si usa il vecchio', () async {
    final s = server();
    final g = GestoreEdifici(
      client: s.client,
      cartella: () async => cartella,
      aConsumo: () async => false,
      indiceValido: Duration.zero,
      riprovaIndice: Duration.zero,
    );
    expect(await g.scarica('8/138/96'), isTrue);
    expect(pacchettiChiesti(s.chieste), 1);
    // Stesso rilascio: non si riscarica.
    expect(await g.scarica('8/138/96'), isTrue);
    expect(pacchettiChiesti(s.chieste), 1);
    // Un mese dopo.
    s.nuovoRilascio('2026-11-18.0');
    expect(utf8.decode((await g.tessera(14, 8838, 6144))!), 'edifici di via Torretta');
    await g.scarica('8/138/96');
    expect(pacchettiChiesti(s.chieste), 2);
    expect(versione().readAsStringSync(), '2026-11-18.0/${pacchetto.length}');
    expect(utf8.decode((await g.tessera(14, 8838, 6144))!), 'edifici di via Torretta');
  });

  test('sui dati a consumo il pacchetto vecchio resta, e si aggiorna dopo', () async {
    final s = server();
    var aConsumo = false;
    final g = GestoreEdifici(
      client: s.client,
      cartella: () async => cartella,
      aConsumo: () async => aConsumo,
      indiceValido: Duration.zero,
      riprovaIndice: Duration.zero,
    );
    expect(await g.scarica('8/138/96'), isTrue);
    s.nuovoRilascio('2026-11-18.0');
    aConsumo = true;
    expect(await g.scarica('8/138/96'), isTrue, reason: 'c\'è quello di prima');
    expect(pacchettiChiesti(s.chieste), 1);
    aConsumo = false;
    expect(await g.scarica('8/138/96'), isTrue);
    expect(pacchettiChiesti(s.chieste), 2);
  });

  test('un aggiornamento arrivato a metà lascia il pacchetto di prima', () async {
    final s = server();
    final g = GestoreEdifici(
      client: s.client,
      cartella: () async => cartella,
      aConsumo: () async => false,
      indiceValido: Duration.zero,
      riprovaIndice: Duration.zero,
    );
    expect(await g.scarica('8/138/96'), isTrue);
    s.nuovoRilascio('2026-11-18.0');
    // Il nuovo pesa di più, ma ne arriva solo un pezzo.
    final g2 = GestoreEdifici(
      client: server(byteNellIndice: pacchetto.length + 10).client,
      cartella: () async => cartella,
      aConsumo: () async => false,
    );
    expect(await g2.scarica('8/138/96'), isTrue);
    expect(File('${cartella.path}/edifici-8-138-96.pmtiles').lengthSync(), pacchetto.length);
    expect(File('${cartella.path}/edifici-8-138-96.pmtiles.mezzo').existsSync(), isFalse);
    expect(utf8.decode((await g2.tessera(14, 8838, 6144))!), 'edifici di via Torretta');
  });

  test('un pacchetto senza versione che pesa giusto si tiene', () async {
    File('${cartella.path}/edifici-8-138-96.pmtiles').writeAsBytesSync(pacchetto);
    final s = server();
    final g = GestoreEdifici(client: s.client, cartella: () async => cartella, aConsumo: () async => false);
    expect(await g.scarica('8/138/96'), isTrue);
    expect(pacchettiChiesti(s.chieste), 0);
    expect(versione().readAsStringSync(), '2026-10-21.0/${pacchetto.length}');
  });

  test('senza rete l\'indice non si richiede a ogni tessera', () async {
    final s = server();
    s.indiceRisponde(503);
    final g = GestoreEdifici(client: s.client, cartella: () async => cartella, aConsumo: () async => false);
    expect(await g.scarica('8/138/96'), isFalse);
    expect(await g.scarica('8/138/96'), isFalse);
    expect(await g.tessera(14, 8838, 6144), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(s.chieste.where((c) => c == 'indice.json').length, 1);
  });
}
