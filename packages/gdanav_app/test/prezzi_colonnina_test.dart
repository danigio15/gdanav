import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/dettaglio_colonnina.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// «Riesci a mettere anche i prezzi di ricarica?» Quelli che il gestore
/// comunica alla PUN, nella scheda della colonnina.
void main() {
  Map<String, Object?> tariffe(Map<String, Map<String, num?>> perCorrente) => {
    'punTariffsDetails': {
      for (final MapEntry(:key, :value) in perCorrente.entries)
        '${key}Tariff': {'energy': null, 'parking': null, 'activation': null, 'time': null, ...value},
    },
  };

  test('una riga per corrente, in euro all\'italiana', () {
    final a2a = Prezzi.daiPunti([
      tariffe({
        'ac': {'energy': 0.63, 'parking': 0.08},
      }),
      tariffe({
        'ac': {'energy': 0.69},
        'dc': {'energy': 0.69, 'parking': 0.15},
      }),
    ]);
    expect(righePrezzi(a2a), ['AC: 0,63–0,69 €/kWh · sosta 0,08 €/min', 'DC: 0,69 €/kWh · sosta 0,15 €/min']);
    final emobitaly = Prezzi.daiPunti([
      tariffe({
        'hpc': {'energy': 0.6, 'activation': 1.14},
      }),
    ]);
    expect(righePrezzi(emobitaly), ['DC ad alta potenza: 0,60 €/kWh · avvio 1,14 €']);
  });

  Future<void> scheda(WidgetTester tester, Prezzi? prezzi) => tester.pumpWidget(
    MaterialApp(
      theme: temaGdanav(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) =>
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: sezionePrezzo(context, prezzi)),
        ),
      ),
    ),
  );

  testWidgets('nella scheda: il prezzo, e da dove viene', (tester) async {
    await scheda(
      tester,
      Prezzi.daiPunti([
        tariffe({
          'ac': {'energy': 0.63},
        }),
      ]),
    );
    expect(find.text('Prezzo'), findsOneWidget);
    expect(find.text('AC: 0,63 €/kWh'), findsOneWidget);
    expect(find.text('Come il gestore lo comunica alla PUN'), findsOneWidget);
  });

  testWidgets('chi non lo comunica: lo si dice, invece di tacere', (tester) async {
    await scheda(tester, Prezzi.nessuno);
    expect(find.byKey(const Key('prezzo-assente')), findsOneWidget);
    expect(find.text('Prezzo'), findsNothing);
  });

  testWidgets('prima di chiederlo: niente', (tester) async {
    await scheda(tester, null);
    expect(find.byType(Text), findsNothing);
  });
}
