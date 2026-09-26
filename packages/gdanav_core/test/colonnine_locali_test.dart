import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Colonnina colonnina(String id, double lat, double lon) => Colonnina(
  id: id,
  nome: 'Area $id',
  operatore: 'Ionity',
  posizione: Punto(lat, lon),
  connettori: const [
    Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 350),
    Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 350),
    Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22),
  ],
);

void main() {
  test('il formato compatto va e torna', () {
    final testo = ArchivioColonnine.scrivi([colonnina('osm-node-1', 44.512345678, 11.3)]);
    final a = ArchivioColonnine.leggi(testo);
    expect(a.quante, 1);
    final c = a.nel((89, 22)).single;
    expect(c.id, 'osm-node-1');
    expect(c.operatore, 'Ionity');
    expect(c.posizione.lat, 44.51235);
    expect(c.connettori.where((p) => p.tipo == TipoConnettore.ccs2), hasLength(2));
    expect(c.potenzaPer({TipoConnettore.ccs2}), 350);
    expect(a.generato, isNotNull);
  });

  test('coperti: quelli scritti nell\'archivio, anche vuoti', () {
    final testo = ArchivioColonnine.scrivi([colonnina('a', 44.5, 11.3)], coperti: {(89, 22), (70, 30)});
    final a = ArchivioColonnine.leggi(testo);
    expect(a.copre((70, 30)), isTrue);
    expect(a.copre((89, 22)), isTrue);
    expect(a.copre((90, 23)), isFalse);
  });

  test('coperti, se l\'archivio non lo dice: i riquadri con colonnine e quelli intorno', () {
    final a = ArchivioColonnine([colonnina('a', 44.5, 11.3)]);
    expect(a.copre((89, 22)), isTrue);
    expect(a.copre((90, 23)), isTrue);
    expect(a.copre((92, 22)), isFalse);
  });

  test("lungo la strada dall'archivio, e dal relay solo i riquadri che mancano", () async {
    // Da Bologna verso nord: i primi riquadri nell'archivio, gli ultimi no.
    final percorso = [for (var i = 0; i <= 30; i++) Punto(44.5 + i * 0.1, 11.3)];
    final chiesti = <String>[];
    final relay = ClienteColonnineRelay(
      Uri.parse('https://gdanav.gdahome.org/'),
      client: MockClient((r) async {
        chiesti.add(r.url.path);
        return http.Response(
          jsonEncode({
            'elements': [
              {
                'type': 'node',
                'id': r.url.path.hashCode,
                'lat': 47.2,
                'lon': 11.3,
                'tags': {'amenity': 'charging_station', 'socket:type2_combo': '1'},
              },
            ],
          }),
          200,
        );
      }),
    );
    final locali = ColonnineLocali(Future.value(ArchivioColonnine([colonnina('bo', 44.6, 11.35)])), riserva: relay);
    final c = await locali.lungo(percorso);
    expect(c.map((x) => x.id), contains('bo'));
    expect(chiesti, isNotEmpty);
    expect(chiesti, everyElement(isNot(anyOf(endsWith('/89/22'), endsWith('/90/22')))));
  });

  test('senza rete, fuori archivio: si va avanti con quel che c\'è', () async {
    final percorso = [for (var i = 0; i <= 30; i++) Punto(44.5 + i * 0.1, 11.3)];
    final relay = ClienteColonnineRelay(
      Uri.parse('https://gdanav.gdahome.org/'),
      client: MockClient((_) async => throw http.ClientException('niente rete')),
    );
    final locali = ColonnineLocali(Future.value(ArchivioColonnine([colonnina('bo', 44.6, 11.35)])), riserva: relay);
    expect((await locali.lungo(percorso)).single.id, 'bo');
  });
}
