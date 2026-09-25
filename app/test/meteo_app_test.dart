import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/schermate/scheda_viaggio.dart';
import 'package:gdanav/stato/gestore_meteo.dart';
import 'package:gdanav/stato/gestore_premium.dart';
import 'package:gdanav/stato/gestore_viaggio.dart';
import 'package:gdanav/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  testWidgets('col freddo previsto il viaggio si calcola col clima, e la scheda mostra il meteo', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 300);
    final fonte = MeteoFinto(-2);
    final meteo = GestoreMeteo(viaggio: a.viaggio, fonte: fonte);
    addTearDown(meteo.dispose);
    a.viaggio.stimaMeteo = meteo.stima;
    a.auto.manuale.imposta(90);

    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Milano', posizione: Punto(45.46, 9.19))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    expect(a.viaggio.condizioni!.temperaturaC, -2);
    expect(a.viaggio.condizioni!.climaW, greaterThan(0));
    expect(meteo.delViaggio, isNotNull);
    expect(meteo.delViaggio!.tappe, isNotEmpty);

    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: Scaffold(
          body: Stack(
            children: [SchedaViaggio(gestore: a.viaggio, onAvvia: () {}, meteo: meteo)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('meteo-viaggio'), skipOffstage: false), findsOneWidget);
    expect(find.text('-2°', skipOffstage: false), findsWidgets);
    expect(find.textContaining('Consumo calcolato con -2 °C', skipOffstage: false), findsOneWidget);
    expect(find.text(MeteoMetNorway.citazione, skipOffstage: false), findsOneWidget);
  });

  testWidgets('senza Premium niente meteo: si calcola come prima', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 300);
    final fonte = MeteoFinto(-2);
    GestorePremium.attivo.value = false;
    addTearDown(() => GestorePremium.attivo.value = true);
    final meteo = GestoreMeteo(viaggio: a.viaggio, fonte: fonte);
    addTearDown(meteo.dispose);
    a.viaggio.stimaMeteo = meteo.stima;
    a.auto.manuale.imposta(90);

    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Milano', posizione: Punto(45.46, 9.19))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    expect(a.viaggio.condizioni!.temperaturaC, 20);
    expect(meteo.delViaggio, isNull);
    expect(fonte.richieste, 0);
  });
}
