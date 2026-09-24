import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/componenti/indicatore_batteria.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(preparaPiattaforma);

  testWidgets('senza dati la batteria è sconosciuta', (tester) async {
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    expect(find.text('Batteria sconosciuta'), findsOneWidget);
    expect(find.text('Dove vuoi andare?'), findsOneWidget);
  });

  testWidgets('la batteria manuale compare con la sua sorgente', (tester) async {
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(64);
    await tester.pump();
    expect(find.textContaining('64% · ≈'), findsOneWidget);
    expect(find.textContaining('Manuale · adesso'), findsOneWidget);
  });

  testWidgets('lo switch cambia la fonte e la ricorda', (tester) async {
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    await tester.tap(find.byType(IndicatoreBatteria));
    await tester.pumpAndSettle();
    expect(find.text('Fonte dati auto'), findsOneWidget);

    await tester.tap(find.text('Home Assistant').last);
    await tester.pumpAndSettle();
    expect(a.auto.modalita, isA<Fissa>().having((f) => f.sorgente, 'sorgente', TipoSorgente.homeAssistant));
    final ricordata = await tester.runAsync(() => Archivio().fonte());
    expect(ricordata, isA<Fissa>().having((f) => f.sorgente, 'sorgente', TipoSorgente.homeAssistant));

    await tester.tap(find.text('Automatica'));
    await tester.pumpAndSettle();
    expect(a.auto.modalita, isA<Automatica>());
  });
}
