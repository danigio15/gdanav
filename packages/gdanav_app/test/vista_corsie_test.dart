import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';
import 'package:gdanav_app/mappa/ponte_3d.dart';
import 'package:gdanav_app/mappa/regia_3d.dart';
import 'package:gdanav_app/mappa/scelta_vista.dart';
import 'package:gdanav_app/mappa/segnaposto.dart';
import 'package:gdanav_app/stato/corsie_relay.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'aiuti.dart';

/// La vista «Corsie»: la scelta, come si ricorda, i messaggi alla pagina, e
/// le corsie chieste al relay (finto) lungo il percorso.
void main() {
  group('la vista Corsie', () {
    test('è una vista della pagina 3D, come il 3D aumentato; fuori dalla guida la mappa di sempre in 3D', () {
      expect(VistaMappa.corsie.scena3d, isTrue);
      expect(VistaMappa.aumentata.scena3d, isTrue);
      expect(VistaMappa.immersiva.scena3d, isFalse);
      expect(VistaMappa.corsie.nativa, VistaMappa.inclinata);
      expect(VistaMappa.daNome('corsie'), VistaMappa.corsie);
    });

    test('si sceglie, e se il telefono non ce la fa si torna alla vista di prima', () {
      final c = ControlloMappa(vista: VistaMappa.immersiva, aumentataPossibile: true);
      c.scegliVista(VistaMappa.corsie);
      expect(c.scenaAumentata, isTrue);
      expect(c.vistaPrima, VistaMappa.immersiva, reason: 'le corsie non sono una vista «di prima»');
      c.lasciaAumentata('lento', ricorda: true);
      expect(c.vista, VistaMappa.immersiva);
      expect(c.aumentataNonVa, 'lento');
      // «Riprova» dalle corsie torna alle corsie.
      c.riprovaAumentata(VistaMappa.corsie);
      expect(c.vista, VistaMappa.corsie);
      expect(c.aumentataNonVa, isNull);
    });

    test('ricordata, ma il telefono non ce la fa: il 3D', () async {
      final c = ControlloMappa(aumentataPossibile: true);
      await c.carica(Future.value(VistaMappa.corsie), nonVa: Future.value('webgl2'));
      expect(c.vista, VistaMappa.inclinata);
    });

    testWidgets('si ricorda come le altre, senza cambiare la vista «di prima»', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, km: 5);
      await tester.runAsync(() async {
        await a.archivio.salvaVistaMappa(VistaMappa.immersiva);
        await a.archivio.salvaVistaMappa(VistaMappa.corsie);
        expect(await a.archivio.vistaMappa(), VistaMappa.corsie);
        expect(await a.archivio.vistaPrimaDellAumentata(), VistaMappa.immersiva);
      });
    });

    Future<ControlloMappa> conLaScelta(WidgetTester tester, {required bool possibile}) async {
      final c = ControlloMappa(aumentataPossibile: possibile);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: SceltaVista(controllo: c)),
          ),
        ),
      );
      await tester.tap(find.byType(SceltaVista));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('nella scelta, col suo nome e la sua spiegazione; toccata, si sceglie', (tester) async {
      final c = await conLaScelta(tester, possibile: true);
      expect(find.byKey(const Key('vista-corsie')), findsOneWidget);
      expect(find.text('Corsie'), findsOneWidget);
      expect(find.text('In guida: le corsie, le righe e la corsia da tenere'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vista-corsie')));
      await tester.pumpAndSettle();
      expect(c.vista, VistaMappa.corsie);
    });

    testWidgets('dove la pagina 3D non c’è, spenta come il 3D aumentato, col perché', (tester) async {
      final c = await conLaScelta(tester, possibile: false);
      expect(find.text('Non c\'è su questo dispositivo'), findsNWidgets(2), reason: '3D aumentato e corsie');
      await tester.tap(find.byKey(const Key('vista-corsie')));
      await tester.pumpAndSettle();
      expect(find.text('Corsie non disponibile'), findsOneWidget);
      expect(c.vista, VistaMappa.inclinata);
    });
  });

  group('i messaggi alla pagina', () {
    test('le opzioni dicono le corsie solo nella vista Corsie', () {
      expect(msgOpzioni(notte: false, vista: VistaMappa.corsie, segnaposto: Segnaposto.freccia)['corsie'], isTrue);
      expect(
        msgOpzioni(notte: false, vista: VistaMappa.aumentata, segnaposto: Segnaposto.freccia).containsKey('corsie'),
        isFalse,
      );
    });

    test('la manovra porta le corsie di TomTom (quali vanno bene) e dove sta', () {
      final d = dritta(5);
      final m = Manovra(
        istruzione: 'Svolta a destra',
        lunghezzaM: 100,
        secondi: 10,
        inizio: 2,
        tipo: 10,
        corsie: const [
          Corsia([DirezioneCorsia.dritto]),
          Corsia([DirezioneCorsia.destra], giusta: true),
        ],
      );
      final v = Viaggio(
        percorso: PercorsoCalcolato(punti: d.punti, tratti: d.tratti, manovre: [m]),
        colonnine: const [],
        piano: null,
      );
      final msg = msgManovra(v, m);
      expect(msg['corsie'], [false, true]);
      expect((msg['dove']! as num).toDouble(), closeTo(Linea(d.punti).cumulate[2], 0.1));
      // Senza corsie, come prima.
      final senza = msgManovra(v, Manovra(istruzione: 'Svolta', lunghezzaM: 100, secondi: 10, inizio: 2, tipo: 10));
      expect(senza.containsKey('corsie'), isFalse);
      expect(msgCorsie({'v': 1, 'strade': []}), {
        'v': 1,
        'tipo': 'corsie',
        'dati': {'v': 1, 'strade': []},
      });
    });
  });

  group('le corsie dal relay', () {
    Map<String, Object?> tessera(int x, int y) => {
      'v': 1,
      'z': 14,
      'x': x,
      'y': y,
      'strade': [
        {
          'id': x * 10 + y,
          'hw': 'primary',
          'g': [12.0, 42.0, 12.001, 42.0],
          'lanes': '2',
        },
      ],
      'nodi': [],
    };

    MockClient relay(List<Uri> chieste, {Set<String> rotte = const {}}) => MockClient((r) async {
      chieste.add(r.url);
      final p = r.url.pathSegments;
      if (rotte.contains('${p[3]}/${p[4]}')) return http.Response('{"errore":"overpass"}', 502);
      return http.Response(jsonEncode(tessera(int.parse(p[3]), int.parse(p[4]))), 200);
    });

    test('una tessera per volta, dal relay dell’app, tenuta in memoria (le ultime)', () async {
      final chieste = <Uri>[];
      final c = CorsieRelay(Uri.parse('https://relay.prova/'), client: relay(chieste, rotte: {'1/1'}), tenute: 2);
      expect(c.indirizzo(8838, 6144).toString(), 'https://relay.prova/v1/corsie/14/8838/6144');
      expect((await c.tessera(8838, 6144))!['x'], 8838);
      await c.tessera(8838, 6144);
      expect(chieste, hasLength(1), reason: 'la seconda volta dalla memoria');
      expect(await c.tessera(1, 1), isNull, reason: 'il relay non ce l’ha');
      await c.tessera(1, 1);
      expect(chieste, hasLength(3), reason: 'una che non è arrivata si richiede');
      await c.tessera(2, 2);
      await c.tessera(3, 3);
      expect(c.inMemoria, 2);
      await c.tessera(8838, 6144);
      expect(chieste.last.path, '/v1/corsie/14/8838/6144', reason: 'la più vecchia è uscita dalla memoria');
    });

    test('le tessere da avere: quella dove si è e quelle dei prossimi chilometri, prima le vicine', () {
      // Verso nord, un punto ogni chilometro: diciotto chilometri.
      final punti = [for (var i = 0; i <= 18; i++) Punto(42 + i * 0.009, 12)];
      final qui = tesseraDi(const Punto(42.0185, 12), zoomTessereStrade);
      final tt = CorsieRelay.tessereDavanti(percorso: punti, daM: 2000, qui: const Punto(42.0185, 12));
      expect(tt.first, qui);
      final lontana = tesseraDi(const Punto(42.07, 12), zoomTessereStrade);
      final avanti = tesseraDi(const Punto(42.04, 12), zoomTessereStrade);
      expect(tt, contains(avanti), reason: 'due chilometri avanti');
      expect(tt, isNot(contains(lontana)), reason: 'sei chilometri avanti: non ancora');
    });

    testWidgets('nella vista Corsie la regia le chiede e le manda alla pagina; nel 3D aumentato no', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, km: 20);
      // Dove si è: la tessera di qui si chiede anche senza un percorso.
      a.posizione.qui = const Punto(42, 12);
      for (final (vista, attese) in [(VistaMappa.aumentata, false), (VistaMappa.corsie, true)]) {
        final chieste = <Uri>[];
        final mandati = <Map<String, Object?>>[];
        final r = Regia3d(
          gestore: a.viaggio,
          posizione: a.posizione,
          guida: a.guida,
          manda: mandati.add,
          notte: () => false,
          vista: () => vista,
          inquadratura: () => (libera: false, sopra: 0.0, sinistra: 0.0, destra: 0.0),
          onNonVa: (_, {required ricorda}) {},
          corsieRelay: CorsieRelay(Uri.parse('https://relay.prova/'), client: relay(chieste)),
        )..avvia();
        r.dallaMappa('{"tipo":"caricata"}');
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        r.dallaGuida();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
        final corsie = mandati.where((m) => m['tipo'] == 'corsie').toList();
        expect(corsie.isNotEmpty, attese, reason: '$vista');
        expect(chieste.isNotEmpty, attese);
        if (attese) {
          expect(corsie.first['dati'], isA<Map<String, Object?>>());
          // Una tessera va alla pagina una volta sola.
          final viste = corsie.map((m) => (m['dati']! as Map)['x'].toString() + (m['dati']! as Map)['y'].toString());
          expect(viste.toSet().length, viste.length);
          final opzioni = mandati.firstWhere((m) => m['tipo'] == 'opzioni');
          expect(opzioni['corsie'], isTrue);
        }
        r.ferma();
      }
    });
  });
}
