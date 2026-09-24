import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/servizi.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_viaggio.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> cercaBologna(WidgetTester tester) async {
    await tester.tap(find.text('Dove andiamo?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bologna');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bologna'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  testWidgets('dalla ricerca al viaggio con le soste', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();

    await cercaBologna(tester);

    expect(a.viaggio.stato, isA<ViaggioPronto>());
    expect(find.textContaining('Arrivo '), findsOneWidget);
    await scorriScheda(tester, volte: 1);
    expect(find.text("all'arrivo"), findsOneWidget);
    expect(find.textContaining('Area '), findsWidgets);
    await scorriScheda(tester);
    expect(find.textContaining('© Open Charge Map'), findsOneWidget);

    // Si torna in cima alla scheda per chiuderla.
    await tester.drag(find.byType(ListView).last, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();
    expect(a.viaggio.stato, isA<NessunViaggio>());
  });

  testWidgets('dalla scheda del viaggio: risparmio e senza pedaggi, e si ricalcola', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await cercaBologna(tester);
    expect(find.text('Più veloce'), findsOneWidget);

    await tester.tap(find.byKey(const Key('opzioni-percorso')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Risparmio'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pedaggi'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(a.viaggio.opzioni.modo, ModoGuida.risparmio);
    expect(a.viaggio.opzioni.evitaPedaggi, isTrue);
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    final salvate = await tester.runAsync(() => Archivio().opzioniPercorso());
    expect(salvate!.riassunto, 'Risparmio · senza pedaggi');

    await tester.tapAt(const Offset(20, 40)); // chiude il foglio
    await tester.pumpAndSettle();
    expect(find.text('Risparmio · senza pedaggi'), findsOneWidget);
  });

  testWidgets('un viaggio corto non ha soste', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 60);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await cercaBologna(tester);
    await scorriScheda(tester, volte: 1);
    expect(find.text('Ci arrivi senza fermarti.'), findsOneWidget);
  });

  testWidgets('i servizi sono cablati: senza impostazioni il viaggio parte', (tester) async {
    preparaPiattaforma();
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await cercaBologna(tester);
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    final i = await tester.runAsync(() => Archivio().impostazioni());
    expect(i!.valhalla, Servizi.valhalla);
    expect(i.mancante, isNull);
  });

  testWidgets('senza batteria chiede di scriverla', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    await cercaBologna(tester);
    expect(find.textContaining('Non so quanta batteria hai'), findsOneWidget);
  });

  testWidgets('senza posizione lo dice', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, posizione: null);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await cercaBologna(tester);
    expect(find.textContaining('Non so dove sei'), findsOneWidget);
  });
}
