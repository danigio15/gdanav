import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/abbina_home_assistant.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Il collegamento vero (archivio, relay) fa passare tempo reale.
Future<void> aspetta(WidgetTester tester, bool Function() fatto) async {
  for (var i = 0; i < 40 && !fatto(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  final casa = Abbinamento.nuovo(relay: Uri.parse('wss://relay.esempio.dev'), nomeAuto: 'Leapmotor B10');

  Future<GestoreAuto> apri(WidgetTester tester, Future<Abbinamento> Function(String) daCodice) async {
    preparaPiattaforma();
    final auto = GestoreAuto(archivio: Archivio());
    await tester.runAsync(auto.avvia);
    addTearDown(auto.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AbbinaHomeAssistant(gestore: auto, daCodice: daCodice, fotocamera: false),
                ),
              ),
              child: const Text('apri'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    return auto;
  }

  testWidgets('si scrive il codice di Home Assistant e ci si collega', (tester) async {
    final scritti = <String>[];
    final auto = await apri(tester, (c) async {
      scritti.add(c);
      return casa;
    });
    expect(find.text('Scrivi il codice'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('codice-abbinamento')), '7kq2m-9xapd');
    await tester.tap(find.text('Collega'));
    await aspetta(tester, () => auto.abbinamento != null && find.text('Scrivi il codice').evaluate().isEmpty);
    expect(scritti, ['7kq2m-9xapd']);
    expect(auto.abbinamento?.uri, casa.uri);
    expect(find.text('Scrivi il codice'), findsNothing); // la schermata si è chiusa
  });

  testWidgets('il link intero incollato va bene lo stesso', (tester) async {
    final auto = await apri(tester, (_) async => throw StateError('non si chiede al relay'));
    await tester.enterText(find.byKey(const Key('codice-abbinamento')), casa.uri);
    await tester.tap(find.text('Collega'));
    await aspetta(tester, () => auto.abbinamento != null && find.text('Scrivi il codice').evaluate().isEmpty);
    expect(auto.abbinamento?.uri, casa.uri);
  });

  testWidgets('codice scaduto: lo dice e si resta lì', (tester) async {
    final auto = await apri(
      tester,
      (_) async => throw const FormatException('Codice sbagliato o scaduto: in Home Assistant chiedine uno nuovo'),
    );
    await tester.enterText(find.byKey(const Key('codice-abbinamento')), '7KQ2M9XAPD');
    await tester.tap(find.text('Collega'));
    await tester.pumpAndSettle();
    expect(find.textContaining('scaduto'), findsOneWidget);
    expect(auto.abbinamento, isNull);
  });
}
