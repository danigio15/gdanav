import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/schermate/pianificatore.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_luoghi.dart';
import 'package:gdanav_app/stato/gestore_premium.dart';
import 'package:gdanav_app/stato/viaggi_pianificati.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Un viaggio come lo scrive la casa (`ponte/src/viaggi.js`).
Map<String, Object?> _dallaCasa({String id = 'v_1', String tipo = 'una'}) => {
  'id': id,
  'utente': 'u1',
  'tipo': tipo,
  'nome': '',
  'da': null,
  'tappe': [
    if (tipo == 'tappe') {'nome': 'Ufficio', 'lat': 41.9, 'lon': 12.5, 'sostaMin': 30},
    {'nome': 'Caserta, centro', 'lat': 41.07, 'lon': 14.33},
  ],
  'quando': {
    'modo': tipo == 'tappe' ? 'partenza' : 'arrivo',
    'ora': '09:00',
    'giorno': tipo == 'settimana' ? null : '2026-10-16',
    'giorni': tipo == 'settimana' ? [1, 2, 3, 4, 5] : <int>[],
  },
  'avviso': {'acceso': true, 'minuti': 10},
  'prepara': {
    'clima': {'entity': 'climate.auto', 'minuti': 10},
    'garage': null,
  },
  'stima': {
    'durataS': 2880,
    'km': 39.4,
    'fonte': 'traffico',
    'alle': DateTime(2026, 10, 15, 20).millisecondsSinceEpoch,
  },
  'prossima': {
    'giorno': '2026-10-16',
    'partenza': DateTime(2026, 10, 16, 8, 12).millisecondsSinceEpoch,
    'arrivo': DateTime(2026, 10, 16, 9).millisecondsSinceEpoch,
    'stimata': true,
  },
  'creatoIl': 1,
  'modificatoIl': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final giovedi = DateTime(2026, 10, 15, 21); // giovedì sera: domani è venerdì 16

  group('il viaggio, come la casa', () {
    test('si legge e si riscrive campo per campo', () {
      final v = ViaggioPianificato.daJson(_dallaCasa())!;
      expect(v.tipo, TipoViaggioPianificato.una);
      expect(v.meta!.nome, 'Caserta, centro');
      expect(v.arrivoEntro, isTrue);
      expect(v.clima, 'climate.auto');
      expect(v.stima!.colTraffico, isTrue);
      expect(oraDetta(v.prossima!.partenza), '8:12');
      expect(v.titolo, 'Caserta');
      final j = v.toJson();
      expect(j['quando'], {'modo': 'arrivo', 'ora': '09:00', 'giorno': '2026-10-16', 'giorni': <int>[]});
      expect(j['prepara'], {
        'clima': {'entity': 'climate.auto', 'minuti': 10},
        'garage': null,
      });
      expect((j['stima'] as Map)['fonte'], 'traffico');
      expect(j.containsKey('utente'), isFalse, reason: 'chi è lo dice la casa, non il telefono');
    });

    test('senza meta, ora o giorni non sta in piedi', () {
      expect(ViaggioPianificato.daJson({..._dallaCasa(), 'tappe': <Object>[]}), isNull);
      expect(
        ViaggioPianificato.daJson({
          ..._dallaCasa(),
          'quando': {'modo': 'arrivo', 'ora': '25:00', 'giorno': '2026-10-16'},
        }),
        isNull,
      );
      expect(
        ViaggioPianificato.daJson({
          ..._dallaCasa(tipo: 'settimana'),
          'quando': {'modo': 'arrivo', 'ora': '08:30', 'giorni': <int>[]},
        }),
        isNull,
      );
    });

    test('la prossima volta: arrivo entro, col traffico fresco o col margine', () {
      final v = ViaggioPianificato.daJson(_dallaCasa())!;
      final p = prossimaVolta(v, giovedi)!;
      expect(p.arrivo, DateTime(2026, 10, 16, 9));
      expect(p.partenza, DateTime(2026, 10, 16, 8, 12));
      // Sei ore dopo la stima il traffico non vale più: 48 min × 1,15.
      final p2 = prossimaVolta(v, DateTime(2026, 10, 16, 3))!;
      expect(p2.partenza, DateTime(2026, 10, 16, 8, 4, 48));
      // Passato da più di un'ora: niente.
      expect(prossimaVolta(v, DateTime(2026, 10, 16, 10, 30)), isNull);
    });

    test('ogni settimana: il prossimo giorno scelto; i giri sommano le soste', () {
      final s = ViaggioPianificato.daJson(_dallaCasa(tipo: 'settimana'))!;
      // Venerdì alle 10 è passato: si va a lunedì 19.
      expect(prossimaVolta(s, DateTime(2026, 10, 16, 10))!.arrivo, DateTime(2026, 10, 19, 9));
      expect(quandoDetto(s, giovedi), 'Lun – Ven · arrivo entro le 9:00');
      final g = ViaggioPianificato.daJson(_dallaCasa(tipo: 'tappe'))!;
      expect(g.dicePartenza, isTrue);
      expect(durataDelViaggio(g, giovedi), const Duration(minutes: 48 + 30));
      expect(prossimaVolta(g, giovedi)!.arrivo, DateTime(2026, 10, 16, 10, 18));
      expect(sottotitoloInAuto(g, giovedi), '2 tappe · 39 km');
    });

    test('in parole', () {
      expect(giorniDetti([1, 2, 3, 4, 5]), 'Lun – Ven');
      expect(giorniDetti([6, 7]), 'Sab, Dom');
      expect(giorniDetti([1, 2, 3, 4, 5, 6, 7]), 'Tutti i giorni');
      expect(durataDetta(const Duration(minutes: 80)), '1 h 20 min');
      final v = ViaggioPianificato.daJson(_dallaCasa())!;
      expect(quandoDetto(v, giovedi), 'Domani · arrivo entro le 9:00');
      expect(sottotitoloInAuto(v, giovedi), 'Domani, parti alle 8:12 · arrivo 9:00');
      expect(sottotitoloInAuto(v, DateTime(2026, 10, 16, 7)), 'Parti alle 8:12 · arrivo 9:00');
    });
  });

  group('dove stanno', () {
    test('nella casa: i comandi ponte/viaggi, e gli errori in parole', () async {
      final mandati = <Map<String, Object?>>[];
      Object? risposta;
      final casa = FonteViaggiDellaCasa((c) async {
        mandati.add(c);
        if (risposta is Exception) throw risposta;
        return risposta;
      });
      risposta = {
        'sbloccato': true,
        'viaggi': [_dallaCasa(), _dallaCasa(id: 'v_2', tipo: 'settimana')],
      };
      final e = await casa.elenco();
      expect(e.sbloccato, isTrue);
      expect(e.viaggi.map((v) => v.id), ['v_1', 'v_2']);
      expect(mandati.last, {'type': 'ponte/viaggi/elenco'});

      risposta = {'viaggio': _dallaCasa(id: 'v_9')};
      final v = ViaggioPianificato.nuovo(TipoViaggioPianificato.una, giovedi).copia(
        tappe: [const PostoPianificato(Luogo(nome: 'Caserta', posizione: Punto(41.07, 14.33)))],
      );
      expect((await casa.salva(v)).id, 'v_9');
      expect(mandati.last['type'], 'ponte/viaggi/salva');
      expect((mandati.last['viaggio'] as Map)['quando'], {
        'modo': 'arrivo',
        'ora': '09:00',
        'giorno': '2026-10-16',
        'giorni': <int>[],
      });

      risposta = {'viaggio': _dallaCasa()};
      await casa.stima('v_1', const StimaViaggio(durata: Duration(minutes: 40), km: 39, colTraffico: true));
      expect(mandati.last['type'], 'ponte/viaggi/stima');
      expect(mandati.last['stima'], {'durataS': 2400, 'km': 39.0, 'fonte': 'traffico'});

      await casa.togli('v_1');
      expect(mandati.last, {'type': 'ponte/viaggi/togli', 'viaggio': 'v_1'});

      risposta = Exception('premium-richiesto');
      await expectLater(
        casa.salva(v),
        throwsA(isA<ErroreViaggi>().having((e) => e.codice, 'codice', 'premium-richiesto')),
      );
    });

    test('nel telefono: si salvano, si cambiano, si tolgono; senza Premium no', () async {
      preparaPiattaforma();
      final archivio = Archivio();
      final telefono = FonteViaggiDelTelefono(archivio, orologio: () => giovedi);
      final v = ViaggioPianificato.nuovo(TipoViaggioPianificato.una, giovedi).copia(
        tappe: [const PostoPianificato(Luogo(nome: 'Caserta', posizione: Punto(41.07, 14.33)))],
        stima: () => StimaViaggio(durata: const Duration(minutes: 48), colTraffico: true, alle: giovedi),
      );
      final salvato = await telefono.salva(v);
      expect(salvato.id, startsWith('v_'));
      expect(oraDetta(salvato.prossima!.partenza), '8:12');
      await telefono.salva(salvato.copia(nome: 'Caserta per lavoro'));
      final e = await telefono.elenco();
      expect(e.viaggi.single.nome, 'Caserta per lavoro');
      await telefono.togli(salvato.id!);
      expect((await telefono.elenco()).viaggi, isEmpty);

      GestorePremium.attivo.value = false;
      addTearDown(() => GestorePremium.attivo.value = true);
      await expectLater(telefono.salva(v), throwsA(isA<ErroreViaggi>()));
    });

    testWidgets('la casa che non risponde ancora: si riprova, e il viaggio arriva', (tester) async {
      // «Ho pianificato il viaggio sull'app ma in auto non l'ho trovato»:
      // all'avvio la casa non rispondeva, e nessuno richiedeva l'elenco.
      var risponde = false;
      final casa = FonteViaggiDellaCasa((c) async {
        if (!risponde) throw Exception('filo non ancora alzato');
        return {
          'sbloccato': true,
          'viaggi': [_dallaCasa()],
        };
      });
      final g = GestoreViaggiPianificati(casa, orologio: () => giovedi);
      await g.carica();
      expect(g.viaggi, isEmpty);
      expect(g.errore, isNotNull);
      risponde = true;
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(g.viaggi.map((v) => v.id), ['v_1']);
      expect(g.errore, isNull);
      g.dispose();
    });

    testWidgets('un «no» della casa non si riprova', (tester) async {
      var chieste = 0;
      final casa = FonteViaggiDellaCasa((c) async {
        chieste++;
        throw Exception('premium-richiesto');
      });
      final g = GestoreViaggiPianificati(casa, orologio: () => giovedi);
      await g.carica();
      await tester.pump(const Duration(minutes: 5));
      expect(chieste, 1);
      g.dispose();
    });

    test('il gestore porta alla casa la stima col traffico dei viaggi vicini', () async {
      final stime = <String>[];
      final casa = FonteViaggiDellaCasa((c) async {
        if (c['type'] == 'ponte/viaggi/stima') {
          stime.add(c['viaggio'] as String);
          return {'viaggio': _dallaCasa()};
        }
        return {
          'sbloccato': true,
          'viaggi': [
            // Stima vecchia (di ieri): si rifà.
            {
              ..._dallaCasa(),
              'stima': {'durataS': 2400, 'fonte': 'strada', 'alle': 0},
            },
          ],
        };
      });
      final g = GestoreViaggiPianificati(
        casa,
        orologio: () => giovedi,
        calcolaStima: (da, per, {conSoste = false}) async =>
            const StimaViaggio(durata: Duration(minutes: 50), km: 40, colTraffico: true),
      );
      await g.carica();
      await Future<void>.delayed(Duration.zero);
      expect(stime, ['v_1']);
    });

    test('alla casa le soste del telefono, sul filo della stima', () async {
      final mandati = <Map<String, Object?>>[];
      final chiesteConSoste = <bool>[];
      final casa = FonteViaggiDellaCasa((c) async {
        mandati.add(c);
        if (c['type'] == 'ponte/viaggi/stima') return {'viaggio': _dallaCasa()};
        return {
          'sbloccato': true,
          'viaggi': [
            {
              ..._dallaCasa(),
              'stima': {'durataS': 2400, 'fonte': 'strada', 'alle': 0},
            },
          ],
        };
      });
      final g = GestoreViaggiPianificati(
        casa,
        orologio: () => giovedi,
        calcolaStima: (da, per, {conSoste = false}) async {
          chiesteConSoste.add(conSoste);
          return StimaViaggio(
            durata: const Duration(minutes: 50),
            km: 40,
            colTraffico: true,
            soste: SostaPianificata.dalPiano(_piano()),
            arrivo: 41.6,
          );
        },
      );
      await g.carica();
      await Future<void>.delayed(Duration.zero);
      expect(chiesteConSoste, [true]);
      final stima = mandati.lastWhere((c) => c['type'] == 'ponte/viaggi/stima')['stima'] as Map;
      expect(stima['arrivo'], 42);
      expect(stima['soste'], [
        {
          'km': 123.5,
          'nome': 'Area di servizio Arda Ovest',
          'operatore': 'Ionity',
          'kw': 350.0,
          'lat': 45.12346,
          'lon': 9.87654,
          'da': 12,
          'a': 80,
          'min': 23,
          'libera': true,
        },
      ]);
    });

    test('nel telefono le soste non si chiedono', () async {
      preparaPiattaforma();
      final telefono = FonteViaggiDelTelefono(Archivio(), orologio: () => giovedi);
      await telefono.salva(
        ViaggioPianificato.nuovo(TipoViaggioPianificato.una, giovedi).copia(
          tappe: [const PostoPianificato(Luogo(nome: 'Caserta', posizione: Punto(41.07, 14.33)))],
        ),
      );
      final chiesteConSoste = <bool>[];
      final g = GestoreViaggiPianificati(
        telefono,
        orologio: () => giovedi,
        calcolaStima: (da, per, {conSoste = false}) async {
          chiesteConSoste.add(conSoste);
          return const StimaViaggio(durata: Duration(minutes: 50), colTraffico: true);
        },
      );
      await g.carica();
      await Future<void>.delayed(Duration.zero);
      expect(chiesteConSoste, everyElement(isFalse));
    });
  });

  group('le soste per la casa', () {
    test('dal piano del telefono: i campi che il ponte controlla', () {
      final soste = SostaPianificata.dalPiano(_piano(nomeLungo: 'A' * 100, operatoreLungo: 'B' * 70))!;
      final j = soste.single.toJson();
      expect((j['nome'] as String).length, 80);
      expect((j['operatore'] as String).length, 60);
      // La potenza più alta della colonnina, anche se l'auto ne prende meno.
      expect(j['kw'], 350);
      expect(j['min'], isA<int>());
    });

    test('libera o no: assente se non si sa; operatore assente se non c\'è', () {
      final j = SostaPianificata.dalPiano(_piano(disponibilita: Disponibilita.sconosciuta, operatore: null))!.single
          .toJson();
      expect(j.containsKey('libera'), isFalse);
      expect(j.containsKey('operatore'), isFalse);
      final occupata = SostaPianificata.dalPiano(_piano(disponibilita: const Disponibilita(occupate: 2, totali: 2)))!
          .single
          .toJson();
      expect(occupata['libera'], isFalse);
    });

    test('senza piano niente soste, e la stima resta com\'era', () {
      expect(SostaPianificata.dalPiano(null), isNull);
      // Una colonnina senza scheda non ha la posizione: le soste le fa la casa.
      expect(SostaPianificata.dalPiano(_piano(senzaScheda: true)), isNull);
      const s = StimaViaggio(durata: Duration(minutes: 40), km: 39, colTraffico: true, arrivo: 30);
      expect(s.toJson(), {'durataS': 2400, 'km': 39.0, 'fonte': 'traffico'});
    });

    test('la batteria basta: soste vuote, e l\'arrivo', () {
      final s = StimaViaggio(
        durata: const Duration(minutes: 40),
        soste: SostaPianificata.dalPiano(const PianoViaggio(soste: [], batteriaArrivo: 55.4, durata: Duration.zero)),
        arrivo: 55.4,
      );
      expect(s.toJson(), {'durataS': 2400, 'fonte': 'strada', 'soste': <Object?>[], 'arrivo': 55});
    });

    test('va e torna', () {
      final s = StimaViaggio(
        durata: const Duration(minutes: 50),
        colTraffico: true,
        soste: SostaPianificata.dalPiano(_piano()),
        arrivo: 42,
      );
      final r = StimaViaggio.daJson(s.toJson())!;
      expect(r.toJson(), s.toJson());
      expect(r.soste!.single.libera, isTrue);
    });
  });

  testWidgets('in auto: i viaggi in cima a «Dove andiamo?», e si parte con le tappe', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    const canale = MethodChannel('gdanav/schermo_auto');
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));

    final a = await ambiente(tester, km: 20);
    final luoghi = GestoreLuoghi(a.archivio);
    await tester.runAsync(luoghi.carica);
    final pianificati = GestoreViaggiPianificati(
      FonteViaggiDellaCasa(
        (c) async => {
          'sbloccato': true,
          'viaggi': [_dallaCasa(tipo: 'tappe')],
        },
      ),
      orologio: () => giovedi,
    );
    await tester.runAsync(pianificati.carica);
    final ponte = PonteAuto(
      viaggio: a.viaggio,
      guida: a.guida,
      posizione: a.posizione,
      luoghi: luoghi,
      pianificati: pianificati,
      canale: canale,
      orologio: () => giovedi,
    )..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();
    final elenco = (chiamate.lastWhere((c) => c.method == 'luoghi').arguments as Map)['elenco'] as List;
    expect(elenco.first, containsPair('tipo', 'pianificato'));
    expect(elenco.first, containsPair('viaggio', 'v_1'));
    expect(elenco.first, containsPair('etichetta', 'Caserta'));
    expect(elenco.first, containsPair('nome', 'Caserta, centro'));
    expect(elenco.first, containsPair('descrizione', '2 tappe · 39 km'));

    a.auto.manuale.imposta(90);
    await tester.runAsync(
      () => messaggero.handlePlatformMessage(
        'gdanav/schermo_auto',
        const StandardMethodCodec().encodeMethodCall(MethodCall('vai', elenco.first)),
        (_) {},
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(a.viaggio.destinazione!.nome, 'Caserta, centro');
    expect(a.viaggio.tappe.map((t) => t.nome), ['Ufficio']);
    expect(a.guida.attiva, isTrue);
  });

  testWidgets('senza Premium il pianificatore non manda viaggi in auto', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    const canale = MethodChannel('gdanav/schermo_auto');
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester, km: 20);
    final luoghi = GestoreLuoghi(a.archivio);
    final pianificati = GestoreViaggiPianificati(
      FonteViaggiDellaCasa(
        (c) async => {
          'sbloccato': false,
          'viaggi': [_dallaCasa()],
        },
      ),
    );
    await tester.runAsync(pianificati.carica);
    final ponte = PonteAuto(
      viaggio: a.viaggio,
      guida: a.guida,
      posizione: a.posizione,
      luoghi: luoghi,
      pianificati: pianificati,
      canale: canale,
    )..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();
    final elenco = (chiamate.lastWhere((c) => c.method == 'luoghi').arguments as Map)['elenco'] as List;
    expect(elenco.where((l) => (l as Map)['tipo'] == 'pianificato'), isEmpty);
  });

  testWidgets('la schermata: elenco, nuovo viaggio di ogni settimana, salva', (tester) async {
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final salvati = <Map<String, Object?>>[];
    final viaggi = <Map<String, Object?>>[_dallaCasa()];
    final g = GestoreViaggiPianificati(
      FonteViaggiDellaCasa((c) async {
        switch (c['type']) {
          case 'ponte/viaggi/salva':
            final v = {...(c['viaggio'] as Map).cast<String, Object?>(), 'id': 'v_nuovo'};
            salvati.add(v);
            viaggi.add(v);
            return {'viaggio': v};
          default:
            return {'sbloccato': true, 'viaggi': viaggi};
        }
      }),
      orologio: () => giovedi,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: SchermataPianificatore(
          gestore: g,
          scegli: (_) async => const Luogo(nome: 'Lavoro', posizione: Punto(40.85, 14.27)),
          avvia: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Caserta'), findsOneWidget);
    expect(find.text('Domani · arrivo entro le 9:00'), findsOneWidget);
    expect(find.text('Parti alle 8:12'), findsOneWidget);
    expect(find.text('Ti avviso alle 8:02, 10 minuti prima di partire'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pianificatore-nuovo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nuovo-settimana')));
    await tester.pumpAndSettle();
    // Sabato in più.
    await tester.tap(find.byKey(const Key('giorno-6')));
    await tester.tap(find.byKey(const Key('campo-dove')));
    await tester.pumpAndSettle();
    expect(find.text('Lavoro'), findsWidgets);
    await tester.tap(find.byKey(const Key('salva-viaggio')));
    await tester.pumpAndSettle();
    expect(salvati.single['tipo'], 'settimana');
    expect((salvati.single['quando'] as Map)['giorni'], [1, 2, 3, 4, 5, 6]);
    expect((salvati.single['tappe'] as List).single, containsPair('nome', 'Lavoro'));
    expect(find.text('OGNI SETTIMANA'), findsOneWidget);
    expect(find.text('Lun – Sab · arrivo entro le 8:30'), findsOneWidget);
  });
}

/// Un piano con una sosta sola, come lo fa il pianificatore del telefono.
PianoViaggio _piano({
  String? nomeLungo,
  String? operatore = 'Ionity',
  String? operatoreLungo,
  Disponibilita disponibilita = const Disponibilita(libere: 3, occupate: 1, totali: 4),
  bool senzaScheda = false,
}) {
  final scheda = Colonnina(
    id: 'osm-node-7',
    nome: nomeLungo ?? 'Area di servizio Arda Ovest',
    operatore: operatoreLungo ?? operatore,
    posizione: const Punto(45.123456, 9.876543),
    connettori: const [
      Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 350),
      Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150),
      Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22),
    ],
  );
  return PianoViaggio(
    soste: [
      Sosta(
        colonnina: ColonninaSulPercorso(
          id: scheda.id,
          nome: scheda.nome,
          distanzaM: 123456,
          potenzaKw: 150,
          disponibilita: disponibilita,
          dettaglio: senzaScheda ? null : scheda,
        ),
        batteriaArrivo: 12.4,
        batteriaPartenza: 80,
        ricarica: const Duration(minutes: 22, seconds: 40),
      ),
    ],
    batteriaArrivo: 41.6,
    durata: const Duration(hours: 2),
  );
}
