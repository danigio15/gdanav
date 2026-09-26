/// L'archivio delle colonnine dentro l'app (`packages/gdanav_app/assets/colonnine.json`),
/// dagli estratti completi di OpenStreetMap (Geofabrik) filtrati con osmium:
///
///     osmium tags-filter italy.osm.pbf nwr/amenity=charging_station -o cs.osm.pbf
///     osmium export cs.osm.pbf -f geojsonseq --add-unique-id=type_id -o cs.geojsonseq
///     dart run tool/colonnine_osm.dart colonnine.json cs.geojsonseq [altri.geojsonseq…]
///
/// Niente Overpass: in CI, quando il messaggio del commit contiene
/// «[colonnine]».
library;

import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';

/// Come la richiesta a Overpass: prese rapide scritte, o una rete rapida.
bool rapida(Map<String, Object?> tag) {
  if (tag.keys.any((k) => RegExp(r'^socket:(type2_combo|chademo|tesla_supercharger.*)$').hasMatch(k))) return true;
  final reti = RegExp(ClienteOverpass.retiRapide, caseSensitive: false);
  return reti.hasMatch('${tag['operator'] ?? ''}') || reti.hasMatch('${tag['brand'] ?? ''}');
}

/// Il centro di una geometria GeoJSON: il punto, o la media dei vertici.
(double, double)? centro(Map<String, Object?> g) {
  final c = g['coordinates'];
  final punti = <List>[];
  void raccogli(Object? x) {
    if (x is List && x.length >= 2 && x[0] is num && x[1] is num) {
      punti.add(x);
    } else if (x is List) {
      x.forEach(raccogli);
    }
  }

  raccogli(c);
  if (punti.isEmpty) return null;
  final lon = punti.map((p) => (p[0] as num).toDouble()).reduce((a, b) => a + b) / punti.length;
  final lat = punti.map((p) => (p[1] as num).toDouble()).reduce((a, b) => a + b) / punti.length;
  return (lat, lon);
}

Future<void> main(List<String> argomenti) async {
  if (argomenti.length < 2) {
    stderr.writeln('uso: colonnine_osm.dart uscita.json ingresso.geojsonseq…');
    exitCode = 2;
    return;
  }
  final elementi = <Map<String, Object?>>[];
  // Coperti: i riquadri di mezzo grado con almeno una colonnina qualunque
  // (anche lenta): lì l'estratto c'è, e se non ci sono rapide è vero.
  final coperti = <(int, int)>{};
  var tutte = 0;
  for (final percorso in argomenti.skip(1)) {
    await for (final riga in File(percorso).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      final testo = riga.replaceAll('\u001e', '').trim();
      if (testo.isEmpty) continue;
      final f = jsonDecode(testo) as Map<String, Object?>;
      final tag = ((f['properties'] as Map?) ?? const {}).cast<String, Object?>();
      if (tag['amenity'] != 'charging_station') continue;
      final c = centro(((f['geometry'] as Map?) ?? const {}).cast<String, Object?>());
      if (c == null) continue;
      tutte++;
      coperti.add(((c.$1 / ClienteColonnineRelay.lato).floor(), (c.$2 / ClienteColonnineRelay.lato).floor()));
      if (!rapida(tag)) continue;
      final id = '${f['id'] ?? tag['@id'] ?? ''}';
      final tipo = switch (id.isEmpty ? '' : id[0]) {
        'w' => 'way',
        'r' => 'relation',
        _ => 'node',
      };
      elementi.add({
        'type': tipo,
        'id': id.length > 1 ? id.substring(1) : '${elementi.length}',
        'lat': c.$1,
        'lon': c.$2,
        'tags': {
          for (final MapEntry(:key, :value) in tag.entries)
            if (!key.startsWith('@')) key: '$value',
        },
      });
    }
  }
  final colonnine = {
    for (final c in ClienteOverpass.leggi({'elements': elementi})) c.id: c,
  }.values.toList();
  final testo = ArchivioColonnine.scrivi(colonnine, coperti: coperti);
  await File(argomenti.first).writeAsString(testo);
  stdout.writeln(
    '::notice title=Archivio colonnine::${colonnine.length} rapide su $tutte colonnine, '
    '${coperti.length} riquadri coperti, ${testo.length ~/ 1024} kB',
  );
  if (colonnine.length < 1000) {
    stdout.writeln('::error title=Archivio colonnine::troppo poche, qualcosa non va');
    exitCode = 1;
  }
}
