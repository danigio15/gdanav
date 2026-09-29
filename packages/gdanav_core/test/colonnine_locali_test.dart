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

  test('la fonte va e torna, e OpenStreetMap non la scrive', () {
    Colonnina da(String id, String fonte) => Colonnina(
          id: id,
          nome: id,
          posizione: const Punto(40.8548, 14.2855),
          connettori: const [Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22)],
          fonte: fonte,
        );
    final testo = ArchivioColonnine.scrivi([da('osm-node-1', 'osm'), da('pun:1', 'pun'), da('pun:2', 'osm+pun')]);
    final righe = (jsonDecode(testo) as Map)['c'] as List;
    expect(righe.map((r) => (r as List).length), [6, 7, 7]);
    final a = ArchivioColonnine.leggi(testo);
    expect({for (final c in a.tutte) c.id: c.fonte}, {'osm-node-1': 'osm', 'pun:1': 'pun', 'pun:2': 'osm+pun'});
  });

  test('gli EVSE ID vanno e tornano, e senza non si scrive niente', () {
    const pun = Colonnina(
      id: 'pun:1',
      nome: 'Isola A3',
      posizione: Punto(40.8548, 14.2855),
      connettori: [Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22)],
      fonte: 'pun',
      evse: ['IT*BEC*EW001*1', 'IT*BEC*EW001*2'],
    );
    const osm = Colonnina(
      id: 'osm-node-1',
      nome: 'Enel X',
      posizione: Punto(40.85, 14.28),
      connettori: [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 50)],
      fonte: 'osm',
    );
    final testo = ArchivioColonnine.scrivi([pun, osm]);
    expect(((jsonDecode(testo) as Map)['c'] as List).map((r) => (r as List).length), [8, 6]);
    final letti = {for (final c in ArchivioColonnine.leggi(testo).tutte) c.id: c};
    expect(letti['pun:1']!.evse, ['IT*BEC*EW001*1', 'IT*BEC*EW001*2']);
    expect(letti['osm-node-1']!.evse, isEmpty);
  });

  test("un archivio di prima, senza il settimo campo, e' tutto OpenStreetMap", () {
    const testo = '{"v":1,"generato":"2026-09-01T00:00:00Z","c":[[44.5,11.3,"osm-node-9","A","",[[0,150,2]]]]}';
    expect(ArchivioColonnine.leggi(testo).tutte.single.fonte, 'osm');
  });

  test('i riquadri cercati si rileggono, per riscriverli', () {
    final a =
        ArchivioColonnine.leggi(ArchivioColonnine.scrivi([colonnina('a', 44.5, 11.3)], coperti: {(89, 22), (70, 30)}));
    expect(a.coperti, {(89, 22), (70, 30)});
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
            200);
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

  /* Lo stato di tutta Italia si dà presa per presa: il punto i-esimo deve
   * essere la presa i-esima anche dove le prese non sono tutte uguali. */
  test('gli EVSE ID si scrivono nell\'ordine delle prese', () {
    final area = Colonnina(
      id: 'pun:area',
      nome: 'Area di servizio',
      posizione: const Punto(41.9, 12.5),
      connettori: const [
        Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150),
        Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22),
        Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150),
      ],
      fonte: 'pun',
      evse: const ['A', 'B', 'C'],
    );
    final letto = ArchivioColonnine.leggi(ArchivioColonnine.scrivi([area]));
    expect(letto.evseInOrdine, isTrue);
    final c = letto.tutte.single;
    expect(c.connettori.map((p) => p.tipo), [TipoConnettore.ccs2, TipoConnettore.ccs2, TipoConnettore.tipo2]);
    expect(c.evse, ['A', 'C', 'B']);
    // Gli archivi di prima non lo dicono, e non ci si conta.
    expect(ArchivioColonnine.leggi('{"v":1,"c":[]}').evseInOrdine, isFalse);
  });
}
