import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/componenti/tachimetro.dart';
import 'package:gdanav/schermate/cerca_destinazione.dart';
import 'package:gdanav/stato/gestore_posizione.dart';
import 'package:gdanav/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Una ricerca che risponde quando lo dice la prova.
class LuoghiLenti implements FonteLuoghi {
  final attese = <Completer<List<Luogo>>>[];

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) {
    final c = Completer<List<Luogo>>();
    attese.add(c);
    return c.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> aspetta(WidgetTester tester, [int ms = 30]) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump();
  }

  testWidgets('mentre cerca, quello che hai scritto resta (non si cancella più)', (tester) async {
    final luoghi = LuoghiLenti();
    await tester.pumpWidget(MaterialApp(home: CercaDestinazione(luoghi: luoghi)));
    await tester.enterText(find.byType(TextField), 'via roma');
    await tester.pump(const Duration(milliseconds: 450));
    // La ricerca è partita: compare la barra di avanzamento.
    expect(luoghi.attese, hasLength(1));
    expect(find.text('via roma'), findsOneWidget);

    // Si continua a scrivere mentre risponde.
    await tester.enterText(find.byType(TextField), 'via roma 10');
    luoghi.attese.first.complete(const [Luogo(nome: 'Via Roma', posizione: Punto(45, 9))]);
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('via roma 10'), findsOneWidget);
    luoghi.attese.last.complete(const [Luogo(nome: 'Via Roma 10', descrizione: 'Milano', posizione: Punto(45, 9))]);
    await tester.pump();
    expect(find.text('Via Roma 10'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancella'));
    await tester.pump();
    expect(find.text('via roma 10'), findsNothing);
    expect(find.text('Via Roma 10'), findsNothing);
  });

  testWidgets('Casa si imposta la prima volta, poi ti ci porta; le mete finiscono nei recenti', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await aspetta(tester);
    expect(find.text('Dove andiamo?'), findsOneWidget);

    await tester.tap(find.text('Casa'));
    await tester.pumpAndSettle();
    expect(find.text('Indirizzo di casa'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bologna');
    await tester.pump(const Duration(milliseconds: 500));
    await aspetta(tester);
    await tester.tap(find.text('Bologna'));
    await tester.pumpAndSettle();
    await aspetta(tester);
    expect(find.text('Casa salvato'), findsOneWidget);
    expect(a.viaggio.stato, isA<NessunViaggio>());

    await tester.tap(find.text('Casa'));
    await aspetta(tester, 80);
    await tester.pumpAndSettle();
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    expect(a.viaggio.destinazione!.nome, 'Bologna');

    // Chiuso il viaggio, Bologna è fra i recenti.
    await tester.tap(find.byTooltip('Chiudi'));
    await tester.pumpAndSettle();
    expect(find.text('Recenti'), findsOneWidget);
    expect(find.text('Emilia-Romagna'), findsOneWidget);
  });

  testWidgets('in guida il tachimetro mostra velocità e limite, e diventa rosso se si corre', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();

    a.posizione.avvia();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[2]);
    a.gps.add(Lettura(punti[2], velocitaMs: 13.9));
    await aspetta(tester);
    expect(find.byType(CartelloLimite), findsOneWidget);
    expect(find.descendant(of: find.byType(CartelloLimite), matching: find.text('50')), findsOneWidget);
    Tachimetro t() => tester.widget<Tachimetro>(find.byType(Tachimetro));
    expect(t().velocitaKmh.round(), 50);
    expect(t().oltre, isFalse);

    a.gps.add(Lettura(punti[3], velocitaMs: 19.4)); // 70 km/h in città
    await aspetta(tester);
    expect(t().oltre, isTrue);

    // Fuori città il limite sale.
    a.posizioni.add(punti[15]);
    await aspetta(tester);
    expect(find.descendant(of: find.byType(CartelloLimite), matching: find.text('90')), findsOneWidget);
    expect(t().oltre, isFalse);
  });

  testWidgets('il bottone giallo segnala dove sei', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    await tester.pumpWidget(a.app());
    a.posizione.avvia();
    a.gps.add(const Lettura(Punto(45.46, 9.19)));
    await aspetta(tester);

    await tester.tap(find.byTooltip('Segnala'));
    await tester.pumpAndSettle();
    expect(find.text('Cosa vedi?'), findsOneWidget);
    await tester.tap(find.text('Polizia'));
    await aspetta(tester, 60);
    await tester.pumpAndSettle();
    expect(a.relay.segnalazioni.single, containsPair('tipo', 'polizia'));
    expect(a.relay.segnalazioni.single, containsPair('lat', 45.46));
    expect(find.textContaining('Grazie!'), findsOneWidget);
    expect(a.segnalazioni.vicine, hasLength(1));
  });

  testWidgets('in guida una segnalazione sul percorso si annuncia, e passata chiede se c\'è ancora', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    // Un incidente a 5 km, sulla strada.
    a.relay.segnalazioni.add({
      'id': 'z~incidente1',
      'tipo': 'incidente',
      'lat': punti[5].lat,
      'lon': punti[5].lon,
      'creata': 0,
      'conferme': 2,
    });
    a.posizione.avvia();
    a.gps.add(Lettura(punti[0]));
    await aspetta(tester, 60);
    expect(a.segnalazioni.vicine, hasLength(1));

    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    a.posizioni.add(punti[1]);
    await aspetta(tester);
    expect(find.text('Incidente segnalato'), findsNothing); // ancora 4 km

    a.posizioni.add(Punto(punti[4].lat + 0.003, punti[4].lon)); // ~700 m prima
    await aspetta(tester);
    expect(find.text('Incidente segnalato'), findsOneWidget);
    expect(find.textContaining('confermata da 2'), findsOneWidget);
    expect(a.voce.frasi.where((f) => f.startsWith('Incidente segnalato tra')), hasLength(1));

    a.posizioni.add(Punto(punti[5].lat + 0.0005, punti[5].lon)); // appena passato
    await aspetta(tester);
    expect(find.text("Incidente: c'è ancora?"), findsOneWidget);
    await tester.tap(find.text('No'));
    await aspetta(tester);
    expect(a.relay.voti, [('z~incidente1', false)]);
    expect(find.text("Incidente: c'è ancora?"), findsNothing);
  });
}
