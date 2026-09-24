/// Tutte le colonnine rapide dell'Italia e dintorni (Svizzera, Austria,
/// Slovenia, Costa Azzurra), da OpenStreetMap, per l'archivio dentro l'app
/// (`app/assets/colonnine.json`).
///
///     dart run tool/colonnine_europa.dart uscita.json
///
/// Gira in CI quando il messaggio del commit contiene «[colonnine]». A
/// riquadri di un grado: Overpass li serve in pochi secondi anche quando è
/// carico, e se risponde «occupato» si riprova solo quel riquadro.
library;

import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;

/// Sud-ovest e nord-est, in gradi interi.
const area = (sud: 35, ovest: 6, nord: 48, est: 19);

const server = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

String richiesta(int lat, int lon) {
  const rapide = r'[~"^socket:(type2_combo|chademo|tesla_supercharger.*)$"~"."]';
  const reti = ClienteOverpass.retiRapide;
  final b = '$lat,$lon,${lat + 1},${lon + 1}';
  return '[out:json][timeout:120];'
      '(nwr["amenity"="charging_station"]$rapide($b);'
      'nwr["amenity"="charging_station"]["operator"~"$reti",i]($b);'
      'nwr["amenity"="charging_station"]["brand"~"$reti",i]($b););'
      'out center tags;';
}

Future<List<Colonnina>> riquadro(http.Client h, int lat, int lon) async {
  Object? ultimo;
  for (var tentativo = 0; tentativo < 10; tentativo++) {
    final s = server[tentativo % server.length];
    try {
      final r = await h.post(Uri.parse(s),
          body: {'data': richiesta(lat, lon)},
          headers: {'user-agent': 'gdanav (github.com/danigio15/gdanav)'}).timeout(const Duration(seconds: 150));
      final testo = utf8.decode(r.bodyBytes);
      if (r.statusCode == 200 && testo.startsWith('{') && !RegExp(r'"remark"\s*:\s*"[^"]*error').hasMatch(testo)) {
        return ClienteOverpass.leggi(jsonDecode(testo) as Map<String, Object?>);
      }
      ultimo = '${Uri.parse(s).host}: ${r.statusCode}';
    } catch (e) {
      ultimo = '${Uri.parse(s).host}: $e';
    }
    await Future<void>.delayed(Duration(seconds: 5 + 5 * tentativo));
  }
  throw Exception('$lat,$lon: $ultimo');
}

Future<void> main(List<String> argomenti) async {
  final h = http.Client();
  final tutte = <String, Colonnina>{};
  final coperti = <(int, int)>{};
  final mancanti = <String>[];
  for (var lat = area.sud; lat < area.nord; lat++) {
    for (var lon = area.ovest; lon < area.est; lon++) {
      try {
        final c = await riquadro(h, lat, lon);
        for (final x in c) {
          tutte[x.id] = x;
        }
        // Un grado sono quattro riquadri da mezzo grado dell'app.
        for (final (dr, dc) in const [(0, 0), (0, 1), (1, 0), (1, 1)]) {
          coperti.add((lat * 2 + dr, lon * 2 + dc));
        }
        stdout.writeln('$lat,$lon: ${c.length}');
      } catch (e) {
        mancanti.add('$lat,$lon');
        stdout.writeln('::warning title=Colonnine $lat,$lon::$e');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
  h.close();
  final totale = (area.nord - area.sud) * (area.est - area.ovest);
  if (mancanti.length > totale ~/ 5) {
    stdout.writeln('::error title=Colonnine::mancano ${mancanti.length} riquadri su $totale');
    exitCode = 1;
    return;
  }
  final testo = ArchivioColonnine.scrivi(tutte.values.toList(), coperti: coperti);
  await File(argomenti.isEmpty ? 'colonnine.json' : argomenti.first).writeAsString(testo);
  stdout.writeln('::notice title=Archivio colonnine::${tutte.length} colonnine, ${testo.length ~/ 1024} kB, '
      '${mancanti.length} riquadri mancanti su $totale');
}
