import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('legge, invia e vota le segnalazioni', () async {
    final chieste = <http.Request>[];
    final client = MockClient((r) async {
      chieste.add(r);
      if (r.method == 'GET') {
        return http.Response(
          '{"segnalazioni":[{"id":"227_45~abcdefgh","tipo":"polizia","lat":45.46,"lon":9.19,"creata":1000,'
          '"conferme":2},{"id":"x","tipo":"ufo","lat":1,"lon":1,"creata":1}]}',
          200,
        );
      }
      if (r.url.path.endsWith('/voto')) return http.Response('{"tolta":true}', 200);
      final j = jsonDecode(r.body) as Map<String, Object?>;
      return http.Response(jsonEncode({...j, 'id': '227_45~nuovanuova', 'creata': 5, 'conferme': 0}), 201);
    });
    final c = ClienteSegnalazioni(Uri.parse('https://relay.esempio.dev/'), client: client);

    final vicine = await c.vicine(const Punto(45.46, 9.2));
    expect(vicine, hasLength(1));
    expect(vicine.single.tipo, TipoSegnalazione.polizia);
    expect(vicine.single.conferme, 2);
    expect(chieste.last.url.toString(), 'https://relay.esempio.dev/v1/segnalazioni?lat=45.46&lon=9.2');

    final nuova = await c.invia(TipoSegnalazione.incidente, const Punto(45.4, 9.3));
    expect(nuova.tipo, TipoSegnalazione.incidente);
    expect(jsonDecode(chieste.last.body), {'tipo': 'incidente', 'lat': 45.4, 'lon': 9.3});

    expect(await c.vota(vicine.single, ancora: false), isNull);
    expect(chieste.last.url.path, '/v1/segnalazioni/227_45~abcdefgh/voto');
  });

  test('troppe segnalazioni: il messaggio del relay arriva', () async {
    final c = ClienteSegnalazioni(
      Uri.parse('https://relay.esempio.dev/'),
      client: MockClient((_) async => http.Response('{"errore":"troppe segnalazioni, riprova tra poco"}', 429)),
    );
    expect(c.invia(TipoSegnalazione.polizia, const Punto(45, 9)), throwsA(predicate((e) => '$e'.contains('troppe'))));
  });

  // Contro il relay vero: GDANAV_RELAY=ws://127.0.0.1:8799 (lo stesso della prova del relay).
  final relay = Platform.environment['GDANAV_RELAY'];
  test('relay vero: si segnala e si ritrova', () async {
    final c = ClienteSegnalazioni(Uri.parse('${relay!.replaceFirst('ws', 'http')}/'));
    final s = await c.invia(TipoSegnalazione.pericolo, const Punto(41.9028, 12.4964));
    final vicine = await c.vicine(const Punto(41.9, 12.5));
    expect(vicine.map((v) => v.id), contains(s.id));
    final dopo = await c.vota(s, ancora: true);
    expect(dopo!.conferme, 1);
    c.chiudi();
  }, skip: relay == null ? 'serve GDANAV_RELAY' : false);
}
