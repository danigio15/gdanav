import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/* Un viaggio finto: un'auto che parte, va, frena, si ferma, riparte, con le
 * curve; un telefono nel supporto girato come capita (che non sa dov'è
 * l'avanti), l'accelerometro rumoroso e storto; il GPS che dice la velocità
 * una volta al secondo, in ritardo e un po' sbagliata. */

/// L'accelerazione di marcia dell'auto a [t] secondi (m/s²).
double accelerazioneVera(double t) {
  final q = t % 60;
  if (q < 6) return 2.2; // parte
  if (q < 20) return 0; // va
  if (q < 24) return -3.3; // frena fino a fermarsi
  if (q < 30) return 0; // ferma
  if (q < 36) return 1.8;
  if (q < 45) return 0;
  if (q < 49) return -2.7;
  return 0;
}

class Viaggio {
  Viaggio({required this.rotazione, this.ritardoGps = 0.6, int seme = 7}) : _r = math.Random(seme);

  /// Dal riferimento dell'auto (avanti, sinistra, su) a quello del telefono.
  List<List<double>> rotazione;
  final double ritardoGps;
  final math.Random _r;
  final _t0 = DateTime.utc(2026, 1, 1, 8);

  final storiaV = <double>[0]; // velocità vera ogni 10 ms
  double v(double t) => storiaV[math.min(storiaV.length - 1, math.max(0, (t * 100).round()))];

  double _gauss() {
    final u1 = math.max(1e-9, _r.nextDouble()), u2 = _r.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  List<double> _ruota(List<double> a) => [
        for (final riga in rotazione) riga[0] * a[0] + riga[1] * a[1] + riga[2] * a[2],
      ];

  DateTime ora(double t) => _t0.add(Duration(microseconds: (t * 1e6).round()));

  /// Da [da] ad [a] secondi: accelerometro a 50 Hz, GPS a 1 Hz.
  void guida(AccelerazioneDiMarcia s, double da, double a, {void Function(double t)? ogni}) {
    for (var k = (da * 100).round(); k < (a * 100).round(); k++) {
      final t = k / 100;
      // La velocità vera.
      if (storiaV.length <= k + 1) storiaV.add(math.max(0.0, storiaV.last + accelerazioneVera(t) * 0.01));
      if (k % 2 == 0) {
        final lungo = v(t) > 0 || accelerazioneVera(t) > 0 ? accelerazioneVera(t) : 0.0;
        final lato = v(t) > 3 ? 1.6 * math.sin(t / 5) : 0.0;
        final su = 0.5 * math.sin(t * 17); // le buche
        final d = _ruota([lungo, lato, su]);
        s.campione(ora(t), d[0] + 0.12 + _gauss() * 0.5, d[1] - 0.07 + _gauss() * 0.5, d[2] + 0.05 + _gauss() * 0.5);
        final g = _ruota([0, 0, 9.81]);
        s.gravita(ora(t), g[0] + _gauss() * 0.05, g[1] + _gauss() * 0.05, g[2] + _gauss() * 0.05);
      }
      if (k % 100 == 0) {
        final vg = math.max(0.0, v(math.max(0, t - ritardoGps)) + _gauss() * 0.15);
        s.velocita(ora(t), vg, cruscotto: false);
      }
      ogni?.call(t);
    }
  }
}

List<List<double>> ruotaXYZ(double ax, double ay, double az) {
  final (cx, sx, cy, sy, cz, sz) = (
    math.cos(ax),
    math.sin(ax),
    math.cos(ay),
    math.sin(ay),
    math.cos(az),
    math.sin(az),
  );
  final rx = [
    [1.0, 0.0, 0.0],
    [0.0, cx, -sx],
    [0.0, sx, cx],
  ];
  final ry = [
    [cy, 0.0, sy],
    [0.0, 1.0, 0.0],
    [-sy, 0.0, cy],
  ];
  final rz = [
    [cz, -sz, 0.0],
    [sz, cz, 0.0],
    [0.0, 0.0, 1.0],
  ];
  List<List<double>> per(List<List<double>> a, List<List<double>> b) => [
        for (var i = 0; i < 3; i++)
          [for (var j = 0; j < 3; j++) a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j]],
      ];
  return per(rz, per(ry, rx));
}

void main() {
  test('col telefono storto nel supporto impara l\'avanti e sente frenate e partenze subito', () {
    final s = AccelerazioneDiMarcia();
    final viaggio = Viaggio(rotazione: ruotaXYZ(-1.1, 0.35, 2.4));
    viaggio.guida(s, 0, 120);
    expect(s.tarata, isTrue, reason: 'dopo due giri di frenate e partenze sa dov\'è l\'avanti');
    expect((s.ritardoGpsMisurato!.inMilliseconds - 600).abs(), lessThanOrEqualTo(200),
        reason: 'e quanto è in ritardo il GPS');
    var errori = 0.0;
    var n = 0;
    viaggio.guida(
      s,
      120,
      180,
      ogni: (t) {
        final a = s.adesso(viaggio.ora(t));
        if (a == null) return;
        // L'accelerometro è lisciato di un quarto di secondo: si confronta
        // con l'accelerazione vera di un attimo prima.
        final vero = viaggio.v(t) > 0 || accelerazioneVera(t) > 0 ? accelerazioneVera(t - 0.25) : 0.0;
        errori += (a - vero) * (a - vero);
        n++;
      },
    );
    expect(n, greaterThan(5000));
    expect(math.sqrt(errori / n), lessThan(0.9), reason: 'in media sbaglia meno di un m/s²');
  });

  test('frenando, la strada fino a fermarsi è quella vera, con un secondo di anticipo sul GPS', () {
    final s = AccelerazioneDiMarcia();
    final viaggio = Viaggio(rotazione: ruotaXYZ(0.4, -0.9, -2.1));
    viaggio.guida(s, 0, 199);
    expect(s.tarata, isTrue);
    // A 200 s (q = 20) si comincia a frenare: da 13,2 m/s a fermi in 4 s.
    viaggio.guida(s, 199, 206);
    final da = viaggio.ora(200);
    final v0 = viaggio.v(200);
    expect(v0, greaterThan(10));
    var vera = 0.0;
    for (var t = 200.0; t < 206; t += 0.01) {
      vera += viaggio.v(t) * 0.01;
    }
    final stimata = s.strada(da, viaggio.ora(206), v0)!;
    // Da sola, senza nessuna correzione del GPS per sei secondi: qualche metro.
    expect((stimata - vera).abs(), lessThan(3.5), reason: 'vera ${vera.toStringAsFixed(1)} m');
    // Senza l'accelerometro: alla velocità di prima, venti metri oltre.
    expect(v0 * 6 - vera, greaterThan(15));
  });

  test('trova il ritardo di questo telefono: un secondo', () {
    final s = AccelerazioneDiMarcia();
    final viaggio = Viaggio(rotazione: ruotaXYZ(0.2, 1.2, 0.7), ritardoGps: 1.0, seme: 3);
    viaggio.guida(s, 0, 120);
    expect(s.tarata, isTrue);
    // A un passo (200 ms) da quello vero.
    expect((s.ritardoGpsMisurato!.inMilliseconds - 1000).abs(), lessThanOrEqualTo(200));
  });

  test('se il telefono si sposta nel supporto, non dice niente finché non reimpara', () {
    final s = AccelerazioneDiMarcia();
    final viaggio = Viaggio(rotazione: ruotaXYZ(-1.1, 0.35, 2.4));
    viaggio.guida(s, 0, 120);
    expect(s.tarata, isTrue);
    viaggio.rotazione = ruotaXYZ(-0.6, 0.35, 2.4); // girato di quasi 30°
    viaggio.guida(s, 120, 125);
    expect(s.tarata, isFalse);
    expect(s.adesso(viaggio.ora(125)), isNull);
    viaggio.guida(s, 125, 260);
    expect(s.tarata, isTrue, reason: 'e poi reimpara');
  });

  test('fermi dall\'inizio, o senza GPS, non si inventa niente', () {
    final s = AccelerazioneDiMarcia();
    final t0 = DateTime.utc(2026, 1, 1);
    for (var k = 0; k < 3000; k++) {
      final t = t0.add(Duration(milliseconds: k * 20));
      s.campione(t, 0.05, -0.02, 0.01);
      if (k % 50 == 0) s.velocita(t, 0, cruscotto: false);
    }
    expect(s.tarata, isFalse);
    expect(s.adesso(t0.add(const Duration(seconds: 60))), isNull);
    expect(s.strada(t0, t0.add(const Duration(seconds: 1)), 5), isNull);
  });
}
