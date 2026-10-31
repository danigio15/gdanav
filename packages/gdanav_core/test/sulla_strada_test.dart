import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Quando e quali autovelox avvisare: poco prima in città, prima in
/// autostrada; solo quelli sulla strada che si fa, davanti.
void main() {
  // Metri in gradi, vicino a 45° nord.
  const latM = 1 / 111195;
  const lonM = 1 / 78626;

  Segnalazione autovelox(Punto p, {int? limite, double? direzione, bool fissa = true}) => Segnalazione(
        id: '${p.lat},${p.lon}',
        tipo: TipoSegnalazione.autovelox,
        punto: p,
        creata: DateTime(2026),
        fissa: fissa,
        limiteKmh: limite,
        direzioneGradi: direzione,
      );

  // Una strada dritta verso nord, cinque chilometri, un punto ogni 100 m.
  const inizio = Punto(45, 9);
  final linea = Linea([for (var i = 0; i <= 50; i++) Punto(inizio.lat + i * 100 * latM, inizio.lon)]);
  Punto lungo(double m, {double accantoM = 0}) => Punto(inizio.lat + m * latM, inizio.lon + accantoM * lonM);

  group('quanto prima', () {
    test('in città, a 50 all\'ora: non a 900 m, ma a circa 200', () {
      final d = distanzaAvvisoM(50, limiteKmh: 50);
      expect(d, closeTo(208, 1));
      expect(d, lessThan(900));
      expect(distanzaAvvisoM(50), closeTo(208, 1), reason: 'anche senza sapere il limite');
      // Mai più di 300 m in città, mai meno di 150.
      expect(distanzaAvvisoM(65, limiteKmh: 50), lessThanOrEqualTo(300));
      expect(distanzaAvvisoM(20, limiteKmh: 30), 150);
      expect(distanzaAvvisoM(0), 150);
    });

    test('fuori città di più, in autostrada molto prima', () {
      expect(distanzaAvvisoM(90, limiteKmh: 90), closeTo(500, 1));
      expect(distanzaAvvisoM(60, limiteKmh: 90), closeTo(333, 1));
      expect(distanzaAvvisoM(130, limiteKmh: 130), closeTo(1083, 1));
      expect(distanzaAvvisoM(130, limiteKmh: 130), greaterThan(distanzaAvvisoM(90, limiteKmh: 90)));
      expect(distanzaAvvisoM(60, limiteKmh: 130), 600, reason: 'in coda in autostrada: il minimo');
      expect(distanzaAvvisoM(200), 1200, reason: 'mai più di così');
    });

    test('chi va forte in città lo sa un po\' prima, ma non a un chilometro', () {
      expect(stradaAvviso(80, limiteKmh: 50), StradaAvviso.fuori);
      expect(distanzaAvvisoM(80, limiteKmh: 50), closeTo(444, 1));
      expect(stradaAvviso(40, limiteKmh: 130), StradaAvviso.veloce);
    });
  });

  group('sul percorso', () {
    test('quello davanti, sulla strada: lungo il percorso', () {
      final s = autovelox(lungo(1200, accantoM: 8), limite: 50, direzione: 0);
      expect(sulPercorso(linea, 1000, s, finoM: 300), closeTo(200, 1));
      // Da 900 m, con l'avviso di città, ancora no.
      expect(sulPercorso(linea, 300, s, finoM: distanzaAvvisoM(50, limiteKmh: 50)), isNull);
      // In autostrada, da 900 m, sì.
      expect(sulPercorso(linea, 300, s, finoM: distanzaAvvisoM(130, limiteKmh: 130)), closeTo(900, 1));
    });

    test('quello già passato non si avvisa', () {
      final s = autovelox(lungo(900, accantoM: 5));
      final dietro = sulPercorso(linea, 1000, s, finoM: 300);
      expect(dietro == null || dietro <= 0, isTrue);
    });

    test('quello su una strada parallela, a 40–80 m, no', () {
      for (final accanto in [40.0, 60.0, 80.0, -50.0]) {
        final s = autovelox(lungo(1200, accantoM: accanto), limite: 50);
        expect(sulPercorso(linea, 1000, s, finoM: 300), isNull, reason: '$accanto m accanto');
      }
      // Una segnalazione, col GPS di chi l'ha messa: un po' più larga, ma
      // non fino alla strada accanto.
      expect(sulPercorso(linea, 1000, autovelox(lungo(1200, accantoM: 30), fissa: false), finoM: 300), isNotNull);
      expect(sulPercorso(linea, 1000, autovelox(lungo(1200, accantoM: 60), fissa: false), finoM: 300), isNull);
    });

    test('quello per l\'altra direzione, o di una strada che incrocia, no', () {
      expect(sulPercorso(linea, 1000, autovelox(lungo(1200, accantoM: 5), direzione: 180), finoM: 300), isNull);
      expect(sulPercorso(linea, 1000, autovelox(lungo(1200), direzione: 90), finoM: 300), isNull);
    });

    test('quello della strada di sotto, col limite di un\'altra strada, no', () {
      final s = autovelox(lungo(1200, accantoM: 10), limite: 50);
      expect(sulPercorso(linea, 1000, s, finoM: 1000, limiteSul: (_) => 130), isNull);
      expect(sulPercorso(linea, 1000, s, finoM: 1000, limiteSul: (_) => 90), isNotNull);
      expect(limitiCompatibili(50, 110), isFalse);
      expect(limitiCompatibili(80, 130), isTrue);
      expect(limitiCompatibili(null, 130), isTrue);
    });

    test('un percorso che più avanti ripassa accanto: conta solo il pezzo davanti', () {
      // Un anello: si va a nord 1 km, a est 60 m, e si torna a sud.
      final anello = Linea([
        for (var i = 0; i <= 10; i++) Punto(inizio.lat + i * 100 * latM, inizio.lon),
        for (var i = 10; i >= 0; i--) Punto(inizio.lat + i * 100 * latM, inizio.lon + 60 * lonM),
      ]);
      // Sulla strada del ritorno, per chi torna verso sud.
      final s = autovelox(lungo(400, accantoM: 60), direzione: 180);
      expect(sulPercorso(anello, 200, s, finoM: 300), isNull, reason: 'all\'andata è la strada accanto');
      final alRitorno = sulPercorso(anello, 1460, s, finoM: 300);
      expect(alRitorno, closeTo(200, 2));
    });
  });

  group('senza percorso', () {
    final qui = lungo(1000);

    test('quello davanti, nella striscia: sì', () {
      final s = autovelox(lungo(1200, accantoM: 6), limite: 50, direzione: 0);
      expect(davantiSenzaPercorso(qui, 0, s, finoM: 300), closeTo(200, 1));
    });

    test('in città non a 600 m', () {
      final s = autovelox(lungo(1600, accantoM: 3), limite: 50);
      expect(davantiSenzaPercorso(qui, 0, s, finoM: distanzaAvvisoM(50, limiteKmh: 50)), isNull);
    });

    test('dietro, o sulla strada parallela: no', () {
      expect(davantiSenzaPercorso(qui, 0, autovelox(lungo(800)), finoM: 300), isNull);
      for (final accanto in [25.0, 40.0, 80.0]) {
        expect(
          davantiSenzaPercorso(qui, 0, autovelox(lungo(1250, accantoM: accanto)), finoM: 600),
          isNull,
          reason: '$accanto m accanto',
        );
      }
      // Vicino la striscia è più stretta.
      expect(davantiSenzaPercorso(qui, 0, autovelox(lungo(1100, accantoM: 15)), finoM: 300), isNull);
      expect(davantiSenzaPercorso(qui, 0, autovelox(lungo(1100, accantoM: 9)), finoM: 300), isNotNull);
    });

    test('per l\'altra direzione, o col limite di un\'altra strada: no', () {
      expect(davantiSenzaPercorso(qui, 0, autovelox(lungo(1200), direzione: 180), finoM: 300), isNull);
      expect(
        davantiSenzaPercorso(qui, 0, autovelox(lungo(1200), limite: 50), finoM: 600, limiteStradaKmh: 110),
        isNull,
      );
    });
  });
}
