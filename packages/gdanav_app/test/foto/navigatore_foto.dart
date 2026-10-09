/// Le fotografie del navigatore: il tasto dell'audio in guida nei suoi tre
/// stati e la mappa principale col tasto 2D/3D.
///
/// Non è una prova: è un attrezzo per **guardare** (il nome non finisce in
/// `_test.dart`, e `flutter test` da solo non lo prende). Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/navigatore_foto.dart
/// ```
///
/// Le fotografie finiscono in `collaudo/foto/navigatore/`, che la repository
/// non tiene. La mappa è un riquadro grigio: quella vera vuole il codice
/// nativo (il percorso col traffico si guarda con `stile_json_foto.dart`).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/schermata_guida.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/voce.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../aiuti.dart';

/// Roboto e le icone di Material, dalla cartella di Flutter: senza, la
/// fotografia esce a quadratini.
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

const _dove = '../../../../collaudo/foto/navigatore';

void main() {
  setUp(_caratteri);

  void tema(WidgetTester tester, {required bool scuro}) {
    tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';

    testWidgets('il tasto dell\'audio, i tre stati ($luce)', (tester) async {
      tester.view
        ..physicalSize = const Size(330 * 3, 120 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final m in ModoAudio.values)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TastoAudio(key: ValueKey(m), audio: m, onPressed: () {}),
                          const SizedBox(height: 8),
                          Text(switch (m) {
                            ModoAudio.tutto => 'Tutto',
                            ModoAudio.soloAvvisi => 'Solo avvisi',
                            ModoAudio.silenzio => 'Silenzio',
                          }, style: Theme.of(context).textTheme.labelMedium),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/audio-tre-stati-$luce.png'));
    });

    testWidgets('la guida, col tasto dell\'audio in ogni stato ($luce)', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, km: 20);
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      tema(tester, scuro: scuro);
      await tester.pumpWidget(a.app());
      a.auto.manuale.imposta(90);
      await tester.pump();
      await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
      await tester.pumpAndSettle();
      expect(a.viaggio.stato, isA<ViaggioPronto>());
      await tester.tap(find.text('Avvia'));
      await tester.pumpAndSettle();
      for (final m in ModoAudio.values) {
        expect(a.guida.audio, m);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/guida-audio-${m.chiave}-$luce.png'));
        await tester.tap(find.byKey(const Key('audio')));
        await tester.pump();
      }
      await tester.runAsync(a.guida.ferma);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('la mappa principale col tasto 2D/3D ($luce)', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, km: 20);
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      tema(tester, scuro: scuro);
      await tester.pumpWidget(a.app());
      await tester.pumpAndSettle();
      // Di partenza 3D: il tasto propone il 2D.
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/principale-in-3d-$luce.png'));
      await tester.tap(find.text('2D'));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/principale-in-2d-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
