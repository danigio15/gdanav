// Le immagini della guida con la mappa 3D: il cruscotto vero di Flutter
// sopra la foto della mappa 3D fatta dal collaudo nel browser
// (`web3d/collaudo/collaudo.mjs`). Non è una prova che gira con
// `flutter test` (sta fuori da test/), si lancia apposta:
//
//     flutter test test_render/mappa_3d_render_test.dart
//
// Legge il percorso e le foto da GDANAV_3D_COLLAUDO (di solito
// web3d/collaudo/uscita) e scrive i PNG in GDANAV_RENDER, a 390×844 punti
// con densità 2. La guida è vera: lo stesso percorso della foto (Rho/Pero,
// A4 → viadotto A52 → A8), l'auto a 1790 m, l'uscita verso l'A8 a 1,2 km.

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

/// Il percorso della foto, con l'uscita verso l'A8 e i limiti.
PercorsoCalcolato _percorso() {
  final j = jsonDecode(File('$collaudo/percorso-rho.json').readAsStringSync()) as Map;
  final xy = (j['punti'] as List).cast<num>();
  final punti = [for (var i = 0; i < xy.length; i += 2) Punto(xy[i + 1].toDouble(), xy[i].toDouble())];
  final linea = Linea(punti);
  // L'uscita dove la mappa 3D ha la freccia (2994 m, come nel prototipo).
  var k = 1;
  while (k < punti.length - 1 && linea.cumulate[k] < 2994) {
    k++;
  }
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 66),
    ],
    manovre: [
      const Manovra(istruzione: 'Parti verso nord', lunghezzaM: 0, secondi: 0, inizio: 0, tipo: 1),
      Manovra(
        istruzione: "Prendi l'uscita a destra verso A8",
        lunghezzaM: linea.lunghezzaM - linea.cumulate[k],
        secondi: 30,
        inizio: k,
        tipo: 20,
        verso: 'A8 · Milano · Varese',
        corsie: const [
          Corsia([DirezioneCorsia.dritto]),
          Corsia([DirezioneCorsia.leggeraDestra], giusta: true, consigliata: DirezioneCorsia.leggeraDestra),
        ],
      ),
      Manovra(istruzione: 'Sei arrivato', lunghezzaM: 0, secondi: 0, inizio: punti.length - 1, tipo: 4),
    ],
    limiti: [for (var i = 1; i < punti.length; i++) linea.cumulate[i] < 1900 ? 80 : 90],
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

  for (final notte in [false, true]) {
    testWidgets('guida con la mappa 3D, ${notte ? 'notte' : 'giorno'}', (tester) async {
      debugDisableShadows = false;
      tester.platformDispatcher.platformBrightnessTestValue = notte ? Brightness.dark : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final percorso = _percorso();
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
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      tester.view.padding = const FakeViewPadding(top: 94, bottom: 68);
      tester.view.viewPadding = const FakeViewPadding(top: 94, bottom: 68);
      final foto = await tester.runAsync(() => File('$collaudo/rho-${notte ? 'notte' : 'giorno'}.png').readAsBytes());
      final immagine = MemoryImage(foto!);
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
      await tester.runAsync(() => a.viaggio.vaiA(Luogo(nome: 'Milano, viale Certosa', posizione: percorso.punti.last)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avvia'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => precacheImage(immagine, tester.element(find.byType(Image).first)));
      // L'auto a 1790 m, a 72 all'ora.
      final qui = _a(linea, 1790);
      final rotta = rottaGradi(qui, _a(linea, 1800));
      a.posizione.avvia();
      for (var i = 0; i < 3; i++) {
        a.gps.add(Lettura(qui, rotta: rotta, velocitaMs: 20));
        a.posizioni.add(qui);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        final confine = _chiave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await confine.toImage(pixelRatio: 2);
        final dati = await img.toByteData(format: ui.ImageByteFormat.png);
        final f = File('$cartella/guida-3d-telefono-${notte ? 'notte' : 'giorno'}.png');
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
