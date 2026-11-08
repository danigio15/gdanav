// «Sul NAV potresti mettere i segnalini delle persone direttamente sulla
// mappa, in modo che quando sei con Android Auto li vedi?» (Andrea)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/persone_in_auto.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/gdanav_app.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';
import 'package:gdanav_app/mappa/mappa_3d.dart';
import 'package:gdanav_app/mappa/ponte_3d.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_app/schermate/scheda_punto.dart';
import 'package:gdanav_app/stato/gestore_persone.dart' show datiPersone, nomeBreve;
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'aiuti.dart';
import 'webview_finta.dart';

const anna = PersonaSullaMappa(
  id: 'person.anna',
  nome: 'Anna Rossi',
  posizione: Punto(42.003, 12),
  dove: 'Via Roma 1, Bracciano',
);
const luca = PersonaSullaMappa(id: 'person.luca', nome: 'Luca', posizione: Punto(41.9, 12.5));

PersonaSullaMappa _spostata(PersonaSullaMappa p, double lat) =>
    PersonaSullaMappa(id: p.id, nome: p.nome, posizione: Punto(lat, p.posizione.lon), dove: p.dove);

/// I nomi nel GeoJSON mandato all'auto.
List<String> _nomi(String geojson) => [
  for (final f in (jsonDecode(geojson) as Map)['features'] as List) ((f as Map)['properties'] as Map)['nome'] as String,
];

double _lat(String geojson, String id) {
  final f = ((jsonDecode(geojson) as Map)['features'] as List).cast<Map>().firstWhere(
    (f) => (f['properties'] as Map)['id'] == id,
  );
  return ((f['geometry'] as Map)['coordinates'] as List)[1] as double;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('il nome corto, per lo schermo dell’auto', () {
    test('il primo nome; lungo, tagliato', () {
      expect(anna.breve, 'Anna');
      expect(luca.breve, 'Luca');
      expect(nomeBreve('  Massimiliano Rossi'), 'Massimilia…');
      expect(nomeBreve('Bartolomeo'), 'Bartolomeo');
      expect(nomeBreve(''), '');
      final f = (datiPersone([anna])['features']! as List).single as Map;
      expect((f['properties'] as Map)['breve'], 'Anna');
    });
  });

  group('lo stile dell’auto ha le persone', () {
    for (final scuro in [false, true]) {
      for (final immersiva in [false, true]) {
        for (final aspetto3d in [false, true]) {
          test('${scuro ? 'notte' : 'giorno'}${immersiva ? ', immersiva' : ''}${aspetto3d ? ', aspetto 3D' : ''}', () {
            final s = stileMappa(scuro: scuro, perAuto: true, immersiva: immersiva, aspetto3d: aspetto3d);
            expect((s['sources']! as Map).containsKey(sorgentePersone), isTrue);
            final strati = {for (final l in s['layers']! as List) (l as Map)['id']: l};
            expect(strati.keys, containsAll(['persone', 'persone-iniziali', 'persone-nome']));
            // Più grandi che sul telefono, per leggerli a un braccio di distanza.
            final cerchio = strati['persone']!['paint'] as Map;
            expect(cerchio['circle-radius'], 18);
            expect(cerchio['circle-color'], coloreDellePersone);
            final nome = strati['persone-nome']!['layout'] as Map;
            expect(jsonEncode(nome['text-field']), contains('breve'));
            expect(nome['text-size'], 16);
            // Fermi: niente transizioni o colori che cambiano col tempo.
            expect(jsonEncode(strati['persone']), isNot(contains('transition')));
            // Sopra le persone c'è ancora il segnaposto di chi guida.
            final ordine = strati.keys.toList();
            expect(ordine.indexOf('persone-nome'), lessThan(ordine.indexOf('io')));
          });
        }
      }
    }

    test('sul telefono resta com’era: nome intero, cerchio di 15', () {
      final s = stileMappa(scuro: false);
      final strati = {for (final l in s['layers']! as List) (l as Map)['id']: l};
      expect((strati['persone']!['paint'] as Map)['circle-radius'], 15);
      expect((strati['persone-nome']!['layout'] as Map)['text-field'], ['get', 'nome']);
    });
  });

  group('verso l’auto, senza tempestarla', () {
    testWidgets('subito all’avvio e quando qualcuno arriva o se ne va; le posizioni al più ogni 30 s', (tester) async {
      final g = GestorePersone()..aggiorna([anna]);
      final mandati = <String>[];
      final p = PersoneInAuto(g, mandati.add)..avvia();
      addTearDown(p.ferma);
      expect(mandati, hasLength(1));
      expect(_nomi(mandati.last), ['Anna Rossi']);

      // Si sposta: la prima mossa subito no (siamo nella pausa dell'avvio),
      // le altre raccolte; alla fine della pausa l'ultima.
      g.aggiorna([_spostata(anna, 42.004)]);
      g.aggiorna([_spostata(anna, 42.005)]);
      await tester.pump(const Duration(seconds: 10));
      expect(mandati, hasLength(1), reason: 'dentro i 30 secondi non si rimanda');
      await tester.pump(const Duration(seconds: 21));
      expect(mandati, hasLength(2));
      expect(_lat(mandati.last, anna.id), 42.005, reason: 'l’ultima vince');

      // Arriva Luca: subito, anche in pausa.
      g.aggiorna([_spostata(anna, 42.005), luca]);
      expect(mandati, hasLength(3));
      expect(_nomi(mandati.last), ['Anna Rossi', 'Luca']);

      // Vanno via tutti (GdAHome non ne manda più): subito, la mappa si svuota.
      g.aggiorna(const []);
      expect(mandati, hasLength(4));
      expect(_nomi(mandati.last), isEmpty);

      // Passata la pausa, la prima mossa va subito.
      await tester.pump(const Duration(seconds: 31));
      expect(mandati, hasLength(4), reason: 'niente di nuovo: niente da mandare');
      g.aggiorna([luca]);
      await tester.pump(const Duration(seconds: 31));
      g.aggiorna([_spostata(luca, 41.95)]);
      expect(mandati, hasLength(6));
      expect(_lat(mandati.last, luca.id), 41.95);
      p.ferma();
    });

    testWidgets('fermato, non manda più niente', (tester) async {
      final g = GestorePersone()..aggiorna([anna]);
      final mandati = <String>[];
      final p = PersoneInAuto(g, mandati.add)..avvia();
      g.aggiorna([_spostata(anna, 42.01)]);
      p.ferma();
      g.aggiorna([anna, luca]);
      await tester.pump(const Duration(seconds: 40));
      expect(mandati, hasLength(1));
    });

    test('chi c’è non cambia spostandosi', () {
      expect(firmaPersone([anna]), firmaPersone([_spostata(anna, 43)]));
      expect(firmaPersone([anna]), isNot(firmaPersone([anna, luca])));
    });
  });

  group('sul canale dello schermo dell’auto', () {
    const canale = MethodChannel('gdanav/schermo_auto');

    testWidgets('le persone arrivano come sorgente; toccata, la scheda con «Naviga verso Anna»', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final chiamate = <MethodCall>[];
      final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messaggero.setMockMethodCallHandler(canale, (c) async {
        chiamate.add(c);
        return null;
      });
      addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
      final a = await ambiente(tester, km: 20);
      final persone = GestorePersone()..aggiorna([anna, luca]);
      final ponte = PonteAuto(
        viaggio: a.viaggio,
        guida: a.guida,
        posizione: a.posizione,
        persone: persone,
        canale: canale,
      )..avvia();
      addTearDown(ponte.ferma);
      await tester.pump();

      List<String> mandate() => [
        for (final c in chiamate)
          if (c.method == 'sorgenti' && ((c.arguments as Map)['dati'] as Map).containsKey(sorgentePersone))
            ((c.arguments as Map)['dati'] as Map)[sorgentePersone] as String,
      ];
      expect(mandate(), hasLength(1));
      final f = ((jsonDecode(mandate().single) as Map)['features'] as List).cast<Map>();
      expect(f.map((x) => (x['properties'] as Map)['breve']), ['Anna', 'Luca']);
      expect((f.first['geometry'] as Map)['coordinates'], [12, 42.003]);

      persone.aggiorna([anna]);
      await tester.pump();
      expect(mandate(), hasLength(2), reason: 'Luca è andato via: subito');

      // Toccata sulla mappa di Android Auto (lo strato `persone`).
      a.posizione.avvia();
      a.gps.add(const Lettura(Punto(42, 12)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      Object? esito;
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('punto', {
              'proprieta': {
                'tipo': 'persona',
                'id': anna.id,
                'nome': anna.nome,
                'iniziali': 'AR',
                'dove': anna.dove,
                'breve': 'Anna',
              },
              'lat': anna.posizione.lat,
              'lon': anna.posizione.lon,
            }),
          ),
          (dati) => esito = const StandardMethodCodec().decodeEnvelope(dati!),
        ),
      );
      final d = esito! as Map;
      expect(d['titolo'], 'Anna Rossi');
      expect(d['vai'], 'Naviga verso Anna');
      final voce = ((d['voci'] as List).single as Map).cast<String, Object?>();
      expect(voce['titolo'], 'Persona di casa');
      expect(voce['testo'], '330 m · Via Roma 1, Bracciano');
      expect((d['luogo'] as Map)['lat'], 42.003);

      // Finito, il ponte smette di ascoltare.
      ponte.ferma();
      persone.aggiorna([anna, luca]);
      await tester.pump(const Duration(seconds: 31));
      expect(mandate(), hasLength(2));
    });

    testWidgets('GdANav da sola (senza GdAHome) non manda persone', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final chiamate = <MethodCall>[];
      final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messaggero.setMockMethodCallHandler(canale, (c) async {
        chiamate.add(c);
        return null;
      });
      addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
      final a = await ambiente(tester, km: 20);
      final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, canale: canale)..avvia();
      addTearDown(ponte.ferma);
      await tester.pump();
      expect(
        chiamate.where(
          (c) => c.method == 'sorgenti' && ((c.arguments as Map)['dati'] as Map).containsKey(sorgentePersone),
        ),
        isEmpty,
      );
    });

    test('la scheda di una persona: dove sta, e quanto è lontana', () {
      final p = PuntoToccato.daElemento((datiPersone([anna])['features']! as List).single as Map)!;
      final s = schedaInAuto(p, qui: const Punto(42, 12));
      expect(s.righe.single.titolo, 'Persona di casa');
      expect(s.righe.single.testo, '330 m · Via Roma 1, Bracciano');
      expect(s.stato, isNull);
    });
  });

  group('nel 3D aumentato del telefono', () {
    late WebViewFinta finta;
    setUp(() {
      finta = WebViewFinta();
      WebViewPlatform.instance = finta;
      provaMappa3dPossibile = true;
    });
    tearDown(() => provaMappa3dPossibile = null);

    testWidgets('le persone arrivano alla pagina 3D, e si aggiornano', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, km: 20);
      final persone = GestorePersone()..aggiorna([anna]);
      await tester.runAsync(() => a.archivio.salvaVistaMappa(VistaMappa.aumentata));
      await tester.pumpWidget(a.app(vero3d: true, persone: persone));
      a.auto.manuale.imposta(90);
      await tester.pump();
      await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
      await tester.pumpAndSettle();
      expect(a.viaggio.stato, isA<ViaggioPronto>());
      await tester.tap(find.text('Avvia'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('mappa-3d')), findsOneWidget);
      final w = finta.ultimo;
      w.dallaPagina(canale3d, {'tipo': 'caricata'});
      // Prima le immagini dello stile, poi i dati.
      for (var i = 0; i < 60 && !w.messaggi.any((m) => m['id'] == sorgentePersone); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }

      List<Map> mandate() => [
        for (final m in w.messaggi)
          if (m['tipo'] == 'sorgente' && m['id'] == sorgentePersone) m['dati']! as Map,
      ];
      expect(mandate(), isNotEmpty);
      final f = ((mandate().last['features'] as List).single as Map)['properties'] as Map;
      expect(f['nome'], 'Anna Rossi');
      expect(f['iniziali'], 'AR');

      persone.aggiorna([anna, luca]);
      await tester.pump();
      expect((mandate().last['features'] as List), hasLength(2));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 20));
    });
  });
}
