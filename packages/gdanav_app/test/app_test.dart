import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(preparaPiattaforma);

  testWidgets('senza dati la batteria è sconosciuta', (tester) async {
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    expect(find.text('Nessun dato: tocca «Fonte dati»'), findsOneWidget);
    expect(find.text('Scegli la tua auto'), findsOneWidget);
    expect(find.text('Dove andiamo?'), findsOneWidget);
  });

  testWidgets('la batteria manuale compare con la sua sorgente', (tester) async {
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(64);
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('scheda-batteria'))).data, '64%');
    expect(find.textContaining('≈ '), findsOneWidget);
    expect(find.text('Batteria scritta a mano · adesso'), findsOneWidget);
  });

  testWidgets("con i dati da Home Assistant la scheda dice che l'auto è connessa", (tester) async {
    final a = await ambiente(tester);
    await tester.runAsync(() => a.auto.scegliVeicolo(catalogoVeicoli.firstWhere((v) => v.id == 'leapmotor-b10-67')));
    await tester.pumpWidget(a.app());
    a.auto.arbitro.registra(
      StatoAuto(sorgente: TipoSorgente.homeAssistant, letto: DateTime.now(), batteria: 47, autonomiaKm: 194),
    );
    await tester.runAsync(() => a.auto.cambiaModalita(a.auto.modalita));
    await tester.pump();
    expect(find.text('Leapmotor B10'), findsOneWidget);
    expect(find.text('67,1 kWh (Design, Pro Max)'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('scheda-batteria'))).data, '47%');
    expect(find.text('≈ 194 km di autonomia'), findsOneWidget);
    expect(find.text('Connesso · Home Assistant · adesso'), findsOneWidget);
    expect(find.byTooltip('Foto della tua auto'), findsOneWidget);
  });

  testWidgets('lo switch cambia la fonte e la ricorda', (tester) async {
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    await tester.tap(find.text('Fonte dati'));
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
