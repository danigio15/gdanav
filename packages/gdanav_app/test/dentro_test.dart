import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';

import 'aiuti.dart';

/// GdANav dentro un'altra app (GdAHome): il tasto del menu apre il menu di
/// chi ospita, e il menu di GdANav si apre da fuori.
void main() {
  setUp(preparaPiattaforma);

  testWidgets('il ☰ apre il menu di GdANav, il tasto accanto quello di chi ospita', (tester) async {
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

    // Il menu di GdANav: dal suo ☰, sulla mappa.
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('La tua auto'), findsOneWidget);
    Navigator.of(tester.element(find.text('La tua auto'))).pop();
    await tester.pumpAndSettle();

    // E chiesto da fuori (la tessera di GdAHome).
    apriIlMenu.value = true;
    await tester.pumpAndSettle();
    expect(find.text('La tua auto'), findsOneWidget);
    expect(apriIlMenu.value, isFalse);
  });

  testWidgets('da sola, GdANav ha il suo ☰ e basta', (tester) async {
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

  testWidgets('le voci di chi ospita stanno nel menu di GdANav', (tester) async {
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

  testWidgets('in auto: solo le impostazioni, senza la mappa, e la X le chiude', (tester) async {
    final a = await ambiente(tester);
    var chiuse = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GdanavDentro(app: a.app() as GdanavApp, soloImpostazioni: true, chiudiImpostazioni: () => chiuse++),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Navigatore e auto'), findsOneWidget);
    expect(find.text('La tua auto'), findsOneWidget);
    expect(find.text('Percorso'), findsOneWidget);
    // Niente mappa e niente ☰: si è già nel menu.
    expect(find.byTooltip('Menu'), findsNothing);

    // Una voce si apre sopra la pagina, e si torna alla pagina.
    await tester.tap(find.text('Percorso'));
    await tester.pumpAndSettle();
    expect(find.text('Navigatore e auto'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Navigatore e auto'), findsOneWidget);

    await tester.tap(find.byTooltip('Chiudi'));
    expect(chiuse, 1);
  });
}
