/// Trova una foto vera per ogni auto del catalogo, su Wikipedia e Wikimedia
/// Commons: solo foto con licenza libera, con autore e licenza da citare.
/// Scrive il JSON che l'app porta con sé (`app/assets/foto_auto.json`).
///
///     dart run tool/foto_auto.dart uscita.json
///
/// Gira in CI (da qui la rete verso Wikipedia può essere chiusa), quando il
/// messaggio del commit contiene «[foto-auto]».
library;

import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;

const _agente = 'gdanav/0.1 (https://github.com/danigio15/gdanav; foto delle auto)';
final _http = http.Client();

Future<Map<String, Object?>> _chiedi(String host, Map<String, String> q) async {
  final uri = Uri.https(host, '/w/api.php', {'format': 'json', 'formatversion': '2', ...q});
  for (var tentativo = 0;; tentativo++) {
    final r = await _http.get(uri, headers: {'user-agent': _agente});
    if (r.statusCode == 200) return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
    if (tentativo >= 3) throw Exception('$host: ${r.statusCode}');
    await Future<void>.delayed(Duration(seconds: 2 << tentativo));
  }
}

/// «EX40 Single Motor 69 kWh» → «EX40»: quello che direbbe una persona.
String termine(ProfiloVeicolo v) {
  var m = v.modello
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(RegExp(r'\d+(?:[.,]\d+)?\s?kWh', caseSensitive: false), ' ')
      .replaceAll(
        RegExp(
          r'\b(standard range|long range|extended range|maximum range|performance|single motor|twin motor|'
          r'dual motor|awd|rwd|fwd|4motion|4matic\+?|quattro|xdrive\d*|edrive\d*|sr|lr|plus|pro|max|'
          r'design|launch edition|gt-line|\d+\s?kw|\d+\s?cv)\b',
          caseSensitive: false,
        ),
        ' ',
      );
  m = m.replaceAll(RegExp(r'\s+'), ' ').trim();
  return '${v.marca} $m'.trim();
}

String _semplice(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[ëé]'), 'e')
    .replaceAll(RegExp('[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// La pagina di Wikipedia dell'auto e la sua foto principale (solo libera).
Future<(String, String)?> pagina(ProfiloVeicolo v) async {
  final t = termine(v);
  final j = await _chiedi('en.wikipedia.org', {
    'action': 'query',
    'generator': 'search',
    'gsrsearch': t,
    'gsrlimit': '6',
    'gsrnamespace': '0',
    'prop': 'pageimages',
    'piprop': 'name',
    'pilicense': 'free',
  });
  final pagine = [...((j['query'] as Map?)?['pages'] as List? ?? const [])]
    ..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
  final marca = _semplice(v.marca).split(' ');
  final primo = _semplice(t).split(' ').skip(marca.length).firstOrNull;
  bool diMarca(Map p) => marca.any(_semplice(p['title'] as String).split(' ').contains);
  bool delModello(Map p) => primo == null || _semplice(p['title'] as String).split(' ').contains(primo);
  for (final ok in [(Map p) => diMarca(p) && delModello(p), diMarca]) {
    for (final p in pagine.cast<Map>()) {
      if (ok(p) && p['pageimage'] is String) return (p['title'] as String, p['pageimage'] as String);
    }
  }
  return null;
}

String _testo(Object? html) => '${html ?? ''}'
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&#039;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Future<void> main(List<String> argomenti) async {
  final uscita = File(argomenti.isEmpty ? 'foto_auto.json' : argomenti.first);
  final trovate = <String, (String, String)>{};
  final perTermine = <String, (String, String)?>{};
  for (final v in catalogoVeicoli) {
    final t = termine(v);
    final p = perTermine.containsKey(t) ? perTermine[t] : (perTermine[t] = await pagina(v));
    if (p != null) trovate[v.id] = p;
    stdout.writeln('${v.id}\t$t\t${p?.$1 ?? '-'}\t${p?.$2 ?? ''}');
  }

  // Autore e licenza da Commons, cinquanta file per volta. Un file che su
  // Commons non c'è sta solo su Wikipedia inglese: si lascia stare.
  final file = {for (final p in trovate.values) p.$2};
  final info = <String, Map<String, String>>{};
  final elenco = file.toList();
  for (var i = 0; i < elenco.length; i += 50) {
    final gruppo = elenco.sublist(i, i + 50 > elenco.length ? elenco.length : i + 50);
    final j = await _chiedi('commons.wikimedia.org', {
      'action': 'query',
      'titles': gruppo.map((f) => 'File:$f').join('|'),
      'prop': 'imageinfo',
      'iiprop': 'url|extmetadata',
      'iiurlwidth': '500',
      'iiextmetadatafilter': 'Artist|LicenseShortName',
    });
    for (final p in ((j['query'] as Map?)?['pages'] as List? ?? const []).cast<Map>()) {
      if (p['missing'] == true) continue;
      final ii = (p['imageinfo'] as List?)?.firstOrNull as Map?;
      if (ii == null) continue;
      final meta = (ii['extmetadata'] as Map?) ?? const {};
      final nome = (p['title'] as String).substring('File:'.length);
      final autore = _testo((meta['Artist'] as Map?)?['value']);
      info[nome.replaceAll(' ', '_')] = {
        'url': ii['thumburl'] as String,
        'fonte': ii['descriptionurl'] as String,
        'autore': autore.length > 80 ? '${autore.substring(0, 79)}…' : autore,
        'licenza': _testo((meta['LicenseShortName'] as Map?)?['value']),
      };
    }
  }

  final risultato = <String, Object?>{};
  for (final MapEntry(key: id, value: (pagina, f)) in trovate.entries) {
    final i = info[f.replaceAll(' ', '_')];
    if (i == null || i['licenza']!.isEmpty) continue;
    risultato[id] = {'pagina': pagina, ...i};
  }
  await uscita.writeAsString(const JsonEncoder.withIndent('  ').convert(risultato));
  stdout.writeln('::notice title=Foto delle auto::${risultato.length} di ${catalogoVeicoli.length}');
  _http.close();
}
