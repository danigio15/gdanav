import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/* Geometrie inventate, in metri attorno a un'origine qualunque: nessun posto
 * vero. x verso est, y verso nord. */

const metriPerGrado = 111195.08;
const origine = Punto(44, 11.5);

Punto a(double est, double nord) => Punto(
      origine.lat + nord / metriPerGrado,
      origine.lon + est / (metriPerGrado * math.cos(origine.lat * math.pi / 180)),
    );

(double, double) dove(Punto p) => (
      (p.lon - origine.lon) * metriPerGrado * math.cos(origine.lat * math.pi / 180),
      (p.lat - origine.lat) * metriPerGrado,
    );

/// Una linea dritta da [da] ad [a], un punto ogni [passo] metri.
List<Punto> dritta((double, double) da, (double, double) fin, {double passo = 50}) {
  final l = math.sqrt(math.pow(fin.$1 - da.$1, 2) + math.pow(fin.$2 - da.$2, 2));
  final n = math.max(1, (l / passo).round());
  return [for (var i = 0; i <= n; i++) a(da.$1 + (fin.$1 - da.$1) * i / n, da.$2 + (fin.$2 - da.$2) * i / n)];
}

/// Quanto la linea [punti] passa lontano da [q] (sui segmenti).
double passaA(List<Punto> punti, (double, double) q) {
  var d = double.infinity;
  for (var i = 1; i < punti.length; i++) {
    final (ax, ay) = dove(punti[i - 1]);
    final (bx, by) = dove(punti[i]);
    final dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
    final t = l2 == 0 ? 0.0 : (((q.$1 - ax) * dx + (q.$2 - ay) * dy) / l2).clamp(0.0, 1.0);
    d = math.min(d, math.sqrt(math.pow(ax + t * dx - q.$1, 2) + math.pow(ay + t * dy - q.$2, 2)));
  }
  return d;
}

void main() {
  test('una strada a otto metri: la linea da disegnare ci sta sopra, e i metri restano quelli del percorso', () {
    // Il percorso verso nord, otto metri a destra della strada.
    final percorso = dritta((8, 0), (8, 1000));
    final strada = TrattoStrada(dritta((0, -100), (0, 1100), passo: 30));
    final s = SullaMappa(percorso).allineata([strada], daM: 0, aM: 1000);
    expect(s.spostata, isTrue);
    for (var y = 100.0; y <= 900; y += 50) {
      final (x, yy) = dove(s.a(y));
      expect(x.abs(), lessThan(0.5), reason: 'a $y m la linea sta a $x m dalla strada');
      // «A tanti metri» è lo stesso posto: di fianco al punto del percorso.
      expect((yy - y).abs(), lessThan(0.5));
    }
    // Il percorso vero non cambia.
    expect(s.percorso, same(percorso));
  });

  test('il senso unico al contrario più vicino non ruba la linea: va sulla strada che va nel suo verso', () {
    final percorso = dritta((0, 0), (0, 800));
    // A tre metri a sinistra un senso unico verso sud; a sette a destra la strada verso nord.
    final contro = TrattoStrada(dritta((-3, 900), (-3, -100), passo: 40), senso: 1);
    final giusta = TrattoStrada(dritta((7, -100), (7, 900), passo: 40), senso: 1);
    final s = SullaMappa(percorso).allineata([contro, giusta], daM: 0, aM: 800);
    for (var y = 150.0; y <= 650; y += 50) {
      expect(dove(s.a(y)).$1, closeTo(7, 0.5));
    }
  });

  test('senza strade sotto, o troppo lontane, la linea resta il percorso', () {
    final percorso = dritta((0, 0), (0, 600));
    expect(SullaMappa(percorso).allineata(const [], daM: 0, aM: 600).spostata, isFalse);
    final lontana = TrattoStrada(dritta((25, -100), (25, 700)));
    expect(SullaMappa(percorso).allineata([lontana], daM: 0, aM: 600).spostata, isFalse);
  });

  test('a uno spigolo la linea gira con la strada, e non torna mai indietro', () {
    // Il percorso: nord per 400 m, poi est. La strada: sei metri più in là
    // (a destra) su tutti e due i tratti: l'angolo della strada è a (6, 394).
    final percorso = [...dritta((0, 0), (0, 400), passo: 20), ...dritta((0, 400), (400, 400), passo: 20).skip(1)];
    final strada =
        TrattoStrada([...dritta((6, -100), (6, 394), passo: 25), ...dritta((6, 394), (500, 394), passo: 25).skip(1)]);
    final s = SullaMappa(percorso).allineata([strada], daM: 0, aM: 800);
    // Lontano dallo spigolo, sulla strada.
    expect(passaA(s.punti, (6, 200)), lessThan(0.6));
    expect(passaA(s.punti, (200, 394)), lessThan(0.6));
    // Vicino allo spigolo, al più un paio di metri dentro l'angolo.
    expect(passaA(s.punti, (6, 394)), lessThan(2.5));
    // Mai indietro rispetto al percorso.
    final l = Linea(percorso);
    for (var i = 1; i < s.punti.length; i++) {
      final m = (s.metri[i - 1] + s.metri[i]) / 2;
      final p0 = dove(l.punti.first);
      final (ax, ay) = dove(s.punti[i - 1]);
      final (bx, by) = dove(s.punti[i]);
      final verso = m < 400 ? (0.0, 1.0) : (1.0, 0.0);
      expect((bx - ax) * verso.$1 + (by - ay) * verso.$2, greaterThanOrEqualTo(-1e-6), reason: 'pezzo $i (a $m m) $p0');
    }
  });

  test('due pezzi uno dopo l\'altro si raccordano: niente scalino dove si toccano', () {
    final percorso = dritta((8, 0), (8, 3000));
    final strada = TrattoStrada(dritta((0, -100), (0, 3100), passo: 40));
    var s = SullaMappa(percorso).allineata([strada], daM: 0, aM: 1500);
    // Prima del secondo pezzo, dopo il primo, la linea torna verso il percorso.
    expect(dove(s.a(2500)).$1, closeTo(8, 0.01));
    s = s.allineata([strada], daM: 1400, aM: 3000);
    for (var y = 100.0; y <= 2900; y += 25) {
      expect(dove(s.a(y)).$1.abs(), lessThan(0.5), reason: 'a $y m');
    }
    // I metri vanno sempre in salita.
    for (var i = 1; i < s.metri.length; i++) {
      expect(s.metri[i], greaterThan(s.metri[i - 1]));
    }
  });

  test('una linea a metri dati: «a tanti metri» segue quei metri, non la sua lunghezza', () {
    final l = Linea.conMetri([a(0, 0), a(0, 10), a(10, 10)], [0, 100, 200]);
    expect(l.lunghezzaM, 200);
    expect(l.proietta(a(0, 5)).lungoM, closeTo(50, 0.01));
  });
}
