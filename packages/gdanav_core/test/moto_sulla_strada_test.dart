import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

const metriPerGrado = 111195.08;

/// Un punto [nord] metri a nord e [est] metri a est di [da].
Punto spostato(Punto da, {double nord = 0, double est = 0}) =>
    Punto(da.lat + nord / metriPerGrado, da.lon + est / (metriPerGrado * math.cos(da.lat * math.pi / 180)));

/// Dal campo: «non segue la strada agli svincoli e alle rotonde». Una strada
/// che va a nord per cento metri, entra in una rotonda di quindici metri di
/// raggio, ne fa tre quarti, ed esce dritta (verso ovest) per altri cento.
Linea rotonda() {
  const partenza = Punto(45, 9);
  final punti = <Punto>[partenza, spostato(partenza, nord: 100)];
  // Il centro della rotonda: quindici metri a est dell'entrata.
  final centro = spostato(partenza, nord: 100, est: 15);
  // Si entra a ovest del centro e si gira passando da nord ed est fino a sud:
  // tre quarti di giro (il verso non conta, per la freccia).
  for (var g = 180.0; g >= -90; g -= 10) {
    final r = g * math.pi / 180;
    punti.add(spostato(centro, est: 15 * math.cos(r), nord: 15 * math.sin(r)));
  }
  final uscita = punti.last;
  punti.add(spostato(uscita, est: -100));
  return Linea(punti);
}

void main() {
  const fotogramma = Duration(milliseconds: 33);

  test('agli svincoli e nelle rotonde la freccia resta sulla strada', () {
    final linea = rotonda();
    const v = 9.0; // 32 all'ora, in rotonda
    final m = MotoSullaStrada()..strada(linea);
    final vecchio = MotoFluido();
    var peggioreSulla = 0.0, peggioreVecchio = 0.0;
    var prima = -1.0;
    for (var t = Duration.zero; t < const Duration(seconds: 30); t += fotogramma) {
      final s = t.inMicroseconds / 1e6;
      // Una lettura al secondo, a volte un poco indietro o avanti lungo la strada.
      if (t.inMilliseconds % 1000 < fotogramma.inMilliseconds) {
        final errore = (s.round() % 3 - 1) * 2.0;
        final metri = (v * s + errore).clamp(0.0, linea.lunghezzaM);
        m.posizione(metri, velocitaMs: v, alle: t);
        final qui = sullaStrada(linea, metri);
        vecchio.posizione(qui.punto, rotta: qui.rotta, velocitaMs: v, alle: t);
      }
      final f = m.fotogramma(t)!;
      final g = vecchio.fotogramma(t)!;
      peggioreSulla = math.max(peggioreSulla, linea.proietta(f.punto).lontanoM);
      peggioreVecchio = math.max(peggioreVecchio, linea.proietta(g.punto).lontanoM);
      // Sempre avanti, mai indietro.
      expect(m.mostrataM!, greaterThanOrEqualTo(prima - 1e-9), reason: 'a ${s.toStringAsFixed(2)} s');
      prima = m.mostrataM!;
    }
    expect(peggioreSulla, lessThan(0.05), reason: 'mai fuori dalla linea');
    // Il conto di prima, sulla stessa strada, ne usciva di metri.
    expect(peggioreVecchio, greaterThan(1.0));
  });

  test('in rotonda la freccia gira con la strada', () {
    final linea = rotonda();
    // Un quarto di giro dopo l'entrata (a nord del centro) la strada va verso est.
    const centroLinea = 100 + 15 * math.pi / 2;
    final qui = sullaStrada(linea, centroLinea);
    expect(diQuantoSiGira(qui.rotta, 90).abs(), lessThan(15));
    // Sul rettilineo prima: nord.
    expect(diQuantoSiGira(sullaStrada(linea, 50).rotta, 0).abs(), lessThan(1));
    // Dopo l'uscita: ovest.
    expect(diQuantoSiGira(sullaStrada(linea, linea.lunghezzaM - 30).rotta, 270).abs(), lessThan(1));
  });

  test('allo svincolo la direzione gira piano, non di colpo', () {
    final linea = rotonda();
    final m = MotoSullaStrada()..strada(linea);
    m.posizione(80, velocitaMs: 10, alle: Duration.zero);
    double? rotta;
    // Dal rettilineo, dentro la rotonda e fuori dall'uscita.
    for (var t = Duration.zero; t < const Duration(seconds: 15); t += fotogramma) {
      if (t.inMilliseconds % 1000 < fotogramma.inMilliseconds) {
        m.posizione(80 + 10 * t.inMilliseconds / 1000, velocitaMs: 10, alle: t);
      }
      final f = m.fotogramma(t)!;
      if (rotta != null) {
        // A dieci metri al secondo, in un fotogramma: pochi gradi.
        expect(diQuantoSiGira(rotta, f.rotta).abs(), lessThan(8), reason: 'a ${t.inMilliseconds} ms');
      }
      rotta = f.rotta;
    }
  });

  test('un pezzo di strada nuovo: la freccia si ritrova dov\'era', () {
    final linea = rotonda();
    final m = MotoSullaStrada()..strada(linea);
    m.posizione(90, velocitaMs: 10, alle: Duration.zero);
    m.fotogramma(Duration.zero);
    final prima = sullaStrada(linea, m.mostrataM!).punto;
    // Lo schermo dell'auto riceve un pezzo che parte quaranta metri indietro.
    final pezzo = Linea(trattoDiStrada(linea, 50, 350));
    m.strada(pezzo);
    expect(m.mostrataM, closeTo(40, 0.5));
    final dopo = m.fotogramma(fotogramma)!;
    expect(distanzaM(prima, dopo.punto), lessThan(1));
  });

  test('una strada nuova lontana (un altro percorso): si ricomincia', () {
    final linea = rotonda();
    final m = MotoSullaStrada()..strada(linea);
    m.posizione(10, velocitaMs: 10, alle: Duration.zero);
    m.fotogramma(Duration.zero);
    const altrove = Punto(45.01, 9.01);
    m.strada(Linea([altrove, spostato(altrove, nord: 200)]));
    expect(m.mostrataM, isNull);
    m.posizione(5, velocitaMs: 10, alle: fotogramma);
    expect(m.fotogramma(fotogramma)!.punto.lat, greaterThan(altrove.lat));
  });

  test('il pezzo di strada ha i due capi e i vertici in mezzo', () {
    final linea = rotonda();
    final pezzo = trattoDiStrada(linea, 50, 130);
    expect(distanzaM(pezzo.first, sullaStrada(linea, 50).punto), lessThan(0.01));
    expect(distanzaM(pezzo.last, sullaStrada(linea, 130).punto), lessThan(0.01));
    expect(Linea(pezzo).lunghezzaM, closeTo(80, 0.5));
  });

  test('da fermi la freccia si ferma, e non torna indietro per poco', () {
    final linea = rotonda();
    final m = MotoSullaStrada()..strada(linea);
    m.posizione(60, velocitaMs: 10, alle: Duration.zero);
    for (var t = Duration.zero; t < const Duration(seconds: 1); t += fotogramma) {
      m.fotogramma(t);
    }
    final arrivata = m.mostrataM!;
    m.posizione(arrivata - 3, velocitaMs: 0, alle: const Duration(seconds: 1));
    for (var t = const Duration(seconds: 1); t < const Duration(seconds: 3); t += fotogramma) {
      m.fotogramma(t);
    }
    expect(m.mostrataM, closeTo(arrivata, 1e-9));
    expect(m.fermo, isTrue);
  });
}
