import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/componenti/anello_batteria.dart';
import 'package:gdanav_app/schermate/la_tua_auto.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  testWidgets('auto termica: si sceglie in «La tua auto» e resta salvata; sparisce il catalogo elettrico', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: LaTuaAuto(auto: a.auto, posizione: a.posizione),
      ),
    );
    expect(a.auto.elettrica, isTrue);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Termica'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(a.auto.elettrica, isFalse);
    expect(await tester.runAsync(a.archivio.elettrica), isFalse);
    expect(find.byKey(const Key('spiega-termica')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Elettrica'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(a.auto.elettrica, isTrue);
    expect(await tester.runAsync(a.archivio.elettrica), isTrue);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('auto termica: si parte senza sapere la batteria, niente soste né batteria, e si guida', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    await tester.pumpWidget(a.app());
    await tester.pump();
    expect(find.byKey(const Key('scheda-auto-termica')), findsOneWidget);
    expect(find.byKey(const Key('scheda-batteria')), findsNothing);

    // Nessuna batteria scritta: con l'elettrica sarebbe un errore.
    expect(a.auto.stato?.batteria, isNull);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.termica, isTrue);
    expect(pronto.viaggio.piano, isNull);
    expect(pronto.viaggio.colonnine, isEmpty);
    expect(pronto.arrivoAlle, pronto.calcolatoAlle.add(pronto.viaggio.percorso.durata));
    expect(find.byKey(const Key('durata-termica')), findsOneWidget);
    expect(find.byType(AnelloBatteria), findsNothing);
    expect(find.textContaining('Colonnine'), findsNothing);

    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    a.posizioni.add(pronto.viaggio.percorso.punti[3]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(a.guida.attiva, isTrue);
    expect(a.guida.avanzamento, isNotNull);
    expect(a.guida.batteriaOra, isNull);
    expect(a.guida.autonomiaOra, isNull);
    expect(find.byKey(const Key('batteria-ora')), findsNothing);
    expect(find.text('Fine'), findsOneWidget);
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets("auto termica su Android Auto: niente batteria nel cruscotto, e l'auto lo sa", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    const canale = MethodChannel('gdanav/schermo_auto');
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester, km: 20);
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, auto: a.auto, canale: canale)
      ..avvia();
    addTearDown(ponte.ferma);
    a.auto.manuale.imposta(80);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    Map<Object?, Object?> cruscotto() => chiamate.lastWhere((c) => c.method == 'cruscotto').arguments as Map;
    expect(cruscotto()['elettrica'], isTrue);
    expect(cruscotto()['batteria'], 80);

    await tester.runAsync(() => a.auto.impostaElettrica(false));
    await tester.pump();
    expect(cruscotto()['elettrica'], isFalse);
    expect(cruscotto()['batteria'], isNull);
    expect(cruscotto()['autonomia_km'], isNull);
  });
}
