/// Lo stile della mappa in JSON, per guardarlo fuori dall'app: con MapLibre
/// GL JS in un browser si disegna il percorso col traffico, chiaro e scuro.
///
/// Non è una prova (il nome non finisce in `_test.dart`). Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && GDANAV_STILE=/tmp/stile flutter test test/foto/stile_json_foto.dart
/// ```
///
/// Scrive `chiaro.json`, `scuro.json`, `auto-chiaro.json` e `auto-scuro.json`
/// nella cartella di `GDANAV_STILE` (di solito `collaudo/foto/stile/`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/stile.dart';

void main() {
  test('lo stile in JSON', () {
    final dove = Directory(Platform.environment['GDANAV_STILE'] ?? 'collaudo/foto/stile')..createSync(recursive: true);
    for (final (nome, scuro, perAuto) in [
      ('chiaro', false, false),
      ('scuro', true, false),
      ('auto-chiaro', false, true),
      ('auto-scuro', true, true),
    ]) {
      final stile = stileMappa(scuro: scuro, chiaveTraffico: 'CHIAVE', perAuto: perAuto);
      File('${dove.path}/$nome.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(stile));
    }
  });
}
