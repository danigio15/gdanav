/// Tutte le colonnine rapide dei paesi dove si va in auto dall'Italia, da
/// OpenStreetMap, per l'archivio dentro l'app (`app/assets/colonnine.json`).
///
///     dart run tool/colonnine_europa.dart uscita.json
///
/// Gira in CI quando il messaggio del commit contiene «[colonnine]»: con
/// pazienza, perché Overpass è spesso sovraccarico, un paese alla volta.
library;

import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;

const paesi = ['IT', 'SM', 'VA', 'CH', 'AT', 'SI', 'FR', 'DE', 'HR', 'MC', 'LI'];

const server = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];

String richiesta(String paese) {
  const rapide = r'[~"^socket:(type2_combo|chademo|tesla_supercharger.*)$"~"."]';
  const reti = ClienteOverpass.retiRapide;
  return '[out:json][timeout:900][maxsize:1073741824];'
      'area["ISO3166-1"="$paese"][admin_level=2]->.p;'
      '(nwr["amenity"="charging_station"]$rapide(area.p);'
      'nwr["amenity"="charging_station"]["operator"~"$reti",i](area.p);'
      'nwr["amenity"="charging_station"]["brand"~"$reti",i](area.p););'
      'out center tags;';
}

Future<List<Colonnina>> scarica(http.Client h, String paese) async {
  Object? ultimo;
  for (var giro = 0; giro < 6; giro++) {
    for (final s in server) {
      try {
        final r = await h.post(Uri.parse(s),
            body: {'data': richiesta(paese)},
            headers: {'user-agent': 'gdanav (github.com/danigio15/gdanav)'}).timeout(const Duration(minutes: 16));
        final testo = utf8.decode(r.bodyBytes);
        if (r.statusCode == 200 && !RegExp(r'"remark"\s*:\s*"[^"]*error').hasMatch(testo)) {
          final c = ClienteOverpass.leggi(jsonDecode(testo) as Map<String, Object?>);
          if (c.isNotEmpty || paese == 'VA') return c;
          ultimo = '$s: nessuna colonnina';
        } else {
          ultimo = '$s: ${r.statusCode}';
        }
      } catch (e) {
        ultimo = '$s: $e';
      }
      stdout.writeln('$paese: $ultimo, riprovo');
      await Future<void>.delayed(Duration(seconds: 20 + 20 * giro));
    }
  }
  throw Exception('$paese: $ultimo');
}

Future<void> main(List<String> argomenti) async {
  final h = http.Client();
  final tutte = <String, Colonnina>{};
  final mancanti = <String>[];
  for (final p in paesi) {
    try {
      final c = await scarica(h, p);
      for (final x in c) {
        tutte[x.id] = x;
      }
      stdout.writeln('::notice title=Colonnine $p::${c.length}');
    } catch (e) {
      mancanti.add(p);
      stdout.writeln('::warning title=Colonnine $p::$e');
    }
  }
  h.close();
  // Senza l'Italia l'archivio non serve: meglio fallire e tenere il vecchio.
  if (mancanti.contains('IT')) {
    stdout.writeln('::error title=Colonnine::manca l\'Italia');
    exitCode = 1;
    return;
  }
  final testo = ArchivioColonnine.scrivi(tutte.values.toList());
  await File(argomenti.isEmpty ? 'colonnine.json' : argomenti.first).writeAsString(testo);
  stdout.writeln('::notice title=Archivio colonnine::${tutte.length} colonnine, ${testo.length ~/ 1024} kB'
      '${mancanti.isEmpty ? '' : ', mancano ${mancanti.join(', ')}'}');
}
