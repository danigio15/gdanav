/// Le fotografie di quello che è arrivato dal campo: il tachimetro e il
/// limite più grandi, gli autovelox (fissi, mobili, semafori) col limite
/// accanto, la mappa
/// principale col tachimetro anche senza percorso. Non è una prova: è un
/// attrezzo per guardare.
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/dal_campo_foto.dart
/// ```
///
/// Le fotografie finiscono in `collaudo/foto/dal-campo/` (le icone in PNG,
/// per la mappa nel browser, anche quelle), che la repository non tiene.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/icone_segnalazioni.dart';
import 'package:gdanav_app/componenti/tachimetro.dart';
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

const _dove = '../../../../collaudo/foto/dal-campo';

void main() {
  setUp(_caratteri);

  testWidgets('le icone degli autovelox, per la mappa', (tester) async {
    await tester.runAsync(() async {
      final cartella = Directory('../../collaudo/foto/dal-campo/icone')..createSync(recursive: true);
      for (final e in (await iconeSegnalazioni()).entries) {
        File('${cartella.path}/${e.key}.png').writeAsBytesSync(e.value);
      }
    });
  });

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';

    testWidgets('il tachimetro col limite ($luce)', (tester) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 300 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
          home: Scaffold(
            backgroundColor: scuro ? const Color(0xFF28324A) : const Color(0xFFE8ECEF),
            body: const Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Tachimetro(velocitaKmh: 48, limiteKmh: 50),
                  SizedBox(height: 16),
                  Tachimetro(velocitaKmh: 112, limiteKmh: 90),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/tachimetro-$luce.png'));
    });

    testWidgets('senza percorso, andando: il tachimetro sulla mappa principale ($luce)', (tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, km: 20);
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(a.app());
      await tester.pumpAndSettle();
      a.posizione.avvia();
      a.gps.add(const Lettura(Punto(42, 12), velocitaMs: 13.5, rotta: 0));
      await tester.pump();
      a.gps.add(const Lettura(Punto(42.0001, 12), velocitaMs: 13.5, rotta: 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('tachimetro-senza-percorso')), findsOneWidget);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/principale-andando-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
