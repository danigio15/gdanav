import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';

import 'aiuti.dart';

/// gdanav dentro un'altra app (gdahome): il tasto del menu apre il menu di
/// chi ospita, e il menu di gdanav si apre da fuori.
void main() {
  setUp(preparaPiattaforma);

  testWidgets('il tasto del menu apre quello di chi ospita', (tester) async {
    final a = await ambiente(tester);
    var aperto = 0;
    final apriIlMenu = ValueNotifier(false);
    addTearDown(apriIlMenu.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GdanavDentro(app: a.app() as GdanavApp, menuOspite: () => aperto++, apriIlMenu: apriIlMenu),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(aperto, 1);
    expect(find.text('La tua auto'), findsNothing);

    // Le impostazioni del navigatore, chieste da fuori.
    apriIlMenu.value = true;
    await tester.pumpAndSettle();
    expect(find.text('La tua auto'), findsOneWidget);
    expect(apriIlMenu.value, isFalse);
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
}
