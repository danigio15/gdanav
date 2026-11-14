import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

const metriPerGrado = 111195.08;

Punto spostato(Punto da, {double nord = 0, double est = 0}) =>
    Punto(da.lat + nord / metriPerGrado, da.lon + est / (metriPerGrado * math.cos(da.lat * math.pi / 180)));

/// Mezzo chilometro di strada, una galleria di un chilometro (dritta, o in
/// curva di 400 m di raggio) e mezzo chilometro dopo. Punti inventati.
Linea strada({required bool curva}) {
  const partenza = Punto(41, 14.3);
  final punti = <Punto>[partenza];
  for (var m = 10.0; m <= 500; m += 10) {
    punti.add(spostato(partenza, nord: m));
  }
  final ingresso = punti.last;
  if (!curva) {
    for (var m = 10.0; m <= 1500; m += 10) {
      punti.add(spostato(ingresso, nord: m));
    }
  } else {
    // Un arco di 1000 m su un cerchio di 400 m di raggio, centro a est.
    const r = 400.0;
    final centro = spostato(ingresso, est: r);
    for (var s = 10.0; s <= 1000; s += 10) {
      final a = math.pi - s / r; // da ovest del centro, verso nord ed est
      punti.add(spostato(centro, est: r * math.cos(a), nord: r * math.sin(a)));
    }
    final fine = punti.last, prima = punti[punti.length - 2];
    final dir = rottaGradi(prima, fine) * math.pi / 180;
    for (var m = 10.0; m <= 500; m += 10) {
      punti.add(spostato(fine, est: m * math.sin(dir), nord: m * math.cos(dir)));
    }
  }
  return Linea(punti);
}

void main() {
  for (final curva in [false, true]) {
    test(
        'galleria di 1 km ${curva ? 'in curva' : 'dritta'} a 70 all\'ora: 50 s senza GPS, la freccia va avanti sulla strada',
        () {
      final linea = strada(curva: curva);
      const v = 70 / 3.6;
      // L'auto in galleria rallenta un poco: a 66 all'ora (la stima non lo sa).
      const vGalleria = 66 / 3.6;
      final t0 = DateTime.utc(2026, 1, 1, 12);
      final stima = StimaSenzaGps();
      final moto = MotoSullaStrada()..strada(linea);
      // Dove sta davvero l'auto al secondo [s].
      double vero(double s) {
        if (s <= 500 / v) return v * s;
        final dentro = s - 500 / v;
        if (dentro <= 50) return 500 + vGalleria * dentro;
        return 500 + vGalleria * 50 + v * (dentro - 50);
      }

      final entra = 500 / v;
      DateTime? ultimaBuona;
      double? metriBuoni;
      var mostrata = 0.0, prima = 0.0, fermaDa = 0.0, ferma = 0.0, peggioreLato = 0.0;
      var maiIndietro = true;
      const passo = Duration(milliseconds: 33);
      var dopoUscita = <double>[];
      for (var f = 0; f * 0.033 < entra + 70; f++) {
        final s = f * 0.033;
        final ora = t0.add(passo * f);
        final senzaGps = s > entra && s < entra + 50;
        // Una lettura al secondo, fuori dalla galleria.
        if (!senzaGps && (ultimaBuona == null || ora.difference(ultimaBuona) >= const Duration(seconds: 1))) {
          ultimaBuona = ora;
          metriBuoni = vero(s);
          stima.lettura(metri: metriBuoni, alle: ora, velocitaMs: s > entra ? v : v);
        }
        // Come la guida: la lettura portata ad adesso, o la stima.
        final meta = stima.stima(ora)
            ? stima.metri(ora, lunghezzaM: linea.lunghezzaM)!
            : metriBuoni! + v * ora.difference(ultimaBuona!).inMilliseconds / 1000;
        moto.posizione(meta, velocitaMs: v, alle: Duration(microseconds: passo.inMicroseconds * f));
        final q = moto.fotogramma(Duration(microseconds: passo.inMicroseconds * f))!;
        mostrata = moto.mostrataM!;
        if (f > 0 && mostrata < prima - 0.01) maiIndietro = false;
        // La freccia non si ferma mai in galleria.
        if (senzaGps) {
          if (mostrata - prima < 0.2 * v * 0.033) {
            fermaDa += 0.033;
            ferma = math.max(ferma, fermaDa);
          } else {
            fermaDa = 0;
          }
        }
        peggioreLato = math.max(peggioreLato, linea.proietta(q.punto).lontanoM);
        if (s > entra + 50) dopoUscita.add((mostrata - vero(s)).abs());
        prima = mostrata;
      }
      expect(maiIndietro, isTrue, reason: 'mai un passo indietro lungo la strada');
      expect(ferma, lessThan(0.1), reason: 'in galleria non si ferma');
      expect(peggioreLato, lessThan(0.5), reason: 'sempre sulla strada, anche in curva');
      // All'uscita (la stima è avanti di ~55 m) si riallinea piano, senza salti.
      expect(dopoUscita.first, greaterThan(20));
      expect(dopoUscita.sublist(dopoUscita.length - 30).reduce(math.max), lessThan(3), reason: 'riallineata');
    });
  }

  test('prima: la guida portava avanti al più 2 s e 60 m, e in galleria la freccia si fermava', () {
    final linea = strada(curva: false);
    const v = 70 / 3.6;
    final moto = MotoSullaStrada()..strada(linea);
    const passo = Duration(milliseconds: 33);
    // L'ultima lettura all'ingresso (500 m), poi niente per 50 s.
    var prima = 0.0, ferma = 0.0;
    double? metaPrima;
    for (var f = 0; f * 0.033 < 50; f++) {
      final eta = math.min(2.0, f * 0.033);
      final meta = 500.0 + math.min(60.0, v * (eta + 0.9));
      final alle = Duration(microseconds: passo.inMicroseconds * f);
      // Come la mappa (`mappa_viaggio.dart`): una stima che non va avanti è un punto fermo.
      final fermaLei = metaPrima != null && meta - metaPrima < 0.5 * v * 0.033;
      metaPrima = meta;
      moto.posizione(meta, velocitaMs: fermaLei ? 0 : v, alle: alle);
      moto.fotogramma(alle);
      if (moto.mostrataM! - prima < 0.01) ferma += 0.033;
      prima = moto.mostrataM!;
    }
    expect(ferma, greaterThan(40), reason: 'ferma all\'ingresso per quasi tutta la galleria');
  });

  test('col tachimetro la stima rallenta con l\'auto', () {
    final t0 = DateTime.utc(2026, 1, 1, 12);
    final s = StimaSenzaGps()..lettura(metri: 1000, alle: t0, velocitaMs: 20);
    // Dopo 10 s il tachimetro dice 10 m/s.
    s.tachimetro(10, t0.add(const Duration(seconds: 10)));
    expect(s.metri(t0.add(const Duration(seconds: 20))), closeTo(1000 + 200 + 100, 0.01));
  });

  test('si stima da 2 s a 3 min, poi «GPS assente» e ci si ferma', () {
    final t0 = DateTime.utc(2026, 1, 1, 12);
    final s = StimaSenzaGps()..lettura(metri: 0, alle: t0, velocitaMs: 20);
    expect(s.stima(t0.add(const Duration(seconds: 1))), isFalse);
    expect(s.stima(t0.add(const Duration(seconds: 3))), isTrue);
    expect(s.persa(t0.add(const Duration(seconds: 179))), isFalse);
    expect(s.stima(t0.add(const Duration(minutes: 4))), isFalse);
    expect(s.persa(t0.add(const Duration(minutes: 4))), isTrue);
    expect(s.metri(t0.add(const Duration(minutes: 10))), closeTo(20 * 180, 0.01), reason: 'ferma dopo tre minuti');
    // Fermi in coda in galleria non si stima niente.
    final f = StimaSenzaGps()..lettura(metri: 50, alle: t0, velocitaMs: 0.3);
    expect(f.stima(t0.add(const Duration(seconds: 5))), isFalse);
    expect(f.metri(t0.add(const Duration(seconds: 5))), 50);
    expect(s.buona(null), isTrue);
    expect(s.buona(12), isTrue);
    expect(s.buona(300), isFalse);
  });
}
