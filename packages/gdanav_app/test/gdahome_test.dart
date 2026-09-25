import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/fonte_gdahome.dart';
import 'package:gdanav_app/sorgenti/sorgente_gdahome.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// La fonte gdahome: l'auto della plancia di gdahome arriva da sola, coi suoi
/// dati, senza abbinamento.
void main() {
  setUp(preparaPiattaforma);

  test('la lettura di gdahome diventa lo stato dell\'auto, e l\'auto della plancia la tua auto', () async {
    final g = SorgenteGdahome()
      ..descrivi(const AutoDiGdahome(nome: 'La Zoe', marca: 'Renault', modello: 'Zoe R135', kwh: 52))
      // Arrivata prima che gdanav si accendesse: non si perde.
      ..manda(StatoAuto(sorgente: TipoSorgente.homeAssistant, letto: DateTime.now(), batteria: 72, autonomiaKm: 250));
    final auto = GestoreAuto(archivio: Archivio(), gdahome: g);
    await auto.avvia();
    await pumpEventQueue();
    expect(auto.veicolo.id, 'renault-zoe-r135');
    expect(auto.stato?.sorgente, TipoSorgente.gdahome);
    expect(auto.stato?.batteria, 72);
    expect(auto.disponibili, contains(TipoSorgente.gdahome));

    // In tempo reale: la lettura dopo sostituisce quella prima.
    g.manda(StatoAuto(sorgente: TipoSorgente.gdahome, letto: DateTime.now(), batteria: 71));
    await pumpEventQueue();
    expect(auto.stato?.batteria, 71);
    auto.dispose();
  });

  test('una scelta a mano resta finché l\'auto della plancia è la stessa', () async {
    final g = SorgenteGdahome()..descrivi(const AutoDiGdahome(marca: 'Renault', modello: 'Zoe R135'));
    final auto = GestoreAuto(archivio: Archivio(), gdahome: g);
    await auto.avvia();
    await pumpEventQueue();
    expect(auto.veicolo.id, 'renault-zoe-r135');

    // Scelta a mano: la stessa auto della plancia non la cambia più.
    await auto.scegliVeicolo(veicoloPerId('renault-zoe-r110')!);
    g.descrivi(const AutoDiGdahome(nome: 'Rinominata', marca: 'Renault', modello: 'Zoe R135'));
    await pumpEventQueue();
    expect(auto.veicolo.id, 'renault-zoe-r110');
    auto.dispose();

    // Anche riaprendo l'app.
    final dopo = GestoreAuto(archivio: Archivio(), gdahome: g);
    await dopo.avvia();
    await pumpEventQueue();
    expect(dopo.veicolo.id, 'renault-zoe-r110');

    // Cambiata l'auto nella plancia, cambia subito anche qui.
    g.descrivi(const AutoDiGdahome(marca: 'Tesla', modello: 'Model 3 Long Range'));
    await pumpEventQueue();
    expect(dopo.veicolo.id, 'tesla-model-3-lr');
    dopo.dispose();
  });

  testWidgets('nell\'app gdanav da sola la voce dice come si accende', (tester) async {
    final auto = GestoreAuto(archivio: Archivio());
    expect(riassuntoGdahome(auto), 'Automatica dentro l\'app gdahome');
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: Scaffold(body: FonteGdahome(gestore: auto)),
      ),
    );
    expect(find.textContaining('nessun codice, nessun QR'), findsOneWidget);
  });

  testWidgets('dentro gdahome si vede l\'auto e cosa arriva', (tester) async {
    final g = SorgenteGdahome()
      ..descrivi(const AutoDiGdahome(nome: 'La Zoe', marca: 'Renault', modello: 'Zoe R135', kwh: 52))
      ..collegamento(true)
      ..manda(StatoAuto(sorgente: TipoSorgente.gdahome, letto: DateTime.now(), batteria: 64));
    final auto = GestoreAuto(archivio: Archivio(), gdahome: g);
    expect(riassuntoGdahome(auto), 'Collegata · La Zoe');
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: Scaffold(body: FonteGdahome(gestore: auto)),
      ),
    );
    expect(find.text('La Zoe'), findsOneWidget);
    expect(find.text('Renault Zoe R135 · 52 kWh'), findsOneWidget);
    expect(find.text('Casa collegata'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
  });
}
