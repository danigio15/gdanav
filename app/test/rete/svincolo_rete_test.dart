import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/componenti/vista_svincolo.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Con la rete e la chiave di Mapillary (in CI, job «svincolo-foto»): su
/// percorsi veri cerca gli svincoli che hanno una foto e ne disegna la vista,
/// come la vedrà chi guida. Le immagini finiscono nella release.
void main() {
  final token = Platform.environment['MAPILLARY'] ?? '';
  final uscita = Platform.environment['USCITA'] ?? 'build/svincoli';
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'foto vere degli svincoli, con la vista sopra',
    () async {
      HttpOverrides.global = null;
      final base = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
      Future<ByteData> f(String n) async => ByteData.sublistView(File('$base/$n').readAsBytesSync());
      await (FontLoader('Roboto')..addFont(f('Roboto-Bold.ttf'))).load();
      await (FontLoader('MaterialIcons')..addFont(f('MaterialIcons-Regular.otf'))).load();
      final valhalla = ClienteValhalla(Uri.parse('https://valhalla1.openstreetmap.de/'));
      final mapillary = ClienteMapillary(token);
      Directory(uscita).createSync(recursive: true);
      const viaggi = [
        // Napoli → Caserta (A1), Milano → Bergamo (A4), Roma → Fiumicino.
        [Punto(40.861, 14.285), Punto(41.073, 14.327)],
        [Punto(45.4642, 9.19), Punto(45.698, 9.677)],
        [Punto(41.90, 12.50), Punto(41.80, 12.25)],
      ];
      var trovate = 0;
      for (final tappe in viaggi) {
        final p = await valhalla.calcola(tappe);
        final linea = Linea(p.punti);
        for (final m in p.manovre.where(haSvincolo)) {
          final r = await mapillary.fotoSvincolo(linea, linea.cumulate[m.inizio]);
          stdout.writeln('${m.istruzione} → ${r == null ? 'nessuna foto' : r.$1.citazione}');
          if (r == null) continue;
          trovate++;
          File('$uscita/svincolo_$trovate.png')
              .writeAsBytesSync(await svincoloPng(m, foto: r.$2, citazione: r.$1.citazione));
          if (trovate >= 4) break;
        }
        if (trovate >= 4) break;
      }
      stdout.writeln('::notice title=Svincoli::$trovate foto trovate');
      expect(trovate, greaterThan(0));
    },
    skip: token.isEmpty ? 'serve MAPILLARY' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
