import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/icona_manovra.dart';
import 'package:gdanav_app/componenti/scena_svincolo.dart';
import 'package:gdanav_app/componenti/vista_svincolo.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  testWidgets('allo svincolo: le corsie giuste accese, il cartello verde con uscita e direzione', (tester) async {
    const m = Manovra(
      istruzione: 'Mantieni la destra per A12',
      lunghezzaM: 800,
      secondi: 30,
      inizio: 0,
      tipo: 23,
      uscita: '12',
      verso: 'A12 · Arnhem',
      corsie: [
        Corsia([DirezioneCorsia.dritto]),
        Corsia(
          [DirezioneCorsia.dritto, DirezioneCorsia.leggeraDestra],
          giusta: true,
          consigliata: DirezioneCorsia.leggeraDestra,
        ),
        Corsia([DirezioneCorsia.leggeraDestra], giusta: true, consigliata: DirezioneCorsia.leggeraDestra),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CorsieSvincolo(corsie: m.corsie),
              const CartelloSvincolo(manovra: m),
            ],
          ),
        ),
      ),
    );
    expect(m.corsieUtili, isTrue);
    expect(iconaManovra(m.tipo), Icons.fork_right);
    // Due frecce «a destra» accese, una «dritto» su una corsia giusta ma spenta.
    final destra = tester.widgetList<Icon>(find.byIcon(Icons.turn_slight_right));
    expect(destra.map((i) => i.color), everyElement(Colors.white));
    final dritte = tester.widgetList<Icon>(find.byIcon(Icons.straight)).map((i) => i.color).toList();
    expect(dritte, [Colors.white30, Colors.white38]);
    expect(find.text('Uscita 12'), findsOneWidget);
    expect(find.text('A12 · Arnhem'), findsOneWidget);
    final cartello = tester.widget<Container>(find.byKey(const Key('cartello')));
    expect((cartello.decoration! as BoxDecoration).color, const Color(0xFF0B7A3E));
  });

  // Una strada verso est che a metà piega a destra (sud-est): lo svincolo.
  final punti = [
    for (var i = 0; i <= 30; i++) Punto(45.0, 9.0 + i * 0.0005),
    for (var i = 1; i <= 20; i++) Punto(45.0 - i * 0.0004, 9.015 + i * 0.0004),
  ];
  final manovraSvincolo = const Manovra(
    istruzione: 'Esci a destra',
    lunghezzaM: 800,
    secondi: 30,
    inizio: 30,
    tipo: 20,
    uscita: '12',
    verso: 'A1 · Roma',
    corsie: [
      Corsia([DirezioneCorsia.dritto]),
      Corsia([DirezioneCorsia.leggeraDestra], giusta: true),
    ],
  );
  final viaggio = Viaggio(
    percorso: PercorsoCalcolato(punti: punti, tratti: const [], manovre: [manovraSvincolo]),
    colonnine: const [],
    piano: null,
  );

  test('lo svincolo in 3D: la scena si disegna, anche senza corsie note e con l\'uscita a sinistra', () async {
    for (final m in [manovraSvincolo, const Manovra(istruzione: '', lunghezzaM: 1, secondi: 1, inizio: 0, tipo: 24)]) {
      final png = await scenaSvincoloPng(m, larghezza: 400, altezza: 240);
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
    }
  });

  /* «Non è che mi propone un tornante quando è una semplice deviazione»: il
   * ramo si disegnava sempre uguale, una curva che si chiudeva a sessantatre
   * gradi, per qualunque uscita. Adesso segue i gradi veri. */
  test('lo svincolo si disegna di quanto gira davvero', () async {
    /* I PNG si confrontano a mano: `expect` su due liste da mezzo megabyte
     * stampa mezzo megabyte quando fallisce, e non si legge. */
    bool uguali(List<int> a, List<int> b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    Future<List<int>> scena(double? gradi) =>
        scenaSvincoloPng(manovraSvincolo, larghezza: 300, altezza: 180, gradi: gradi);

    expect(
      uguali(await scena(-18), await scena(-85)),
      isFalse,
      reason: 'una deviazione di diciotto gradi e una rampa di ottantacinque non possono venire uguali',
    );
    /* Senza i gradi resta il disegno di prima: sessantatré, e dalla parte che
     * dice il tipo della manovra — qui 20, uscita a destra. */
    expect(uguali(await scena(null), await scena(ScenaSvincolo.senzaGradi)), isTrue);
    /* Il segno NON sceglie il lato: lo dice il tipo della manovra (qui 20,
     * uscita a destra), come all'icona e al cartello. Una strada che piega
     * dalla parte opposta fa solo staccare il ramo più dolcemente. */
    expect(uguali(await scena(40), await scena(-40)), isFalse);
    expect(uguali(await scena(-40), await scena(-ScenaSvincolo.controGradi)), isTrue);
    expect(uguali(await scena(-40), await scena(ScenaSvincolo.controGradi)), isTrue);
    // Oltre i limiti non si va: una rampa da centoquaranta gradi si disegna
    // come una da ottanta, che è già il massimo che entra nell'inquadratura.
    expect(uguali(await scena(140), await scena(ScenaSvincolo.massimoGradi)), isTrue);
  });

  /* Napoli, SS162dir verso l'Autostrada del Sole: «tieni la sinistra», le
   * due corsie di sinistra giuste, il cartello con la freccia a sinistra e
   * l'icona del bivio a sinistra — e la scena col ramo a destra, perché la
   * strada dopo il bivio piega a destra e i gradi battevano il tipo. Ora il
   * lato è uno solo per tutti: quello della manovra. */
  group('il lato dello svincolo è quello della manovra', () {
    /// Dove sta il blu delle corsie giuste, sotto l'orizzonte: la x media,
    /// da 0 (sinistra) a 1 (destra).
    Future<double> dovEIlBlu(Manovra m, double? gradi) async {
      const w = 480.0, h = 270.0;
      final registro = ui.PictureRecorder();
      ScenaSvincolo(m, gradi: gradi).paint(Canvas(registro), const Size(w, h));
      final img = await registro.endRecording().toImage(w.round(), h.round());
      final px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var somma = 0.0, quanti = 0;
      for (var y = (h * 0.45).round(); y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w.round() + x) * 4;
          final r = px.getUint8(o), g = px.getUint8(o + 1), b = px.getUint8(o + 2);
          if (b > r + 80 && b > g + 40) {
            somma += x;
            quanti++;
          }
        }
      }
      expect(quanti, greaterThan(200), reason: 'le corsie giuste devono essere blu');
      return somma / quanti / w;
    }

    const tieniSinistra = Manovra(
      istruzione: 'Mantieni la sinistra per SS162dir',
      lunghezzaM: 600,
      secondi: 25,
      inizio: 0,
      tipo: 24,
      strada: 'SS162dir',
      verso: 'SS162dir',
      corsie: [
        Corsia([DirezioneCorsia.leggeraSinistra], giusta: true, consigliata: DirezioneCorsia.leggeraSinistra),
        Corsia([DirezioneCorsia.leggeraSinistra], giusta: true, consigliata: DirezioneCorsia.leggeraSinistra),
        Corsia([DirezioneCorsia.leggeraDestra]),
      ],
    );
    const tieniDestra = Manovra(
      istruzione: 'Mantieni la destra per A1',
      lunghezzaM: 600,
      secondi: 25,
      inizio: 0,
      tipo: 23,
      verso: 'A1',
      corsie: [
        Corsia([DirezioneCorsia.leggeraSinistra]),
        Corsia([DirezioneCorsia.leggeraDestra], giusta: true, consigliata: DirezioneCorsia.leggeraDestra),
        Corsia([DirezioneCorsia.leggeraDestra], giusta: true, consigliata: DirezioneCorsia.leggeraDestra),
      ],
    );

    test(
      'tieni la sinistra in autostrada: ramo e corsie blu a sinistra, anche se poi la strada piega a destra',
      () async {
        expect(iconaManovra(tieniSinistra.tipo), Icons.fork_left);
        for (final gradi in [null, -35.0, 35.0, 70.0]) {
          expect(latoDellaManovra(tieniSinistra, gradi: gradi), -1);
          expect(await dovEIlBlu(tieniSinistra, gradi), lessThan(0.45), reason: 'gradi $gradi');
        }
      },
    );

    test('tieni la destra: ramo e corsie blu a destra, anche se poi la strada piega a sinistra', () async {
      expect(iconaManovra(tieniDestra.tipo), Icons.fork_right);
      for (final gradi in [null, 35.0, -35.0, -70.0]) {
        expect(latoDellaManovra(tieniDestra, gradi: gradi), 1);
        expect(await dovEIlBlu(tieniDestra, gradi), greaterThan(0.55), reason: 'gradi $gradi');
      }
    });
  });

  testWidgets('allo svincolo il popup: la mappa 3D, cartello, corsie, metri; e si chiude', (tester) async {
    var chiuso = false;
    expect(haSvincolo(manovraSvincolo), isTrue);
    expect(haSvincolo(const Manovra(istruzione: 'Svolta', lunghezzaM: 1, secondi: 1, inizio: 0, tipo: 10)), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PopupSvincolo(
            viaggio: viaggio,
            manovra: manovraSvincolo,
            metri: 430,
            onChiudi: () => chiuso = true,
            mappa: (_, _) => const ColoredBox(key: Key('mappa-svincolo'), color: Colors.grey),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('mappa-svincolo')), findsOneWidget);
    expect(find.text('Uscita 12'), findsOneWidget);
    expect(find.text('450 m'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('chiudi-svincolo')));
    expect(chiuso, isTrue);
  });
}
