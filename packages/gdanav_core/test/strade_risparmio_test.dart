import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Un percorso finto lungo [punti], che dura [minuti] e consuma [kwh].
PercorsoCalcolato strada(List<Punto> punti, int minuti, {double? kwh, bool autostrada = false}) {
  var metri = 0.0;
  for (var i = 1; i < punti.length; i++) {
    metri += distanzaM(punti[i - 1], punti[i]);
  }
  return PercorsoCalcolato(
    punti: punti,
    tratti: [Tratto(lunghezzaM: metri, velocitaKmh: metri / (minuti * 60) * 3.6)],
    manovre: const [],
    conAutostrade: autostrada,
    consumoTomTom: kwh,
  );
}

/// Da [a] a [b] in linea retta, un punto ogni chilometro circa.
List<Punto> dritto(Punto a, Punto b) {
  final n = (distanzaM(a, b) / 1000).ceil().clamp(1, 1000);
  return [for (var i = 0; i <= n; i++) Punto(a.lat + (b.lat - a.lat) * i / n, a.lon + (b.lon - a.lon) * i / n)];
}

void main() {
  const da = Punto(40.85, 14.27), a = Punto(40.65, 14.45);
  // La strada di adesso, dritta; l'alternativa gira a ovest per la statale.
  final adesso = strada(dritto(da, a), 72, kwh: 14.2, autostrada: true);
  final statale = strada(
      [...dritto(da, const Punto(40.75, 14.25)), ...dritto(const Punto(40.75, 14.25), a).skip(1)], 76,
      kwh: 12.4);
  double consumo(PercorsoCalcolato p) => p.consumoTomTom!;

  group('la proposta in guida', () {
    test('la strada che risparmia almeno la soglia, senza costare troppi minuti', () {
      final p = scegliProposta(
        adesso: adesso,
        eco: [statale],
        soglie: const SoglieRisparmio(),
        consumo: consumo,
      )!;
      expect(p.motivo, MotivoProposta.risparmio);
      expect(p.risparmio, closeTo(1.8, 0.001));
      expect(p.differenza, const Duration(minutes: 4));
      expect(p.senzaAutostrada, isTrue);
      expect(p.firma, isNotEmpty);
    });

    test('sotto la soglia, o troppo più lenta, non si propone', () {
      expect(
        scegliProposta(
          adesso: adesso,
          eco: [statale],
          soglie: const SoglieRisparmio(minimoPercento: 15),
          consumo: consumo,
        ),
        isNull,
        reason: '1,8 su 14,2 è il 13%',
      );
      expect(
        scegliProposta(
          adesso: adesso,
          eco: [statale],
          soglie: const SoglieRisparmio(massimoInPiu: Duration(minutes: 3)),
          consumo: consumo,
        ),
        isNull,
      );
      expect(
        scegliProposta(adesso: adesso, eco: [statale], soglie: const SoglieRisparmio(proponi: false), consumo: consumo),
        isNull,
      );
    });

    test('rifiutata una volta, la stessa strada non torna — anche un po\' più avanti', () {
      final prima = scegliProposta(adesso: adesso, eco: [statale], soglie: const SoglieRisparmio(), consumo: consumo)!;
      // Cinque minuti dopo: la strada di adesso e l'alternativa partono più
      // avanti, ma la deviazione è la stessa.
      final qui = adesso.punti[6];
      final dopo = strada(adesso.punti.skip(6).toList(), 66, kwh: 13.1, autostrada: true);
      final ancora = strada(
          [...dritto(qui, const Punto(40.75, 14.25)), ...dritto(const Punto(40.75, 14.25), a).skip(1)], 70,
          kwh: 11.3);
      expect(
        scegliProposta(
          adesso: dopo,
          eco: [ancora],
          soglie: const SoglieRisparmio(),
          consumo: consumo,
          rifiutate: [prima.firma],
        ),
        isNull,
      );
    });

    test('con «anche le più rapide», quella che il traffico ha aperto', () {
      final rapida = strada(statale.punti, 64, kwh: 14.9);
      final p = scegliProposta(adesso: adesso, rapide: [rapida], soglie: const SoglieRisparmio(), consumo: consumo)!;
      expect(p.motivo, MotivoProposta.rapida);
      expect(p.differenza, const Duration(minutes: -8));
      expect(
        scegliProposta(
          adesso: adesso,
          rapide: [rapida],
          soglie: const SoglieRisparmio(ancheRapide: false),
          consumo: consumo,
        ),
        isNull,
      );
      // Due minuti prima non valgono il disturbo.
      expect(
        scegliProposta(
          adesso: adesso,
          rapide: [strada(statale.punti, 70, kwh: 14)],
          soglie: const SoglieRisparmio(),
          consumo: consumo,
        ),
        isNull,
      );
    });

    test('quello che resta della strada di adesso, da dove si è', () {
      final l = Linea(adesso.punti);
      final resto = restoDelPercorso(adesso, 10500);
      final qui = l.proietta(resto.first);
      expect(qui.lungoM, closeTo(10500, 1));
      expect(qui.lontanoM, lessThan(1));
      expect(resto.last, adesso.punti.last);
      expect(Linea(resto).lunghezzaM, closeTo(l.lunghezzaM - 10500, 1));
      expect(restoDelPercorso(adesso, 0), adesso.punti);
      expect(restoDelPercorso(adesso, l.lunghezzaM + 50), [adesso.punti.last]);
    });

    test('la stessa strada di adesso non è una proposta', () {
      expect(
        scegliProposta(
          adesso: adesso,
          eco: [strada(adesso.punti, 72, kwh: 12)],
          soglie: const SoglieRisparmio(),
          consumo: consumo,
        ),
        isNull,
      );
    });
  });

  group('le alternative prima di partire', () {
    test('i nomi come in ABRP: più rapida, risparmia energia, tempo simile, più lenta', () {
      final simile = strada(statale.punti.reversed.toList(), 73, kwh: 13.9);
      final lenta = strada(statale.punti, 95, kwh: 14.5);
      expect(etichetteStrade([adesso, statale, simile, lenta], consumo), [
        EtichettaStrada.piuRapida,
        EtichettaStrada.risparmia,
        EtichettaStrada.tempoSimile,
        EtichettaStrada.piuLenta,
      ]);
      // Se la più rapida consuma anche meno, nessuna «risparmia».
      expect(etichetteStrade([strada(adesso.punti, 72, kwh: 12), statale], consumo), [
        EtichettaStrada.piuRapida,
        EtichettaStrada.tempoSimile,
      ]);
      // E nemmeno senza consumi (tutti zero), anche con la soglia a zero.
      expect(etichetteStrade([adesso, statale], (_) => 0, minimoPercento: 0), [
        EtichettaStrada.piuRapida,
        EtichettaStrada.tempoSimile,
      ]);
    });

    test('la strada eco si aggiunge solo se è davvero un\'altra', () {
      expect(conStradaEco([adesso], strada(adesso.punti, 74, kwh: 13)), hasLength(1));
      expect(conStradaEco([adesso], statale), [adesso, statale]);
    });
  });

  group('il modello di consumo per TomTom', () {
    test('l\'elettrica: la curva che cresce con la velocità, i rendimenti che TomTom accetta', () {
      final m = ModelloConsumoTomTom.elettrica(ProfiloVeicolo.esempio);
      final curva = m.parametri['constantSpeedConsumptionInkWhPerHundredkm']!.single.split(':').map((c) {
        final [v, k] = c.split(',');
        return (int.parse(v), double.parse(k));
      }).toList();
      expect(curva.map((c) => c.$1), ModelloConsumoTomTom.velocita);
      for (var i = 1; i < curva.length; i++) {
        expect(curva[i].$2, greaterThan(curva[i - 1].$2));
      }
      // A 130 all'ora un'elettrica media sta fra 15 e 30 kWh/100 km.
      expect(curva.last.$2, inInclusiveRange(15, 30));
      double num(String k) => double.parse(m.parametri[k]!.single);
      expect(num('accelerationEfficiency') * num('decelerationEfficiency'), lessThanOrEqualTo(1));
      expect(num('uphillEfficiency') * num('downhillEfficiency'), lessThanOrEqualTo(1));
      expect(m.parametri['vehicleEngineType'], ['electric']);
      expect(m.unita, 'kWh');
    });

    test('la termica: litri, di meno col gasolio', () {
      final benzina = ModelloConsumoTomTom.termica(Carburante.benzina);
      final diesel = ModelloConsumoTomTom.termica(Carburante.diesel);
      expect(benzina.parametri['vehicleEngineType'], ['combustion']);
      expect(benzina.unita, 'l');
      expect(ModelloConsumoTomTom.termica(Carburante.metano).unita, 'kg');
      expect(diesel.parametri['constantSpeedConsumptionInLitersPerHundredkm']!.single,
          isNot(benzina.parametri['constantSpeedConsumptionInLitersPerHundredkm']!.single));
      // Cento chilometri a 90 all'ora: la curva.
      expect(ModelloConsumoTomTom.litriTratto(100000, 90, Carburante.benzina), closeTo(5.8, 0.001));
      expect(ModelloConsumoTomTom.litriTratto(100000, 80, Carburante.benzina), closeTo(5.65, 0.001));
      expect(ModelloConsumoTomTom.litriTratto(100000, 150, Carburante.benzina), greaterThan(8.3));
    });
  });

  group('TomTom: le strade migliori di quella che si fa', () {
    Map<String, Object?> risposta() {
      final j = jsonDecode(File('test/dati/tomtom_corso_malta.json').readAsStringSync()) as Map<String, Object?>;
      final prima = (j['routes'] as List).first as Map<String, Object?>;
      final seconda = jsonDecode(jsonEncode(prima)) as Map<String, Object?>;
      (prima['summary'] as Map)['batteryConsumptionInkWh'] = 2.4;
      (seconda['summary'] as Map)['batteryConsumptionInkWh'] = 1.9;
      j['routes'] = [prima, seconda];
      return j;
    }

    test('ricostruita dai suoi punti, con le sole alternative migliori e il consumo di ognuna', () async {
      final chieste = <http.Request>[];
      final c = ClienteTomTom(
        'CHIAVE',
        client: MockClient((r) async {
          chieste.add(r);
          return http.Response(jsonEncode(risposta()), 200, headers: const {'content-type': 'application/json'});
        }),
      );
      final m = ModelloConsumoTomTom.elettrica(ProfiloVeicolo.esempio);
      final davanti = dritto(da, a);
      final rotte = await c.migliori(
        davanti,
        eco: true,
        consumo: m,
        evita: const [Rettangolo(40.845, 14.245, 40.855, 14.255)],
      );
      expect(rotte, hasLength(2));
      expect(rotte.first.consumoTomTom, 2.4);
      expect(rotte.last.consumoTomTom, 1.9);
      final r = chieste.single;
      expect(r.method, 'POST');
      final q = r.url.queryParameters;
      expect(q['routeType'], 'eco');
      expect(q['alternativeType'], 'betterRoute');
      expect(q['minDeviationDistance'], '500');
      expect(q['maxAlternatives'], '2');
      expect(q['vehicleEngineType'], 'electric');
      expect(q['constantSpeedConsumptionInkWhPerHundredkm'], isNotEmpty);
      expect(r.url.path,
          endsWith('${davanti.first.lat},${davanti.first.lon}:${davanti.last.lat},${davanti.last.lon}/json'));
      final corpo = jsonDecode(r.body) as Map<String, Object?>;
      expect((corpo['supportingPoints'] as List), hasLength(davanti.length));
      expect((corpo['avoidAreas'] as Map)['rectangles'], hasLength(1));
    });

    test('se TomTom non prende il modello di consumo, si richiede senza', () async {
      final chieste = <http.Request>[];
      final c = ClienteTomTom(
        'CHIAVE',
        client: MockClient((r) async {
          chieste.add(r);
          if (r.url.queryParameters.containsKey('vehicleEngineType')) {
            return http.Response('{"detailedError":{"message":"Invalid consumption"}}', 400);
          }
          return http.Response(jsonEncode(risposta()), 200, headers: const {'content-type': 'application/json'});
        }),
      );
      final scelte = await c.alternative(da, a, consumo: ModelloConsumoTomTom.elettrica(ProfiloVeicolo.esempio));
      expect(scelte, hasLength(2));
      expect(chieste, hasLength(2));
      expect(chieste.last.url.queryParameters.containsKey('vehicleEngineType'), isFalse);
      // Senza modello e con un altro errore, l'errore resta.
      await expectLater(
        ClienteTomTom('CHIAVE', client: MockClient((_) async => http.Response('{}', 400))).alternative(da, a),
        throwsA(isA<ErrorePercorso>()),
      );
    });

    test('la strada eco è una richiesta con routeType=eco', () async {
      final chieste = <http.Request>[];
      final c = ClienteTomTom(
        'CHIAVE',
        client: MockClient((r) async {
          chieste.add(r);
          return http.Response(jsonEncode(risposta()), 200, headers: const {'content-type': 'application/json'});
        }),
      );
      final eco = await c.calcola([da, a], eco: true, consumo: ModelloConsumoTomTom.termica(Carburante.diesel));
      expect(eco.consumoTomTom, 2.4);
      expect(chieste.single.url.queryParameters['routeType'], 'eco');
      expect(chieste.single.url.queryParameters['vehicleEngineType'], 'combustion');
      await c.calcola([da, a]);
      expect(chieste.last.url.queryParameters['routeType'], 'fastest');
      expect(chieste.last.url.queryParameters.containsKey('vehicleEngineType'), isFalse);
    });
  });
}
