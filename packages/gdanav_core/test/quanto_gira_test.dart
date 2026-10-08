import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/* ── «Non è che mi propone un tornante quando è una semplice deviazione» ───
 *
 * Il tipo della manovra di Valhalla dice «uscita a sinistra» e basta: un
 * raccordo che si stacca di quindici gradi e una rampa che torna indietro
 * hanno lo stesso numero. I gradi stanno solo nei punti del percorso. */
void main() {
  /// Una strada dritta verso nord che, dal punto [dove], piega di [gradi].
  PercorsoCalcolato piega(double gradi, {int dove = 20, int quanti = 40}) {
    const passo = 0.00009; // ~10 m
    final punti = <Punto>[for (var i = 0; i <= dove; i++) Punto(45 + i * passo, 9)];
    var lat = 45 + dove * passo, lon = 9.0;
    final r = gradi * math.pi / 180;
    for (var i = 1; i <= quanti; i++) {
      lat += math.cos(r) * passo;
      lon += math.sin(r) * passo / math.cos(45 * math.pi / 180);
      punti.add(Punto(lat, lon));
    }
    return PercorsoCalcolato(
      punti: punti,
      tratti: const [],
      manovre: [Manovra(istruzione: 'Esci', lunghezzaM: 400, secondi: 30, inizio: dove, tipo: 21)],
    );
  }

  test('una deviazione di venti gradi si misura venti gradi', () {
    final p = piega(-20);
    expect(quantoGiraLaManovra(p, p.manovre.first), closeTo(-20, 1.5));
  });

  test('un tornante si misura tornante', () {
    final p = piega(-140);
    expect(quantoGiraLaManovra(p, p.manovre.first), closeTo(-140, 2));
  });

  test('il segno dice da che parte, e non lo dice il tipo della manovra', () {
    // Tipo 21 è «uscita a sinistra», ma questa strada piega a destra.
    final p = piega(40);
    expect(p.manovre.first.tipo, 21);
    expect(quantoGiraLaManovra(p, p.manovre.first), closeTo(40, 1.5));
  });

  test('su una rampa che si chiude piano si tiene la misura più larga', () {
    /* Trecento metri dritti, poi una rampa che gira dieci gradi ogni dieci
     * metri: a quaranta metri ha girato poco, a centocinquanta è tutt'altra
     * cosa, ed è quella che conta per disegnarla. */
    const passo = 0.00009;
    final punti = <Punto>[for (var i = 0; i <= 30; i++) Punto(45 + i * passo, 9)];
    var lat = 45 + 30 * passo, lon = 9.0;
    for (var i = 1; i <= 20; i++) {
      final r = -i * 4.0 * math.pi / 180;
      lat += math.cos(r) * passo;
      lon += math.sin(r) * passo / math.cos(45 * math.pi / 180);
      punti.add(Punto(lat, lon));
    }
    final p = PercorsoCalcolato(
      punti: punti,
      tratti: const [],
      manovre: const [Manovra(istruzione: 'Esci', lunghezzaM: 200, secondi: 20, inizio: 30, tipo: 21)],
    );
    final largo = quantoGiraLaManovra(p, p.manovre.first)!;
    final corto = quantoGiraLaManovra(p, p.manovre.first, dopoM: const [40])!;
    expect(largo.abs(), greaterThan(corto.abs()));
    expect(largo, lessThan(-25));
  });

  test('senza abbastanza strada intorno non si inventa un numero', () {
    final corto = PercorsoCalcolato(
      punti: const [Punto(45, 9), Punto(45.00001, 9), Punto(45.00002, 9)],
      tratti: const [],
      manovre: const [Manovra(istruzione: 'Esci', lunghezzaM: 2, secondi: 1, inizio: 1, tipo: 21)],
    );
    expect(quantoGiraLaManovra(corto, corto.manovre.first), isNull);
  });

  /* Il lato dello svincolo è uno solo, per icona, cartello, corsie e scena:
   * quello del tipo della manovra. I gradi dicono dove va la strada dopo, e
   * contano solo quando il tipo non dice niente. */
  group('latoDellaManovra', () {
    Manovra m(int tipo, [List<Corsia> corsie = const []]) =>
        Manovra(istruzione: '', lunghezzaM: 300, secondi: 10, inizio: 0, tipo: tipo, corsie: corsie);

    test('tieni la sinistra resta a sinistra anche se la strada poi piega a destra', () {
      expect(latoDellaManovra(m(24), gradi: 45), -1);
      expect(latoDellaManovra(m(21), gradi: 30), -1);
      expect(latoDellaManovra(m(19)), -1);
    });

    test('tieni la destra resta a destra anche se la strada poi piega a sinistra', () {
      expect(latoDellaManovra(m(23), gradi: -45), 1);
      expect(latoDellaManovra(m(20), gradi: -30), 1);
      expect(latoDellaManovra(m(18)), 1);
    });

    test('senza lato nel tipo: prima le corsie giuste, poi i gradi', () {
      const sx = [
        Corsia([DirezioneCorsia.dritto], giusta: true),
        Corsia([DirezioneCorsia.dritto])
      ];
      const dx = [
        Corsia([DirezioneCorsia.dritto]),
        Corsia([DirezioneCorsia.dritto], giusta: true)
      ];
      expect(latoDellaManovra(m(17, sx), gradi: 40), -1);
      expect(latoDellaManovra(m(17, dx), gradi: -40), 1);
      expect(latoDellaManovra(m(22), gradi: -30), -1);
      expect(latoDellaManovra(m(22), gradi: 30), 1);
      expect(latoDellaManovra(m(22), gradi: 3), 0);
      expect(latoDellaManovra(m(8)), 0);
    });
  });
}
