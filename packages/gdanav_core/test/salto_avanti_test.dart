import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/* «Ero ancora all'incrocio e la freccia più avanti della posizione reale»:
 * entrando piano in una rotonda, il GPS che cade di qualche metro verso
 * l'anello è più vicino al percorso più avanti che alla strada su cui si è. */
void main() {
  const lat0 = 45.0, lon0 = 9.0;
  final kx = 111320 * math.cos(lat0 * math.pi / 180);
  const ky = 110540.0;
  Punto xy(double x, double y) => Punto(lat0 + y / ky, lon0 + x / kx);

  /// Su verso nord per 40 m, a destra per 12, giù verso sud per 40: un
  /// percorso che torna accanto a sé stesso, come all'ingresso di un anello.
  final percorso = PercorsoCalcolato(
    punti: [
      for (var y = 0.0; y <= 40; y += 4) xy(0, y),
      for (var x = 4.0; x <= 12; x += 4) xy(x, 40),
      for (var y = 36.0; y >= 0; y -= 4) xy(12, y),
    ],
    tratti: const [],
    manovre: const [Manovra(istruzione: 'Parti', lunghezzaM: 92, secondi: 60, inizio: 0, tipo: 1)],
  );

  PuntoInMoto a(double x, double y, int s) => PuntoInMoto(
        xy(x, y).lat,
        xy(x, y).lon,
        velocitaMs: 1.1,
        precisioneM: 8,
        alle: DateTime.utc(2026, 1, 1, 8, 0, s),
      );

  test('a passo d\'uomo una lettura più vicina al percorso dopo non fa saltare avanti', () {
    final g = Guida(percorso);
    for (var s = 0; s <= 20; s++) {
      g.aggiorna(a(0, 8 + s.toDouble(), s));
    }
    // Il GPS cade verso destra, un po' più vicino al ritorno (a 64 m di
    // percorso) che alla strada su cui si è (a 29 m).
    final dopo = g.aggiorna(a(6.5, 29, 21));
    expect(dopo.percorsiM, lessThan(40), reason: 'si è ancora prima della curva');
    expect(dopo.percorsiM, greaterThan(26));
  });

  test('andando davvero oltre, ci si trova dove si è', () {
    final g = Guida(percorso);
    for (var s = 0; s <= 8; s++) {
      g.aggiorna(a(0, 4.0 * s, s));
    }
    // Un buco di segnale: si ricompare sul ritorno, lontani.
    final dopo = g.aggiorna(a(12, 20, 30));
    expect(dopo.percorsiM, closeTo(72, 1));
  });
}
