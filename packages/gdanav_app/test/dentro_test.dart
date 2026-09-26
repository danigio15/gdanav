import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';

import 'aiuti.dart';

/// gdanav dentro un'altra app (gdahome): il tasto del menu apre il menu di
/// chi ospita, e il menu di gdanav si apre da fuori.
void main() {
  setUp(preparaPiattaforma);

  testWidgets('il ☰ apre il menu di gdanav, il tasto accanto quello di chi ospita', (tester) async {
    final a = await ambiente(tester);
    var aperto = 0;
    final apriIlMenu = ValueNotifier(false);
    addTearDown(apriIlMenu.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GdanavDentro(
            app: a.app() as GdanavApp,
            menuOspite: () => aperto++,
            iconaOspite: const Icon(Icons.cottage),
            apriIlMenu: apriIlMenu,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu dell\'app'));
    await tester.pumpAndSettle();
    expect(aperto, 1);
    expect(find.byIcon(Icons.cottage), findsOneWidget);
    expect(find.text('La tua auto'), findsNothing);

    // Il menu di gdanav: dal suo ☰, sulla mappa.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('La tua auto'), findsOneWidget);
    Navigator.of(tester.element(find.text('La tua auto'))).pop();
    await tester.pumpAndSettle();

    // E chiesto da fuori (la tessera di gdahome).
    apriIlMenu.value = true;
    await tester.pumpAndSettle();
    expect(find.text('La tua auto'), findsOneWidget);
    expect(apriIlMenu.value, isFalse);
  });

  testWidgets('da sola, gdanav ha il suo ☰ e basta', (tester) async {
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(find.byTooltip('Menu dell\'app'), findsNothing);
  });

  testWidgets('chiesto prima che ci fosse, il menu si apre appena c\'è', (tester) async {
    final a = await ambiente(tester);
    final apriIlMenu = ValueNotifier(true);
    addTearDown(apriIlMenu.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GdanavDentro(app: a.app() as GdanavApp, menuOspite: () {}, apriIlMenu: apriIlMenu),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('La tua auto'), findsOneWidget);
  });

  testWidgets('le voci di chi ospita stanno nel menu di gdanav', (tester) async {
    final a = await ambiente(tester);
    var aperta = 0;
    final apriIlMenu = ValueNotifier(true);
    addTearDown(apriIlMenu.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GdanavDentro(
            app: a.app() as GdanavApp,
            menuOspite: () {},
            apriIlMenu: apriIlMenu,
            vociOspite: [
              VoceOspite(
                icona: Icons.bolt,
                titolo: 'Comandi rapidi in auto',
                sotto: 'Cancello, garage',
                apri: () => aperta++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comandi rapidi in auto'));
    await tester.pumpAndSettle();
    expect(aperta, 1);
  });
}
