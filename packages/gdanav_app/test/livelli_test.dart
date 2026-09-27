import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/fonte_dati_auto.dart';
import 'package:gdanav_app/schermate/scheda_viaggio.dart';
import 'package:gdanav_app/sorgenti/sorgente_gdahome.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/gestore_premium.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Cosa è gratis e cosa è Premium (`docs/LICENZE.md` di gdahome, riga
/// gdanav): termica completa, elettrica a mano e senza soste, traffico,
/// autovelox e meteo per tutti; batteria letta dall'auto, soste e colonnine in
/// tempo reale, Android Auto e CarPlay con Premium.
void main() {
  void senzaPremium() {
    GestorePremium.attivo.value = false;
    addTearDown(() => GestorePremium.attivo.value = true);
  }

  Widget scheda(GestoreViaggio v, {VoidCallback? onPremium}) => MaterialApp(
    theme: temaGdanav(Brightness.light),
    home: Scaffold(
      body: Stack(children: [SchedaViaggio(gestore: v, onAvvia: () {}, onPremium: onPremium)]),
    ),
  );

  testWidgets('elettrica senza Premium: il percorso sì, le soste no, e la scheda lo dice', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    senzaPremium();
    final a = await ambiente(tester, km: 500);
    a.auto.manuale.imposta(40);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Lontano', posizione: Punto(46.5, 12))));
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.senzaSoste, isTrue);
    expect(pronto.termica, isFalse);
    expect(pronto.viaggio.piano, isNull);
    expect(pronto.viaggio.colonnine, isEmpty);
    expect(pronto.arrivoAlle, isNotNull);
    expect(pronto.batteriaPartenza, 40);

    var aperto = 0;
    await tester.pumpWidget(scheda(a.viaggio, onPremium: () => aperto++));
    await tester.pumpAndSettle();
    expect(find.text('Le soste di ricarica sono con Premium'), findsOneWidget);
    expect(find.textContaining('Parti col 40%'), findsOneWidget);
    expect(find.text('Avvia'), findsOneWidget);
    expect(find.textContaining('soste'), findsWidgets);
    expect(find.text('Le soste'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('apri-premium-soste')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apri-premium-soste')));
    expect(aperto, 1);
  });

  testWidgets('elettrica con Premium: le soste ci sono, e nessun avviso', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 500);
    a.auto.manuale.imposta(40);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Lontano', posizione: Punto(46.5, 12))));
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.senzaSoste, isFalse);
    expect(pronto.viaggio.piano!.soste, isNotEmpty);
    await tester.pumpWidget(scheda(a.viaggio, onPremium: () {}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('soste-con-premium')), findsNothing);
  });

  testWidgets('la termica senza Premium è completa: come prima, senza avvisi', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    senzaPremium();
    final a = await ambiente(tester, km: 500);
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Lontano', posizione: Punto(46.5, 12))));
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.termica, isTrue);
    expect(pronto.senzaSoste, isFalse);
    await tester.pumpWidget(scheda(a.viaggio, onPremium: () {}));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('durata-termica')), findsOneWidget);
    expect(find.byKey(const Key('soste-con-premium')), findsNothing);
  });

  testWidgets('traffico per tutti: anche senza Premium il viaggio pronto si aggiorna', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    senzaPremium();
    final a = await ambiente(tester, km: 50);
    a.viaggio.trafficoFinto = (p) async => PercorsoCalcolato(
      punti: p.punti,
      tratti: [for (final t in p.tratti) Tratto(lunghezzaM: t.lunghezzaM, velocitaKmh: 30)],
      manovre: p.manovre,
      limiti: p.limiti,
    );
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Vicino', posizione: Punto(42.45, 12))));
    final prima = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.durata;
    final dopo = await tester.runAsync(a.viaggio.aggiornaTraffico);
    expect(dopo, isNotNull);
    expect(dopo!.viaggio.percorso.durata, greaterThan(prima));
    expect(dopo.senzaSoste, isTrue);
  });

  testWidgets('autovelox per tutti: le segnalazioni fisse restano senza Premium', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final strada = dritta(20).punti;
    final autovelox = ArchivioAutovelox.leggi(
      ArchivioAutovelox.scrivi([(strada[5].lat, strada[5].lon + 0.0001, 90, 0)]),
    );
    final a = await ambiente(tester, km: 20, autovelox: autovelox);
    senzaPremium();
    await tester.pumpWidget(a.app());
    a.posizione.avvia();
    a.gps.add(Lettura(strada[0]));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
    expect(a.segnalazioni.vicine.where((s) => s.fissa && s.tipo == TipoSegnalazione.autovelox), hasLength(1));
  });

  group('fonti della batteria', () {
    setUp(preparaPiattaforma);

    test('senza Premium vale solo la batteria scritta a mano; tornato Premium, la scelta di prima', () async {
      await Archivio().salvaFonte(const Fissa(TipoSorgente.gdahome));
      final g = SorgenteGdahome()..descrivi(const AutoDiGdahome(marca: 'Renault', modello: 'Zoe R135'));
      final auto = GestoreAuto(archivio: Archivio(), gdahome: g)..premium = false;
      await auto.avvia();
      addTearDown(auto.dispose);
      expect(auto.modalita, isA<Fissa>().having((f) => f.sorgente, 'sorgente', TipoSorgente.manuale));
      expect(auto.sceltaUtente, isA<Fissa>().having((f) => f.sorgente, 'sorgente', TipoSorgente.gdahome));

      // La casa manda la batteria: senza Premium non conta.
      g.manda(StatoAuto(sorgente: TipoSorgente.gdahome, letto: DateTime.now(), batteria: 64));
      await pumpEventQueue();
      expect(auto.stato, isNull);
      expect(auto.percheSenzaDati, contains('Premium'));

      // Lo switch non si sposta sulle fonti automatiche.
      await auto.cambiaModalita(const Automatica());
      expect(auto.modalita, isA<Fissa>());

      auto.manuale.imposta(50);
      await pumpEventQueue();
      expect(auto.stato?.sorgente, TipoSorgente.manuale);
      expect(auto.stato?.batteria, 50);

      // Premium: torna la scelta di prima.
      await auto.consentiPremium(true);
      expect(auto.modalita, isA<Fissa>().having((f) => f.sorgente, 'sorgente', TipoSorgente.gdahome));
      expect(auto.stato?.batteria, 64);
    });

    test('Premium scaduto: si ripiega sulla batteria scritta a mano, con l\'ultima letta', () async {
      final g = SorgenteGdahome()..descrivi(const AutoDiGdahome(marca: 'Renault', modello: 'Zoe R135'));
      final auto = GestoreAuto(archivio: Archivio(), gdahome: g);
      await auto.avvia();
      addTearDown(auto.dispose);
      g.manda(StatoAuto(sorgente: TipoSorgente.gdahome, letto: DateTime.now(), batteria: 71));
      await pumpEventQueue();
      expect(auto.stato?.sorgente, TipoSorgente.gdahome);

      await auto.consentiPremium(false);
      expect(auto.modalita, isA<Fissa>().having((f) => f.sorgente, 'sorgente', TipoSorgente.manuale));
      expect(auto.stato?.sorgente, TipoSorgente.manuale);
      expect(auto.stato?.batteria, 71);
      // La scelta salvata resta quella dell'utente.
      expect(await Archivio().fonte(), isA<Automatica>());
    });

    testWidgets('lo switch senza Premium: le fonti automatiche col lucchetto portano a Premium', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final auto = GestoreAuto(archivio: Archivio())..premium = false;
      await tester.runAsync(auto.avvia);
      addTearDown(auto.dispose);
      var premium = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: temaGdanav(Brightness.light),
          home: Scaffold(
            body: FonteDatiAuto(gestore: auto, onPremium: () => premium++),
          ),
        ),
      );
      expect(find.byKey(const Key('fonti-premium')), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      // La manuale si sceglie (ed è quella scelta); le altre no.
      expect(find.byType(RadioListTile<TipoSorgente?>), findsOneWidget);
      await tester.tap(find.byKey(const Key('fonte-obd')));
      await tester.tap(find.byKey(const Key('fonte-homeAssistant')));
      await tester.tap(find.text('Automatica'));
      expect(premium, 3);
      expect(auto.modalita, isA<Fissa>());

      // Con Premium: i soliti interruttori, senza lucchetti.
      await tester.runAsync(() => auto.consentiPremium(true));
      await tester.pump();
      expect(find.byKey(const Key('fonti-premium')), findsNothing);
      expect(find.byType(RadioListTile<TipoSorgente?>), findsNWidgets(5));
    });
  });
}
