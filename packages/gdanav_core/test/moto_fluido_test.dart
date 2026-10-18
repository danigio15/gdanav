import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

const metriPerGrado = 111195.08;

/// Metri a nord di [da] (negativi a sud).
double nordDi(Punto da, Punto p) => (p.lat - da.lat) * metriPerGrado;

/// Metri a est di [da] (negativi a ovest).
double estDi(Punto da, Punto p) => (p.lon - da.lon) * metriPerGrado * math.cos(da.lat * math.pi / 180);

/// Un punto [nord] metri a nord e [est] metri a est di [da].
Punto spostato(Punto da, {double nord = 0, double est = 0}) =>
    Punto(da.lat + nord / metriPerGrado, da.lon + est / (metriPerGrado * math.cos(da.lat * math.pi / 180)));

void main() {
  const partenza = Punto(45, 9);
  const fotogramma = Duration(milliseconds: 40);

  /// I fotogrammi da [da] a [a], a 25 al secondo: dove si è disegnata l'auto.
  List<Punto> fotogrammi(MotoFluido m, Duration da, Duration a, [Duration passo = fotogramma]) => [
        for (var t = da; t <= a; t += passo) m.fotogramma(t)!.punto,
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

  test('una posizione nuova un po\' indietro non fa tornare indietro la freccia, né la ferma', () {
    final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 20, alle: Duration.zero);
    final prima = fotogrammi(m, Duration.zero, const Duration(seconds: 1) - fotogramma);
    // Il GPS dice che si è fatto meno: 12 m invece di 20 (si è frenato), e
    // da lì si va a 12 m/s, una posizione al secondo.
    final dopo = <Punto>[];
    for (var s = 1; s <= 4; s++) {
      m.posizione(spostato(partenza, nord: 12.0 * s), rotta: 0, velocitaMs: 12, alle: Duration(seconds: s));
      dopo.addAll(fotogrammi(m, Duration(seconds: s), Duration(seconds: s + 1) - fotogramma));
    }
    final tutti = [...prima, ...dopo];
    for (var i = 1; i < tutti.length; i++) {
      expect(nordDi(tutti[i - 1], tutti[i]), greaterThan(0), reason: 'fotogramma $i: mai indietro, mai fermi');
    }
    // E la previsione, che va avanti, la riprende: alla fine sono insieme.
    final previsione = m.previsione(const Duration(milliseconds: 4960))!.punto;
    expect(distanzaM(dopo.last, previsione), lessThan(1));
  });

  test('una posizione nuova di lato: la freccia si corregge verso di lei, senza salto', () {
    final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 0, alle: Duration.zero);
    m.fotogramma(Duration.zero);
    // Cinque metri a est.
    final est = spostato(partenza, est: 5);
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
      ..posizione(spostato(partenza, nord: 15), rotta: 20, velocitaMs: 15, alle: const Duration(seconds: 1));
    final p = m.previsione(const Duration(milliseconds: 1500))!;
    expect(p.rotta, closeTo(30, 1e-6));
    // Dritto sarebbe andata a nord-nord-est di 20°: girando, più a est.
    final dritto = spostato(partenza, nord: 15 + 7.5 * 0.9396926207859084, est: 7.5 * 0.3420201433256687);
    expect(p.punto.lon, greaterThan(dritto.lon));
  });

  test('a velocità zero si ferma lì, senza tornare indietro, e non chiede più fotogrammi', () {
    final m = MotoFluido()..posizione(partenza, rotta: 90, velocitaMs: 10, alle: Duration.zero);
    final andando = fotogrammi(m, Duration.zero, const Duration(milliseconds: 960));
    final qui = spostato(partenza, est: 9);
    m.posizione(qui, rotta: 90, velocitaMs: 0, alle: const Duration(seconds: 1));
    final punti = [...andando, ...fotogrammi(m, const Duration(milliseconds: 1040), const Duration(seconds: 4))];
    expect(m.fermo, isTrue);
    // Si prevedevano 10 m, si è fermata a 9: la freccia era già un poco oltre,
    // e lì resta invece di fare un passo indietro.
    expect(distanzaM(punti.last, qui), lessThan(1.5));
    for (var i = 1; i < punti.length; i++) {
      expect(estDi(punti[i - 1], punti[i]), greaterThanOrEqualTo(-1e-9), reason: 'fotogramma $i: indietro');
    }
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

  /* ─── Le piccole pause ─────────────────────────────────────────────────── */

  group('con un GPS vero (una posizione al secondo, che sbaglia di un paio di metri)', () {
    // 50 km/h verso nord, a 30 fotogrammi al secondo; il GPS legge ogni
    // secondo con 2,5 m di errore lungo la strada e 1 m di lato, alternati.
    const v = 13.9;
    const passo = Duration(microseconds: 33333);
    late List<Punto> punti;
    late List<double> velocita;

    setUp(() {
      final m = MotoFluido();
      punti = [];
      velocita = [];
      final errori = [2.5, -2.5, 1.5, -2.0, 2.5, -1.0, 0.5, -2.5, 2.0, -1.5];
      var t = Duration.zero;
      for (var s = 0; s < errori.length; s++) {
        m.posizione(
          spostato(partenza, nord: v * s + errori[s], est: s.isEven ? 1 : -1),
          rotta: 0,
          velocitaMs: v,
          alle: Duration(seconds: s),
        );
        for (; t < Duration(seconds: s + 1); t += passo) {
          punti.add(m.fotogramma(t)!.punto);
          velocita.add(m.velocitaMostrata);
        }
      }
    });

    test('la freccia va sempre avanti, e mai sotto un quarto della velocità', () {
      final dt = passo.inMicroseconds / 1e6;
      for (var i = 2; i < punti.length; i++) {
        final avanti = nordDi(punti[i - 1], punti[i]);
        expect(avanti, greaterThan(0), reason: 'fotogramma $i: indietro o fermo');
        expect(avanti, greaterThanOrEqualTo(v * MotoFluido.almenoDellaVelocita * dt * 0.99), reason: 'fotogramma $i');
        expect(avanti, lessThanOrEqualTo(math.max(2 * v, v + 10) * dt + 0.05), reason: 'fotogramma $i: uno scatto');
      }
    });

    test('la velocità della freccia cambia piano: niente strappi fra due fotogrammi', () {
      for (var i = 2; i < velocita.length; i++) {
        final cambio = (velocita[i] - velocita[i - 1]).abs();
        // Al più l'8% della velocità in un fotogramma da 33 ms.
        expect(cambio, lessThan(0.08 * v), reason: 'fotogramma $i: da ${velocita[i - 1]} a ${velocita[i]}');
      }
      // E resta vicina a quella dell'auto: corregge, non va a strappi.
      final media = velocita.skip(30).reduce((a, b) => a + b) / (velocita.length - 30);
      expect(media, closeTo(v, 1.0));
    });

    test('i passi di lato sono piccoli: la correzione si spalma', () {
      for (var i = 2; i < punti.length; i++) {
        expect(estDi(punti[i - 1], punti[i]).abs(), lessThan(0.4), reason: 'fotogramma $i');
      }
    });
  });

  test('una posizione nuova avanti della previsione si recupera in un paio di secondi, senza salto', () {
    final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 10, alle: Duration.zero);
    fotogrammi(m, Duration.zero, const Duration(milliseconds: 960));
    // Tre metri più avanti di quanto si prevedeva.
    m.posizione(spostato(partenza, nord: 13), rotta: 0, velocitaMs: 10, alle: const Duration(seconds: 1));
    final punti = fotogrammi(m, const Duration(seconds: 1), const Duration(milliseconds: 1960));
    // E un secondo dopo, giusta.
    m.posizione(spostato(partenza, nord: 23), rotta: 0, velocitaMs: 10, alle: const Duration(seconds: 2));
    punti.addAll(fotogrammi(m, const Duration(seconds: 2), const Duration(seconds: 3)));
    for (var i = 1; i < punti.length; i++) {
      final passo = nordDi(punti[i - 1], punti[i]);
      expect(passo, lessThan(20 * 0.04 + 1e-6), reason: 'fotogramma $i: al più il doppio');
      expect(passo, greaterThan(0), reason: 'fotogramma $i');
    }
    final scarto = distanzaM(punti.last, m.previsione(const Duration(seconds: 3))!.punto);
    expect(scarto, lessThan(0.4));
  });

  test('la direzione passa per il nord come si deve: da 359° a 1° sono due gradi, non 358', () {
    final m = MotoFluido()..posizione(partenza, rotta: 359, velocitaMs: 10, alle: Duration.zero);
    fotogrammi(m, Duration.zero, const Duration(milliseconds: 960));
    m.posizione(spostato(partenza, nord: 10), rotta: 1, velocitaMs: 10, alle: const Duration(seconds: 1));
    final rotte = <double>[];
    for (var t = const Duration(seconds: 1); t <= const Duration(seconds: 2); t += fotogramma) {
      rotte.add(m.fotogramma(t)!.rotta);
    }
    for (final r in rotte) {
      expect(r < 5 || r > 355, isTrue, reason: 'rotta $r: ha fatto il giro lungo');
      expect(r, inInclusiveRange(0, 360));
    }
    expect(diQuantoSiGira(rotte.last, m.previsione(const Duration(seconds: 2))!.rotta).abs(), lessThan(0.5));
    // Sempre girando verso est, mai indietro.
    for (var i = 1; i < rotte.length; i++) {
      expect(diQuantoSiGira(rotte[i - 1], rotte[i]), greaterThanOrEqualTo(-1e-9));
    }
  });

  test('a 20 o a 60 fotogrammi al secondo la freccia fa la stessa strada', () {
    Punto dove(Duration passo) {
      final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 15, alle: Duration.zero);
      var t = Duration.zero;
      for (; t < const Duration(seconds: 1); t += passo) {
        m.fotogramma(t);
      }
      m.posizione(spostato(partenza, nord: 13), rotta: 0, velocitaMs: 15, alle: const Duration(seconds: 1));
      for (; t <= const Duration(seconds: 2); t += passo) {
        m.fotogramma(t);
      }
      return m.fotogramma(const Duration(seconds: 2))!.punto;
    }

    final lenta = dove(const Duration(milliseconds: 50));
    final veloce = dove(const Duration(microseconds: 16667));
    expect(distanzaM(lenta, veloce), lessThan(0.3));
  });

  test('un fotogramma in ritardo (la mappa occupata) non diventa un salto', () {
    final m = MotoFluido()..posizione(partenza, rotta: 0, velocitaMs: 30, alle: Duration.zero);
    fotogrammi(m, Duration.zero, const Duration(milliseconds: 400));
    final prima = m.mostrata!;
    // Mezzo secondo senza fotogrammi.
    final dopo = m.fotogramma(const Duration(milliseconds: 900))!.punto;
    // Mezzo secondo a 30 m/s sono 15 m: la freccia ne recupera una parte
    // adesso e il resto nei fotogrammi dopo.
    expect(nordDi(prima, dopo), lessThan(0.75 * 15));
    expect(nordDi(prima, dopo), greaterThan(0));
  });

  /* ─── La mappa senza percorso ──────────────────────────────────────────── */

  group('la telecamera senza percorso', () {
    test('vicina in città, come in guida: 17,5 e 3D con l\'auto in basso', () {
      final c = telecameraLibera(velocitaMs: 0, tridimensionale: true);
      expect(c.zoom, 17.5);
      expect(c.inclinazione, 55);
      expect(c.sopra, 0.3);
      expect(telecameraLibera(velocitaMs: 30 / 3.6, tridimensionale: true).zoom, closeTo(17.5, 1e-9));
    });

    test('andando forte un poco più lontana, mai quanto prima (15,5)', () {
      var prima = double.infinity;
      for (var kmh = 0; kmh <= 160; kmh += 5) {
        final z = telecameraLibera(velocitaMs: kmh / 3.6, tridimensionale: true).zoom;
        expect(z, lessThanOrEqualTo(prima + 1e-12), reason: '$kmh km/h: più veloce, mai più vicina');
        expect(z, greaterThanOrEqualTo(16.2 - 1e-9), reason: '$kmh km/h');
        expect(z, greaterThan(15.5));
        prima = z;
      }
      expect(telecameraLibera(velocitaMs: 130 / 3.6, tridimensionale: true).zoom, closeTo(16.2, 1e-9));
      final mezzo = telecameraLibera(velocitaMs: 70 / 3.6, tridimensionale: true).zoom;
      expect(mezzo, closeTo((17.5 + 16.2) / 2, 1e-9));
    });

    test('senza salti: un km/h in più cambia lo zoom di poco', () {
      for (var kmh = 0.0; kmh < 150; kmh += 0.5) {
        final a = telecameraLibera(velocitaMs: kmh / 3.6, tridimensionale: true).zoom;
        final b = telecameraLibera(velocitaMs: (kmh + 0.5) / 3.6, tridimensionale: true).zoom;
        expect((a - b).abs(), lessThan(0.02), reason: '$kmh km/h');
      }
    });

    test('in 2D dall\'alto, con l\'auto in mezzo; i tasti + e − spostano lo zoom', () {
      final c = telecameraLibera(velocitaMs: 10, tridimensionale: false);
      expect(c.inclinazione, 0);
      expect(c.sopra, 0);
      expect(telecameraLibera(velocitaMs: 0, tridimensionale: true, scarto: -1).zoom, 16.5);
      expect(telecameraLibera(velocitaMs: 0, tridimensionale: true, scarto: 5).zoom, 19.5);
    });

    test('una velocità che non c\'è è da fermi', () {
      expect(telecameraLibera(velocitaMs: double.nan, tridimensionale: true).zoom, 17.5);
      expect(telecameraLibera(velocitaMs: -3, tridimensionale: true).zoom, 17.5);
    });
  });
}
