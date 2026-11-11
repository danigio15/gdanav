import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/mappa/mappa_3d.dart';
import 'package:gdanav_app/mappa/ponte_3d.dart';
import 'package:gdanav_app/mappa/scelta_vista.dart';
import 'package:gdanav_app/mappa/segnaposto.dart';
import 'package:gdanav_app/mappa/stile.dart' show stratiToccabili;
import 'package:gdanav_app/schermate/scheda_punto.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Il messaggio dentro la chiamata JavaScript, come lo riceve la pagina.
Map<String, Object?> _dentro(String js) {
  const inizio = 'window.gdanav3d&&window.gdanav3d.ricevi(';
  expect(js, startsWith(inizio));
  expect(js, endsWith(');'));
  return (jsonDecode(js.substring(inizio.length, js.length - 2)) as Map).cast<String, Object?>();
}

void main() {
  // Dritto verso nord per ~330 m, poi a destra verso est (come le prove della freccia).
  final punti = [
    for (var i = 0; i <= 30; i++) Punto(45 + i * 0.0001, 9),
    for (var i = 1; i <= 30; i++) Punto(45.003, 9 + i * 0.00014),
  ];
  const uscita = Manovra(istruzione: 'Esci a destra', lunghezzaM: 300, secondi: 20, inizio: 30, tipo: 20);
  final viaggio = Viaggio(
    percorso: PercorsoCalcolato(
      punti: punti,
      tratti: const [],
      manovre: const [uscita],
      code: const [Coda(daM: 100, aM: 220, ritardo: Duration(minutes: 2), livello: 3)],
    ),
    colonnine: const [],
    piano: null,
  );

  group('i messaggi verso la mappa 3D', () {
    test('ogni messaggio ha la versione e il tipo; la chiamata è JavaScript con dentro JSON', () {
      final m = msgPausa(true);
      expect(m, {'v': versionePonte3d, 'tipo': 'pausa', 'si': true});
      expect(_dentro(chiamata3d(m)), m);
      // Una stringa con apici e a capo resta una stringa.
      final s = msgSorgente('gdanav-arrivo', {'nome': "l'arrivo\n</script>"});
      expect(_dentro(chiamata3d(s)), s);
    });

    test('le opzioni: notte, vista, auto rossa di partenza', () {
      final m = msgOpzioni(notte: true, vista: VistaMappa.immersiva, segnaposto: Segnaposto.freccia);
      expect(m['notte'], true);
      expect(m['vista'], 'immersiva');
      expect(m['auto'], '#d62a26', reason: 'la freccia di partenza è l’auto rossa, che sul blu si vede');
      expect(m['icona'], 'freccia');
      expect(
        msgOpzioni(notte: false, vista: VistaMappa.inclinata, segnaposto: Segnaposto.autoBianca)['auto'],
        '#f1f3f5',
      );
      for (final s in Segnaposto.values) {
        expect(coloreAuto3d(s), matches(RegExp(r'^#[0-9a-f]{6}$')));
      }
    });

    test('il percorso: coppie lon/lat, i metri della guida per ogni punto, le code', () {
      final m = msgPercorso(viaggio);
      final p = m['punti']! as List;
      final metri = m['metri']! as List;
      expect(p, hasLength(punti.length * 2));
      expect(p.take(2), [9.0, 45.0], reason: 'prima la longitudine');
      expect(metri, hasLength(punti.length));
      expect(metri.last as double, closeTo(Linea(punti).lunghezzaM, 0.1));
      expect(m['code'], [
        [100.0, 220.0, 3],
      ]);
      expect(msgPercorso(null)['punti'], isNull);
      // Un punto che non è un numero non arriva alla pagina (il JSON non sa cosa sia NaN).
      final storto = Viaggio(
        percorso: PercorsoCalcolato(punti: [...punti, const Punto(double.nan, 9)], tratti: const [], manovre: const []),
        colonnine: const [],
        piano: null,
      );
      expect(() => jsonEncode(msgPercorso(storto)), returnsNormally);
      expect((msgPercorso(storto)['punti']! as List).length, punti.length * 2);
    });

    test('la freccia della manovra: lo stesso tratto della mappa di sempre, in metri', () {
      final m = msgManovra(viaggio, uscita);
      final t = trattoManovraM(viaggio, uscita)!;
      expect(m['da'], t.$1);
      expect(m['a'], t.$2);
      final l = Linea(punti);
      expect(t.$1, closeTo(l.cumulate[30] - 60, 0.01));
      expect(t.$2, greaterThan(l.cumulate[30] + 10));
      const prosegui = Manovra(istruzione: 'Prosegui', lunghezzaM: 300, secondi: 20, inizio: 30, tipo: 8);
      expect(msgManovra(viaggio, prosegui), containsPair('da', null));
      expect(msgManovra(null, null), containsPair('a', null));
    });

    test('la posizione: arrotondata, mai NaN, la velocità mai negativa', () {
      final m = msgPosizione(
        qui: const Punto(45.123456789, 9.987654321),
        rotta: 361.26,
        metri: 1234.567,
        velocitaMs: -1,
        zoom: 17.912,
        quando: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(m['lat'], 45.123457);
      expect(m['lon'], 9.987654);
      expect(m['rotta'], 1.3);
      expect(m['metri'], 1234.6);
      expect(m['velocita'], 0.0);
      expect(m['zoom'], 17.91);
      expect(m['quando'], 1700000000000);
      // Lo zoom che cambia da sé non lo dice; quello scelto coi tasti sì, e
      // la pagina ci va subito («zoom in e zoom out non va»).
      expect(m.containsKey('zoomSubito'), isFalse);
      final tasto = msgPosizione(
        qui: const Punto(45.1, 9.9),
        rotta: 0,
        metri: 10,
        velocitaMs: 0,
        zoom: 18.4,
        quando: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        zoomSubito: true,
      );
      expect(tasto['zoomSubito'], isTrue);
      final fuori = msgPosizione(
        qui: const Punto(45, 9),
        rotta: 0,
        metri: double.nan,
        velocitaMs: double.nan,
        zoom: 18,
        quando: DateTime(2026),
      );
      expect(fuori['metri'], isNull);
      expect(fuori['velocita'], 0.0);
      expect(fuori.containsKey('lettura'), isFalse);
    });

    test('la lettura del GPS com\'era, per il filtro della pagina, e la velocità del cruscotto', () {
      final m = msgPosizione(
        qui: const Punto(45, 9),
        rotta: 0,
        metri: 1250,
        velocitaMs: 13.9,
        zoom: 18,
        quando: DateTime.fromMillisecondsSinceEpoch(1700000001000),
        lettura: (
          metri: 1236.04,
          alle: DateTime.fromMillisecondsSinceEpoch(1700000000200),
          velocitaMs: 13.876,
          precisioneM: 4.27,
        ),
      );
      expect(m['lettura'], {'metri': 1236.0, 'alle': 1700000000200, 'v': 13.88, 'precisione': 4.3});
      // Senza velocità né precisione del GPS: solo dove e quando.
      final senza = msgPosizione(
        qui: const Punto(45, 9),
        rotta: 0,
        metri: 10,
        velocitaMs: 0,
        zoom: 18,
        quando: DateTime(2026),
        lettura: (metri: 10, alle: DateTime.fromMillisecondsSinceEpoch(5), velocitaMs: null, precisioneM: null),
      );
      expect(senza['lettura'], {'metri': 10.0, 'alle': 5});
      final v = msgVelocita(ms: -0.4, alle: DateTime.fromMillisecondsSinceEpoch(77));
      expect(v['tipo'], 'velocita');
      expect(v['v'], versionePonte3d, reason: 'la versione resta: la velocità sta in «ms»');
      expect(v['ms'], 0.0);
      expect(v['alle'], 77);
    });

    test('la telecamera: segui, libera, panoramica col riquadro', () {
      expect(msgCamera(ModoCamera3d.libera)['modo'], 'libera');
      final p = msgCamera(ModoCamera3d.panoramica, sopra: 120, riquadro: confini(viaggio));
      expect(p['sopra'], 120);
      expect(p['riquadro'], [45.0, 9.0, 45.003, closeTo(9.0042, 1e-9)]);
      expect(msgCamera(ModoCamera3d.segui).containsKey('riquadro'), isFalse);
      // Di traverso il cruscotto copre la sinistra: la pagina sposta l'auto.
      expect(msgCamera(ModoCamera3d.segui, sinistra: 435)['sinistra'], 435);
      expect(msgCamera(ModoCamera3d.segui).containsKey('sinistra'), isFalse);
      // Lo schermo diviso: l'altra app copre la destra.
      expect(msgCamera(ModoCamera3d.segui, destra: 300)['destra'], 300);
      expect(msgCamera(ModoCamera3d.segui).containsKey('destra'), isFalse);
      final c = ControlloMappa();
      var avvisi = 0;
      c.addListener(() => avvisi++);
      c.copriSinistra(435);
      c.copriSinistra(435.4);
      expect((c.copertoSinistra, avvisi), (435, 1));
    });

    test('le immagini in base64, la strada a risparmio', () {
      final m = msgImmagine('arrivo-bandiera', Uint8List.fromList([1, 2, 3]));
      expect(m['png'], 'AQID');
      expect(m['ratio'], 3);
      expect(msgRisparmio(null)['punti'], isNull);
    });

    test('lo zoom: vicino, l’immersiva più vicina, più lontano in autostrada con la manovra lontana', () {
      final citta = zoom3d(VistaMappa.inclinata, velocitaStradaKmh: 50, allaProssimaM: 200);
      expect(citta, 17.9);
      expect(zoom3d(VistaMappa.immersiva, velocitaStradaKmh: 50, allaProssimaM: 200), greaterThan(citta));
      expect(zoom3d(VistaMappa.inclinata, velocitaStradaKmh: 130, allaProssimaM: 20000), lessThan(citta));
      // «In navigazione su autostrada lo zoom è troppo lontano»: al più mezzo livello.
      expect(zoom3d(VistaMappa.inclinata, velocitaStradaKmh: 130, allaProssimaM: 20000), closeTo(citta - 0.5, 1e-9));
    });
  });

  group('i messaggi dalla mappa 3D', () {
    test('si capiscono quelli noti, gli altri no', () {
      expect(MessaggioDalla3d.leggi('{"tipo":"caricata","versione":1}'), isA<Caricata3d>());
      expect(MessaggioDalla3d.leggi('{"tipo":"pronto"}'), isA<Pronta3d>());
      final e = MessaggioDalla3d.leggi('{"tipo":"errore","motivo":"software","gpu":"SwiftShader"}');
      expect(
        e,
        isA<Errore3d>().having((x) => x.motivo, 'motivo', 'software').having((x) => x.gpu, 'gpu', 'SwiftShader'),
      );
      final p = MessaggioDalla3d.leggi('{"tipo":"prestazioni","fps":14.5,"p90":90,"lento":true,"triangoli":600000}');
      expect(p, isA<Prestazioni3d>().having((x) => x.lento, 'lento', true).having((x) => x.fps, 'fps', 14.5));
      expect(MessaggioDalla3d.leggi('{"tipo":"toccata"}'), isA<Toccata3d>());
      final t = MessaggioDalla3d.leggi(
        '{"tipo":"tocco","elementi":[{"type":"Feature","geometry":{"type":"Point","coordinates":[9,45]},'
        '"properties":{"tipo":"distributore","id":"d1","nome":"Q8"}}]}',
      );
      expect(t, isA<Tocco3d>().having((x) => x.elementi, 'elementi', hasLength(1)));
      expect(MessaggioDalla3d.leggi('{"tipo":"boh"}'), isNull);
      expect(MessaggioDalla3d.leggi('non json'), isNull);
      expect(MessaggioDalla3d.leggi('[1,2]'), isNull);
    });
  });

  group('la vista «3D aumentato»', () {
    test('è una vista come le altre: si ricorda per nome, e la mappa di sempre la disegna come il 3D', () {
      expect(VistaMappa.values, [VistaMappa.piatta, VistaMappa.inclinata, VistaMappa.immersiva, VistaMappa.aumentata]);
      expect(VistaMappa.daNome('aumentata'), VistaMappa.aumentata);
      expect(VistaMappa.aumentata.nome, '3D aumentato');
      expect(VistaMappa.aumentata.sigla, '3D+');
      expect(VistaMappa.aumentata.nativa, VistaMappa.inclinata);
      for (final v in [VistaMappa.piatta, VistaMappa.inclinata, VistaMappa.immersiva]) {
        expect(v.nativa, v);
      }
      expect(
        avvisoAumentatoNonVa(VistaMappa.inclinata, ricorda: true),
        '3D aumentato non è disponibile su questo telefono: torno alla vista 3D',
      );
      expect(
        avvisoAumentatoNonVa(VistaMappa.piatta, ricorda: false),
        '3D aumentato non è partito: torno alla vista 2D',
      );
      expect(spiegaAumentatoNonVa('lento'), contains('scatti'));
      expect(spiegaAumentatoNonVa('software'), contains('non lo può disegnare'));
    });

    test('la scena 3D solo col 3D aumentato scelto e il telefono che ce la fa', () {
      final c = ControlloMappa(aumentataPossibile: true);
      expect(c.scenaAumentata, isFalse);
      c.scegliVista(VistaMappa.aumentata);
      expect(c.scenaAumentata, isTrue);
      expect(c.inclinata, isTrue, reason: 'la mappa segue chi guida');
      c.aumentataNonVa = 'lento';
      expect(c.scenaAumentata, isFalse);
      expect(ControlloMappa(vista: VistaMappa.aumentata).scenaAumentata, isFalse, reason: 'senza WebView no');
    });

    test('se il telefono non ce la fa: si torna alla vista di prima, e lo si ricorda', () async {
      final salvate = <VistaMappa>[];
      final nonVa = <String>[];
      var dimenticato = 0;
      final c = ControlloMappa(
        aumentataPossibile: true,
        salvaVista: (v) async => salvate.add(v),
        salvaAumentataNonVa: (m) async => nonVa.add(m),
        dimenticaAumentataNonVa: () async => dimenticato++,
      );
      c.scegliVista(VistaMappa.immersiva);
      c.scegliVista(VistaMappa.aumentata);
      expect(c.vistaPrima, VistaMappa.immersiva);
      // Un intoppo di questa volta: si torna indietro senza ricordarlo.
      c.lasciaAumentata('tempo', ricorda: false);
      expect(c.vista, VistaMappa.immersiva);
      expect(c.aumentataNonVa, isNull);
      expect(nonVa, isEmpty);
      expect(salvate, [VistaMappa.immersiva, VistaMappa.aumentata]);
      // Troppo lento: si ricorda, e resta scelta la vista di prima.
      c.scegliVista(VistaMappa.aumentata);
      c.lasciaAumentata('lento', ricorda: true);
      expect(c.vista, VistaMappa.immersiva);
      expect(c.aumentataNonVa, 'lento');
      expect(c.aumentataDisponibile, isFalse);
      expect(nonVa, ['lento']);
      expect(salvate.last, VistaMappa.immersiva);
      // «Riprova»: si dimentica e si sceglie di nuovo.
      c.riprovaAumentata();
      expect(c.vista, VistaMappa.aumentata);
      expect(c.aumentataNonVa, isNull);
      expect(dimenticato, 1);
      expect(salvate.last, VistaMappa.aumentata);
    });

    test('ricordato il 3D aumentato su un telefono che non ce la fa, si parte dal 3D', () async {
      final c = ControlloMappa(aumentataPossibile: true, vista: VistaMappa.piatta);
      await c.carica(Future.value(VistaMappa.aumentata), nonVa: Future.value('webgl2'));
      expect(c.vista, VistaMappa.inclinata);
      expect(c.letta, isTrue);
      final d = ControlloMappa(aumentataPossibile: true);
      await d.carica(Future.value(VistaMappa.aumentata), nonVa: Future.value(null));
      expect(d.vista, VistaMappa.aumentata);
      expect(d.scenaAumentata, isTrue);
    });

    test('si ricorda nell’archivio: la vista, e perché non va finché non si riprova', () async {
      preparaPiattaforma();
      final a = Archivio();
      expect(await a.vistaPrimaDellAumentata(), isNull);
      await a.salvaVistaMappa(VistaMappa.immersiva);
      await a.salvaVistaMappa(VistaMappa.aumentata);
      expect(await a.vistaMappa(), VistaMappa.aumentata);
      expect(await a.vistaPrimaDellAumentata(), VistaMappa.immersiva);
      expect(Archivio.vistaScelta.value, VistaMappa.aumentata);
      expect(await a.aumentataNonVa(), isNull);
      await a.salvaAumentataNonVa('lento');
      expect(await a.aumentataNonVa(), 'lento');
      await a.dimenticaAumentataNonVa();
      expect(await a.aumentataNonVa(), isNull);
    });

    Future<ControlloMappa> scelta(WidgetTester tester, ControlloMappa c) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ListenableBuilder(
                listenable: c,
                builder: (context, _) => SceltaVista(controllo: c),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SceltaVista));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('nel tasto della vista: quattro voci, e scelto il tasto dice «3D» con la scintilla', (tester) async {
      final c = await scelta(tester, ControlloMappa(aumentataPossibile: true));
      for (final v in VistaMappa.values) {
        expect(find.byKey(Key('vista-${v.name}')), findsOneWidget);
      }
      expect(find.text('3D aumentato'), findsOneWidget);
      expect(find.text('In guida: viadotti, alberi ed edifici in 3D'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vista-aumentata')));
      await tester.pumpAndSettle();
      expect(c.vista, VistaMappa.aumentata);
      expect(find.byType(IconaAumentata), findsOneWidget);
      expect(find.byTooltip('Vista: 3D aumentato'), findsOneWidget);
    });

    testWidgets('spento perché il telefono non ce la fa: si spiega, e «Riprova» lo riaccende', (tester) async {
      final c = await scelta(tester, ControlloMappa(aumentataPossibile: true)..aumentataNonVa = 'lento');
      expect(find.text('Su questo telefono va a scatti'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vista-aumentata')));
      await tester.pumpAndSettle();
      expect(c.vista, VistaMappa.inclinata, reason: 'non si sceglie da solo');
      expect(find.byKey(const Key('vista-aumentata-spiegazione')), findsOneWidget);
      expect(find.textContaining('torna da sola'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vista-aumentata-riprova')));
      await tester.pumpAndSettle();
      expect(c.vista, VistaMappa.aumentata);
      expect(c.aumentataNonVa, isNull);
    });

    testWidgets('senza WebView (qui nelle prove) si vede spento, e non c’è «Riprova»', (tester) async {
      final c = await scelta(tester, ControlloMappa());
      expect(find.text('Non c\'è su questo dispositivo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vista-aumentata')));
      await tester.pumpAndSettle();
      expect(c.vista, VistaMappa.inclinata);
      expect(find.byKey(const Key('vista-aumentata-riprova')), findsNothing);
      await tester.tap(find.text('Chiudi'));
      await tester.pumpAndSettle();
    });

    testWidgets('il 3D aumentato che si ferma: si torna alla vista di prima e lo si dice una volta', (tester) async {
      final c = ControlloMappa(aumentataPossibile: true)
        ..scegliVista(VistaMappa.piatta)
        ..scegliVista(VistaMappa.aumentata);
      late BuildContext contesto;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                contesto = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      lasciaAumentataConAvviso(contesto, c, 'lento', ricorda: true);
      await tester.pump(const Duration(milliseconds: 400));
      expect(c.vista, VistaMappa.piatta);
      expect(find.text('3D aumentato non è disponibile su questo telefono: torno alla vista 2D'), findsOneWidget);
      // Già tornati indietro: niente secondo avviso.
      lasciaAumentataConAvviso(contesto, c, 'lento', ricorda: true);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('aumentato-non-va')), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('aumentato-non-va')), findsNothing);
    });

    testWidgets('nel menu non c’è più l’interruttore «Mappa 3D»: si sceglie dalla vista', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester);
      await tester.pumpWidget(a.app());
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-mappa-3d')), findsNothing);
      expect(find.text('Mappa 3D'), findsNothing);
    });

    test('nelle prove (e senza WebView) il 3D aumentato non si prova: resta la mappa di sempre', () {
      expect(mappa3dPossibile, isFalse);
    });
  });

  group('i segni del viaggio si toccano (anche in quota, sui viadotti)', () {
    Map<String, Object?> elemento(String strato, Map<String, Object?> p) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [9.1, 45.5],
      },
      'properties': p,
      'layer': strato,
    };

    test('gli strati del viaggio sono fra quelli toccabili (a terra e nella pagina 3D)', () {
      expect(stratiToccabili, containsAll(['segnalazioni', 'tappe', 'arrivo', 'gdanav-soste']));
      final js = File('web3d/src/principale.js').readAsStringSync();
      for (final s in ['segnalazioni', 'tappe', 'arrivo']) {
        expect(js, contains("'$s'"));
      }
    });

    test('autovelox, tappa, arrivo e sosta diventano il punto giusto per la scheda', () {
      final s = datiSegnalazioni([
        Segnalazione(
          id: 'av1',
          tipo: TipoSegnalazione.autovelox,
          punto: const Punto(45.5, 9.1),
          creata: DateTime(2026, 11, 8, 10),
          conferme: 3,
          limiteKmh: 90,
        ),
      ]);
      final props = ((s['features']! as List).first as Map)['properties'] as Map<String, Object?>;
      expect(props['conferme'], 3);
      expect(props['limite'], 90);
      final av = PuntoToccato.daElemento(elemento('segnalazioni', props))!;
      expect((av.tipo, av.id, av.nome), ('segnalazione', 'av1', 'Autovelox'));
      expect(av.posizione, const Punto(45.5, 9.1));
      final tappa = PuntoToccato.daElemento(elemento('tappe', {'numero': 2, 'nome': 'Bologna', 'tappa': true}))!;
      expect((tappa.tipo, tappa.nome), ('tappa', 'Bologna'));
      final arrivo = PuntoToccato.daElemento(elemento('arrivo', {'arrivo': true}))!;
      expect(arrivo.tipo, 'arrivo');
      final sosta = PuntoToccato.daElemento(
        elemento('gdanav-soste', {'id': 'c1', 'nome': 'Ionity', 'sosta': true, 'numero': 1, 'stato': 'libera'}),
      )!;
      expect((sosta.tipo, sosta.id, sosta.nome), ('colonnina', 'c1', 'Ionity'));
    });

    testWidgets('la scheda di un autovelox toccato: cosa è e cosa si sa, senza «Vai»', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => mostraPunto(
                  context,
                  PuntoToccato(
                    tipo: 'segnalazione',
                    id: 'av1',
                    nome: 'Autovelox',
                    posizione: const Punto(45.5, 9.1),
                    proprieta: {
                      'tipo': 'autovelox',
                      'limite': 90,
                      'conferme': 3,
                      'creata': DateTime.now().subtract(const Duration(minutes: 12)).toIso8601String(),
                    },
                  ),
                  onVai: (_) {},
                ),
                child: const Text('tocca'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('tocca'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scheda-punto-segnalazione')), findsOneWidget);
      expect(find.text('AUTOVELOX'), findsOneWidget);
      expect(find.text('Limite 90 km/h'), findsOneWidget);
      expect(find.text('Confermata da 3 persone'), findsOneWidget);
      expect(find.text('Segnalata 12 min fa'), findsOneWidget);
      expect(find.byKey(const Key('vai-punto')), findsNothing);
    });

    test('da quanto', () {
      expect(fa(const Duration(seconds: 20)), 'adesso');
      expect(fa(const Duration(minutes: 5)), '5 min fa');
      expect(fa(const Duration(hours: 3)), '3 ore fa');
      expect(fa(const Duration(days: 4)), '4 giorni fa');
    });
  });

  group('la pagina impacchettata', () {
    // Dentro l'app tutto il codice: niente script né fogli da internet (App
    // Store 2.5.2). Da internet solo le tessere, i caratteri e il traffico.
    test('c’è, è dichiarata fra le risorse, e non carica codice da fuori', () {
      final pagina = File('assets/web3d/index.html').readAsStringSync();
      expect(pagina, contains('src="gdanav3d.js"'));
      expect(pagina, contains('href="gdanav3d.css"'));
      expect(pagina, isNot(contains('http')));
      expect(File('assets/web3d/gdanav3d.js').lengthSync(), greaterThan(500000));
      expect(File('assets/web3d/gdanav3d.css').existsSync(), isTrue);
      expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/web3d/'));
      expect(paginaMappa3d, 'packages/gdanav_app/assets/web3d/index.html');
      final js = File('assets/web3d/gdanav3d.js').readAsStringSync();
      expect(js, startsWith('/* GdANav 3D: file generato'));
      expect(RegExp(r'''import\(\s*["']https?:''').hasMatch(js), isFalse);
    });
  });
}
