import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/la_tua_auto.dart';
import 'package:gdanav_app/sorgenti/sorgente_gdahome.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/stato/gestore_consumo.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Il confronto con ABRP: lo stesso viaggio, la stessa B10, e gdanav più
/// pessimista e coi dati «di 2 h fa».
void main() {
  setUp(preparaPiattaforma);
  final b10 = catalogoVeicoli.firstWhere((v) => v.id == 'leapmotor-b10-56');

  test('gdanav chiede dati freschi anche a GdAHome: all\'avvio e in viaggio', () async {
    var chieste = 0;
    final g = SorgenteGdahome()..aggiorna = () async => chieste++;
    final auto = GestoreAuto(archivio: Archivio(), gdahome: g);
    await auto.avvia();
    await pumpEventQueue();
    expect(chieste, 1, reason: 'all\'avvio');
    await auto.chiediAggiornamento();
    expect(chieste, 2, reason: 'quando la guida lo chiede');
    auto.dispose();
  });

  test('una casa che non risponde non rompe niente', () async {
    final g = SorgenteGdahome()..aggiorna = () async => throw StateError('filo caduto');
    await g.chiediAggiornamento();
    final senza = SorgenteGdahome();
    await senza.chiediAggiornamento();
  });

  test('il consumo di riferimento di ABRP diventa il correttivo, e resta', () async {
    final archivio = Archivio();
    final c = GestoreConsumo(archivio);
    await c.carica(b10.id);
    await c.impostaRiferimento(whKm: 188, kmh: 110, veicolo: b10);
    expect(c.imparato.fattore, closeTo(fattoreDaRiferimento(whKm: 188, kmh: 110, profilo: b10), 1e-9));
    expect(c.imparato.fattore, inInclusiveRange(1.0, 1.15));
    final dopo = GestoreConsumo(archivio);
    await dopo.carica(b10.id);
    expect(dopo.imparato.riferimento?.whKm, 188);
    expect(dopo.imparato.fattore, c.imparato.fattore);
    // Le condizioni del piano lo portano dentro.
    expect(dopo.condizioni(null).fattoreConsumo, c.imparato.fattore);
  });

  testWidgets('in La tua auto il consumo lo impara gdanav: niente numeri da altre app', (tester) async {
    final archivio = Archivio();
    await archivio.salvaVeicolo(b10);
    final auto = GestoreAuto(archivio: archivio);
    await tester.runAsync(auto.avvia);
    final consumo = GestoreConsumo(archivio);
    await tester.runAsync(() => consumo.carica(b10.id));
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: LaTuaAuto(
          auto: auto,
          posizione: GestorePosizione(archivio: archivio, letture: () => const Stream.empty()),
          consumo: consumo,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Consumo imparato'), findsOneWidget);
    expect(find.textContaining('ABRP'), findsNothing);
    expect(find.byKey(const Key('consumo-riferimento')), findsNothing);
    auto.dispose();
  });
}
