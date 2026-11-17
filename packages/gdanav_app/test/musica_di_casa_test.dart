// La musica di casa in auto: l'elenco che dà la casa, dove suona ogni voce
// (in auto col lettore del navigatore, nell'app di Spotify, solo in casa), le
// ultime suonate per prime, il tocco, «falla partire in casa», e la scheda
// «Dalla casa»; la radio si comanda dal lettore del navigatore, e mai dal
// volante (nessuna sessione, nessun servizio in primo piano). Stazioni e
// playlist inventate.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/mini_lettore.dart';
import 'package:gdanav_app/componenti/musica_di_casa.dart';
import 'package:gdanav_app/tema.dart';

// Un PNG vero di un punto.
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

Map<String, Object?> _risposta() => {
  'letto': 1700000000000,
  'radio': [
    {
      'id': 'r1',
      'titolo': 'Radio Lungomare',
      'provenienza': 'Radio Browser',
      'come': 'flusso',
      'flusso': 'https://flussi.esempio.it/r1.mp3',
      'mime': 'audio/mpeg',
      'immagine': {'tipo': 'image/png', 'dati': _png},
    },
    {'id': 'r2', 'titolo': 'Onda Vesuviana', 'come': 'flusso', 'flusso': 'https://flussi.esempio.it/r2.aac'},
    // Una radio che trasmette solo in chiaro: al telefono non arriva.
    {'id': 'r3', 'titolo': 'Radio Collina 98', 'come': 'casa', 'perche': 'solo-http'},
    // Un indirizzo in chiaro che sfuggisse alla casa non passa comunque.
    {'id': 'r4', 'titolo': 'Radio in chiaro', 'come': 'flusso', 'flusso': 'http://flussi.esempio.it/r4.mp3'},
  ],
  'playlist': [
    {
      'id': 'p1',
      'titolo': 'Viaggio in auto',
      'provenienza': 'Spotify',
      'lettore': 'Cucina',
      'come': 'spotify',
      'uri': 'spotify:playlist:0000000000000000000001',
      'in_casa': true,
    },
    {
      'id': 'p2',
      'titolo': 'Cena tranquilla',
      'provenienza': 'Sonos',
      'lettore': 'Sonos Soggiorno',
      'come': 'casa',
      'in_casa': true,
    },
    {
      'id': 'p5',
      'titolo': 'Hit della settimana',
      'provenienza': 'Alexa · Amazon Music',
      'come': 'cerca',
      'servizio': 'amazon',
      'cerca': 'Hit della settimana',
      'in_casa': true,
    },
    {'id': 'p6', 'titolo': 'Ninne nanne', 'provenienza': 'Home Assistant', 'come': 'flusso'},
    {'titolo': 'Senza id'},
  ],
};

/// Una casa finta: risponde e si ricorda cosa le si è chiesto.
class _Casa {
  final chieste = <Map<String, Object?>>[];
  Object? Function(Map<String, Object?>)? risponde;

  Future<Object?> chiedi(Map<String, Object?> c) async {
    chieste.add(c);
    final r = risponde?.call(c);
    if (r is Exception) throw r;
    if (r != null) return r;
    return switch (c['type']) {
      'ponte/musica/della-casa' => _risposta(),
      'ponte/musica/flusso' => {
        'brani': [
          {'titolo': 'Stella stellina', 'url': 'https://casa.esempio.it/1.mp3?authSig=x', 'mime': 'audio/mpeg'},
          {'titolo': 'In chiaro', 'url': 'http://casa.esempio.it/2.mp3'},
        ],
      },
      'ponte/musica/in-casa' => {'fatto': true, 'lettore': 'Sonos Soggiorno'},
      _ => null,
    };
  }
}

void main() {
  group('l\'elenco della casa', () {
    test('si legge com\'è, senza le voci rotte e senza la rete in chiaro', () {
      final e = ElencoDiCasa.daRisposta(_risposta());
      expect(e.radio.map((v) => v.id), ['r1', 'r2', 'r3', 'r4']);
      expect(e.playlist.map((v) => v.id), ['p1', 'p2', 'p5', 'p6']);
      expect(e.radio.first.immagine, isNotNull);
      expect(e.radio.first.flusso, 'https://flussi.esempio.it/r1.mp3');
      expect(e.radio[3].flusso, isNull);
      expect(e.radio[2].perche, 'solo-http');
      expect(e.playlist.first.uri, 'spotify:playlist:0000000000000000000001');
      expect(e.playlist[1].inCasa, isTrue);
      expect(e.letto, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(ElencoDiCasa.daRisposta('niente').vuoto, isTrue);
    });
  });

  group('dove suona', () {
    final e = ElencoDiCasa.daRisposta(_risposta());
    VoceDiCasa v(String id) => [...e.radio, ...e.playlist].firstWhere((x) => x.id == id);

    test('una radio in auto, col lettore del navigatore, su Android e sull\'iPhone', () {
      expect(riproduzione(v('r1'), android: true).dove, DoveSuona.inAuto);
      expect(riproduzione(v('r1'), android: false).dove, DoveSuona.inAuto);
    });

    test('una radio solo in chiaro: solo in casa, e si dice perché', () {
      final r = riproduzione(v('r3'), android: true);
      expect(r.dove, DoveSuona.soloInCasa);
      expect(r.spiegazione, contains('http'));
    });

    test('Spotify su Android parte nell\'app; senza l\'app, solo in casa; sull\'iPhone si apre da fermi', () {
      final r = riproduzione(v('p1'), android: true, installate: {'com.spotify.music'});
      expect(r.dove, DoveSuona.nellApp);
      expect(r.app, 'com.spotify.music');
      expect(r.etichetta, 'Su Spotify');
      final senza = riproduzione(v('p1'), android: true, installate: {'com.altra.app'});
      expect(senza.dove, DoveSuona.soloInCasa);
      expect(senza.spiegazione, contains('non c\'è Spotify'));
      expect(senza.spiegazione, contains('su Cucina'));
      expect(riproduzione(v('p1'), android: false).dove, DoveSuona.apriDaFermo);
    });

    test('un preferito di Alexa nell\'app del suo servizio; sull\'iPhone solo in casa', () {
      expect(riproduzione(v('p5'), android: true, installate: {'com.amazon.mp3'}).app, 'com.amazon.mp3');
      expect(riproduzione(v('p5'), android: false).dove, DoveSuona.soloInCasa);
    });

    test('Sonos: solo in casa, e si propone di farla partire lì', () {
      final r = riproduzione(v('p2'), android: true);
      expect(r.dove, DoveSuona.soloInCasa);
      expect(r.suonaInAuto, isFalse);
      expect(r.spiegazione, contains('solo sui lettori di casa'));
      expect(r.spiegazione, contains('Puoi farla partire in casa, su Sonos Soggiorno'));
    });
  });

  group('il gestore', () {
    test('le ultime suonate per prime; le playlist in auto prima di quelle di casa', () async {
      final casa = _Casa();
      final l = LettoreFinto();
      final g = GestoreMusicaDiCasa(
        chiedi: () => casa.chiedi,
        lettore: l,
        android: true,
        installate: () async => {'com.spotify.music'},
      );
      await g.aggiorna();
      expect(g.playlist.map((v) => v.id), ['p1', 'p6', 'p2', 'p5']);
      expect(await g.suona(g.radio[1], daFermi: true), isNull);
      expect(g.radio.first.id, 'r2');
      expect(g.ultima?.id, 'r2');
      // All'auto l'elenco, con dove suona ognuna e l'ultima.
      expect(l.radioPerLAuto.first['id'], 'r2');
      expect(l.playlistPerLAuto.map((m) => m['dove']), ['nellApp', 'inAuto', 'soloInCasa', 'soloInCasa']);
      expect(l.playlistPerLAuto.first['app'], 'com.spotify.music');
    });

    test('una radio suona col lettore nativo insieme alle altre preferite (⏮ ⏭)', () async {
      final casa = _Casa();
      final l = LettoreFinto();
      final g = GestoreMusicaDiCasa(chiedi: () => casa.chiedi, lettore: l, android: true);
      await g.aggiorna();
      final r1 = g.radio.firstWhere((v) => v.id == 'r1');
      expect(await g.suona(r1, daFermi: false), isNull);
      // Solo quelle che hanno un flusso: r1 e r2.
      expect(l.casa.map((v) => v.id), ['r1', 'r2']);
      expect(l.comandi.last, 'flussi:r1');
      expect(l.app, 'Radio di casa');
      expect(l.brano?.titolo, 'Radio Lungomare');
      await l.successivo();
      expect(l.brano?.titolo, 'Onda Vesuviana');
    });

    test('Spotify nell\'app, senza aprirla; da fermi lo si dice al lato nativo', () async {
      final casa = _Casa();
      final l = LettoreFinto();
      final g = GestoreMusicaDiCasa(chiedi: () => casa.chiedi, lettore: l, android: true);
      await g.aggiorna();
      await g.suona(g.playlist.first, daFermi: true);
      expect(l.comandi.last, 'app:com.spotify.music:spotify:playlist:0000000000000000000001:fermo');
    });

    test('una playlist solo di casa non suona in auto: torna la spiegazione, il lettore non si tocca', () async {
      final casa = _Casa();
      final l = LettoreFinto();
      final g = GestoreMusicaDiCasa(chiedi: () => casa.chiedi, lettore: l, android: true);
      await g.aggiorna();
      final sonos = g.playlist.firstWhere((v) => v.id == 'p2');
      final detto = await g.suona(sonos, daFermi: true);
      expect(detto, contains('solo sui lettori di casa'));
      expect(l.comandi, isEmpty);
      expect(await g.avviaInCasa(sonos), 'Parte in casa, su Sonos Soggiorno');
      expect(casa.chieste.last, {'type': 'ponte/musica/in-casa', 'voce': 'p2'});
    });

    test('un file di casa: i brani chiesti adesso alla casa, solo quelli in https', () async {
      final casa = _Casa();
      final l = LettoreFinto();
      final g = GestoreMusicaDiCasa(chiedi: () => casa.chiedi, lettore: l, android: true);
      await g.aggiorna();
      final ninne = g.playlist.firstWhere((v) => v.id == 'p6');
      expect(await g.suona(ninne, daFermi: true), isNull);
      expect(casa.chieste.last, {'type': 'ponte/musica/flusso', 'voce': 'p6'});
      expect(l.casa.map((v) => v.titolo), ['Stella stellina']);
      expect(l.nomeCasa, 'Ninne nanne');
    });

    test('l\'elenco si tiene dieci minuti; senza casa, o senza utente, lo si dice', () async {
      var ora = DateTime(2026, 11, 17, 8);
      final casa = _Casa();
      final g = GestoreMusicaDiCasa(chiedi: () => casa.chiedi, android: true, adesso: () => ora);
      await g.aggiorna();
      await g.aggiorna();
      expect(casa.chieste.length, 1);
      ora = ora.add(const Duration(minutes: 11));
      await g.aggiorna();
      expect(casa.chieste.length, 2);

      final senza = GestoreMusicaDiCasa(chiedi: () => null, android: true);
      await senza.aggiorna();
      expect(senza.errore, 'La casa non è collegata');
      final noUtente = _Casa()..risponde = (_) => Exception('unauthorized: per questo entra col tuo utente');
      final g2 = GestoreMusicaDiCasa(chiedi: () => noUtente.chiedi, android: true);
      await g2.aggiorna();
      expect(g2.errore, contains('riabbina'));
    });

    test('dall\'auto: «solo in casa» la fa partire in casa; un id vuoto rilegge l\'elenco', () async {
      final casa = _Casa();
      final l = LettoreFinto();
      GestoreMusicaDiCasa(chiedi: () => casa.chiedi, lettore: l, android: true);
      expect(await l.toccata!('p2'), 'Parte in casa, su Sonos Soggiorno');
      final prima = casa.chieste.length;
      expect(await l.toccata!(''), isNull);
      expect(casa.chieste.length, prima + 1);
      expect(casa.chieste.last['type'], 'ponte/musica/della-casa');
      expect(await l.toccata!('inventata'), contains('Non c\'è più'));
    });
  });

  group('la scheda «Dalla casa»', () {
    Future<(GestoreMusicaDiCasa, LettoreFinto, _Casa)> monta(WidgetTester tester) async {
      final casa = _Casa();
      final l = LettoreFinto();
      final g = GestoreMusicaDiCasa(chiedi: () => casa.chiedi, lettore: l, android: true);
      await tester.runAsync(g.aggiorna);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaGdanav(Brightness.light),
          home: Scaffold(body: SchedaDallaCasa(gestore: g, chiudi: false)),
        ),
      );
      await tester.pump();
      return (g, l, casa);
    }

    testWidgets('due righe, Radio e Playlist; un tocco su una radio la suona', (tester) async {
      final (_, l, _) = await monta(tester);
      expect(find.text('Radio'), findsOneWidget);
      expect(find.text('Playlist'), findsOneWidget);
      expect(find.text('Su Spotify'), findsOneWidget);
      expect(find.text('Solo in casa'), findsWidgets);
      await tester.tap(find.byKey(const Key('dalla-casa-r1')));
      await tester.pump();
      expect(l.comandi.last, 'flussi:r1');
    });

    testWidgets('una solo di casa: la spiegazione, e «Avvia in casa»', (tester) async {
      final (_, l, casa) = await monta(tester);
      final voce = find.byKey(const Key('dalla-casa-p2'));
      await tester.scrollUntilVisible(voce, 100, scrollable: find.byType(Scrollable).last);
      await tester.tap(voce);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('solo-in-casa')), findsOneWidget);
      expect(find.textContaining('al telefono non arriva'), findsOneWidget);
      await tester.tap(find.byKey(const Key('avvia-in-casa')));
      await tester.pumpAndSettle();
      expect(casa.chieste.last['type'], 'ponte/musica/in-casa');
      expect(find.text('Parte in casa, su Sonos Soggiorno'), findsOneWidget);
      expect(l.comandi, isEmpty);
    });
  });

  group('il mini-lettore', () {
    testWidgets('«Dalla casa» c\'è da fermi, accanto a ▶; in movimento no', (tester) async {
      final l = LettoreFinto(
        app: null,
        prossima: const AppDellaMusica(pacchetto: 'com.spotify.music', nome: 'Spotify'),
      );
      final g = GestoreMusicaDiCasa(chiedi: () => _Casa().chiedi, lettore: l, android: true);
      Future<void> con(bool inMovimento) => tester.pumpWidget(
        MaterialApp(
          theme: temaGdanav(Brightness.light),
          home: Scaffold(
            body: MiniLettore(lettore: l, inMovimento: inMovimento, dallaCasa: g),
          ),
        ),
      );
      await con(false);
      expect(find.byKey(const Key('lettore-avvio')), findsOneWidget);
      expect(find.byKey(const Key('lettore-dalla-casa')), findsOneWidget);
      await con(true);
      expect(find.byKey(const Key('lettore-dalla-casa')), findsNothing);
    });
  });

  group('la radio si comanda dal lettore del navigatore', () {
    testWidgets('suona, e ⏯ ⏭ toccati sul lettore vanno a lei', (tester) async {
      final casa = _Casa();
      final l = LettoreFinto();
      final g = GestoreMusicaDiCasa(chiedi: () => casa.chiedi, lettore: l, android: true);
      await g.aggiorna();
      await g.suona(g.radio.firstWhere((v) => v.id == 'r1'), daFermi: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaGdanav(Brightness.light),
          home: Scaffold(body: MiniLettore(lettore: l, inMovimento: true)),
        ),
      );
      expect(find.text('Radio Lungomare'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lettore-successivo')));
      await tester.pump();
      expect(find.text('Onda Vesuviana'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lettore-play')));
      await tester.pump();
      expect(l.comandi.skip(1), ['successivo', 'playPausa']);
      expect(l.suona, isFalse);
    });
  });

  // Niente comandi dal volante: la musica di casa non dichiara niente al
  // sistema che il Play Store (o Apple) chieda di giustificare. Le prove
  // girano dalla cartella del pacchetto.
  group('nessuna sessione e nessun servizio per la musica di casa', () {
    String leggi(String percorso) => File(percorso).readAsStringSync();

    test('Android: nel manifesto solo il servizio in primo piano della posizione', () {
      final m = leggi('android/src/main/AndroidManifest.xml');
      expect(m, isNot(contains('FOREGROUND_SERVICE_MEDIA_PLAYBACK')));
      expect(m, isNot(contains('mediaPlayback')));
      expect(m, isNot(contains('MediaLibraryService')));
      expect(m, isNot(contains('ServizioLettoreDiCasa')));
      expect(RegExp(r'foregroundServiceType="([^"]*)"').allMatches(m).map((x) => x[1]), ['location']);
      expect(RegExp(r'android\.permission\.FOREGROUND_SERVICE[A-Z_]*').allMatches(m).map((x) => x[0]).toSet(), {
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_LOCATION',
      });
    });

    test('Android: solo ExoPlayer, senza media3-session; nessuna sessione media3 nel codice', () {
      final g = leggi('android/build.gradle.kts');
      expect(g, contains('"androidx.media3:media3-exoplayer:'));
      expect(g, isNot(contains('"androidx.media3:media3-session')));
      expect(g, isNot(contains('"androidx.media3:media3-ui')));
      final kotlin = Directory('android/src/main/kotlin').listSync(recursive: true).whereType<File>();
      for (final f in kotlin) {
        final t = f.readAsStringSync();
        expect(t, isNot(contains('androidx.media3.session')), reason: f.path);
        expect(t, isNot(contains('MediaSessionService')), reason: f.path);
      }
    });

    test('iPhone: niente comandi remoti né «In riproduzione» per la radio di casa', () {
      final s = leggi('ios/gdanav_app/Sources/gdanav_app/LettoreDiCasa.swift');
      expect(s, isNot(contains('MPRemoteCommandCenter.shared')));
      expect(s, isNot(contains('MPNowPlayingInfoCenter.default')));
    });
  });
}
