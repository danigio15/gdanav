/// Gli autovelox fissi di OpenStreetMap per l'archivio dentro l'app
/// (`packages/gdanav_app/assets/autovelox.json`):
///
///     osmium tags-filter italy.osm.pbf n/highway=speed_camera -o av.osm.pbf
///     osmium export av.osm.pbf -f geojsonseq -o av.geojsonseq
///     dart run tool/autovelox_osm.dart autovelox.json av.geojsonseq [altri…]
///
/// In CI, insieme alle colonnine, quando il commit contiene «[colonnine]».
library;

import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';

/// «50», «IT:urban», «90 mph», «50;70»: in km/h, il più basso.
int? limite(Object? v) {
  if (v is! String) return null;
  const nazionali = {'IT:urban': 50, 'IT:rural': 90, 'IT:trunk': 110, 'IT:motorway': 130};
  if (nazionali[v] case final n?) return n;
  final numeri = RegExp(r'\d+').allMatches(v).map((m) => int.parse(m.group(0)!)).toList();
  if (numeri.isEmpty) return null;
  final n = numeri.reduce((a, b) => a < b ? a : b);
  final kmh = v.contains('mph') ? (n * 1.609).round() : n;
  return kmh >= 5 && kmh <= 200 ? kmh : null;
}

/// «90», «NE», «NNW»: in gradi. «forward», «both»: non si sa.
double? direzione(Object? v) {
  if (v is! String) return null;
  final n = double.tryParse(v.trim());
  if (n != null) return n % 360;
  const punti = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
  final i = punti.indexOf(v.trim().toUpperCase());
  return i < 0 ? null : i * 22.5;
}

Future<void> main(List<String> argomenti) async {
  final tutti = <(double, double, int?, double?)>[];
  for (final percorso in argomenti.skip(1)) {
    await for (final riga in File(percorso).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      final testo = riga.replaceAll('\u001e', '').trim();
      if (testo.isEmpty) continue;
      final f = jsonDecode(testo) as Map<String, Object?>;
      final tag = ((f['properties'] as Map?) ?? const {}).cast<String, Object?>();
      final g = (f['geometry'] as Map?)?.cast<String, Object?>();
      if (tag['highway'] != 'speed_camera' || g?['type'] != 'Point') continue;
      final c = (g!['coordinates'] as List).cast<num>();
      tutti.add((c[1].toDouble(), c[0].toDouble(), limite(tag['maxspeed']), direzione(tag['direction'])));
    }
  }
  final testo = ArchivioAutovelox.scrivi(tutti);
  await File(argomenti.first).writeAsString(testo);
  final conLimite = tutti.where((a) => a.$3 != null).length;
  final conDirezione = tutti.where((a) => a.$4 != null).length;
  stdout.writeln(
    '::notice title=Autovelox::${tutti.length} fissi, $conLimite col limite, '
    '$conDirezione con la direzione, ${testo.length ~/ 1024} kB',
  );
  if (tutti.length < 100) {
    stdout.writeln('::error title=Autovelox::troppo pochi, qualcosa non va');
    exitCode = 1;
  }
}
