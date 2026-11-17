/// Le fotografie della musica di casa sul telefono: la scheda «Dalla casa»
/// (le radio preferite e le playlist della plancia di GdAHome), la
/// spiegazione di una playlist che si suona solo in casa, il lettore mentre
/// suona una radio di casa, e la voce nelle impostazioni. Stazioni e playlist
/// inventate.
///
/// Non è una prova: è un attrezzo per guardare. Si lancia a mano:
///
/// ```sh
/// SFONDI=/percorso/degli/sfondi DATI=/percorso/immagini FOTO_CASA=/percorso/uscita \
///   flutter test --update-goldens test/foto/musica_di_casa_foto.dart
/// ```
///
/// In `DATI` i loghi `radio-1.png`… e le copertine `pl-1.png`…, e l'icona
/// (finta) dell'app della musica `icona-app.png`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../aiuti.dart';

Future<void> _caratteri() async {
  final radice = Platform.environment['FLUTTER_ROOT'];
  if (radice == null || radice.isEmpty) return;
  final cartella = '$radice/bin/cache/artifacts/material_fonts';
  Future<ByteData> leggi(String nome) => File('$cartella/$nome').readAsBytes().then((b) => b.buffer.asByteData());
  for (final famiglia in ['Roboto', 'packages/gdanav_app/Roboto']) {
    final f = FontLoader(famiglia);
    for (final peso in ['Regular', 'Medium', 'Bold', 'Black']) {
      if (File('$cartella/Roboto-$peso.ttf').existsSync()) f.addFont(leggi('Roboto-$peso.ttf'));
    }
    await f.load();
  }
  if (File('$cartella/MaterialIcons-Regular.otf').existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(leggi('MaterialIcons-Regular.otf'))).load();
  }
}

final _dove = Platform.environment['FOTO_CASA'] ?? '../../../../collaudo/foto/musica-di-casa';
final _sfondi = Platform.environment['SFONDI'];
final _sfondiLibera = Platform.environment['SFONDI_LIBERA'] ?? _sfondi;
final _dati = Platform.environment['DATI'];

Map<String, Object?>? _img(String nome) {
  final f = _dati == null ? null : File('$_dati/$nome.png');
  return f != null && f.existsSync() ? {'tipo': 'image/png', 'dati': base64Encode(f.readAsBytesSync())} : null;
}

/// Quello che risponderebbe il ponte di una casa inventata.
Map<String, Object?> _risposta() => {
  'letto': 0,
  'radio': [
    for (final (i, nome) in [
      'Radio Lungomare',
      'Onda Vesuviana',
      'Radio Collina 98',
      'Jazz di Notte',
      'Radio Campanile',
      'Notiziario Ventiquattro',
    ].indexed)
      {
        'id': 'r${i + 1}',
        'titolo': nome,
        'provenienza': 'Radio Browser',
        'immagine': _img('radio-${i + 1}'),
        // Radio Collina 98 trasmette solo in chiaro (http): in auto no.
        if (i == 2) ...{
          'come': 'casa',
          'perche': 'solo-http',
        } else ...{
          'come': 'flusso',
          'flusso': 'https://flussi.esempio.it/r${i + 1}.mp3',
          'mime': 'audio/mpeg',
        },
      },
  ],
  'playlist': [
    {
      'id': 'p1',
      'titolo': 'Viaggio in auto',
      'provenienza': 'Spotify',
      'lettore': 'Cucina',
      'immagine': _img('pl-1'),
      'come': 'spotify',
      'uri': 'spotify:playlist:0000000000000000000001',
      'in_casa': true,
    },
    {
      'id': 'p2',
      'titolo': 'Cena tranquilla',
      'provenienza': 'Sonos',
      'lettore': 'Sonos Soggiorno',
      'immagine': _img('pl-2'),
      'come': 'casa',
      'in_casa': true,
    },
    {
      'id': 'p3',
      'titolo': 'Domenica mattina',
      'provenienza': 'Music Assistant · Spotify',
      'lettore': 'Studio',
      'immagine': _img('pl-3'),
      'come': 'spotify',
      'uri': 'spotify:playlist:0000000000000000000003',
      'in_casa': true,
    },
    {
      'id': 'p4',
      'titolo': 'Classici italiani',
      'provenienza': 'Music Assistant',
      'lettore': 'Studio',
      'immagine': _img('pl-4'),
      'come': 'casa',
      'in_casa': true,
    },
    {
      'id': 'p5',
      'titolo': 'Hit della settimana',
      'provenienza': 'Alexa · Spotify',
      'lettore': 'Echo Cucina',
      'immagine': _img('pl-5'),
      'come': 'cerca',
      'servizio': 'spotify',
      'cerca': 'Hit della settimana',
      'in_casa': true,
    },
    {
      'id': 'p6',
      'titolo': 'Ninne nanne',
      'provenienza': 'Home Assistant',
      'immagine': _img('pl-6'),
      'come': 'flusso',
      'in_casa': false,
    },
  ],
};

final _spotify = AppDellaMusica(
  pacchetto: ElencoAppMusica.spotify,
  nome: 'Spotify',
  icona: switch (_dati) {
    final d? when File('$d/icona-app.png').existsSync() => MemoryImage(File('$d/icona-app.png').readAsBytesSync()),
    _ => null,
  },
);

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
      Manovra(istruzione: 'Parti', lunghezzaM: 400, secondi: 30, inizio: 0, tipo: 1, strada: 'Via Appia'),
      Manovra(
        istruzione: 'Svolta a destra in Via Roma',
        lunghezzaM: 300,
        secondi: 25,
        inizio: 4,
        tipo: 10,
        strada: 'Via Roma',
      ),
      Manovra(istruzione: 'Sei arrivato', lunghezzaM: 0, secondi: 0, inizio: 200, tipo: 4),
    ],
    limiti: [for (var i = 0; i < 200; i++) 50],
  );
}

typedef _Caso = ({String nome, bool apri, String? tocca, bool fermo, bool libera, bool soloVerticale});

final _casi = <_Caso>[
  // Da fermo, niente che suona: «▶ Spotify» e accanto il tondo della casa; toccato, la scheda.
  (nome: 'dalla-casa', apri: true, tocca: null, fermo: true, libera: true, soloVerticale: false),
  // Toccata una playlist di Sonos: si suona solo in casa, e si propone di farla partire lì.
  (nome: 'dalla-casa-solo-in-casa', apri: true, tocca: 'p2', fermo: true, libera: true, soloVerticale: true),
  // Toccata una radio che trasmette solo in chiaro: lo si dice (e in casa no: le radio si avviano dalla plancia).
  (nome: 'dalla-casa-radio-solo-http', apri: true, tocca: 'r3', fermo: true, libera: true, soloVerticale: true),
  // Toccata una radio: la scheda si chiude e il lettore la suona (da fermi, la scelta «Dalla casa»).
  (nome: 'radio-di-casa', apri: true, tocca: 'r1', fermo: true, libera: true, soloVerticale: false),
  // La stessa radio in guida, in movimento: solo il lettore.
  (nome: 'radio-di-casa-in-guida', apri: true, tocca: 'r1', fermo: false, libera: false, soloVerticale: true),
];

void main() {
  setUp(_caratteri);

  for (final verticale in [true, false]) {
    for (final notte in [false, true]) {
      final verso = verticale ? 'verticale' : 'orizzontale';
      final luce = notte ? 'notte' : 'giorno';
      for (final caso in _casi) {
        if (caso.soloVerticale && !verticale) continue;
        testWidgets('${caso.nome}, $verso, $luce', (tester) async {
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
          tester.view
            ..physicalSize = const Size(390 * 3, 844 * 3)
            ..devicePixelRatio = 3
            ..padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
          tester.platformDispatcher.platformBrightnessTestValue = notte ? Brightness.dark : Brightness.light;
          addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
          final cartella = caso.libera ? _sfondiLibera : _sfondi;
          final file = cartella == null ? null : File('$cartella/$verso-$luce.png');
          final fondo = file != null && file.existsSync() ? MemoryImage(file.readAsBytesSync()) : null;
          final lettore = LettoreFinto(app: null, prossima: _spotify, appInstallate: [_spotify]);
          addTearDown(lettore.dispose);
          final risposta = _risposta();
          final musica = GestoreMusicaDiCasa(
            chiedi: () =>
                (c) async => risposta,
            lettore: lettore,
            android: true,
            installate: () async => {ElencoAppMusica.spotify},
          );
          final casa = GestoreCasaInGuida(
            archivio: a.archivio,
            coda: CodaAvvisiDiCasa(),
            lettore: lettore,
            musicaDiCasa: musica,
          );
          addTearDown(casa.dispose);
          final app = GdanavApp(
            posizione: a.posizione,
            archivio: a.archivio,
            auto: a.auto,
            viaggio: a.viaggio,
            guida: a.guida,
            segnalazioni: a.segnalazioni,
            casaInGuida: casa,
            mappa: (context, c) => fondo == null
                ? const ColoredBox(color: Colors.grey)
                : Image(image: fondo, fit: BoxFit.cover, gaplessPlayback: true),
          );
          await tester.pumpWidget(_conBarra(app, verticale: verticale, notte: notte));
          final contesto = tester.element(find.byType(Scaffold).first);
          await tester.runAsync(() async {
            if (fondo != null) await precacheImage(fondo, contesto);
            if (_spotify.icona case final i?) await precacheImage(i, contesto);
            await musica.aggiorna();
          });
          a.posizione.avvia();
          a.auto.manuale.imposta(90);
          await tester.pump();
          if (!caso.libera) {
            await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Villa Gialla', posizione: Punto(42.18, 12))));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Avvia'));
          }
          await tester.pumpAndSettle();
          if (!verticale) {
            tester.view
              ..physicalSize = const Size(844 * 3, 390 * 3)
              ..padding = const FakeViewPadding(left: 47 * 3, right: 47 * 3, bottom: 21 * 3);
            await tester.pumpAndSettle();
          }
          const qui = Punto(42.0009, 12);
          Future<void> gps(double v) => tester.runAsync(() async {
            a.gps.add(Lettura(qui, velocitaMs: v, rotta: 0, precisioneM: 5));
            a.posizioni.add(qui);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          // Si sceglie da fermi; in guida poi si riparte.
          await gps(0);
          await tester.pump(const Duration(milliseconds: 400));
          if (caso.apri) {
            if (!caso.libera) {
              // In guida da fermi il lettore è chiuso a pillola: la scelta la si fa
              // dalla scheda come farebbe la pillola.
              await tester.runAsync(() async {});
              mostraDallaCasa(tester.element(find.byType(Scaffold).first), musica);
            } else {
              await tester.tap(find.byKey(const Key('lettore-dalla-casa')));
            }
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            // Le immagini della scheda, lette davvero.
            await tester.runAsync(() async {
              for (final el in find.byType(Image).evaluate()) {
                final w = el.widget as Image;
                await precacheImage(w.image, el);
              }
            });
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (caso.tocca case final id?) {
            final voce = find.byKey(Key('dalla-casa-$id'));
            await tester.scrollUntilVisible(voce, 120, scrollable: find.byType(Scrollable).last);
            await tester.pump(const Duration(milliseconds: 300));
            await tester.tap(voce);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
          }
          if (!caso.fermo) {
            await gps(13.4);
            await tester.pump(const Duration(milliseconds: 600));
          }
          await tester.runAsync(() async {
            for (final el in find.byType(Image).evaluate()) {
              await precacheImage((el.widget as Image).image, el);
            }
          });
          await tester.pump(const Duration(milliseconds: 300));
          await expectLater(
            find.byKey(const Key('foto')),
            matchesGoldenFile('$_dove/telefono-$verso-$luce-${caso.nome}.png'),
          );
          if (!caso.libera) await tester.runAsync(a.guida.ferma);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  for (final notte in [false, true]) {
    final luce = notte ? 'notte' : 'giorno';
    testWidgets('impostazioni, $luce', (tester) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 1700 * 3)
        ..devicePixelRatio = 3
        ..padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      preparaPiattaforma();
      final lettore = LettoreFinto(permesso: true, appInstallate: [_spotify]);
      addTearDown(lettore.dispose);
      final casa = GestoreCasaInGuida(
        archivio: Archivio(),
        coda: CodaAvvisiDiCasa(),
        lettore: lettore,
        musicaDiCasa: GestoreMusicaDiCasa(
          chiedi: () =>
              (c) async => _risposta(),
          lettore: lettore,
          android: true,
        ),
      );
      addTearDown(casa.dispose);
      await tester.runAsync(casa.carica);
      final pagina = MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaGdanav(notte ? Brightness.dark : Brightness.light),
        home: NotificheNelNavigatoreSchermata(gestore: casa),
      );
      await tester.pumpWidget(_conBarra(pagina, verticale: true, notte: notte));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('foto')),
        matchesGoldenFile('$_dove/telefono-impostazioni-musica-di-casa-$luce.png'),
      );
    });
  }
}

Widget _conBarra(Widget app, {required bool verticale, required bool notte}) {
  final chiaro = notte ? Colors.white : Colors.black;
  return KeyedSubtree(
    key: const Key('foto'),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          app,
          if (verticale)
            Positioned(
              top: 14,
              left: 40,
              right: 30,
              child: IgnorePointer(
                child: Row(
                  children: [
                    Text(
                      '08:06',
                      style: TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w700, color: chiaro),
                    ),
                    const Spacer(),
                    Icon(Icons.signal_cellular_alt_rounded, size: 17, color: chiaro),
                    const SizedBox(width: 4),
                    Icon(Icons.wifi_rounded, size: 17, color: chiaro),
                    const SizedBox(width: 4),
                    Icon(Icons.battery_5_bar_rounded, size: 18, color: chiaro),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
