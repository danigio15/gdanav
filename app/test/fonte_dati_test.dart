import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/schermate/fonte_dati_auto.dart';
import 'package:gdanav/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  Widget dentro(Widget w) => MaterialApp(
    theme: temaGdanav(Brightness.light),
    home: Scaffold(body: ListView(children: [w])),
  );

  testWidgets('i dati che arrivano: quelli che ci sono, e quelli che no', (tester) async {
    await tester.pumpWidget(
      dentro(
        DatiUsati(
          stato: StatoAuto(
            sorgente: TipoSorgente.homeAssistant,
            letto: DateTime.now().subtract(const Duration(minutes: 3)),
            batteria: 64,
            autonomiaKm: 321,
            temperaturaEsternaC: 18,
          ),
        ),
      ),
    );
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('321 km'), findsOneWidget);
    expect(find.text('18 °C'), findsOneWidget);
    expect(find.text('non arriva'), findsNWidgets(7));
    expect(find.textContaining('Da Home Assistant'), findsOneWidget);
  });

  testWidgets('la precisione per strade urbane, extraurbane e autostrade', (tester) async {
    var c = const ConsumoImparato();
    for (var i = 0; i < 4; i++) {
      c = c.con(previstoWh: 2000, realeWh: 2200, km: 10, tipo: TipoStrada.autostrada);
    }
    c = c.con(previstoWh: 1200, realeWh: 1250, km: 8, tipo: TipoStrada.urbana);
    await tester.pumpWidget(dentro(PrecisioneConsumo(imparato: c)));
    expect(find.textContaining('Autostrade'), findsOneWidget);
    expect(find.textContaining('40 km · previsto'), findsOneWidget);
    expect(find.textContaining('Correttivo +'), findsOneWidget);
    expect(find.textContaining('Correttivo suo tra 12 km'), findsOneWidget);
    expect(find.text('Ancora nessuna misura'), findsOneWidget); // extraurbane
    final autostrada = tester.widget<Text>(find.byKey(const Key('precisione-autostrada'))).data!;
    expect(int.parse(autostrada.replaceAll('%', '')), inInclusiveRange(80, 99));
    expect(tester.widget<Text>(find.byKey(const Key('precisione-extraurbana'))).data, '–');
  });
}
