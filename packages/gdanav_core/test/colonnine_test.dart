import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// Gli esempi sono scritti sul formato documentato di Open Charge Map
// (compact=true) e di OCPI 2.2.1: questa rete non raggiunge i servizi veri.
List<Object?> dati(String nome) => jsonDecode(File('test/dati/$nome').readAsStringSync()) as List<Object?>;

void main() {
  const ccs = {TipoConnettore.ccs2};

  group('Open Charge Map', () {
    final colonnine = ClienteOpenChargeMap.leggi(dati('ocm_esempio.json'));

    test('scarta pianificate e senza coordinate', () {
      expect(colonnine.map((c) => c.id), ['ocm:101', 'ocm:102']);
    });

    test('le prese si moltiplicano per quantità, con tipo e stato', () {
      final c = colonnine.first;
      expect(c.nome, 'Area di servizio Secchia Ovest');
      expect(c.operatore, 'Ionity');
      expect(c.connettori.where((p) => p.tipo == TipoConnettore.ccs2), hasLength(4));
      expect(c.connettori.firstWhere((p) => p.tipo == TipoConnettore.chademo).stato, StatoPresa.fuoriServizio);
    });

    test('la potenza utile dipende dalle prese dell\'auto', () {
      expect(colonnine.first.potenzaPer(ccs), 350);
      expect(colonnine.first.potenzaPer({TipoConnettore.chademo}), 0); // guasta
      expect(colonnine[1].potenzaPer(ccs), 0);
      expect(colonnine[1].potenzaPer({TipoConnettore.tipo2}), 22);
    });

    test('chiede per polyline, con la chiave nell\'intestazione', () async {
      late Uri chiesto;
      final client = MockClient((r) async {
        chiesto = r.url;
        expect(r.headers['X-API-Key'], 'chiave-ocm');
        return http.Response(jsonEncode(dati('ocm_esempio.json')), 200);
      });
      final ocm = ClienteOpenChargeMap(chiave: 'chiave-ocm', client: client);
      final percorso = [for (var i = 0; i <= 2000; i++) Punto(44 + i * 0.001, 10 + i * 0.0005)];
      final trovate = await ocm.lungo(percorso, distanzaKm: 2);
      expect(trovate, hasLength(2));
      expect(chiesto.queryParameters['distance'], '2.0');
      expect(chiesto.queryParameters['compact'], 'true');
      final inviato = decodificaPolyline(chiesto.queryParameters['polyline']!, precisione: 5);
      expect(inviato.first, percorso.first);
      expect(inviato.last.lat, closeTo(percorso.last.lat, 1e-5));
      expect(chiesto.queryParameters['polyline']!.length, lessThanOrEqualTo(6000));
    });
  });

  group('OCPI', () {
    final colonnine = Ocpi.leggiLocations(dati('ocpi_esempio.json'));

    test('legge location, prese e stati', () {
      final c = colonnine.first;
      expect(c.id, 'ocpi:ITION:LOC1');
      expect(c.posizione, const Punto(44.60452, 10.86515));
      expect(c.connettori.map((p) => p.stato), [StatoPresa.occupata, StatoPresa.disponibile, StatoPresa.fuoriServizio]);
      expect(c.connettori.first.potenzaKw, 350);
      // Senza max_electric_power: tensione per corrente.
      expect(c.connettori.last.potenzaKw, closeTo(460, 1e-9));
    });

    test('in trifase la potenza è per tre fasi', () {
      expect(colonnine[1].connettori.single.potenzaKw, closeTo(22.08, 1e-9));
      expect(colonnine[1].connettori.single.tipo, TipoConnettore.tipo2);
    });

    test('occupata del tutto solo se nessuna presa utile è libera', () {
      expect(colonnine.first.tuttaOccupata(ccs), isFalse);
    });
  });

  test("lo stato in tempo reale sostituisce quello dell'anagrafica vicina", () {
    final ocm = ClienteOpenChargeMap.leggi(dati('ocm_esempio.json'));
    final ocpi = Ocpi.leggiLocations(dati('ocpi_esempio.json'));
    final unite = unisciColonnine(ocm, ocpi);
    expect(unite, hasLength(3)); // 2 OCM + Piazza Grande che OCM non ha
    final secchia = unite.first;
    expect(secchia.id, 'ocm:101');
    expect(secchia.fonte, 'ocm+ocpi');
    expect(secchia.connettori.map((p) => p.stato), contains(StatoPresa.disponibile));
    expect(unite.last.id, 'ocpi:ITABC:LOC2');
  });

  test('sul percorso: solo quelle utili, ordinate, con la deviazione', () {
    final linea = Linea(const [Punto(44.5, 10.8), Punto(44.7, 11.0)]);
    final vicine = colonnineSulPercorso(
      linea,
      ClienteOpenChargeMap.leggi(dati('ocm_esempio.json')),
      compatibili: ccs,
    );
    expect(vicine.map((c) => c.id), ['ocm:101']);
    final c = vicine.single;
    expect(c.potenzaKw, 350);
    expect(c.distanzaM, inInclusiveRange(10000, 16000));
    expect(c.deviazioneM, greaterThan(0));
  });
}
