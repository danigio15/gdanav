import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/componenti/tachimetro.dart';
import 'package:gdanav/schermate/diagnosi_auto.dart';
import 'package:gdanav/tema.dart';
import 'package:gdanav/schermate/cerca_destinazione.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_posizione.dart';
import 'package:gdanav/stato/gestore_premium.dart';
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
    // Sotto la scheda dell'auto.
    await tester.scrollUntilVisible(
      find.text('Emilia-Romagna'),
      100,
      scrollable: find.ancestor(of: find.text('Dove andiamo?'), matching: find.byType(Scrollable)).first,
    );
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

  testWidgets('autovelox fisso: avviso col limite, solo nella nostra direzione, senza «c\'è ancora?»', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    // La strada di prova va dritta verso nord: il primo guarda chi sale, il
    // secondo chi scende (l'altra carreggiata).
    final strada = dritta(20).punti;
    final autovelox = ArchivioAutovelox.leggi(
      ArchivioAutovelox.scrivi([
        (strada[5].lat, strada[5].lon + 0.0001, 90, 0),
        (strada[8].lat, strada[8].lon + 0.0001, 70, 180),
      ]),
    );
    final a = await ambiente(tester, km: 20, autovelox: autovelox);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizione.avvia();
    a.gps.add(Lettura(punti[0]));
    await aspetta(tester, 60);
    expect(a.segnalazioni.vicine.where((s) => s.fissa), hasLength(2));
    // Senza Premium gli autovelox non ci sono.
    GestorePremium.attivo.value = false;
    expect(a.segnalazioni.vicine.where((s) => s.fissa), isEmpty);
    GestorePremium.attivo.value = true;

    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    a.posizioni.add(Punto(punti[4].lat + 0.003, punti[4].lon)); // ~700 m prima del primo
    await aspetta(tester);
    expect(find.text('Autovelox fisso'), findsOneWidget);
    expect(a.voce.frasi.where((f) => f.startsWith('Autovelox, limite 90 tra')), hasLength(1));

    a.posizioni.add(Punto(punti[5].lat + 0.0005, punti[5].lon)); // passato
    await aspetta(tester);
    expect(find.textContaining("c'è ancora?"), findsNothing);

    a.posizioni.add(Punto(punti[7].lat + 0.003, punti[7].lon)); // prima del secondo, che guarda dall'altra parte
    await aspetta(tester);
    expect(a.voce.frasi.where((f) => f.contains('limite 70')), isEmpty);
  });

  testWidgets('in guida: 2D/3D al volo, mappa libera con «Riprendi», e dopo 20 s torna da sola', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    final c = a.controllo!;
    expect(c.inclinata, isTrue);

    await tester.tap(find.byKey(const Key('2d-3d')));
    await tester.pump();
    expect(c.inclinata, isFalse);
    expect(find.text('3D'), findsOneWidget);

    // Un dito sposta la mappa: resta lì, e compare «Riprendi».
    c.toccata();
    await tester.pump();
    expect(find.byKey(const Key('riprendi')), findsOneWidget);
    await tester.tap(find.byKey(const Key('riprendi')));
    await tester.pump();
    expect(c.libera, isFalse);
    expect(find.byKey(const Key('riprendi')), findsNothing);

    // Toccata e lasciata: dopo 20 secondi segue di nuovo l'auto.
    c.toccata();
    await tester.pump(const Duration(seconds: 10));
    expect(c.libera, isTrue);
    await tester.pump(const Duration(seconds: 11));
    expect(c.libera, isFalse);
    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();
  });

  test('senza velocità dal GPS la si ricava dagli spostamenti, e da fermi torna a zero', () {
    var adesso = DateTime(2026, 9, 24, 8);
    final gps = StreamController<Lettura>(sync: true);
    addTearDown(gps.close);
    final p = GestorePosizione(archivio: Archivio(), letture: () => gps.stream, orologio: () => adesso)..avvia();
    gps.add(const Lettura(Punto(45, 9)));
    adesso = adesso.add(const Duration(seconds: 1));
    // 20 metri in un secondo: 72 km/h.
    gps.add(Lettura(Punto(45 + 20 / 111195, 9)));
    expect(p.velocitaAdesso(), closeTo(72, 1));
    // Il GPS dà la velocità: vince la sua.
    adesso = adesso.add(const Duration(seconds: 1));
    gps.add(Lettura(Punto(45 + 40 / 111195, 9), velocitaMs: 25));
    expect(p.velocitaAdesso(), closeTo(90, 0.1));
    // Fermi e senza letture per cinque secondi: zero.
    adesso = adesso.add(const Duration(seconds: 5));
    expect(p.velocitaAdesso(), 0);
    p.dispose();
  });

  testWidgets('in guida la batteria è sempre in vista: partenza, adesso, arrivo e consumo', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[10]);
    await aspetta(tester);

    String testo(String chiave) => tester.widget<Text>(find.byKey(Key(chiave))).data!;
    expect(testo('batteria-partenza'), '90%');
    final stimata = int.parse(testo('batteria-ora').replaceAll('%', ''));
    final arrivo = int.parse(testo('batteria-arrivo').replaceAll('%', ''));
    expect(stimata, inExclusiveRange(arrivo, 90));
    expect(find.text('ora (stima)'), findsOneWidget);
    expect(double.parse(testo('consumo').replaceAll(',', '.')), inInclusiveRange(8, 35));

    // L'auto manda la batteria vera, più bassa del previsto: arrivo e consumo si adeguano.
    a.auto.arbitro.registra(
      StatoAuto(sorgente: TipoSorgente.homeAssistant, letto: DateTime.now(), batteria: stimata - 4.0),
    );
    await tester.runAsync(() => a.auto.cambiaModalita(a.auto.modalita));
    a.posizioni.add(punti[11]);
    await aspetta(tester);
    expect(find.text('auto · adesso'), findsOneWidget);
    expect(testo('batteria-ora'), '${stimata - 4}%');
    expect(int.parse(testo('batteria-arrivo').replaceAll('%', '')), inInclusiveRange(arrivo - 5, arrivo - 3));
    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();
  });

  testWidgets('la diagnosi di Android Auto dice cosa vede il telefono', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: const Scaffold(
          body: DiagnosiAuto(
            dati: {
              'servizio': true,
              'navigazione': true,
              'descrittore': true,
              'androidAuto': '15.2.1',
              'installatore': null,
              'android': '15',
              'telefono': 'samsung SM-S921B',
            },
          ),
        ),
      ),
    );
    expect(find.text('Registrato come app di navigazione'), findsOneWidget);
    expect(find.text('Versione 15.2.1'), findsOneWidget);
    expect(find.text('file APK (fuori dal Play Store)'), findsOneWidget);
  });

  testWidgets('il menu non è tagliato: anche su un telefono piccolo si arriva all\'ultima voce', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    // Un telefono piccolo, con la barra di navigazione in basso.
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 144);
    tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 144);
    await tester.pumpWidget(a.app());
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    for (final voce in [
      'La tua auto',
      'Ricarica',
      'Fonte dati auto',
      'Home Assistant',
      'Mappe offline',
      'Android Auto',
    ]) {
      await tester.scrollUntilVisible(find.text(voce), 60, scrollable: find.byType(Scrollable).last);
      final r = tester.getRect(find.text(voce));
      // Sopra la barra di navigazione, dentro lo schermo.
      expect(r.bottom, lessThanOrEqualTo(640 - 48), reason: voce);
    }
    await tester.tap(find.text('Android Auto'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Se gdanav non compare sull\'auto'), findsOneWidget);
  });

  testWidgets('in viaggio la batteria vera corregge il consumo e, se si scosta, le soste si ricalcolano', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    final primo = (a.viaggio.stato as ViaggioPronto).viaggio;
    final punti = primo.percorso.punti;
    final consumo = a.viaggio.consumo!;
    expect(consumo.imparato.kmOsservati, 0);

    Future<void> letturaVera(int i, double batteria) async {
      a.posizioni.add(punti[i]);
      await aspetta(tester);
      a.auto.arbitro.registra(
        StatoAuto(sorgente: TipoSorgente.homeAssistant, letto: DateTime.now(), batteria: batteria),
      );
      await tester.runAsync(() => a.auto.cambiaModalita(a.auto.modalita));
      await aspetta(tester, 80);
      await tester.pumpAndSettle();
    }

    // A 3 km la batteria è in linea col piano: nessun ricalcolo.
    await letturaVera(3, a.guida.batteriaOra!.valore.roundToDouble());
    expect(identical((a.viaggio.stato as ViaggioPronto).viaggio, primo), isTrue);

    // A 8 km l'auto dice 6 punti in meno del previsto: si impara e si ricalcola.
    final prevista = a.guida.batteriaOra!.valore;
    await letturaVera(8, (prevista - 6).roundToDouble());
    expect(consumo.imparato.kmOsservati, greaterThan(4));
    expect(consumo.imparato.fattore, greaterThan(1.1));
    expect(identical((a.viaggio.stato as ViaggioPronto).viaggio, primo), isFalse);
    expect(a.guida.attiva, isTrue);
    // Senza «Ricalcolo il percorso»: non si è sbagliata strada.
    expect(a.voce.frasi, isNot(contains('Ricalcolo il percorso.')));
    // Il consumo mostrato ora è quello misurato.
    expect(a.guida.consumoKwh100, greaterThan(0));
    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();
  });

  testWidgets('con il ricalcolo automatico spento, lo chiede; e «Ricalcola» si può premere sempre', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.cambiaOpzioni(const OpzioniPercorso(ricalcoloAutomatico: false)));
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    final primo = (a.viaggio.stato as ViaggioPronto).viaggio;
    final punti = primo.percorso.punti;

    Future<void> letturaVera(int i, double batteria) async {
      a.posizioni.add(punti[i]);
      await aspetta(tester);
      a.auto.arbitro.registra(
        StatoAuto(sorgente: TipoSorgente.homeAssistant, letto: DateTime.now(), batteria: batteria),
      );
      await tester.runAsync(() => a.auto.cambiaModalita(a.auto.modalita));
      await aspetta(tester, 80);
      await tester.pumpAndSettle();
    }

    await letturaVera(3, a.guida.batteriaOra!.valore.roundToDouble());
    await letturaVera(8, (a.guida.batteriaOra!.valore - 6).roundToDouble());
    // Non ricalcola da solo: chiede.
    expect(identical((a.viaggio.stato as ViaggioPronto).viaggio, primo), isTrue);
    expect(find.text('Consumi più del previsto: ricalcolo le soste?'), findsOneWidget);

    await tester.tap(find.text('Ricalcola'));
    await aspetta(tester, 80);
    await tester.pumpAndSettle();
    expect(identical((a.viaggio.stato as ViaggioPronto).viaggio, primo), isFalse);
    expect(find.textContaining('ricalcolo le soste?'), findsNothing);
    expect(a.voce.frasi, contains('Ricalcolo il viaggio.'));

    // Il bottone in basso: sempre.
    final secondo = (a.viaggio.stato as ViaggioPronto).viaggio;
    await tester.tap(find.byKey(const Key('ricalcola')));
    await aspetta(tester, 80);
    await tester.pumpAndSettle();
    expect(identical((a.viaggio.stato as ViaggioPronto).viaggio, secondo), isFalse);
    expect(a.guida.attiva, isTrue);
    await tester.tap(find.text('Fine'));
    await tester.pumpAndSettle();
  });
}
