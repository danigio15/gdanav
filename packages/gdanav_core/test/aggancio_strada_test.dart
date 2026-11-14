import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

const metriPerGrado = 111195.08;
const origine = Punto(41, 14.3);

/// Il punto a [est], [nord] metri dall'origine (punti inventati, non di nessuno).
Punto a(double est, double nord) => Punto(
    origine.lat + nord / metriPerGrado, origine.lon + est / (metriPerGrado * math.cos(origine.lat * math.pi / 180)));

/// Quanto [p] sta a est e a nord dell'origine.
(double, double) dove(Punto p) => (
      (p.lon - origine.lon) * metriPerGrado * math.cos(origine.lat * math.pi / 180),
      (p.lat - origine.lat) * metriPerGrado,
    );

void main() {
  // Una strada dritta verso nord, sull'asse x = 0.
  final nordSud = TrattoStrada([a(0, -500), a(0, 500)]);

  test('il GPS a 5, 10, 15 metri di lato finisce sulla strada', () {
    for (final lato in [5.0, -10.0, 15.0]) {
      final g = AggancioStrada();
      final r = g.aggancia(a(lato, 0), rotta: 2, velocitaMs: 12, strade: [nordSud]);
      expect(r, isNotNull, reason: 'a $lato m');
      final (x, y) = dove(r!.punto);
      expect(x.abs(), lessThan(0.01));
      expect(y, closeTo(0, 0.01));
      expect(r.lontanoM, closeTo(lato.abs(), 0.01));
      expect(diQuantoSiGira(r.rotta, 0).abs(), lessThan(0.1), reason: 'la rotta è quella della strada, verso nord');
    }
  });

  test('troppo lontano, o di traverso, non si aggancia', () {
    expect(AggancioStrada().aggancia(a(30, 0), rotta: 0, velocitaMs: 12, strade: [nordSud]), isNull);
    // Si va verso est su una strada che va a nord: un'altra strada, che la mappa non ha.
    expect(AggancioStrada().aggancia(a(5, 0), rotta: 90, velocitaMs: 12, strade: [nordSud]), isNull);
    // Fermi la direzione del GPS non conta: ci si aggancia.
    expect(AggancioStrada().aggancia(a(5, 0), rotta: 90, velocitaMs: 0.5, strade: [nordSud]), isNotNull);
  });

  test('su una strada a doppio senso si va in tutti e due i versi; su un senso unico no', () {
    final r = AggancioStrada().aggancia(a(6, 0), rotta: 181, velocitaMs: 10, strade: [nordSud]);
    expect(diQuantoSiGira(r!.rotta, 180).abs(), lessThan(0.1));
    final sensoUnico = TrattoStrada([a(0, -500), a(0, 500)], senso: 1);
    expect(AggancioStrada().aggancia(a(6, 0), rotta: 181, velocitaMs: 10, strade: [sensoUnico]), isNull);
    // Contromano su un senso unico disegnato al contrario (senso -1): verso nord no, verso sud sì.
    final alContrario = TrattoStrada([a(0, -500), a(0, 500)], senso: -1);
    expect(AggancioStrada().aggancia(a(6, 0), rotta: 0, velocitaMs: 10, strade: [alContrario]), isNull);
    expect(AggancioStrada().aggancia(a(6, 0), rotta: 180, velocitaMs: 10, strade: [alContrario]), isNotNull);
  });

  test('fra due strade parallele non salta a ogni lettura', () {
    // Due strade a 20 m l'una dall'altra; si va sulla prima (x = 0) e il GPS
    // balla fra 3 e 12 metri verso la seconda, a volte più vicino a lei.
    final prima = TrattoStrada([a(0, -500), a(0, 1000)]);
    final seconda = TrattoStrada([a(20, -500), a(20, 1000)]);
    final g = AggancioStrada();
    final lati = [3.0, 8.0, 12.0, 6.0, 11.0, 4.0, 12.5, 9.0, 2.0, 11.0];
    for (var i = 0; i < lati.length; i++) {
      final r = g.aggancia(a(lati[i], i * 14.0), rotta: 0, velocitaMs: 14, strade: [seconda, prima]);
      final (x, _) = dove(r!.punto);
      expect(x.abs(), lessThan(0.01), reason: 'lettura $i a ${lati[i]} m: resta sulla prima');
    }
    // Ma passando davvero sull'altra (tre letture a 2 m da lei) ci si sposta.
    var x = 0.0;
    for (var i = 0; i < 3; i++) {
      final r = g.aggancia(a(18, 200 + i * 14.0), rotta: 0, velocitaMs: 14, strade: [seconda, prima]);
      x = dove(r!.punto).$1;
    }
    expect(x, closeTo(20, 0.01));
  });

  test("all'incrocio la traversa più vicina non ruba l'auto", () {
    // Si va a nord sulla x = 0; una traversa est-ovest a y = 0. Il GPS, a 8 m
    // di lato e 3 m prima dell'incrocio, è più vicino alla traversa.
    final traversa = TrattoStrada([a(-300, 0), a(300, 0)]);
    final g = AggancioStrada();
    for (var y = -60.0; y <= 60; y += 12) {
      final r = g.aggancia(a(8, y == -0 ? -3 : y - 3), rotta: 0, velocitaMs: 12, strade: [traversa, nordSud]);
      final (x, _) = dove(r!.punto);
      expect(x.abs(), lessThan(0.01), reason: 'a ${y - 3} m dall\'incrocio resta sulla strada che va a nord');
    }
    // Svoltando davvero (si va a est, sulla traversa) si passa alla traversa.
    final r = g.aggancia(a(30, 4), rotta: 88, velocitaMs: 8, strade: [traversa, nordSud]);
    final (_, y) = dove(r!.punto);
    expect(y.abs(), lessThan(0.01));
  });

  test('una curva: la strada spezzata in pezzi si segue', () {
    // Un quarto di cerchio di 60 m di raggio, a pezzi di 10°, il GPS 7 m fuori.
    final pezzi = <TrattoStrada>[];
    for (var g = 0; g < 90; g += 10) {
      final r0 = g * math.pi / 180, r1 = (g + 10) * math.pi / 180;
      pezzi.add(
          TrattoStrada([a(60 - 60 * math.cos(r0), 60 * math.sin(r0)), a(60 - 60 * math.cos(r1), 60 * math.sin(r1))]));
    }
    final ag = AggancioStrada();
    for (var g = 5; g < 90; g += 10) {
      final r = g * math.pi / 180;
      final gps = a(60 - 67 * math.cos(r), 67 * math.sin(r));
      final rotta = g.toDouble(); // da nord verso est
      final s = ag.aggancia(gps, rotta: rotta, velocitaMs: 10, strade: pezzi);
      expect(s, isNotNull, reason: 'a $g°');
      final (x, y) = dove(s!.punto);
      expect(math.sqrt((x - 60) * (x - 60) + y * y), closeTo(60, 0.6), reason: 'sulla curva');
    }
  });
}
