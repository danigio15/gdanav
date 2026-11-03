import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Una strada dritta verso nord: un punto ogni ~1 km, a [kmh].
PercorsoCalcolato dritta(int km, {double kmh = 120}) {
  final punti = [for (var i = 0; i <= km; i++) Punto(42 + i * 0.009, 12)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: kmh),
    ],
    manovre: const [],
  );
}

void main() {
  // «Mostra lateralmente la striscia del traffico con i minuti di ritardo e
  // man mano a che punto è il traffico.»
  group('la striscia del traffico', () {
    test('senza code non c\'è niente da mostrare', () {
      expect(strisciaTraffico(dritta(40), percorsiM: 0), isNull);
      expect(strisciaTraffico(dritta(40).conTraffico(const []), percorsiM: 0), isNull);
    });

    test('una coda al suo posto, coi minuti che fa perdere davvero', () {
      final p = dritta(40).conTraffico([const Coda(daM: 5000, aM: 12000, ritardo: Duration(minutes: 7))]);
      final s = strisciaTraffico(p, percorsiM: 0)!;
      final lunghezza = p.lunghezzaM;
      expect(s.scalaM, closeTo(lunghezza, 1));
      expect(s.tagliata, isFalse);
      expect(s.code, hasLength(1));
      final c = s.code.single;
      expect(c.da, closeTo(5000 / lunghezza, 0.001));
      expect(c.a, closeTo(12000 / lunghezza, 0.001));
      expect(c.minuti, 7);
      expect(c.distanzaM, 5000);
      expect(c.dentro, isFalse);
      expect(c.livello, 2);
    });

    test('andando avanti la coda scende verso l\'auto, e dentro conta solo quel che resta', () {
      final p = dritta(40).conTraffico([const Coda(daM: 5000, aM: 12000, ritardo: Duration(minutes: 7))]);
      final prima = strisciaTraffico(p, percorsiM: 0)!.code.single;
      final dopo = strisciaTraffico(p, percorsiM: 3000)!.code.single;
      expect(dopo.distanzaM, 2000);
      expect(dopo.da, lessThan(prima.da));
      // A metà coda: metà dei minuti, e ci si è dentro.
      final dentro = strisciaTraffico(p, percorsiM: 8500)!.code.single;
      expect(dentro.dentro, isTrue);
      expect(dentro.da, 0);
      expect(dentro.minuti, closeTo(4, 1));
      // Passata: la striscia se ne va.
      expect(strisciaTraffico(p, percorsiM: 12500), isNull);
    });

    test('due code, dal basso verso l\'alto, coi loro livelli', () {
      final p = dritta(40).conTraffico([
        const Coda(daM: 20000, aM: 26000, ritardo: Duration(minutes: 10)),
        const Coda(daM: 4000, aM: 9000, ritardo: Duration(minutes: 8), livello: 3),
      ]);
      final s = strisciaTraffico(p, percorsiM: 0)!;
      expect(s.code.map((c) => c.livello), [3, 2]);
      expect(s.code.map((c) => c.minuti), [8, 10]);
      expect(s.minuti, 18);
      // Dopo la prima resta solo la seconda.
      final dopo = strisciaTraffico(p, percorsiM: 10000)!;
      expect(dopo.code.single.minuti, 10);
      expect(dopo.code.single.distanzaM, 10000);
    });

    test('viaggio lungo: la striscia guarda i prossimi 100 km, e le code più in là non si disegnano', () {
      final p = dritta(300).conTraffico([
        const Coda(daM: 50000, aM: 60000, ritardo: Duration(minutes: 6)),
        const Coda(daM: 200000, aM: 210000, ritardo: Duration(minutes: 9)),
      ]);
      final s = strisciaTraffico(p, percorsiM: 0)!;
      expect(s.scalaM, finestraPredefinitaM);
      expect(s.tagliata, isTrue);
      expect(s.code, hasLength(1));
      expect(s.code.single.a, closeTo(0.6, 0.001));
      // Più avanti entra anche la seconda.
      expect(strisciaTraffico(p, percorsiM: 120000)!.code.single.minuti, 9);
    });

    test('una coda a cavallo della cima si taglia alla cima', () {
      final p = dritta(300).conTraffico([const Coda(daM: 95000, aM: 105000, ritardo: Duration(minutes: 5))]);
      final c = strisciaTraffico(p, percorsiM: 0)!.code.single;
      expect(c.da, closeTo(0.95, 0.001));
      expect(c.a, 1);
      expect(c.minuti, 5);
    });

    test('coi tempi di TomTom (niente versione senza traffico) valgono i minuti dichiarati', () {
      final d = dritta(40);
      final p = PercorsoCalcolato(
        punti: d.punti,
        tratti: d.tratti,
        manovre: const [],
        code: const [Coda(daM: 10000, aM: 20000, ritardo: Duration(minutes: 12), livello: 3)],
      );
      expect(p.senzaTraffico, isNull);
      expect(strisciaTraffico(p, percorsiM: 0)!.code.single.minuti, 12);
      expect(strisciaTraffico(p, percorsiM: 15000)!.code.single.minuti, 6);
    });
  });
}
