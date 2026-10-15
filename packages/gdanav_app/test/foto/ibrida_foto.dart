/// La fotografia di «La tua auto» con una termica ibrida (e-Power). Non è
/// una prova: è un attrezzo per guardare.
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/ibrida_foto.dart
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/la_tua_auto.dart';
import 'package:gdanav_app/tema.dart';

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

final _dove = Platform.environment['FOTO_IBRIDA'] ?? '../../../../collaudo/foto/ibrida';

void main() {
  setUp(_caratteri);
  for (final scuro in [false, true]) {
    testWidgets('la tua auto, ibrida (${scuro ? 'scuro' : 'chiaro'})', (tester) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 900 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester);
      await tester.runAsync(() async {
        await a.auto.impostaElettrica(false);
        await a.auto.impostaIbrida(true);
      });
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
          home: LaTuaAuto(auto: a.auto, posizione: a.posizione),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/la-tua-auto-${scuro ? 'scuro' : 'chiaro'}.png'));
    });
  }
}
