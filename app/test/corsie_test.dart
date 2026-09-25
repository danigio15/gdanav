import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/componenti/icona_manovra.dart';
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
}
