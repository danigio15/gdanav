import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> aspetta(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
  }

  Future<void> apriMenu(WidgetTester tester, String voce) async {
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(voce));
    await aspetta(tester);
  }

  testWidgets("si sceglie l'auto, e si ricorda", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();

    await apriMenu(tester, 'La tua auto');
    await tester.enterText(find.byType(TextField), 'model 3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Model 3 Long Range'));
    await aspetta(tester);

    expect(a.auto.veicolo.id, 'tesla-model-3-lr');
    // La scheda dell'auto nel pannello mostra quella scelta.
    expect(find.text('Tesla Model 3 Long Range'), findsOneWidget);
    final ricordata = await tester.runAsync(() => Archivio().veicolo());
    expect(ricordata!.id, 'tesla-model-3-lr');
  });

  testWidgets('le preferenze di ricarica si salvano', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    await apriMenu(tester, 'Ricarica');
    expect(find.text('Evita le colonnine piene'), findsOneWidget);
    await tester.tap(find.text('≥ 150'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evita le colonnine piene'));
    await aspetta(tester);
    final p = await tester.runAsync(() => Archivio().preferenze());
    expect(p!.potenzaMinimaKw, 150);
    expect(p.evitaOccupate, isFalse);

    // La potenza è quella delle soste: la scelta più bassa è 22 kW, non «Tutte».
    expect(find.text('Soste del viaggio (kW)'), findsOneWidget);
    expect(find.text('Tutte'), findsNothing);
    await tester.tap(find.text('≥ 22'));
    await aspetta(tester);
    final bassa = await tester.runAsync(() => Archivio().preferenze());
    expect(bassa!.potenzaMinimaKw, PreferenzeRicarica.minimaSoste);
  });

  testWidgets('le soste dicono se la colonnina è libera o piena, e si evita la piena', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(46.5, 12))));
    await tester.pumpAndSettle();

    final pronto = a.viaggio.stato as ViaggioPronto;
    final soste = pronto.viaggio.piano!.soste;
    expect(soste, isNotEmpty);
    // Le aree ai km multipli di 120 sono piene: il piano le evita.
    expect(soste.every((s) => !s.colonnina.disponibilita.piena), isTrue);
    await scorriScheda(tester);
    expect(find.text('2 libere su 4'), findsWidgets);
  });

  testWidgets('«Fermati qui» mette la sosta, «Togli» la leva', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 150);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Vicino', posizione: Punto(43.3, 12))));
    await tester.pumpAndSettle();
    expect((a.viaggio.stato as ViaggioPronto).viaggio.piano!.soste, isEmpty);

    await scorriScheda(tester);
    await tester.tap(find.text('Area 60'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fermati qui'));
    await aspetta(tester);

    final piano = (a.viaggio.stato as ViaggioPronto).viaggio.piano!;
    expect(piano.soste.single.colonnina.id, 'c60');
    expect(piano.soste.single.colonnina.obbligata, isTrue);
    await scorriScheda(tester);

    await tester.tap(find.text('Area 60').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Togli questa sosta'));
    await aspetta(tester);
    expect((a.viaggio.stato as ViaggioPronto).viaggio.piano!.soste, isEmpty);
  });

  testWidgets('la mappa parte in 3D; il bottone la mette in 2D, e la scelta si ricorda', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    await tester.pumpAndSettle();
    // Il bottone dice dove si va: in 3D propone il 2D.
    expect(find.text('2D'), findsOneWidget);
    await tester.tap(find.text('2D'));
    await tester.pumpAndSettle();
    expect(find.text('3D'), findsOneWidget);
    expect(await tester.runAsync(a.archivio.vistaInclinata), isFalse);

    // Riaperta l'app, la mappa è ancora in 2D.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(a.app());
    await tester.pumpAndSettle();
    expect(find.text('3D'), findsOneWidget);
  });
}
