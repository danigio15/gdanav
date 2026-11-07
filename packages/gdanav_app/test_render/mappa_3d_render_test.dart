// Le immagini della guida con la mappa 3D: il cruscotto vero di Flutter
// sopra la foto della mappa 3D fatta dal collaudo nel browser
// (`web3d/collaudo/collaudo.mjs`). Non è una prova che gira con
// `flutter test` (sta fuori da test/), si lancia apposta:
//
//     flutter test test_render/mappa_3d_render_test.dart
//
// Legge i percorsi e le foto da GDANAV_3D_COLLAUDO (di solito
// web3d/collaudo/uscita) e scrive i PNG in GDANAV_RENDER: per ogni caso del
// collaudo il telefono dritto di giorno e di notte (390×844 punti, densità
// 2), e per Rho/Pero anche di traverso. La guida è vera: lo stesso percorso
// della foto, l'auto dove la mette il collaudo, una manovra davanti.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../test/aiuti.dart';

final cartella = Platform.environment['GDANAV_RENDER'] ?? '/home/user/render/gdanav-3d';
final collaudo = Platform.environment['GDANAV_3D_COLLAUDO'] ?? 'web3d/collaudo/uscita';
final _font =
    Platform.environment['GDANAV_FONT'] ??
    '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter'}/bin/cache/artifacts/material_fonts';

Future<void> _caricaFont() async {
  Future<ByteData> leggi(String nome) async => ByteData.sublistView(await File('$_font/$nome').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final peso in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(leggi('Roboto-$peso.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(leggi('MaterialIcons-Regular.otf'))).load();
}

/// La manovra davanti all'auto in ogni caso: dove (metri dall'auto, o
/// assoluti con [metri]), cosa dice il cartello, le corsie; il limite e la
/// velocità; e il nome della meta.
class _Caso {
  const _Caso(
    this.istruzione,
    this.verso, {
    this.davanti = 600,
    this.metri,
    this.tipo = 20,
    this.corsie = const [],
    this.limite = 90,
    this.kmh = 72,
    this.meta = 'Destinazione',
    this.percorso,
    this.foto,
  });
  final String istruzione;
  final String verso;
  final double davanti;
  final double? metri;
  final int tipo;
  final List<Corsia> corsie;
  final int limite;
  final int kmh;
  final String meta;

  /// Il percorso di un altro caso (per il «prima», la mappa di oggi).
  final String? percorso;

  /// Il nome della foto della mappa, se non è quella del caso.
  final String? foto;
}

const _destra = [
  Corsia([DirezioneCorsia.dritto]),
  Corsia([DirezioneCorsia.leggeraDestra], giusta: true, consigliata: DirezioneCorsia.leggeraDestra),
];
const _casi = {
  'rho': _Caso(
    "Prendi l'uscita a destra verso A8",
    'A8 · Milano · Varese',
    metri: 2994,
    corsie: _destra,
    limite: 80,
    meta: 'Milano, viale Certosa',
  ),
  'roma': _Caso(
    'Prosegui sulla rampa verso A24',
    "A24 · L'Aquila · Teramo",
    davanti: 450,
    tipo: 22,
    meta: 'Roma, Tor Cervara',
  ),
  'bologna': _Caso(
    'Prosegui sulla SS569 verso Vignola',
    'SS569 · Vignola',
    davanti: 420,
    tipo: 22,
    limite: 70,
    kmh: 64,
    meta: 'Casalecchio di Reno',
  ),
  'cavalcavia': _Caso(
    'Prosegui sulla A14 verso Casalecchio',
    'A14 · Casalecchio',
    davanti: 380,
    tipo: 22,
    limite: 130,
    kmh: 112,
    meta: 'Bologna, Borgo Panigale',
  ),
  'napoli': _Caso(
    'Prosegui verso la Tangenziale',
    'Tangenziale · Pozzuoli',
    davanti: 320,
    tipo: 22,
    limite: 60,
    kmh: 58,
    meta: 'Napoli, Capodichino',
  ),
  'torino': _Caso(
    'Alla fine della rampa svolta a destra',
    'Corso Francia · Rivoli',
    davanti: 210,
    tipo: 10,
    limite: 40,
    kmh: 38,
    meta: 'Torino, corso Francia',
  ),
  'genova': _Caso(
    'Prosegui sulla A10 verso Aeroporto',
    'A10 · Genova Aeroporto',
    davanti: 700,
    tipo: 22,
    limite: 80,
    kmh: 78,
    meta: 'Genova, Sampierdarena',
  ),
  // La stessa guida di Rho con la mappa di oggi (MapLibre nativa inclinata).
  'rho-prima': _Caso(
    "Prendi l'uscita a destra verso A8",
    'A8 · Milano · Varese',
    metri: 2994,
    corsie: _destra,
    limite: 80,
    meta: 'Milano, viale Certosa',
    percorso: 'rho',
    foto: 'rho-telefono-prima',
  ),
  'sottopasso': _Caso(
    'Prosegui nel sottopasso',
    'Centro',
    davanti: 250,
    tipo: 22,
    limite: 50,
    kmh: 46,
    meta: 'Milano, Isola',
  ),
};

/// Il percorso della foto, con la manovra del caso e i limiti.
(PercorsoCalcolato, double) _percorso(String nome, _Caso c) {
  final j = jsonDecode(File('$collaudo/percorso-${c.percorso ?? nome}.json').readAsStringSync()) as Map;
  final xy = (j['punti'] as List).cast<num>();
  final auto = (j['auto'] as num).toDouble();
  final punti = [for (var i = 0; i < xy.length; i += 2) Punto(xy[i + 1].toDouble(), xy[i].toDouble())];
  final linea = Linea(punti);
  final dove = c.metri ?? auto + c.davanti;
  var k = 1;
  while (k < punti.length - 2 && linea.cumulate[k] < dove) {
    k++;
  }
  return (
    PercorsoCalcolato(
      punti: punti,
      tratti: [
        for (var i = 1; i < punti.length; i++)
          Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: c.kmh.toDouble()),
      ],
      manovre: [
        const Manovra(istruzione: 'Parti', lunghezzaM: 0, secondi: 0, inizio: 0, tipo: 1),
        Manovra(
          istruzione: c.istruzione,
          lunghezzaM: linea.lunghezzaM - linea.cumulate[k],
          secondi: 30,
          inizio: k,
          tipo: c.tipo,
          verso: c.verso,
          corsie: c.corsie,
        ),
        Manovra(istruzione: 'Sei arrivato', lunghezzaM: 0, secondi: 0, inizio: punti.length - 1, tipo: 4),
      ],
      limiti: [for (var i = 1; i < punti.length; i++) c.limite],
    ),
    auto,
  );
}

Punto _a(Linea l, double metri) {
  for (var i = 1; i < l.punti.length; i++) {
    if (l.cumulate[i] >= metri) {
      final t = (metri - l.cumulate[i - 1]) / (l.cumulate[i] - l.cumulate[i - 1]);
      final a = l.punti[i - 1], b = l.punti[i];
      return Punto(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
    }
  }
  return l.punti.last;
}

final _chiave = GlobalKey();

void main() {
  setUpAll(_caricaFont);

  for (final MapEntry(key: nome, value: c) in _casi.entries) {
    for (final notte in [false, true]) {
      // Di traverso solo con GDANAV_TRAVERSO=1: il cruscotto della guida su un
      // telefono di traverso non ci sta (la barra in fondo esce dallo schermo,
      // anche con la mappa di sempre), e la foto lo mostrerebbe.
      for (final traverso in [false, if (Platform.environment['GDANAV_TRAVERSO'] == '1') true]) {
        final momento = notte ? 'notte' : 'giorno';
        final foto = File(
          c.foto == null
              ? '$collaudo/$nome-${traverso ? 'orizzontale' : 'telefono'}-$momento.png'
              : '$collaudo/${c.foto}-$momento.png',
        );
        if ((c.foto != null && traverso) ||
            !foto.existsSync() ||
            !File('$collaudo/percorso-${c.percorso ?? nome}.json').existsSync()) {
          continue;
        }
        testWidgets('guida con la mappa 3D: $nome, $momento${traverso ? ', di traverso' : ''}', (tester) async {
          debugDisableShadows = false;
          tester.platformDispatcher.platformBrightnessTestValue = notte ? Brightness.dark : Brightness.light;
          addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
          preparaPiattaforma(portachiavi: impostazioniComplete);
          final (percorso, auto) = _percorso(nome, c);
          final linea = Linea(percorso.punti);
          final a = await ambiente(
            tester,
            posizione: percorso.punti.first,
            costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
              percorsi: (_) async => percorso,
              colonnine: ColonnineFinte(),
              profilo: profilo,
              preferenze: preferenze,
            ),
          );
          tester.view.physicalSize = traverso ? const Size(1688, 780) : const Size(780, 1688);
          tester.view.devicePixelRatio = 2;
          final bordo = traverso
              ? const FakeViewPadding(left: 94, right: 94, bottom: 42)
              : const FakeViewPadding(top: 94, bottom: 68);
          tester.view.padding = bordo;
          tester.view.viewPadding = bordo;
          final byte = await tester.runAsync(() => foto.readAsBytes());
          final immagine = MemoryImage(byte!);
          await tester.pumpWidget(
            RepaintBoundary(
              key: _chiave,
              child: GdanavApp(
                posizione: a.posizione,
                archivio: a.archivio,
                auto: a.auto,
                viaggio: a.viaggio,
                guida: a.guida,
                segnalazioni: a.segnalazioni,
                // La mappa 3D com'è sul telefono: qui la sua foto dal browser.
                mappa: (_, _) => Image(image: immagine, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
          );
          a.auto.manuale.imposta(82);
          await tester.pump();
          await tester.runAsync(() => a.viaggio.vaiA(Luogo(nome: c.meta, posizione: percorso.punti.last)));
          await tester.pumpAndSettle();
          // La guida parte come quando la avvia l'auto: si apre la sua schermata.
          a.guida.avvia();
          await tester.pumpAndSettle();
          await tester.runAsync(() => precacheImage(immagine, tester.element(find.byType(Image).first)));
          final qui = _a(linea, auto);
          final rotta = rottaGradi(qui, _a(linea, auto + 10));
          a.posizione.avvia();
          for (var i = 0; i < 3; i++) {
            a.gps.add(Lettura(qui, rotta: rotta, velocitaMs: c.kmh / 3.6));
            a.posizioni.add(qui);
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
            await tester.pump(const Duration(milliseconds: 300));
          }
          await tester.pump(const Duration(milliseconds: 500));
          await tester.runAsync(() async {
            final confine = _chiave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final img = await confine.toImage(pixelRatio: 2);
            final dati = await img.toByteData(format: ui.ImageByteFormat.png);
            final f = File('$cartella/$nome-guida-${traverso ? 'orizzontale' : 'telefono'}-$momento.png');
            await f.parent.create(recursive: true);
            await f.writeAsBytes(dati!.buffer.asUint8List());
            debugPrint('scritto ${f.path}');
          });
          // Via la guida dallo schermo: i suoi orologi si fermano con lei.
          await tester.pumpWidget(const SizedBox());
          debugDisableShadows = true;
        });
      }
    }
  }
}
