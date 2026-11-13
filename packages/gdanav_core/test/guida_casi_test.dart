import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/* ── Tre casi della guida sui bordi ────────────────────────────────────────
 *
 * «Sei arrivato» a centoventi metri dalla meta su un'altra strada;
 * un'inversione a U sulla stessa strada presa per contromano; un giro che
 * torna alla partenza dove la prima lettura si agganciava alla fine. */

/// Punto a [nordM] metri a nord e [estM] a est di (41.9, 12.5).
Punto pt(double nordM, double estM) =>
    Punto(41.9 + nordM / 111195.08, 12.5 + estM / (111195.08 * math.cos(41.9 * math.pi / 180)));

PercorsoCalcolato percorso(List<Punto> punti, List<Manovra> manovre) {
  final l = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++) Tratto(lunghezzaM: l.cumulate[i] - l.cumulate[i - 1], velocitaKmh: 50),
    ],
    manovre: manovre,
  );
}

void main() {
  test('arrivato solo vicino alla meta, non a 150 m di distanza su un\'altra strada', () {
    // Verso nord 1 km, poi a destra 100 m fino alla meta.
    final punti = [for (var m = 0; m <= 1000; m += 50) pt(m.toDouble(), 0), pt(1000, 50), pt(1000, 100)];
    final p = percorso(punti, [
      const Manovra(istruzione: 'Parti', lunghezzaM: 1000, secondi: 72, inizio: 0, tipo: 1),
      Manovra(
          istruzione: 'Gira a destra',
          lunghezzaM: 100,
          secondi: 8,
          inizio: punti.length - 3,
          tipo: 10,
          voce: 'Gira a destra'),
      Manovra(istruzione: 'Arrivo', lunghezzaM: 0, secondi: 0, inizio: punti.length - 1, tipo: 4),
    ]);
    final g = Guida(p);
    for (var m = 0; m <= 950; m += 50) {
      g.aggiorna(pt(m.toDouble(), 0));
    }
    // Non si gira: si tira dritto e poi si va avanti verso nord-est, su
    // un'altra strada, a 150 m dalla meta.
    final a1 = g.aggiorna(pt(1000, 0));
    final a2 = g.aggiorna(pt(1060, 40));
    final a3 = g.aggiorna(pt(1120, 120));
    expect(a1.arrivato || a2.arrivato, isFalse);
    expect(a3.arrivato, isFalse, reason: 'a ${a3.lontanoM.round()} m dalla linea non si è arrivati');
  });

  test('inversione a U sulla stessa strada: niente fuori percorso né metri all\'indietro', () {
    // 600 m verso nord, inversione, 600 m verso sud sulla stessa linea (strada
    // a una carreggiata, come la disegna OpenStreetMap).
    final andata = [for (var m = 0; m <= 600; m += 30) pt(m.toDouble(), 0)];
    final ritorno = [for (var m = 570; m >= 0; m -= 30) pt(m.toDouble(), 0)];
    final punti = [...andata, ...ritorno];
    final p = percorso(punti, [
      const Manovra(istruzione: 'Parti', lunghezzaM: 600, secondi: 43, inizio: 0, tipo: 1),
      Manovra(
          istruzione: 'Fai inversione',
          lunghezzaM: 600,
          secondi: 43,
          inizio: andata.length - 1,
          tipo: 13,
          voce: 'Fai inversione'),
      Manovra(istruzione: 'Arrivo', lunghezzaM: 0, secondi: 0, inizio: punti.length - 1, tipo: 4),
    ]);
    final g = Guida(p);
    var fuori = 0;
    double? prima;
    var indietro = 0;
    for (final q in [
      for (var m = 0; m <= 600; m += 15) pt(m.toDouble(), 1),
      for (var m = 585; m >= 100; m -= 15) pt(m.toDouble(), -1),
    ]) {
      final a = g.aggiorna(q);
      if (a.fuoriPercorso) fuori++;
      if (prima != null && a.percorsiM < prima - 5) indietro++;
      prima = a.percorsiM;
    }
    expect(fuori, 0);
    expect(indietro, 0);
    // Sul ritorno, a cento metri dalla partenza: fatti 600 + 500 metri.
    expect(prima, closeTo(1100, 20));
  });

  test('la prima lettura non si aggancia alla fine di un percorso che torna al punto di partenza', () {
    // Un giro: 500 m a nord, 500 a est, 500 a sud, 480 a ovest: si torna a 20 m dalla partenza.
    final punti = [
      for (var m = 0; m <= 500; m += 50) pt(m.toDouble(), 0),
      for (var m = 50; m <= 500; m += 50) pt(500, m.toDouble()),
      for (var m = 450; m >= 0; m -= 50) pt(m.toDouble(), 500),
      for (var m = 450; m >= 20; m -= 50) pt(-3, m.toDouble()),
      pt(-3, 20),
    ];
    final p = percorso(punti, [
      const Manovra(istruzione: 'Parti', lunghezzaM: 500, secondi: 36, inizio: 0, tipo: 1),
      Manovra(istruzione: 'Arrivo', lunghezzaM: 0, secondi: 0, inizio: punti.length - 1, tipo: 4),
    ]);
    // Il GPS alla partenza, due metri a sud: più vicino all'ultimo tratto.
    final a = Guida(p).aggiorna(pt(-2, 10));
    expect(a.arrivato, isFalse);
    expect(a.restantiM, greaterThan(1900));
  });

  test('arrivati davvero, vicino alla linea, si è arrivati', () {
    final punti = [for (var m = 0; m <= 500; m += 50) pt(m.toDouble(), 0)];
    final p = percorso(punti, [
      const Manovra(istruzione: 'Parti', lunghezzaM: 500, secondi: 36, inizio: 0, tipo: 1),
      Manovra(istruzione: 'Arrivo', lunghezzaM: 0, secondi: 0, inizio: punti.length - 1, tipo: 4),
    ]);
    final g = Guida(p);
    for (var m = 0; m <= 450; m += 50) {
      expect(g.aggiorna(pt(m.toDouble(), 3)).arrivato, isFalse);
    }
    // Dall'altra parte della strada, dieci metri oltre la meta.
    expect(g.aggiorna(pt(510, -8)).arrivato, isTrue);
  });
}
