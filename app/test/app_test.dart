import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/main.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_auto.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Il portachiavi finto: una mappa in memoria.
    FlutterSecureStorage.setMockInitialValues({});
    // Nessun codice nativo per Android Auto: il canale risponde con un errore
    // e la sorgente tace, come su iPhone.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      const EventChannel('gdanav/auto'),
      null,
    );
  });

  Future<GestoreAuto> gestore(WidgetTester tester) async {
    final g = GestoreAuto(archivio: Archivio());
    await tester.runAsync(g.avvia);
    addTearDown(g.dispose);
    return g;
  }

  Widget app(GestoreAuto g) => GdanavApp(
    gestore: g,
    mappa: (_) => const ColoredBox(color: Colors.grey),
  );

  testWidgets('senza dati la batteria è sconosciuta', (tester) async {
    await tester.pumpWidget(app(await gestore(tester)));
    expect(find.text('Batteria sconosciuta'), findsOneWidget);
  });

  testWidgets('la batteria manuale compare con la sua sorgente', (tester) async {
    final g = await gestore(tester);
    await tester.pumpWidget(app(g));
    g.manuale.imposta(64);
    await tester.pump();
    expect(find.text('64% · Manuale · adesso'), findsOneWidget);
  });

  testWidgets('lo switch cambia la fonte e la ricorda', (tester) async {
    final g = await gestore(tester);
    await tester.pumpWidget(app(g));
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    expect(find.text('Fonte dati auto'), findsOneWidget);

    await tester.tap(find.text('Home Assistant').last);
    await tester.pumpAndSettle();
    expect(g.modalita, isA<Fissa>().having((f) => f.sorgente, 'sorgente', TipoSorgente.homeAssistant));
    final ricordata = await tester.runAsync(() => Archivio().fonte());
    expect(ricordata, isA<Fissa>().having((f) => f.sorgente, 'sorgente', TipoSorgente.homeAssistant));

    await tester.tap(find.text('Automatica'));
    await tester.pumpAndSettle();
    expect(g.modalita, isA<Automatica>());
  });
}
