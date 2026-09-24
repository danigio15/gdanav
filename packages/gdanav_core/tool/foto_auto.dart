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

/// Dove il nome porta all'auto sbagliata (la Capri del 1969, l'Explorer
/// americano a benzina): le sole pagine da provare.
const _pagineGiuste = <String, List<String>>{
  'Ford Capri': ['Ford Capri (2024)', 'Ford Capri EV', 'Ford Capri (electric)'],
  'Ford Explorer': ['Ford Explorer EV', 'Ford Explorer (electric)'],
  'Ford E-Tourneo Custom': ['Ford Transit Custom'],
  'MG MG4': ['MG4 EV', 'MG 4 EV', 'MG4'],
  'MG MG4 XPOWER': ['MG4 EV', 'MG 4 EV', 'MG4'],
  'MG MG5 Electric': ['MG5 EV', 'MG 5 EV'],
  'MG MGS5': ['MG S5 EV', 'MG S5'],
  'MG IM5': ['IM L6', 'IM Motors L6'],
  'MG IM6': ['IM LS6', 'IM Motors LS6'],
  'Lancia Ypsilon HF': ['Lancia Ypsilon (2024)', 'Lancia Ypsilon'],
  'Abarth 600e': ['Abarth 600e', 'Fiat 600 (2023)'],
  'Mercedes-Benz AMG EQE 53 +': ['Mercedes-Benz EQE'],
  'Mercedes-Benz EQV 300': ['Mercedes-Benz V-Class'],
  'Nissan Townstar EV': ['Nissan Townstar'],
  'Toyota Proace Verso Electric': ['Toyota ProAce'],
  'Toyota Proace City Verso Electric': ['Toyota ProAce City'],
  'Subaru Solterra': ['Subaru Solterra'],
  'Peugeot iOn': ['Peugeot iOn', 'Mitsubishi i-MiEV'],
  'Škoda Citigo e iV': ['Škoda Citigo'],
  'GWM ORA 03': ['Ora 03', 'Ora Good Cat', 'Great Wall Ora Good Cat'],
  // La i3 di prima, non la berlina del 2026.
  'BMW i3 94 Ah': ['BMW i3 (hatchback)'],
  'BMW i3 120 Ah': ['BMW i3 (hatchback)'],
  'BMW i3s 120 Ah': ['BMW i3 (hatchback)'],
  'Audi SQ8 e-tron': ['Audi Q8 e-tron'],
  // Senza una foto giusta: meglio l'auto disegnata.
  'Alpine A290': [],
  'Fiat E-Ulysse': [],
  'Mercedes-Benz EQT': [],
  'Jeep Compass Elettrica': [],
};

/// Le foto buone: niente loghi né disegni.
bool _foto(String? f) =>
    f != null && !f.toLowerCase().contains('logo') && RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(f);

/// «ë-C4 X» → «c4x», «e-2008» → «2008», «ID.3» → «id3»: per dire se la
/// pagina trovata parla davvero di quel modello.
String _chiaveModello(String termine, String marca) {
  final m = _semplice(termine.substring(marca.length)).split(' ')
    ..removeWhere((w) => const {'electric', 'elettrica', 'e tech', 'tech', 'con', 'tecnologia', 'eq'}.contains(w));
  if (m.isNotEmpty && m.first == 'e' && m.length > 1) m.removeAt(0);
  return m.take(2).join();
}

/// Le pagine da provare per nome esatto: il termine intero, poi togliendo
/// una parola alla volta dalla fine («Škoda Elroq 50» → «Škoda Elroq»).
List<String> _candidate(String t, String marca) {
  if (_pagineGiuste[t] case final giuste?) return giuste;
  // «#», «|», le parentesi: nei titoli di Wikipedia non ci possono stare.
  final parole = t.replaceAll(RegExp(r'[#<>\[\]{}|+]'), ' ').trim().split(RegExp(r'\s+'));
  final n = marca.split(' ').length;
  return [for (var i = parole.length; i > n; i--) parole.sublist(0, i).join(' ')];
}

/// La pagina di Wikipedia dell'auto e la sua foto principale (solo libera).
Future<(String, String)?> pagina(ProfiloVeicolo v) async {
  final t = termine(v);
  final candidate = _candidate(t, v.marca);
  if (candidate.isEmpty) return null;
  final esatte = await _chiedi('en.wikipedia.org', {
    'action': 'query',
    'titles': candidate.join('|'),
    'redirects': '1',
    'prop': 'pageimages',
    'piprop': 'name',
    'pilicense': 'free',
  });
  final q = (esatte['query'] as Map?) ?? const {};
  String segui(String titolo, String chiave) {
    for (final r in ((q[chiave] as List?) ?? const []).cast<Map>()) {
      if (r['from'] == titolo) return r['to'] as String;
    }
    return titolo;
  }

  final perTitolo = {for (final p in ((q['pages'] as List?) ?? const []).cast<Map>()) p['title']: p};
  final marca = _semplice(v.marca).split(' ');
  bool diMarca(String titolo) => marca.any(_semplice(titolo).split(' ').contains);
  for (final (i, c) in candidate.indexed) {
    final titolo = segui(segui(c, 'normalized'), 'redirects');
    final p = perTitolo[titolo];
    if (p == null || p['missing'] == true || !_foto(p['pageimage'] as String?)) continue;
    // Il nome intero può portare altrove (Opel Ampera-e → Chevrolet Bolt: è
    // la stessa auto); accorciato, deve restare della stessa marca.
    if (i == 0 || _pagineGiuste.containsKey(t) || diMarca(titolo)) return (titolo, p['pageimage'] as String);
  }
  if (_pagineGiuste.containsKey(t)) return null;

  // Se no, la ricerca; ma la pagina deve nominare marca e modello.
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
  final chiave = _chiaveModello(t, v.marca);
  for (final p in pagine.cast<Map>()) {
    final titolo = p['title'] as String;
    final compatto = _semplice(titolo).replaceAll(' ', '');
    if (diMarca(titolo) && chiave.isNotEmpty && compatto.contains(chiave) && _foto(p['pageimage'] as String?)) {
      return (titolo, p['pageimage'] as String);
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
  try {
    await _main(argomenti);
  } catch (e, st) {
    stdout.writeln('::error title=Foto delle auto::${'$e'.split('\n').first} ${'$st'.split('\n').take(3).join(' | ')}');
    exitCode = 1;
  }
  _http.close();
}

Future<void> _main(List<String> argomenti) async {
  final uscita = File(argomenti.isEmpty ? 'foto_auto.json' : argomenti.first);
  final trovate = <String, (String, String)>{};
  final perTermine = <String, (String, String)?>{};
  for (final v in catalogoVeicoli) {
    final t = termine(v);
    (String, String)? p;
    try {
      p = perTermine.containsKey(t) ? perTermine[t] : (perTermine[t] = await pagina(v));
    } catch (e) {
      final riga = '$e'.split('\n').first;
      stdout.writeln('::warning title=Foto ${v.id}::$riga');
    }
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
}
