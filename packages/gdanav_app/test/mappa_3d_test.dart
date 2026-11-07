import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/mappa/mappa_3d.dart';
import 'package:gdanav_app/mappa/ponte_3d.dart';
import 'package:gdanav_app/mappa/segnaposto.dart';
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
      expect(msgOpzioni(notte: false, vista: VistaMappa.inclinata, segnaposto: Segnaposto.autoBianca)['auto'], '#f1f3f5');
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
    });

    test('la telecamera: segui, libera, panoramica col riquadro', () {
      expect(msgCamera(ModoCamera3d.libera)['modo'], 'libera');
      final p = msgCamera(ModoCamera3d.panoramica, sopra: 120, riquadro: confini(viaggio));
      expect(p['sopra'], 120);
      expect(p['riquadro'], [45.0, 9.0, 45.003, closeTo(9.0042, 1e-9)]);
      expect(msgCamera(ModoCamera3d.segui).containsKey('riquadro'), isFalse);
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
    });
  });

  group('i messaggi dalla mappa 3D', () {
    test('si capiscono quelli noti, gli altri no', () {
      expect(MessaggioDalla3d.leggi('{"tipo":"caricata","versione":1}'), isA<Caricata3d>());
      expect(MessaggioDalla3d.leggi('{"tipo":"pronto"}'), isA<Pronta3d>());
      final e = MessaggioDalla3d.leggi('{"tipo":"errore","motivo":"software","gpu":"SwiftShader"}');
      expect(e, isA<Errore3d>().having((x) => x.motivo, 'motivo', 'software').having((x) => x.gpu, 'gpu', 'SwiftShader'));
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

  group('l’impostazione «Mappa 3D»', () {
    test('di partenza accesa; spenta a mano; spenta da sola se il telefono non ce la fa', () {
      expect(const SceltaMappa3d().accesa, isTrue);
      expect(const SceltaMappa3d(scelta: 'no').accesa, isFalse);
      expect(const SceltaMappa3d(esito: 'lento').accesa, isFalse);
      expect(const SceltaMappa3d(esito: 'lento').nonCeLaFa, isTrue);
      expect(const SceltaMappa3d(scelta: 'no', esito: 'lento').nonCeLaFa, isFalse);
      expect(const SceltaMappa3d(esito: 'lento').riassunto, contains('scatti'));
      expect(const SceltaMappa3d(esito: 'webgl2').riassunto, contains('non la può disegnare'));
    });

    test('si ricorda; riaccesa a mano si riprova anche dove era andata male', () async {
      preparaPiattaforma();
      final a = Archivio();
      expect((await a.mappa3d()).accesa, isTrue);
      await a.salvaMappa3dFallita('lento');
      expect((await a.mappa3d()).accesa, isFalse);
      expect((await a.mappa3d()).esito, 'lento');
      await a.salvaMappa3d(false);
      expect((await a.mappa3d()).accesa, isFalse);
      await a.salvaMappa3d(true);
      final s = await a.mappa3d();
      expect(s.accesa, isTrue);
      expect(s.esito, isNull);
    });

    testWidgets('nel menu: l’interruttore la spegne e la riaccende', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester);
      await tester.pumpWidget(a.app());
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      final voce = find.byKey(const Key('menu-mappa-3d'));
      final interruttore = find.descendant(of: voce, matching: find.byType(SwitchListTile));
      await tester.scrollUntilVisible(voce, 120, scrollable: find.byType(Scrollable).last);
      expect(tester.widget<SwitchListTile>(interruttore).value, isTrue);
      expect(find.text('In guida: viadotti, alberi ed edifici in 3D'), findsOneWidget);
      await tester.tap(voce);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(interruttore).value, isFalse);
      expect((await a.archivio.mappa3d()).scelta, 'no');
      await tester.tap(voce);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(interruttore).value, isTrue);
    });

    test('nelle prove (e senza WebView) il 3D non si prova: resta la mappa di sempre', () {
      expect(mappa3dPossibile, isFalse);
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
