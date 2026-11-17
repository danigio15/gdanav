// Gli avvisi di casa sopra la mappa in guida, e la musica. Nomi inventati.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/avvisi_di_casa_in_auto.dart';
import 'package:gdanav_app/componenti/avviso_di_casa.dart';
import 'package:gdanav_app/componenti/mini_lettore.dart';
import 'package:gdanav_app/gdanav_app.dart' show GdanavApp, NotificheNelNavigatoreSchermata;
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_casa_in_guida.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Una svolta fra 300 m e poi una rotonda: la manovra e il «Poi».
PercorsoCalcolato _strada() {
  final punti = [for (var i = 0; i <= 200; i++) Punto(42 + i * 0.0009, 12)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 50),
    ],
    manovre: const [
      Manovra(istruzione: 'Parti', lunghezzaM: 400, secondi: 30, inizio: 0, tipo: 1),
      Manovra(istruzione: 'Svolta a destra', lunghezzaM: 300, secondi: 25, inizio: 4, tipo: 10, strada: 'Via Roma'),
      Manovra(istruzione: 'Rotonda', lunghezzaM: 19000, secondi: 1400, inizio: 7, tipo: 26, strada: 'Corso Europa'),
      Manovra(istruzione: 'Sei arrivato', lunghezzaM: 0, secondi: 0, inizio: 200, tipo: 4),
    ],
    limiti: [for (var i = 0; i < 200; i++) 50],
  );
}

AvvisoDiCasa _campanello({String id = 'campanello'}) => AvvisoDiCasa(
  id: id,
  categoria: CategoriaAvvisoDiCasa.campanello,
  urgenza: UrgenzaAvvisoDiCasa.importante,
  titolo: 'Suonano al cancello',
  testo: 'Corriere al cancello',
  voce: 'Campanello di casa',
  azioni: const [
    AzioneAvvisoDiCasa('apri', 'Apri cancello', principale: true, domanda: 'Aprire il cancello?'),
    AzioneAvvisoDiCasa('ignora', 'Ignora'),
  ],
);

AvvisoDiCasa _lavatrice({String id = 'lavatrice', String titolo = 'Lavatrice finita'}) =>
    AvvisoDiCasa(id: id, categoria: CategoriaAvvisoDiCasa.elettrodomestici, sotto: 'lavatrice', titolo: titolo);

AvvisoDiCasa _fumo() => AvvisoDiCasa(
  id: 'fumo',
  categoria: CategoriaAvvisoDiCasa.sicurezza,
  sotto: 'fumo',
  titolo: 'Fumo in cucina',
  urgenza: UrgenzaAvvisoDiCasa.urgente,
);

/// L'antifurto che suona: urgente, a voce, con due tasti che fanno qualcosa.
AvvisoDiCasa _allarme() => AvvisoDiCasa(
  id: 'allarme',
  categoria: CategoriaAvvisoDiCasa.antifurto,
  sotto: 'allarme',
  titolo: 'Allarme scattato',
  urgenza: UrgenzaAvvisoDiCasa.urgente,
  voce: 'Allarme scattato',
  azioni: const [
    AzioneAvvisoDiCasa('disinserisci', 'Disinserisci', principale: true, domanda: 'Disinserire l\'antifurto?'),
    AzioneAvvisoDiCasa('sirena', 'Spegni la sirena'),
  ],
);

Widget _scheda(CodaAvvisiDiCasa coda, {bool inMovimento = true}) => MaterialApp(
  theme: temaGdanav(Brightness.light),
  home: Scaffold(
    body: Column(
      children: [SchedaAvvisoDiCasa(coda: coda, inMovimento: inMovimento)],
    ),
  ),
);

/// Una notifica come la manda il ponte (`ponte/src/notifiche.js`).
Map<String, Object?> _busta(
  String tipo,
  String titolo, {
  String testo = '',
  String urg = 'normale',
  String? entita,
  List<Map<String, Object?>> azioni = const [],
}) => {
  'v': 1,
  'id': '$tipo-$titolo',
  'tipo': tipo,
  'cat': 'casa',
  'urg': urg,
  'titolo': titolo,
  'testo': testo,
  'entita': ?entita,
  'azioni': azioni,
};

void main() {
  group('dalla notifica di GdAHome', () {
    test('la lavatrice finita: elettrodomestici, info, senza voce', () {
      final a = AvvisoDiCasa.daNotifica(
        _busta('elettrodomestici', '🧺 Lavatrice finita', testo: '1 h 52 min · 0,9 kWh', entita: 'sensor.lavatrice'),
        casa: 'Villa Gialla',
      )!;
      expect(a.titolo, 'Lavatrice finita');
      expect(a.categoria, CategoriaAvvisoDiCasa.elettrodomestici);
      expect(a.sotto, 'lavatrice');
      expect(a.urgenza, UrgenzaAvvisoDiCasa.info);
      expect(a.voce, isNull);
      expect(a.casa, 'Villa Gialla');
      expect(aspettoDi(a).icona, Icons.local_laundry_service_rounded);
    });

    test('forno, asciugatrice e lavastoviglie hanno la loro icona', () {
      for (final (parola, sotto) in [
        ('Forno', 'forno'),
        ('Asciugatrice', 'asciugatrice'),
        ('Lavastoviglie', 'lavastoviglie'),
      ]) {
        final a = AvvisoDiCasa.daNotifica(_busta('elettrodomestici', '$parola finita'))!;
        expect(a.sotto, sotto, reason: parola);
      }
    });

    test('l\'antifurto inserito è info; «Disinserisci» chiede prima', () {
      final a = AvvisoDiCasa.daNotifica(
        _busta(
          'inserimenti',
          '🛡️ Antifurto inserito',
          testo: 'Fuori casa · da Marta',
          azioni: [
            {'id': 'disinserisci', 'etichetta': 'Disinserisci'},
            {'id': 'guarda', 'etichetta': 'Guarda', 'apre': true},
          ],
        ),
      )!;
      expect(a.categoria, CategoriaAvvisoDiCasa.antifurto);
      expect(a.sotto, 'inserito');
      expect(a.urgenza, UrgenzaAvvisoDiCasa.info);
      expect(a.azioni.first.domanda, 'Disinserire l\'antifurto?');
      expect(a.azioni.first.principale, isTrue);
      // «Guarda» apre l'app: in movimento non c'è.
      expect(a.tasti(inMovimento: true).map((x) => x.id), ['disinserisci']);
      expect(a.tasti(inMovimento: false).map((x) => x.id), ['disinserisci', 'guarda']);
    });

    test('l\'allarme che suona e il fumo sono urgenti', () {
      final allarme = AvvisoDiCasa.daNotifica(_busta('antifurto', '🚨 Allarme in casa', urg: 'urgente'))!;
      expect(allarme.urgente, isTrue);
      expect(allarme.sotto, 'allarme');
      final acqua = AvvisoDiCasa.daNotifica(
        _busta('allarmi', 'Allagamento in bagno', urg: 'urgente', entita: 'binary_sensor.perdita_bagno'),
      )!;
      expect(acqua.categoria, CategoriaAvvisoDiCasa.sicurezza);
      expect(acqua.sotto, 'acqua');
      expect(acqua.urgente, isTrue);
      expect(acqua.voce, 'Allagamento in bagno');
    });

    test('il campanello in guida è importante, non urgente', () {
      final a = AvvisoDiCasa.daNotifica(
        _busta(
          'campanello',
          'Suonano al cancello',
          urg: 'urgente',
          azioni: [
            {'id': 'apri', 'etichetta': 'Apri cancello'},
            {'id': 'ignora', 'etichetta': 'Ignora'},
          ],
        ),
      )!;
      expect(a.urgenza, UrgenzaAvvisoDiCasa.importante);
      expect(a.azioni.first.domanda, 'Aprire il cancello?');
      expect(a.azioni.last.principale, isFalse);
    });

    test('dalle parole: auto, persone, clima, meteo, aggiornamenti, altre', () {
      AvvisoDiCasa da(String tipo, String titolo, [String? entita]) =>
          AvvisoDiCasa.daNotifica(_busta(tipo, titolo, entita: entita))!;
      expect(da('ha_notify', 'Auto carica all\'80%').categoria, CategoriaAvvisoDiCasa.energia);
      expect(da('ha_notify', 'Auto carica all\'80%').sotto, 'auto');
      expect(da('suggerimenti', 'Il fotovoltaico produce 4 kW').sotto, 'sole');
      expect(da('blackout', 'Manca la corrente').categoria, CategoriaAvvisoDiCasa.energia);
      expect(da('arrivi', 'Marta è arrivata a casa').categoria, CategoriaAvvisoDiCasa.persone);
      expect(da('arrivi', 'Luca è uscito').sotto, 'uscita');
      expect(da('personalizzata', 'Termostato: 16 °C in sala').categoria, CategoriaAvvisoDiCasa.clima);
      expect(da('ha_notify', 'Allerta meteo arancione').categoria, CategoriaAvvisoDiCasa.meteo);
      expect(da('ha_notify', 'Allerta meteo arancione').urgenza, UrgenzaAvvisoDiCasa.importante);
      expect(da('aggiorna_app', 'Aggiorna GdAHome').categoria, CategoriaAvvisoDiCasa.aggiornamenti);
      expect(da('aperture', 'Cucina: la finestra è ancora aperta').sotto, 'finestra');
      expect(da('aperture', 'Cucina: la finestra è ancora aperta').urgenza, UrgenzaAvvisoDiCasa.importante);
      expect(da('ha_notify', 'Il gatto ha mangiato').categoria, CategoriaAvvisoDiCasa.altre);
      // «importante» non è una porta.
      expect(da('ha_notify', 'Promemoria importante').categoria, CategoriaAvvisoDiCasa.altre);
    });

    test('un tasto col codice si fa da fermi', () {
      final a = AvvisoDiCasa.daNotifica(
        _busta(
          'uscito',
          'Sei uscito: l\'antifurto è spento',
          azioni: [
            {'id': 'inserisci', 'etichetta': 'Inserisci', 'pin': true},
            {'id': 'piu-tardi', 'etichetta': 'Più tardi'},
          ],
        ),
      )!;
      expect(a.tasti(inMovimento: true).map((x) => x.id), ['piu-tardi']);
      expect(a.azioni.first.domanda, 'Inserire l\'antifurto?');
    });

    test('senza titolo, o un promemoria dei viaggi: niente', () {
      expect(AvvisoDiCasa.daNotifica(_busta('elettrodomestici', '')), isNull);
      expect(AvvisoDiCasa.daNotifica(_busta('viaggi', 'Parti fra 10 minuti')), isNull);
    });
  });

  group('quali si mostrano', () {
    test('di serie tutte', () {
      const s = SceltaAvvisiDiCasa();
      expect(s.mostra(_lavatrice()), isTrue);
      expect(s.mostra(_campanello()), isTrue);
    });

    test('a scelta per categoria; gli urgenti passano sempre', () {
      final s = const SceltaAvvisiDiCasa().conCategoria(CategoriaAvvisoDiCasa.elettrodomestici, false);
      expect(s.modo, NotificheNelNavigatore.scelte);
      expect(s.mostra(_lavatrice()), isFalse);
      expect(s.mostra(_campanello()), isTrue);
      final senzaSicurezza = s.conCategoria(CategoriaAvvisoDiCasa.sicurezza, false);
      expect(senzaSicurezza.mostra(_fumo()), isTrue);
      expect(SceltaAvvisiDiCasa.leggi(s.inJson()), s);
    });

    test('«nessuna» ferma tutto', () {
      expect(SceltaAvvisiDiCasa.nessuna.mostra(_fumo()), isFalse);
    });

    test('al più due tasti', () {
      final a = AvvisoDiCasa(
        id: 'x',
        categoria: CategoriaAvvisoDiCasa.antifurto,
        titolo: 'Allarme',
        azioni: const [AzioneAvvisoDiCasa('a', 'A'), AzioneAvvisoDiCasa('b', 'B'), AzioneAvvisoDiCasa('c', 'C')],
      );
      expect(a.tasti(inMovimento: false).map((x) => x.id), ['a', 'b']);
    });
  });

  group('la coda', () {
    testWidgets('una info se ne va da sola, un\'urgente resta', (tester) async {
      final coda = CodaAvvisiDiCasa(durata: const Duration(seconds: 9));
      addTearDown(coda.dispose);
      await tester.pumpWidget(_scheda(coda));
      coda.aggiungi(_lavatrice());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Lavatrice finita'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();
      expect(find.text('Lavatrice finita'), findsNothing);

      coda.aggiungi(_fumo());
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 5));
      expect(find.text('Fumo in cucina'), findsOneWidget);
      expect(find.textContaining('URGENTE'), findsOneWidget);
      // Senza tasti: si chiude con la X.
      await tester.tap(find.byKey(const Key('avviso-casa-chiudi')));
      await tester.pumpAndSettle();
      expect(find.text('Fumo in cucina'), findsNothing);
    });

    testWidgets('un importante resta il doppio', (tester) async {
      final coda = CodaAvvisiDiCasa(durata: const Duration(seconds: 8));
      addTearDown(coda.dispose);
      await tester.pumpWidget(_scheda(coda));
      coda.aggiungi(_campanello());
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(coda.attuale?.id, 'campanello');
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(coda.attuale, isNull);
    });

    testWidgets('l\'urgente passa davanti, le altre aspettano', (tester) async {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      await tester.pumpWidget(_scheda(coda));
      coda
        ..aggiungi(_lavatrice())
        ..aggiungi(_campanello())
        ..aggiungi(_fumo());
      await tester.pumpAndSettle();
      expect(coda.attuale?.id, 'fumo');
      expect(coda.inCoda, 2);
      expect(find.text('+2'), findsOneWidget);
      coda.chiudi();
      // Torna quella che era in vista prima, poi il campanello.
      expect(coda.attuale?.id, 'lavatrice');
      coda.chiudi();
      expect(coda.attuale?.id, 'campanello');
      coda.chiudi();
      expect(coda.attuale, isNull);
      await tester.pumpAndSettle();
    });

    test('lo stesso avviso non si ripete', () {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      coda
        ..aggiungi(_campanello())
        ..aggiungi(_lavatrice())
        ..aggiungi(_lavatrice())
        ..aggiungi(_campanello());
      expect(coda.attuale?.id, 'campanello');
      expect(coda.inCoda, 1);
    });

    test('con la categoria spenta la lavatrice non entra', () {
      final coda = CodaAvvisiDiCasa(
        scelta: const SceltaAvvisiDiCasa().conCategoria(CategoriaAvvisoDiCasa.elettrodomestici, false),
      );
      addTearDown(coda.dispose);
      coda.aggiungi(_lavatrice());
      expect(coda.attuale, isNull);
    });

    test('la voce dice la frase breve', () {
      final frasi = <String>[];
      final coda = CodaAvvisiDiCasa(onVoce: frasi.add);
      addTearDown(coda.dispose);
      coda.aggiungi(_campanello());
      expect(frasi, ['Campanello di casa']);
    });

    test('un urgente messo da parte fa passare gli altri, e torna quando non c\'è altro', () {
      final frasi = <String>[];
      final coda = CodaAvvisiDiCasa(onVoce: frasi.add);
      addTearDown(coda.dispose);
      coda
        ..aggiungi(_allarme())
        ..aggiungi(_campanello());
      expect(coda.attuale?.id, 'allarme');
      expect(frasi, ['Allarme scattato']);
      coda.mettiDaParte('allarme');
      // Tocca al campanello; l'allarme aspetta dietro a tutti.
      expect(coda.attuale?.id, 'campanello');
      expect(coda.daParte('allarme'), isTrue);
      expect(coda.inCoda, 1);
      expect(coda.tempo, isNotNull, reason: 'il campanello ha il suo tempo: la coda cammina');
      coda.chiudi();
      // Non c'è altro: torna in vista (sul telefono), senza ridirlo a voce.
      expect(coda.attuale?.id, 'allarme');
      expect(coda.tempo, isNull);
      expect(frasi, ['Allarme scattato', 'Campanello di casa']);
      // Uno che arriva dopo gli passa davanti.
      coda.aggiungi(_lavatrice());
      expect(coda.attuale?.id, 'lavatrice');
      coda.chiudi();
      expect(coda.attuale?.id, 'allarme');
      // Rimandato dalla casa (scatta di nuovo): torna come nuovo.
      coda.aggiungi(_allarme());
      expect(coda.daParte('allarme'), isFalse);
      expect(coda.attuale?.id, 'allarme');
      coda.chiudi();
      expect(coda.attuale, isNull);
      // Chi non è un urgente in coda non si mette da parte.
      coda.aggiungi(_lavatrice());
      coda.mettiDaParte('lavatrice');
      expect(coda.daParte('lavatrice'), isFalse);
      expect(coda.attuale?.id, 'lavatrice');
    });

    test('un urgente che nessuno tocca non resta per sempre', () {
      var ora = DateTime(2026, 11, 17, 18);
      final coda = CodaAvvisiDiCasa(orologio: () => ora);
      addTearDown(coda.dispose);
      coda
        ..aggiungi(_fumo())
        ..aggiungi(_allarme());
      coda.mettiDaParte('fumo');
      ora = ora.add(const Duration(minutes: 14));
      coda.scartaVecchi();
      expect(coda.attuale?.id, 'allarme');
      expect(coda.daParte('fumo'), isTrue);
      // Passato il quarto d'ora se ne vanno, anche quello messo da parte.
      ora = ora.add(const Duration(minutes: 2));
      coda.scartaVecchi();
      expect(coda.attuale, isNull);
      expect(coda.daParte('fumo'), isFalse);
      // E all'arrivo di un altro, quello vecchio non gli resta davanti.
      coda.aggiungi(_fumo());
      ora = ora.add(const Duration(minutes: 20));
      coda.aggiungi(_allarme());
      expect(coda.attuale?.id, 'allarme');
      expect(coda.inCoda, 0);
    });

    testWidgets('tante insieme diventano un gruppo, che si apre solo da fermi', (tester) async {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      await tester.pumpWidget(_scheda(coda));
      coda
        ..aggiungi(_lavatrice())
        ..aggiungi(_lavatrice(id: 'forno', titolo: 'Forno pronto'))
        ..aggiungi(_lavatrice(id: 'auto', titolo: 'Auto carica'));
      // Non pumpAndSettle: la barra del tempo correrebbe fino in fondo.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(coda.attuale, isNull);
      expect(coda.gruppo, hasLength(3));
      expect(find.text('3 notifiche di casa'), findsOneWidget);
      expect(find.text('Mostra'), findsNothing);
      expect(find.textContaining('le vedi da fermo'), findsOneWidget);

      // Fermi: «Mostra» apre l'elenco, e una riga si toglie da sola.
      await tester.pumpWidget(_scheda(coda, inMovimento: false));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Mostra'));
      await tester.pumpAndSettle();
      expect(find.text('Forno pronto'), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      expect(coda.aperto, isTrue);
      await tester.tap(find.byKey(const Key('avviso-casa-togli-forno')));
      await tester.pump();
      // In due non è più un gruppo: torna la prima.
      expect(coda.attuale?.id, 'lavatrice');

      // Un urgente passa davanti anche al gruppo.
      coda
        ..aggiungi(_lavatrice(id: 'forno', titolo: 'Forno pronto'))
        ..aggiungi(_fumo());
      expect(coda.attuale?.id, 'fumo');
      coda.chiudi();
      expect(coda.gruppo, hasLength(3));
      coda.chiudi();
      expect(coda.gruppo, isNull);
      expect(coda.attuale, isNull);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('«Apri cancello» chiede prima, con un tocco solo', (tester) async {
    final fatte = <String>[];
    final coda = CodaAvvisiDiCasa(onAzione: (_, az) => fatte.add(az.id));
    addTearDown(coda.dispose);
    await tester.pumpWidget(_scheda(coda));
    coda.aggiungi(_campanello());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Suonano al cancello'), findsOneWidget);

    await tester.tap(find.text('Apri cancello'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Aprire il cancello?'), findsOneWidget);
    expect(fatte, isEmpty);
    // Mentre si decide non scade.
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Aprire il cancello?'), findsOneWidget);

    await tester.tap(find.text('No'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Suonano al cancello'), findsOneWidget);

    await tester.tap(find.text('Apri cancello'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Sì, apri cancello'));
    await tester.pumpAndSettle();
    expect(fatte, ['apri']);
    expect(find.byKey(const Key('avviso-casa')), findsNothing);
  });

  testWidgets('«Ignora» la toglie e basta', (tester) async {
    final fatte = <String>[];
    final coda = CodaAvvisiDiCasa(onAzione: (_, az) => fatte.add(az.id));
    addTearDown(coda.dispose);
    await tester.pumpWidget(_scheda(coda));
    coda.aggiungi(_campanello());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Ignora'));
    await tester.pumpAndSettle();
    expect(fatte, ['ignora']);
    expect(find.byKey(const Key('avviso-casa')), findsNothing);
  });

  testWidgets('i tasti sono grandi: almeno 56 di altezza', (tester) async {
    final coda = CodaAvvisiDiCasa();
    addTearDown(coda.dispose);
    await tester.pumpWidget(_scheda(coda));
    coda.aggiungi(_campanello());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Apri cancello')).height, greaterThanOrEqualTo(56));
    expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Ignora')).height, greaterThanOrEqualTo(56));
    coda.chiudi();
    await tester.pumpAndSettle();
  });

  group('il mini-lettore', () {
    const brani = [
      BranoInAscolto(titolo: 'Strade di notte', artista: 'Le Lucciole'),
      BranoInAscolto(titolo: 'Vento a favore', artista: 'Orsa Minore'),
    ];
    const preferite = [PlaylistPreferita(id: 'viaggio', nome: 'Viaggio'), PlaylistPreferita(id: 'mix', nome: 'Mix 1')];

    Widget lettore(LettoreFinto l, {bool inMovimento = true}) => MaterialApp(
      theme: temaGdanav(Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MiniLettore(lettore: l, inMovimento: inMovimento),
        ),
      ),
    );

    testWidgets('⏮ ⏯ ⏭ comandano il lettore', (tester) async {
      final l = LettoreFinto(brani: brani, preferite: preferite);
      addTearDown(l.dispose);
      await tester.pumpWidget(lettore(l));
      expect(find.text('Strade di notte'), findsOneWidget);
      expect(find.text('Le Lucciole'), findsOneWidget);
      expect(find.text('Spotify'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lettore-successivo')));
      await tester.pump();
      expect(find.text('Vento a favore'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lettore-play')));
      await tester.tap(find.byKey(const Key('lettore-precedente')));
      await tester.pump();
      expect(l.comandi, ['successivo', 'playPausa', 'precedente']);
      expect(l.suona, isFalse);
      // Tasti grandi anche qui.
      expect(tester.getSize(find.byKey(const Key('lettore-play'))).height, greaterThanOrEqualTo(48));
    });

    testWidgets('le playlist solo da fermi', (tester) async {
      final l = LettoreFinto(brani: brani, preferite: preferite);
      addTearDown(l.dispose);
      await tester.pumpWidget(lettore(l));
      expect(find.text('Viaggio'), findsNothing);
      await tester.pumpWidget(lettore(l, inMovimento: false));
      await tester.tap(find.text('Viaggio'));
      await tester.pump();
      expect(l.comandi, ['riprendi:viaggio']);
    });

    testWidgets('si richiude in un bottone tondo e si riapre', (tester) async {
      final l = LettoreFinto(brani: brani);
      addTearDown(l.dispose);
      await tester.pumpWidget(lettore(l));
      await tester.tap(find.byKey(const Key('lettore-richiudi')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mini-lettore')), findsNothing);
      await tester.tap(find.byKey(const Key('lettore-chiuso')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mini-lettore')), findsOneWidget);
    });
  });

  testWidgets('la pagina «Casa e musica in guida»: i due interruttori e le categorie', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final musica = LettoreFinto(permesso: false);
    final g = GestoreCasaInGuida(archivio: Archivio(), coda: CodaAvvisiDiCasa(), lettore: musica);
    addTearDown(g.dispose);
    await tester.runAsync(g.carica);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: NotificheNelNavigatoreSchermata(gestore: g),
      ),
    );
    // Di serie tutto acceso.
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('avvisi-di-casa'))).value, isTrue);
    await tester.tap(find.byKey(const Key('categoria-elettrodomestici')));
    await tester.pump();
    expect(g.scelta.modo, NotificheNelNavigatore.scelte);
    expect(g.scelta.spente, {CategoriaAvvisoDiCasa.elettrodomestici});
    // Spento l'interruttore: niente categorie; riacceso, tornano quelle scelte.
    await tester.tap(find.byKey(const Key('avvisi-di-casa')));
    await tester.pump();
    expect(g.avvisiAccesi, isFalse);
    expect(find.byKey(const Key('categoria-elettrodomestici')), findsNothing);
    await tester.tap(find.byKey(const Key('avvisi-di-casa')));
    await tester.pump();
    expect(g.scelta.spente, {CategoriaAvvisoDiCasa.elettrodomestici});
    // La musica: senza permesso, la spiegazione e «Consenti».
    await tester.scrollUntilVisible(find.byKey(const Key('spiegazione-musica')), 200);
    expect(find.textContaining('Accesso alle notifiche'), findsOneWidget);
    await tester.tap(find.text('Consenti'));
    await tester.pump();
    expect(musica.comandi, contains('permesso'));
    expect(find.byKey(const Key('spiegazione-musica')), findsNothing);
    await tester.scrollUntilVisible(find.byKey(const Key('musica-nel-navigatore')), 200);
    await tester.tap(find.byKey(const Key('musica-nel-navigatore')));
    await tester.pump();
    expect(g.musica, isFalse);
    expect(musica.acceso, isFalse);
    // Le scelte restano: un gestore nuovo le rilegge.
    final altro = GestoreCasaInGuida(archivio: Archivio(), coda: CodaAvvisiDiCasa());
    addTearDown(altro.dispose);
    await tester.runAsync(altro.carica);
    expect(altro.scelta.spente, {CategoriaAvvisoDiCasa.elettrodomestici});
    expect(altro.musica, isFalse);
    musica.dispose();
  });

  testWidgets('in guida sta sotto la manovra e il «Poi»; la musica sopra la barra dell\'arrivo', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(
      tester,
      km: 20,
      costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (_) async => _strada(),
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      ),
    );
    final coda = CodaAvvisiDiCasa();
    final musica = LettoreFinto(
      brani: const [BranoInAscolto(titolo: 'Strade di notte', artista: 'Le Lucciole')],
    );
    addTearDown(musica.dispose);
    final casa = GestoreCasaInGuida(archivio: a.archivio, coda: coda, lettore: musica);
    addTearDown(casa.dispose);
    await tester.pumpWidget(
      GdanavApp(
        posizione: a.posizione,
        archivio: a.archivio,
        auto: a.auto,
        viaggio: a.viaggio,
        guida: a.guida,
        segnalazioni: a.segnalazioni,
        casaInGuida: casa,
        mappa: (context, c) => const ColoredBox(color: Colors.grey),
      ),
    );
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Casa', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    a.posizioni.add(const Punto(42.0009, 12));
    await tester.pump(const Duration(milliseconds: 200));
    coda.aggiungi(_campanello());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final scheda = tester.getRect(find.byKey(const Key('avviso-casa')));
    final manovra = tester.getRect(find.text('Via Roma'));
    final poi = tester.getRect(find.text('Corso Europa'));
    expect(scheda.top, greaterThan(manovra.bottom));
    expect(scheda.top, greaterThan(poi.bottom));
    final lettore = tester.getRect(find.byKey(const Key('mini-lettore')));
    final fine = tester.getRect(find.text('Fine'));
    expect(lettore.top, greaterThan(scheda.bottom));
    expect(lettore.bottom, lessThan(fine.top));
    coda.chiudi();
    await tester.runAsync(a.guida.ferma);
    await tester.pumpWidget(const SizedBox());
  });

  group('il gestore della casa in guida', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('le notifiche passano solo in guida, e finita la guida se ne vanno', () async {
      var inGuida = false;
      final guida = ChangeNotifier();
      final notifiche = StreamController<Map<String, Object?>>();
      final g = GestoreCasaInGuida(
        archivio: Archivio(),
        notifiche: notifiche.stream,
        inGuida: () => inGuida,
        guida: guida,
      );
      addTearDown(g.dispose);
      await g.carica();
      notifiche.add(_busta('elettrodomestici', 'Lavatrice finita'));
      await Future<void>.delayed(Duration.zero);
      expect(g.coda!.attuale, isNull, reason: 'fuori dalla guida resta sul telefono');
      inGuida = true;
      notifiche.add({..._busta('elettrodomestici', 'Lavatrice finita'), '_casa': 'Villa Gialla'});
      await Future<void>.delayed(Duration.zero);
      expect(g.coda!.attuale?.titolo, 'Lavatrice finita');
      expect(g.coda!.attuale?.casa, 'Villa Gialla');
      inGuida = false;
      guida.notifyListeners();
      expect(g.coda!.attuale, isNull);
      await notifiche.close();
    });

    test('con gli avvisi spenti non entra niente, nemmeno il fumo', () async {
      final g = GestoreCasaInGuida(archivio: Archivio(), coda: CodaAvvisiDiCasa());
      addTearDown(g.dispose);
      await g.carica();
      await g.accendiAvvisi(false);
      g.arrivata(_busta('allarmi', 'Fumo in cucina', urg: 'urgente'));
      expect(g.coda!.attuale, isNull);
      await g.accendiAvvisi(true);
      g.arrivata(_busta('allarmi', 'Fumo in cucina', urg: 'urgente'));
      expect(g.coda!.attuale?.urgente, isTrue);
    });

    test('la categoria spenta filtra, gli urgenti passano lo stesso', () async {
      final g = GestoreCasaInGuida(archivio: Archivio(), coda: CodaAvvisiDiCasa());
      addTearDown(g.dispose);
      await g.carica();
      await g.cambiaScelta(g.scelta.conCategoria(CategoriaAvvisoDiCasa.elettrodomestici, false));
      await g.cambiaScelta(g.scelta.conCategoria(CategoriaAvvisoDiCasa.antifurto, false));
      g.arrivata(_busta('elettrodomestici', 'Lavatrice finita'));
      expect(g.coda!.attuale, isNull);
      g.arrivata(_busta('antifurto', 'Allarme in casa', urg: 'urgente'));
      expect(g.coda!.attuale?.titolo, 'Allarme in casa');
    });

    test('il tasto torna a chi ospita con la notifica com\'era', () async {
      final premuti = <(Map<String, Object?>, String)>[];
      final g = GestoreCasaInGuida(
        archivio: Archivio(),
        coda: CodaAvvisiDiCasa(),
        onAzione: (n, t) => premuti.add((n, t)),
      );
      addTearDown(g.dispose);
      await g.carica();
      final busta = {
        ..._busta(
          'inserimenti',
          'Antifurto inserito',
          azioni: [
            {'id': 'disinserisci', 'etichetta': 'Disinserisci'},
          ],
        ),
        '_casa_id': 'casa-1',
      };
      g.arrivata(busta);
      final c = g.coda!;
      c.premi(c.attuale!.azioni.first);
      // Prima la domanda: niente è partito.
      expect(premuti, isEmpty);
      expect(c.daConfermare?.id, 'disinserisci');
      c.premi(c.daConfermare!);
      expect(premuti.single.$2, 'disinserisci');
      expect(premuti.single.$1['_casa_id'], 'casa-1');
    });

    test('riacceso lo schermo dell\'auto, l\'urgente del viaggio di prima non torna', () async {
      var ora = DateTime(2026, 11, 17, 18);
      final g = GestoreCasaInGuida(
        archivio: Archivio(),
        coda: CodaAvvisiDiCasa(orologio: () => ora),
        inGuida: () => false,
      );
      addTearDown(g.dispose);
      await g.carica();
      // In auto, con la mappa del telefono davanti: scatta l'allarme.
      g.mappaInVista(true);
      g.schermoDellAuto(true);
      g.arrivata(_busta('antifurto', 'Allarme in casa', urg: 'urgente'));
      expect(g.coda!.attuale?.urgente, isTrue);
      // Scesi dall'auto col telefono ancora sulla mappa: lì resta.
      g.schermoDellAuto(false);
      expect(g.coda!.attuale, isNotNull);
      // Il viaggio dopo: quello vecchio non si ripresenta sull'auto.
      ora = ora.add(const Duration(minutes: 40));
      g.schermoDellAuto(true);
      expect(g.coda!.attuale, isNull);
      // E quello arrivato solo per l'auto se ne va con lei.
      g.mappaInVista(false);
      g.arrivata(_busta('antifurto', 'Allarme in casa', urg: 'urgente'));
      expect(g.coda!.attuale, isNotNull);
      g.schermoDellAuto(false);
      expect(g.coda!.attuale, isNull);
    });

    test('la musica: spenta non si accende, l\'invito una volta sola', () async {
      final l = LettoreFinto(permesso: false);
      addTearDown(l.dispose);
      final g = GestoreCasaInGuida(archivio: Archivio(), lettore: l);
      addTearDown(g.dispose);
      await g.carica();
      expect(l.acceso, isTrue);
      expect(g.coda, isNull, reason: 'GdANav da sola: niente avvisi di casa');
      expect(g.invitoDaMostrare, isTrue);
      expect(l.invitiVisti, 0);
      g.segnaInvitoVisto();
      expect(g.invitoDaMostrare, isFalse);
      // «Non ora» arriva anche al lato nativo: l'auto non insiste.
      expect(l.invitiVisti, 1);
      await g.cambiaMusica(false);
      expect(l.acceso, isFalse);
      expect(g.lettoreInGuida, isNull);
      // Riaperto: l'invito non torna, la musica resta spenta.
      final dopo = GestoreCasaInGuida(archivio: Archivio(), lettore: l);
      addTearDown(dopo.dispose);
      await dopo.carica();
      expect(l.invitiVisti, 2, reason: 'riaperta l\'app lo si ridice: il lato nativo può averlo perso');
      expect(dopo.musica, isFalse);
      await dopo.cambiaMusica(true);
      expect(dopo.invitoDaMostrare, isFalse);
    });
  });

  group('sullo schermo dell\'auto', () {
    (AvvisiDiCasaInAuto, List<Map<String, Object?>>) auto(
      CodaAvvisiDiCasa coda, {
      Future<Uint8List> Function(Color, IconData)? disegna,
    }) {
      final mandati = <Map<String, Object?>>[];
      final a = AvvisiDiCasaInAuto(coda, (metodo, dati) {
        // Solo `avviso_casa` (un `expect` qui, mentre il tempo finto gira,
        // la prova non lo regge: si guarda dopo).
        if (metodo == 'avviso_casa') mandati.add(dati);
      }, disegna: disegna);
      return (a, mandati);
    }

    test('l\'urgente che l\'auto toglie da sola non tiene fermi quelli dopo', () {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      final (a, _) = auto(coda);
      coda
        ..aggiungi(_fumo())
        ..aggiungi(_campanello());
      expect(a.adesso()['id'], 'fumo');
      // Il tasto finto di un avviso che non è quello in vista non vale.
      a.tasto('lavatrice', AvvisiDiCasaInAuto.scaduto);
      expect(a.adesso()['id'], 'fumo');
      // Dieci minuti senza un tocco: l'auto lo toglie e lo dice.
      a.tasto('fumo', AvvisiDiCasaInAuto.scaduto, conferma: false);
      expect(a.adesso()['id'], 'campanello', reason: 'sull\'auto passa quello dopo');
      expect(coda.daParte('fumo'), isTrue, reason: 'sul telefono resta');
      a.tasto('campanello', 'ignora');
      // Non c'è altro: sul telefono torna il fumo, sull'auto no.
      expect(coda.attuale?.id, 'fumo');
      expect(a.adesso(), isEmpty);
      // Detto due volte non cambia niente.
      a.tasto('fumo', AvvisiDiCasaInAuto.scaduto);
      expect(coda.attuale?.id, 'fumo');
    });

    test('la domanda lasciata lì torna all\'avviso; chi ha un tempo suo resta com\'è', () {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      final (a, _) = auto(coda);
      coda.aggiungi(_campanello());
      a.tasto('campanello', 'apri');
      expect(a.adesso()['conferma'], isTrue);
      // L'auto parla dell'avviso di prima, non della domanda: niente.
      a.tasto('campanello', AvvisiDiCasaInAuto.scaduto, conferma: false);
      expect(coda.daConfermare, isNotNull);
      // La domanda senza risposta: è un «No».
      a.tasto('campanello', AvvisiDiCasaInAuto.scaduto, conferma: true);
      expect(coda.daConfermare, isNull);
      expect(a.adesso()['conferma'], isFalse);
      expect(a.adesso()['secondi'], 16);
      // Il campanello ha il suo tempo: tolto dall'auto, dal telefono no.
      a.tasto('campanello', AvvisiDiCasaInAuto.scaduto);
      expect(coda.attuale?.id, 'campanello');
      expect(coda.daParte('campanello'), isFalse);
      expect(a.adesso()['id'], 'campanello');
    });

    test('un urgente ha sempre un modo di chiuderlo: il primo tasto, e «Chiudi»', () {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      final (a, _) = auto(coda);
      coda.aggiungi(_allarme());
      List<Object?> tasti() => [for (final t in a.adesso()['tasti'] as List) (t as Map)['id']];
      expect(tasti(), ['disinserisci', AvvisiDiCasaInAuto.chiudi]);
      a.tasto('allarme', AvvisiDiCasaInAuto.chiudi);
      expect(coda.attuale, isNull);
      // Con «Ignora» fra i due restano tutti e due: chiude lui.
      coda.aggiungi(
        AvvisoDiCasa(
          id: 'fumo-2',
          categoria: CategoriaAvvisoDiCasa.sicurezza,
          urgenza: UrgenzaAvvisoDiCasa.urgente,
          titolo: 'Fumo in cucina',
          azioni: const [
            AzioneAvvisoDiCasa('chiama', 'Chiama casa', principale: true),
            AzioneAvvisoDiCasa('ignora', 'Ignora'),
          ],
        ),
      );
      expect(tasti(), ['chiama', 'ignora']);
      // E chi se ne va da solo tiene i suoi due tasti.
      coda
        ..chiudi()
        ..aggiungi(
          AvvisoDiCasa(
            id: 'auto',
            categoria: CategoriaAvvisoDiCasa.energia,
            titolo: 'Auto carica',
            azioni: const [
              AzioneAvvisoDiCasa('stacca', 'Ferma la ricarica'),
              AzioneAvvisoDiCasa('clima', 'Accendi il clima'),
            ],
          ),
        );
      expect(tasti(), ['stacca', 'clima']);
    });

    testWidgets('il gruppo che cresce si rimanda; riacceso lo schermo, anche lo stesso', (tester) async {
      var ora = DateTime(2026, 11, 17, 18);
      final coda = CodaAvvisiDiCasa(orologio: () => ora);
      final (a, mandati) = auto(coda, disegna: (_, _) async => Uint8List.fromList([1, 2, 3]));
      a.avvia();
      coda
        ..aggiungi(_lavatrice())
        ..aggiungi(_lavatrice(id: 'forno', titolo: 'Forno pronto'))
        ..aggiungi(_lavatrice(id: 'auto', titolo: 'Auto carica'));
      await tester.pump();
      expect(mandati.last['titolo'], '3 notifiche di casa');
      expect(mandati.last['secondi'], 16);
      await tester.pump(const Duration(seconds: 5));
      ora = ora.add(const Duration(seconds: 5));
      // Ne arriva una quarta: stesso id («gruppo»), titolo e testo nuovi.
      coda.aggiungi(_lavatrice(id: 'lavastoviglie', titolo: 'Lavastoviglie finita'));
      await tester.pump();
      expect(mandati.last['id'], 'gruppo');
      expect(mandati.last['titolo'], '4 notifiche di casa');
      expect(mandati.last['testo'], contains('Lavastoviglie finita'));
      expect(mandati.last['secondi'], 11, reason: 'il tempo che resta, non quello intero');
      // Fine sessione e auto riaccesa: l'auto l'ha dimenticato, lo si rimanda.
      final prima = mandati.length;
      a.schermo(false);
      expect(mandati.length, prima);
      a.schermo(true);
      await tester.pump();
      expect(mandati.length, prima + 1);
      expect(mandati.last['titolo'], '4 notifiche di casa');
      a.ferma();
      coda.dispose();
    });

    testWidgets('l\'avviso non aspetta l\'icona più di 400 ms, e parte senza', (tester) async {
      final coda = CodaAvvisiDiCasa();
      // Il telefono è bloccato: il disegno resta in attesa.
      final disegni = <Completer<Uint8List>>[];
      final (a, mandati) = auto(
        coda,
        disegna: (_, _) {
          disegni.add(Completer<Uint8List>());
          return disegni.last.future;
        },
      );
      a.avvia();
      await tester.pump();
      expect(disegni, hasLength(1), reason: 'all\'avvio si preparano le icone, una alla volta');
      coda.aggiungi(_lavatrice());
      await tester.pump(const Duration(milliseconds: 390));
      expect(mandati.single, isEmpty, reason: 'fin qui aspetta l\'icona');
      await tester.pump(const Duration(milliseconds: 20));
      expect(mandati.last['titolo'], 'Lavatrice finita');
      expect(mandati.last.containsKey('icona'), isFalse);
      // Sbloccato il telefono l'icona arriva: resta per la volta dopo.
      for (final d in disegni) {
        d.complete(Uint8List.fromList([7]));
      }
      await tester.pump();
      coda
        ..chiudi()
        ..aggiungi(_lavatrice(id: 'lavatrice-2'));
      await tester.pump();
      expect(mandati.last['id'], 'lavatrice-2');
      expect(mandati.last['icona'], [7]);
      a.ferma();
      coda.dispose();
    });

    testWidgets('le icone delle categorie sono pronte prima dell\'avviso', (tester) async {
      final coda = CodaAvvisiDiCasa();
      var disegnate = 0;
      final (a, mandati) = auto(
        coda,
        disegna: (_, _) async {
          disegnate++;
          return Uint8List.fromList([9]);
        },
      );
      a.avvia();
      await tester.pump();
      expect(disegnate, greaterThan(CategoriaAvvisoDiCasa.values.length));
      final prima = disegnate;
      for (final avviso in [_lavatrice(), _campanello(), _fumo(), _allarme()]) {
        coda.aggiungi(avviso);
        await tester.pump();
        expect(mandati.last['id'], avviso.id);
        expect(mandati.last['icona'], [9]);
        coda.chiudi();
      }
      expect(disegnate, prima, reason: 'niente da disegnare quando arriva l\'avviso');
      a.ferma();
      coda.dispose();
    });

    test('al più due tasti, mai quelli da fermo; con uno solo, «Chiudi»', () {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      final (a, _) = auto(coda);
      coda.aggiungi(
        AvvisoDiCasa.daNotifica(
          _busta(
            'inserimenti',
            'Antifurto inserito',
            azioni: [
              {'id': 'disinserisci', 'etichetta': 'Disinserisci'},
              {'id': 'guarda', 'etichetta': 'Guarda', 'apre': true},
            ],
          ),
        )!,
      );
      final dati = a.adesso();
      final tasti = (dati['tasti'] as List).cast<Map<String, Object?>>();
      expect(tasti.map((t) => t['id']), ['disinserisci', AvvisiDiCasaInAuto.chiudi]);
      expect(dati['secondi'], 8);
      // «Guarda» (apre l'app) dall'auto non passa nemmeno se arriva.
      a.tasto(coda.attuale!.id, 'guarda');
      expect(coda.daConfermare, isNull);
      expect(coda.attuale, isNotNull);
    });

    test('il tasto con la domanda diventa «Sì / No», e il «Sì» passa', () {
      final fatte = <String>[];
      final coda = CodaAvvisiDiCasa(onAzione: (_, az) => fatte.add(az.id));
      addTearDown(coda.dispose);
      final (a, _) = auto(coda);
      coda.aggiungi(_campanello());
      a.tasto('campanello', 'apri');
      final dati = a.adesso();
      expect(dati['conferma'], isTrue);
      expect(dati['titolo'], 'Aprire il cancello?');
      expect((dati['tasti'] as List).map((t) => (t as Map)['etichetta']), ['Sì, apri cancello', 'No']);
      expect(dati['secondi'], isNull, reason: 'mentre si decide non scade');
      a.tasto('campanello', AvvisiDiCasaInAuto.no);
      expect(coda.daConfermare, isNull);
      expect(fatte, isEmpty);
      a.tasto('campanello', 'apri');
      a.tasto('campanello', 'apri');
      expect(fatte, ['apri']);
      expect(coda.attuale, isNull);
    });

    test('l\'urgente resta (senza durata), un tasto vecchio non vale', () {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      final (a, _) = auto(coda);
      coda.aggiungi(_fumo());
      expect(a.adesso()['secondi'], isNull);
      expect(a.adesso()['urgente'], isTrue);
      a.tasto('lavatrice', AvvisiDiCasaInAuto.chiudi);
      expect(coda.attuale?.id, 'fumo');
      a.tasto('fumo', AvvisiDiCasaInAuto.chiudi);
      expect(coda.attuale, isNull);
      expect(a.adesso(), isEmpty);
    });

    test('tante insieme: una sola, «3 notifiche di casa», che si chiude tutta', () {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      final (a, _) = auto(coda);
      coda
        ..aggiungi(_lavatrice())
        ..aggiungi(_lavatrice(id: 'forno', titolo: 'Forno pronto'))
        ..aggiungi(_lavatrice(id: 'auto', titolo: 'Auto carica'));
      expect(a.adesso()['titolo'], '3 notifiche di casa');
      a.tasto('gruppo', AvvisiDiCasaInAuto.chiudi);
      expect(coda.gruppo, isNull);
    });

    testWidgets('all\'auto va con la sua icona, e «{}» quando non c\'è più', (tester) async {
      final coda = CodaAvvisiDiCasa();
      addTearDown(coda.dispose);
      final (a, mandati) = auto(coda);
      a.avvia();
      expect(mandati.single, isEmpty);
      await tester.runAsync(() async {
        coda.aggiungi(_lavatrice());
        for (var i = 0; i < 50 && mandati.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(mandati.last['titolo'], 'Lavatrice finita');
      expect(mandati.last['icona'], isA<Uint8List>());
      coda.chiudi();
      expect(mandati.last, isEmpty);
      a.ferma();
    });
  });

  group('il lettore del telefono', () {
    const canale = MethodChannel('gdanav/musica');
    final chiamate = <MethodCall>[];

    setUp(() {
      chiamate.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canale, (c) async {
        chiamate.add(c);
        return c.method == 'avvia' ? {'permesso': false} : null;
      });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canale, null),
    );

    test('legge lo stato del lato nativo, e manda i comandi', () async {
      final l = LettoreDelTelefono(fonte: FonteMusica.telefono);
      addTearDown(l.dispose);
      await l.accendi(true);
      expect(l.permesso, isFalse);
      expect(l.brano, isNull);
      l.leggi({
        'permesso': true,
        'app': 'Lettore Prova',
        'titolo': 'Strade di notte',
        'artista': 'Le Lucciole',
        'suona': true,
        'copertina': Uint8List.fromList([1, 2, 3]),
        'durata_ms': 200000,
      });
      expect(l.permesso, isTrue);
      expect(l.app, 'Lettore Prova');
      expect(l.brano?.titolo, 'Strade di notte');
      expect(l.brano?.copertina, isA<MemoryImage>());
      expect(l.brano?.durata, const Duration(seconds: 200));
      await l.playPausa();
      await l.successivo();
      await l.precedente();
      await l.chiediPermesso();
      await l.accendi(false);
      expect(chiamate.map((c) => '${c.method}:${c.arguments ?? ''}'), [
        'avvia:',
        'comando:playPausa',
        'comando:successivo',
        'comando:precedente',
        'chiediPermesso:',
        'ferma:',
      ]);
      // Niente titolo: niente brano (un lettore aperto ma vuoto).
      l.leggi({'permesso': true, 'app': 'Lettore Prova'});
      expect(l.brano, isNull);
      expect(l.app, 'Lettore Prova');
    });

    test('«Non ora» va al lato nativo; chi non lo conosce non rompe niente', () async {
      final l = LettoreDelTelefono(fonte: FonteMusica.telefono);
      addTearDown(l.dispose);
      await l.invitoVisto();
      expect(chiamate.single.method, 'invitoVisto');
      expect(chiamate.single.arguments, isNull);
      // CarPlay finché non lo aggiunge: «non c'è».
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canale, null);
      await l.invitoVisto();
    });

    testWidgets('senza permesso il riquadro non c\'è; l\'invito si vede una volta', (tester) async {
      final l = LettoreFinto(brani: const [BranoInAscolto(titolo: 'Strade di notte')], permesso: false);
      addTearDown(l.dispose);
      var visto = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: temaGdanav(Brightness.light),
          home: Scaffold(
            body: Column(
              children: [
                MiniLettore(lettore: l),
                InvitoMusica(lettore: l, onVisto: () => visto++),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('mini-lettore')), findsNothing);
      expect(find.text('Serve l\'accesso alle notifiche'), findsOneWidget);
      await tester.tap(find.byKey(const Key('invito-musica-si')));
      await tester.pump();
      expect(l.comandi, ['permesso']);
      expect(visto, 1);
      expect(find.byKey(const Key('mini-lettore')), findsOneWidget);
      // Tolto dallo schermo dopo il tocco: non conta due volte.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(visto, 1);
    });

    testWidgets('senza nessun lettore aperto il riquadro non c\'è', (tester) async {
      final l = LettoreFinto(app: null);
      addTearDown(l.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MiniLettore(lettore: l)),
        ),
      );
      expect(find.byKey(const Key('mini-lettore')), findsNothing);
    });
  });
}
