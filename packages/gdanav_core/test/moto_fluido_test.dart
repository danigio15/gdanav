import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Metri a nord di [da] (negativi a sud).
double nordDi(Punto da, Punto p) => (p.lat - da.lat) * 111195.08;

void main() {
  const partenza = Punto(45, 9);
  const fotogramma = Duration(milliseconds: 40);

  /// I fotogrammi da [da] a [a], a 25 al secondo: dove si è disegnata l'auto.
  List<Punto> fotogrammi(MotoFluido m, Duration da, Duration a) => [
        for (var t = da; t <= a; t += fotogramma) m.fotogramma(t)!.punto,
      ];

  test('fra una posizione e l\'altra l\'auto va avanti da sola, senza fermarsi ad aspettare', () {
    final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 20, alle: Duration.zero);
    final punti = fotogrammi(m, Duration.zero, const Duration(seconds: 1));
    // Una posizione intermedia: a mezzo secondo fra la partenza e i 10 m previsti.
    final mezzo = punti[12];
    expect(nordDi(partenza, mezzo), inExclusiveRange(4, 10.5));
    // Sempre avanti, a passi da fotogramma (20 m/s per 40 ms = 0,8 m).
    for (var i = 1; i < punti.length; i++) {
      final passo = nordDi(punti[i - 1], punti[i]);
      expect(passo, greaterThan(0), reason: 'fotogramma $i: mai fermi andando');
      expect(passo, lessThan(1.6), reason: 'fotogramma $i: niente scatti');
    }
    // Dopo un secondo la previsione è 20 m avanti; la freccia la insegue da vicino.
    expect(nordDi(partenza, punti.last), inInclusiveRange(15, 20.01));
    expect(m.fermo, isFalse);
  });

  test('una posizione nuova un po\' indietro non fa tornare indietro la freccia', () {
    final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 20, alle: Duration.zero);
    final prima = fotogrammi(m, Duration.zero, const Duration(seconds: 1));
    // Il GPS dice che si è fatto meno: 12 m invece di 20 (si è frenato).
    final indietro = Punto(partenza.lat + 12 / 111195.08, partenza.lon);
    m.posizione(indietro, rotta: 0, velocitaMs: 12, alle: const Duration(seconds: 1));
    final dopo = fotogrammi(m, const Duration(milliseconds: 1040), const Duration(seconds: 3));
    final tutti = [...prima, ...dopo];
    for (var i = 1; i < tutti.length; i++) {
      expect(nordDi(tutti[i - 1], tutti[i]), greaterThanOrEqualTo(-1e-6), reason: 'fotogramma $i: indietro');
    }
    // E la previsione, che va avanti, la riprende: alla fine sono insieme.
    final previsione = m.previsione(const Duration(seconds: 3))!.punto;
    expect(distanzaM(dopo.last, previsione), lessThan(1));
  });

  test('una posizione nuova di lato: la freccia si corregge verso di lei, senza salto', () {
    final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 0, alle: Duration.zero);
    m.fotogramma(Duration.zero);
    // Cinque metri a est.
    final est = Punto(partenza.lat, partenza.lon + 5 / (111195.08 * 0.7071067811865476));
    m.posizione(est, rotta: 0, velocitaMs: 0, alle: Duration.zero);
    final punti = fotogrammi(m, fotogramma, const Duration(seconds: 2));
    var prima = distanzaM(partenza, est);
    for (final p in punti) {
      final adesso = distanzaM(p, est);
      expect(adesso, lessThanOrEqualTo(prima + 1e-9), reason: 'sempre più vicina');
      expect(prima - adesso, lessThan(1.5), reason: 'un passo, non un salto');
      prima = adesso;
    }
    expect(prima, lessThan(0.3));
  });

  test('in curva la previsione gira come stava girando', () {
    final m = MotoFluido()
      ..posizione(partenza, rotta: 0, velocitaMs: 15, alle: Duration.zero)
      ..posizione(Punto(partenza.lat + 15 / 111195.08, partenza.lon),
          rotta: 20, velocitaMs: 15, alle: const Duration(seconds: 1));
    final p = m.previsione(const Duration(milliseconds: 1500))!;
    expect(p.rotta, closeTo(30, 1e-6));
    // Dritto sarebbe andata a nord-nord-est di 20°: girando, più a est.
    final dritto = Punto(
      partenza.lat + (15 + 7.5 * 0.9396926207859084) / 111195.08,
      partenza.lon + 7.5 * 0.3420201433256687 / (111195.08 * 0.7071067811865476),
    );
    expect(p.punto.lon, greaterThan(dritto.lon));
  });

  test('a velocità zero si ferma lì, e non chiede più fotogrammi', () {
    final m = MotoFluido()..posizione(partenza, rotta: 90, velocitaMs: 10, alle: Duration.zero);
    fotogrammi(m, Duration.zero, const Duration(milliseconds: 960));
    final qui = Punto(partenza.lat, partenza.lon + 9 / (111195.08 * 0.7071067811865476));
    m.posizione(qui, rotta: 90, velocitaMs: 0, alle: const Duration(seconds: 1));
    final punti = fotogrammi(m, const Duration(milliseconds: 1040), const Duration(seconds: 4));
    expect(m.fermo, isTrue);
    expect(distanzaM(punti.last, qui), lessThan(0.3));
    // Ferma: la previsione non va avanti col tempo.
    expect(m.previsione(const Duration(seconds: 30))!.punto, qui);
  });

  test('col GPS muto la previsione si ferma dopo un secondo e mezzo', () {
    final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 20, alle: Duration.zero);
    final a = m.previsione(const Duration(milliseconds: 1500))!.punto;
    final b = m.previsione(const Duration(seconds: 10))!.punto;
    expect(nordDi(partenza, a), closeTo(30, 1e-6));
    expect(b, a);
    fotogrammi(m, Duration.zero, const Duration(seconds: 4));
    expect(m.fermo, isTrue);
  });

  test('una posizione lontana (un ricalcolo, il GPS che torna) si disegna subito lì', () {
    final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 20, alle: Duration.zero);
    fotogrammi(m, Duration.zero, const Duration(milliseconds: 400));
    final lontano = Punto(partenza.lat + 0.01, partenza.lon);
    m.posizione(lontano, rotta: 0, velocitaMs: 20, alle: const Duration(milliseconds: 440));
    expect(m.fotogramma(const Duration(milliseconds: 440))!.punto, lontano);
  });
}
