import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/componenti/icona_manovra.dart';
import 'package:gdanav/componenti/vista_svincolo.dart';
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

  test('lo svincolo in 3D: la mappa vera inclinata, la freccia sulla strada e sul ramo giusto', () {
    final scena = scenaSvincolo(viaggio, manovraSvincolo, scuro: false);
    final q = scena.inquadratura;
    // Si guarda verso est (con un po' di sud-est), dall'alto e inclinati.
    expect(q.rotta, inInclusiveRange(90, 125));
    expect(q.inclinazione, greaterThan(50));
    // Centrati poco oltre lo svincolo: si vedono l'arrivo e il ramo giusto.
    expect(q.centro.lon, closeTo(9.015, 0.003));
    final sorgenti = scena.stile['sources']! as Map;
    final freccia = ((sorgenti['svincolo-freccia'] as Map)['data'] as Map)['geometry'] as Map;
    final coordinate = (freccia['coordinates'] as List).cast<List>();
    // Parte prima dello svincolo e finisce sul ramo che scende.
    expect(coordinate.first[0] as double, lessThan(9.015));
    expect(coordinate.last[1] as double, lessThan(45.0));
    final strati = (scena.stile['layers']! as List).cast<Map>();
    expect(strati.map((l) => l['id']), containsAll(['svincolo-freccia', 'svincolo-punta']));
    expect(strati.firstWhere((l) => l['id'] == 'edifici-3d')['layout'], containsPair('visibility', 'visible'));
    expect(strati.any((l) => l['id'] == 'io'), isFalse);
    // Il percorso c'è, anche senza viaggio sulla mappa principale.
    expect((((sorgenti['gdanav-percorso'] as Map)['data'] as Map)['features'] as List), hasLength(1));
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
    expect(find.byKey(const Key('corsie')), findsOneWidget);
    expect(find.text('450 m'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('chiudi-svincolo')));
    expect(chiuso, isTrue);
    final punta = await tester.runAsync(puntaPng);
    expect(punta!.sublist(1, 4), 'PNG'.codeUnits);
  });
}
