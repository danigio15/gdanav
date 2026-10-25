/// La punta della freccia di manovra in PNG, per i render della mappa.
///
/// ```sh
/// cd packages/gdanav_app && GDANAV_FOTO=/tmp/scena flutter test test/foto/punta_manovra_foto.dart
/// ```
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/icona_manovra.dart';

void main() {
  testWidgets('la punta', (tester) async {
    final dove = Directory(Platform.environment['GDANAV_FOTO'] ?? 'collaudo/foto/svincolo')
      ..createSync(recursive: true);
    final png = await tester.runAsync(puntaManovraPng);
    File('${dove.path}/manovra-punta.png').writeAsBytesSync(png!);
    File('${dove.path}/arrivo-bandiera.png').writeAsBytesSync((await tester.runAsync(bandieraArrivoPng))!);
  });
}
