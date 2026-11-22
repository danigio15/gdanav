import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/riquadro_manovra.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart' show Lettura;
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Il riquadro della manovra sul telefono: una riga sola lontano dalla
/// svolta, grande vicino, senza sfarfallare in mezzo e senza uscire dallo
/// schermo a nessuna misura.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const destra = Manovra(
    istruzione: 'Gira a destra in Via delle Prove',
    lunghezzaM: 900,
    secondi: 60,
    inizio: 0,
    tipo: 10,
    strada: 'Via delle Prove',
  );
  const lunga = Manovra(
    istruzione: 'Gira a destra',
    lunghezzaM: 900,
    secondi: 60,
    inizio: 0,
    tipo: 10,
    strada: 'Via del Nome Lunghissimo che Non Finisce Mai Neanche a Volerlo, Traversa Seconda',
  );
  const svincolo = Manovra(
    istruzione: "Prendi l'uscita a destra",
    lunghezzaM: 900,
    secondi: 60,
    inizio: 0,
    tipo: 20,
    strada: 'Raccordo del Nome Lunghissimo che Non Finisce Mai',
    uscita: '12',
    verso: 'Centro · Zona Industriale Nord · Stazione delle Prove',
  );
  const poi = Manovra(
    istruzione: 'Gira a sinistra',
    lunghezzaM: 300,
    secondi: 20,
    inizio: 1,
    tipo: 15,
    strada: 'Viale Dopo del Nome Anche Lui Lunghissimo',
  );

  tearDown(() => dimensioneIndicazioni.value = DimensioneIndicazioni.automatica);

  group('riquadroCompatto: le soglie e l\'isteresi', () {
    test('lontano piccolo, vicino grande', () {
      for (final prima in [false, true]) {
        expect(riquadroCompatto(metri: 2000, prima: prima), isTrue);
        expect(riquadroCompatto(metri: 501, prima: prima), isTrue);
        expect(riquadroCompatto(metri: 299, prima: prima), isFalse);
        expect(riquadroCompatto(metri: 0, prima: prima), isFalse);
      }
    });

    test('fra 300 e 500 m resta com\'era', () {
      for (final metri in [300.0, 400.0, 500.0]) {
        expect(riquadroCompatto(metri: metri, prima: true), isTrue, reason: '$metri');
        expect(riquadroCompatto(metri: metri, prima: false), isFalse, reason: '$metri');
      }
    });

    test('avvicinandosi col GPS che balla non sfarfalla', () {
      var compatto = false;
      final cambi = <double>[];
      for (final metri in <double>[
        1500,
        900,
        520,
        480,
        510,
        470,
        495,
        380,
        420,
        310,
        290,
        320,
        305,
        280,
        600,
        450,
        520,
      ]) {
        final adesso = riquadroCompatto(metri: metri, prima: compatto);
        if (adesso != compatto) cambi.add(metri);
        compatto = adesso;
      }
      // Piccolo subito, grande sotto i 300 e nient'altro fino alla manovra
      // dopo (600 m): lì di nuovo piccolo.
      expect(cambi, [1500, 290, 600]);
    });

    test('con due manovre ravvicinate, o con «Normale», sempre grande', () {
      expect(riquadroCompatto(metri: 3000, prima: true, poiVicino: true), isFalse);
      expect(riquadroCompatto(metri: 3000, prima: true, dimensione: DimensioneIndicazioni.normale), isFalse);
    });
  });

  Widget prova({
    required Manovra manovra,
    required double metri,
    Manovra? dopo,
    bool scuro = false,
    bool ricalcolando = false,
    DimensioneIndicazioni dimensione = DimensioneIndicazioni.automatica,
  }) => MaterialApp(
    theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
    home: Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: RiquadroManovra(
            manovra: manovra,
            metri: metri,
            dopo: dopo,
            ricalcolando: ricalcolando,
            dimensione: dimensione,
          ),
        ),
      ),
    ),
  );

  testWidgets('lontano la riga sola, vicino il riquadro grande, e in mezzo resta com\'era', (tester) async {
    Future<void> a(double metri) async {
      await tester.pumpWidget(prova(manovra: destra, metri: metri, dopo: poi));
      await tester.pumpAndSettle();
    }

    await a(1500);
    expect(find.byKey(const Key('riquadro-compatto')), findsOneWidget);
    expect(find.text('1,5 km'), findsOneWidget);
    expect(find.text('Via delle Prove'), findsOneWidget);
    // Nella riga sola niente «Poi».
    expect(find.byKey(const Key('poi')), findsNothing);
    final piccolo = tester.getSize(find.byKey(const Key('riquadro-manovra'))).height;
    await a(400);
    expect(find.byKey(const Key('riquadro-compatto')), findsOneWidget);
    await a(250);
    expect(find.byKey(const Key('riquadro-grande')), findsOneWidget);
    expect(find.byKey(const Key('poi')), findsOneWidget);
    final grande = tester.getSize(find.byKey(const Key('riquadro-manovra'))).height;
    expect(piccolo, lessThan(grande * 0.7), reason: 'la riga sola ruba meno mappa: $piccolo contro $grande');
    await a(450);
    expect(find.byKey(const Key('riquadro-grande')), findsOneWidget);
    await a(650);
    expect(find.byKey(const Key('riquadro-compatto')), findsOneWidget);
  });

  testWidgets('il passaggio è animato, e immediato con «riduci animazioni»', (tester) async {
    await tester.pumpWidget(prova(manovra: destra, metri: 1500));
    await tester.pumpAndSettle();
    await tester.pumpWidget(prova(manovra: destra, metri: 200));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: prova(manovra: destra, metri: 1500),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byKey(const Key('riquadro-compatto')), findsOneWidget);
  });

  testWidgets('con il «poi» vicino resta grande anche lontano; con «Normale» sempre grande', (tester) async {
    const ravvicinata = Manovra(
      istruzione: 'Gira a destra',
      lunghezzaM: 80,
      secondi: 6,
      inizio: 0,
      tipo: 10,
      strada: 'Via delle Prove',
    );
    await tester.pumpWidget(prova(manovra: ravvicinata, metri: 1500, dopo: poi));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('riquadro-grande')), findsOneWidget);
    expect(find.byKey(const Key('poi')), findsOneWidget);

    await tester.pumpWidget(prova(manovra: destra, metri: 5000, dimensione: DimensioneIndicazioni.normale));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('riquadro-grande')), findsOneWidget);
  });

  testWidgets('ricalcolando la misura resta quella di prima', (tester) async {
    await tester.pumpWidget(prova(manovra: destra, metri: 200));
    await tester.pumpAndSettle();
    await tester.pumpWidget(prova(manovra: destra, metri: 3000, ricalcolando: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('riquadro-grande')), findsOneWidget);
    expect(find.text('Ricalcolo…'), findsOneWidget);
  });

  // Larghezza × altezza in punti.
  const schermi = <String, Size>{
    'iPhone piccolo (320×568)': Size(320, 568),
    'iPhone SE (375×667)': Size(375, 667),
    'telefono grande (430×932)': Size(430, 932),
    'di traverso (844×390)': Size(844, 390),
    'tablet (820×1180)': Size(820, 1180),
  };

  for (final MapEntry(key: nome, value: punti) in schermi.entries) {
    for (final scala in [1.0, 1.3]) {
      testWidgets('$nome, testo ×$scala: piccolo e grande senza overflow, i nomi lunghi coi puntini', (tester) async {
        tester.view
          ..physicalSize = punti * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scala;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (final m in [destra, lunga, svincolo]) {
          for (final metri in [12000.0, 150.0]) {
            for (final scuro in [false, true]) {
              await tester.pumpWidget(prova(manovra: m, metri: metri, dopo: poi, scuro: scuro));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: '${m.strada} a $metri m');
              final r = tester.getRect(find.byKey(const Key('riquadro-manovra')));
              expect(r.left, greaterThanOrEqualTo(0));
              expect(r.right, lessThanOrEqualTo(punti.width));
              expect(find.byKey(Key(metri > compattoSopraM ? 'riquadro-compatto' : 'riquadro-grande')), findsOneWidget);
            }
          }
        }
        // Il nome lungo nella riga sola: una riga, coi puntini.
        await tester.pumpWidget(prova(manovra: lunga, metri: 12000));
        await tester.pumpAndSettle();
        final via = find.text(lunga.strada);
        final testo = tester.widget<Text>(via);
        expect((testo.maxLines, testo.overflow), (1, TextOverflow.ellipsis));
        final disegno = tester.renderObject<RenderParagraph>(find.descendant(of: via, matching: find.byType(RichText)));
        expect(disegno.didExceedMaxLines, isTrue);
        // E la distanza intera, mai tagliata.
        expect(tester.renderObject<RenderParagraph>(find.text('12 km')).didExceedMaxLines, isFalse);
      });
    }
  }

  Future<(Ambiente, List<Punto>)> inGuida(WidgetTester tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final punti = [for (var i = 0; i <= 40; i++) Punto(42 + i * 0.0009, 12)];
    final linea = Linea(punti);
    final percorso = PercorsoCalcolato(
      punti: punti,
      tratti: [
        for (var i = 1; i < punti.length; i++)
          Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 50),
      ],
      manovre: [
        Manovra(istruzione: 'Parti', lunghezzaM: linea.cumulate[25], secondi: 100, inizio: 0, tipo: 1),
        Manovra(
          istruzione: 'Gira a destra in Via delle Prove',
          lunghezzaM: linea.lunghezzaM - linea.cumulate[25],
          secondi: 60,
          inizio: 25,
          tipo: 10,
          strada: 'Via delle Prove',
        ),
        Manovra(istruzione: 'Sei arrivato', lunghezzaM: 0, secondi: 0, inizio: punti.length - 1, tipo: 4),
      ],
      limiti: [for (var i = 1; i < punti.length; i++) 50],
    );
    final a = await ambiente(
      tester,
      km: 4,
      costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (_) async => percorso,
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      ),
    );
    await tester.pumpWidget(a.app());
    a.posizione.avvia();
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.036, 12))));
    await tester.pumpAndSettle();
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    return (a, punti);
  }

  Future<void> vaiA(WidgetTester tester, Ambiente a, Punto p) async {
    a.posizioni.add(p);
    a.gps.add(Lettura(p, velocitaMs: 13.9, rotta: 0));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
  }

  testWidgets('in guida: piccolo a 1,5 km dalla svolta, grande a 200 m', (tester) async {
    final (a, punti) = await inGuida(tester);
    await vaiA(tester, a, punti[10]);
    expect(find.byKey(const Key('riquadro-compatto')), findsOneWidget);
    await vaiA(tester, a, punti[23]);
    expect(find.byKey(const Key('riquadro-grande')), findsOneWidget);
    await tester.runAsync(a.guida.ferma);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('di traverso (844×390): il riquadro di lato nel pannello, lontano dall\'auto e dai tasti', (
    tester,
  ) async {
    final (a, punti) = await inGuida(tester);
    const schermo = Size(844, 390);
    tester.view
      ..physicalSize = schermo * 3
      ..devicePixelRatio = 3;
    const bordo = FakeViewPadding(left: 47 * 3, right: 47 * 3, bottom: 21 * 3);
    tester.view
      ..padding = bordo
      ..viewPadding = bordo;
    for (final (i, quale) in [(10, 'riquadro-compatto'), (23, 'riquadro-grande')]) {
      await vaiA(tester, a, punti[i]);
      expect(tester.takeException(), isNull);
      expect(find.byKey(Key(quale)), findsOneWidget);
      final riquadro = tester.getRect(find.byKey(const Key('riquadro-manovra')));
      final pannello = tester.getRect(find.byKey(const Key('pannello-traverso')));
      expect(riquadro.right, lessThanOrEqualTo(pannello.right + 0.5), reason: quale);
      // L'auto la mappa la mette nel mezzo della parte libera a destra.
      final libera = Rect.fromLTRB(pannello.right, 0, schermo.width, schermo.height);
      expect(riquadro.contains(libera.center), isFalse, reason: quale);
      expect(riquadro.right, lessThan(libera.center.dx - 40), reason: quale);
      for (final tasto in [
        find.byKey(const Key('2d-3d')),
        find.byKey(const Key('ricalcola')),
        find.byKey(const Key('audio')),
        find.text('Fine'),
      ]) {
        expect(riquadro.overlaps(tester.getRect(tasto)), isFalse, reason: '$quale sopra $tasto');
      }
    }
    await tester.runAsync(a.guida.ferma);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('«Dimensione indicazioni» nel menu: Normale si sceglie e si ricorda', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('menu-indicazioni')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.descendant(of: find.byKey(const Key('menu-indicazioni')), matching: find.text('Automatica')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('menu-indicazioni')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('indicazioni-normale')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    expect(dimensioneIndicazioni.value, DimensioneIndicazioni.normale);
    expect(await tester.runAsync(() => Archivio().dimensioneIndicazioni()), DimensioneIndicazioni.normale);
    // E tornando ad Automatica la chiave sparisce: il valore di base.
    await tester.runAsync(() => Archivio().salvaDimensioneIndicazioni(DimensioneIndicazioni.automatica));
    expect(await tester.runAsync(() => Archivio().dimensioneIndicazioni()), DimensioneIndicazioni.automatica);
  });
}
