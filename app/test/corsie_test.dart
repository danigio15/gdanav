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

  testWidgets('allo svincolo il popup: il disegno, i metri che mancano, e si chiude', (tester) async {
    const m = Manovra(
      istruzione: 'Esci a destra',
      lunghezzaM: 800,
      secondi: 30,
      inizio: 42,
      tipo: 20,
      uscita: '12',
      verso: 'A1 · Roma',
    );
    var chiuso = false;
    expect(haSvincolo(m), isTrue);
    expect(haSvincolo(const Manovra(istruzione: 'Svolta', lunghezzaM: 1, secondi: 1, inizio: 0, tipo: 10)), isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PopupSvincolo(manovra: m, metri: 430, onChiudi: () => chiuso = true),
        ),
      ),
    );
    expect(find.byKey(const Key('popup-svincolo')), findsOneWidget);
    expect(find.text('450 m'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('chiudi-svincolo')));
    expect(chiuso, isTrue);
    // Per Android Auto la stessa vista in PNG.
    final png = await tester.runAsync(() => svincoloPng(m));
    expect(png!.sublist(1, 4), 'PNG'.codeUnits);
  });

  testWidgets('con la foto vera: la foto sotto, freccia e cartello sopra, e la citazione', (tester) async {
    const m = Manovra(
      istruzione: 'Esci a destra',
      lunghezzaM: 800,
      secondi: 30,
      inizio: 7,
      tipo: 20,
      verso: 'A1 · Roma',
      corsie: [
        Corsia([DirezioneCorsia.dritto]),
        Corsia([DirezioneCorsia.leggeraDestra], giusta: true),
      ],
    );
    // Una «foto» qualsiasi: lo svincolo disegnato, in PNG.
    final byte = (await tester.runAsync(() => svincoloPng(m)))!;
    final foto = FotoStrada(
      id: '1',
      url: 'https://foto.esempio/1.jpg',
      punto: const Punto(45, 9),
      direzione: 90,
      scattata: DateTime.utc(2024, 5),
      autore: 'mario',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PopupSvincolo(manovra: m, metri: 600, foto: (foto, byte), onChiudi: () {}),
        ),
      ),
    );
    expect(find.byKey(const Key('foto-svincolo')), findsOneWidget);
    expect(find.text('© mario, Mapillary · 2024 · CC BY-SA'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Per l'auto: la foto con sopra la vista, sempre in PNG.
    final png = await tester.runAsync(() => svincoloPng(m, foto: byte, citazione: foto.citazione));
    expect(png!.sublist(1, 4), 'PNG'.codeUnits);
  });
}
