/// Le ZTL e le aree pedonali per l'archivio dentro l'app
/// (`packages/gdanav_app/assets/ztl.json`), dall'estratto d'Italia di
/// OpenStreetMap (Geofabrik) filtrato con osmium. I comuni (`admin_level=8`)
/// servono a dire di che città è ogni ZTL:
///
///     osmium tags-filter italy.osm.pbf wr/boundary=limited_traffic_zone \
///         wr/highway=pedestrian wr/area:highway=pedestrian \
///         n/place=city,town,village r/admin_level=8 -o zone.osm.pbf
///     osmium export zone.osm.pbf -f geojsonseq --add-unique-id=type_id \
///         --geometry-types=point,polygon -o zone.geojsonseq
///     dart run tool/ztl_osm.dart ztl.json zone.geojsonseq
///
/// In CI, quando il messaggio del commit contiene «[ztl]».
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:gdanav_core/gdanav_core.dart';

/// Sotto questa superficie un'area pedonale è un marciapiede largo: sulla
/// mappa non si vede, e non cambia nessun percorso.
const superficieMinimaM2 = 300.0;

/// «ZTL Centro Storico», «Z.T.L. - Centro», «Zona a traffico limitato
/// Chiaia»: il nome senza la sigla, e senza la città se c'è anche lei
/// («Bologna - Centro Storico», «Via Matteotti Lerici», «ZTL di Verona»).
/// Vuoto se non resta altro.
String nomeZtl(String? nome, [String? citta]) {
  const separatori = r'[\s\-–:,.·/]';
  const sigla = r'(?:z\s*\.?\s*t\s*\.?\s*l\s*\.?|zona\s+(?:a\s+|di\s+)?traffico\s+limitato)';
  // «di», «del», «della»… dopo la sigla: «ZTL del Centro Storico».
  const di = r"(?:di|del|dello|della|dei|degli|delle|d['’])";
  String pulito(String n) =>
      n.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp('^$separatori+|$separatori+\$'), '').trim();
  var n = (nome ?? '').trim();
  final c = (citta ?? '').trim();
  if (c.isNotEmpty) {
    // La città come parola intera: «Lancianovecchia» resta com'è.
    final parola = RegExp('(?<![\\p{L}\\d])${RegExp.escape(c)}(?![\\p{L}\\d])', caseSensitive: false, unicode: true);
    n = pulito(n.replaceAll(parola, ' '));
  }
  final senzaSigla = n.replaceFirst(RegExp('^$sigla(?=\$|$separatori)$separatori*', caseSensitive: false), '');
  if (senzaSigla != n) n = senzaSigla.replaceFirst(RegExp('^$di(?:\\s+|(?<=[\'’]))', caseSensitive: false), '');
  n = pulito(n);
  // Restava solo «di»: era «ZTL di Verona».
  return RegExp('^$di\$', caseSensitive: false).hasMatch(n) ? '' : n;
}

/// Il nome italiano, se c'è: «Casteddu/Cagliari» è «Cagliari».
String? nomeItaliano(Map<String, Object?> tag) {
  for (final chiave in const ['name:it', 'name']) {
    final v = tag[chiave];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

/// Il comune in cui cade [p]: il più piccolo, se più d'uno la contiene (un
/// comune dentro l'altro). I comuni sono zone col nome del comune.
String? comuneDi(Punto p, List<ZonaLimitata> comuni) {
  final dentro = comuni.where((c) => c.contiene(p)).toList();
  if (dentro.isEmpty) return null;
  double area(ZonaLimitata c) => c.anelli.map(superficieM2).fold(0.0, (a, b) => a + b);
  dentro.sort((a, b) => area(a).compareTo(area(b)));
  return dentro.first.nome;
}

/// L'id di OpenStreetMap che non cambia: «w123», «r456». osmium scrive le
/// aree anche come `a<n>`, con n = 2·id della via o 2·id+1 della relazione.
String idOsm(Object? id) {
  final s = '${id ?? ''}';
  if (s.startsWith('a')) {
    final n = int.tryParse(s.substring(1));
    if (n != null) return n.isEven ? 'w${n ~/ 2}' : 'r${(n - 1) ~/ 2}';
  }
  return s;
}

/// I contorni esterni di un Polygon o MultiPolygon GeoJSON.
List<List<Punto>> contorni(Map<String, Object?> g) {
  List<Punto> anello(Object? a) => [
        for (final c in (a as List).cast<List>()) Punto((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
  return switch (g['type']) {
    'Polygon' => [anello((g['coordinates'] as List).first)],
    'MultiPolygon' => [for (final p in (g['coordinates'] as List).cast<List>()) anello(p.first)],
    _ => const [],
  };
}

/// Superficie in metri quadrati, su un piano locale.
double superficieM2(List<Punto> a) {
  if (a.length < 3) return 0;
  final kx = math.cos(a.first.lat * math.pi / 180) * 111320, ky = 111320.0;
  var s = 0.0;
  for (var i = 0, j = a.length - 1; i < a.length; j = i++) {
    s += (a[j].lon * kx) * (a[i].lat * ky) - (a[i].lon * kx) * (a[j].lat * ky);
  }
  return s.abs() / 2;
}

/// Douglas–Peucker con [tolleranzaM] metri, su un piano locale.
List<Punto> semplificato(List<Punto> punti, double tolleranzaM) {
  if (punti.length <= 4) return punti;
  final kx = math.cos(punti.first.lat * math.pi / 180) * 111320, ky = 111320.0;
  final tieni = List.filled(punti.length, false);
  tieni[0] = tieni[punti.length - 1] = true;
  final pila = <(int, int)>[(0, punti.length - 1)];
  while (pila.isNotEmpty) {
    final (da, a) = pila.removeLast();
    final ax = punti[da].lon * kx, ay = punti[da].lat * ky;
    final bx = punti[a].lon * kx, by = punti[a].lat * ky;
    final dx = bx - ax, dy = by - ay;
    final l = math.sqrt(dx * dx + dy * dy);
    var massimo = 0.0, dove = -1;
    for (var i = da + 1; i < a; i++) {
      final px = punti[i].lon * kx, py = punti[i].lat * ky;
      final d = l == 0
          ? math.sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay))
          : ((px - ax) * dy - (py - ay) * dx).abs() / l;
      if (d > massimo) {
        massimo = d;
        dove = i;
      }
    }
    if (massimo > tolleranzaM && dove > 0) {
      tieni[dove] = true;
      pila
        ..add((da, dove))
        ..add((dove, a));
    }
  }
  final fuori = [
    for (var i = 0; i < punti.length; i++)
      if (tieni[i]) punti[i]
  ];
  // Il primo e l'ultimo sono lo stesso punto: non serve ripeterlo.
  if (fuori.length > 3 && fuori.first == fuori.last) fuori.removeLast();
  return fuori.length >= 3 ? fuori : punti;
}

/// La città di una ZTL: dai suoi tag se c'è, se no il comune in cui cade,
/// se no il paese più vicino.
String? citta(Map<String, Object?> tag, Punto centro, List<(Punto, String, int)> luoghi,
    [List<ZonaLimitata> comuni = const []]) {
  for (final chiave in const ['addr:city', 'is_in:city']) {
    final v = tag[chiave];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  final operatore = '${tag['operator'] ?? ''}';
  final comune = RegExp(r'^Comune di\s+(.+)$', caseSensitive: false).firstMatch(operatore.trim());
  if (comune != null) return comune.group(1)!.trim();
  final dentro = comuneDi(centro, comuni);
  if (dentro != null) return dentro;
  (String, double)? migliore;
  for (final (p, nome, _) in luoghi) {
    if ((p.lat - centro.lat).abs() > 0.15 || (p.lon - centro.lon).abs() > 0.2) continue;
    final d = distanzaM(p, centro);
    if (d <= 15000 && (migliore == null || d < migliore.$2)) migliore = (nome, d);
  }
  return migliore?.$1;
}

Punto centroDi(List<List<Punto>> anelli) {
  final tutti = anelli.expand((a) => a).toList();
  return Punto(
    tutti.map((p) => p.lat).reduce((a, b) => a + b) / tutti.length,
    tutti.map((p) => p.lon).reduce((a, b) => a + b) / tutti.length,
  );
}

Future<void> main(List<String> argomenti) async {
  if (argomenti.length < 2) {
    stderr.writeln('uso: ztl_osm.dart uscita.json ingresso.geojsonseq…');
    exitCode = 2;
    return;
  }
  final ztl = <(String, Map<String, Object?>, List<List<Punto>>)>[];
  final pedonali = <(String, Map<String, Object?>, List<List<Punto>>)>[];
  final luoghi = <(Punto, String, int)>[];
  final comuni = <ZonaLimitata>[];
  final comuniVisti = <String>{};
  for (final percorso in argomenti.skip(1)) {
    await for (final riga in File(percorso).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      final testo = riga.replaceAll('\u001e', '').trim();
      if (testo.isEmpty) continue;
      final f = jsonDecode(testo) as Map<String, Object?>;
      final tag = ((f['properties'] as Map?) ?? const {}).cast<String, Object?>();
      final g = ((f['geometry'] as Map?) ?? const {}).cast<String, Object?>();
      final id = idOsm(f['id'] ?? tag['@id']);
      if (g['type'] == 'Point') {
        final rango = const {'city': 3, 'town': 2, 'village': 1}[tag['place']];
        final nome = nomeItaliano(tag);
        if (rango != null && nome != null) {
          final c = (g['coordinates'] as List).cast<num>();
          luoghi.add((Punto(c[1].toDouble(), c[0].toDouble()), nome, rango));
        }
        continue;
      }
      final anelli = contorni(g);
      if (anelli.isEmpty) continue;
      if (tag['boundary'] == 'administrative' && '${tag['admin_level']}' == '8') {
        final nome = nomeItaliano(tag);
        if (nome == null || !comuniVisti.add(id)) continue;
        final semplici = [
          for (final a in anelli)
            if (semplificato(a, 20) case final s when s.length >= 3) s
        ];
        if (semplici.isEmpty) continue;
        comuni.add(ZonaLimitata(id: id, tipo: TipoZona.ztl, nome: nome, anelli: semplici));
        continue;
      }
      if (tag['boundary'] == 'limited_traffic_zone') {
        ztl.add((id, tag, anelli));
      } else if (tag['area:highway'] == 'pedestrian' ||
          (tag['highway'] == 'pedestrian' && (tag['area'] == 'yes' || id.startsWith('r')))) {
        pedonali.add((id, tag, anelli));
      }
    }
  }

  final zone = <ZonaLimitata>[];
  var conOrari = 0, orariCapiti = 0;
  final nonCapiti = <String>[];
  final citta0 = <String, int>{};
  final visti = <String>{};
  for (final (id, tag, anelli) in ztl) {
    if (!visti.add(id)) continue;
    final semplici = [for (final a in anelli) semplificato(a, 3)];
    final orari = OrariZtl.daiTag(tag);
    final testoOrari = ['motor_vehicle:conditional', 'vehicle:conditional', 'access:conditional', 'opening_hours']
        .map((k) => tag[k])
        .whereType<String>()
        .where((v) => v.trim().isNotEmpty)
        .firstOrNull;
    final dove = citta(tag, centroDi(semplici), luoghi, comuni);
    citta0[dove ?? '(senza città)'] = (citta0[dove ?? '(senza città)'] ?? 0) + 1;
    final nome = nomeZtl(nomeItaliano(tag), dove);
    final zona = ZonaLimitata(
      id: id,
      tipo: TipoZona.ztl,
      nome: nome,
      citta: dove,
      orari: orari,
      orariTesto: testoOrari?.trim(),
      anelli: semplici,
    );
    if (testoOrari != null) {
      conOrari++;
      if (orari != null || OrariZtl.sempre(testoOrari)) {
        orariCapiti++;
      } else {
        nonCapiti.add('| ${zona.etichetta} | `${testoOrari.trim()}` |');
      }
    }
    zone.add(zona);
  }
  var piccole = 0;
  for (final (id, tag, anelli) in pedonali) {
    if (!visti.add(id)) continue;
    final grandi = [
      for (final a in anelli)
        if (superficieM2(a) >= superficieMinimaM2) semplificato(a, 2)
    ];
    if (grandi.isEmpty) {
      piccole++;
      continue;
    }
    zone.add(ZonaLimitata(
      id: id,
      tipo: TipoZona.pedonale,
      nome: '${tag['name'] ?? ''}'.trim(),
      anelli: grandi,
    ));
  }
  zone.sort((a, b) => a.id.compareTo(b.id));

  final testo = ArchivioZtl.scrivi(zone);
  await File(argomenti.first).writeAsString(testo);
  final quanteZtl = zone.where((z) => z.tipo == TipoZona.ztl).length;
  stdout
    ..writeln('::notice title=ZTL::$quanteZtl ZTL ($conOrari con gli orari scritti, $orariCapiti che si capiscono), '
        '${zone.length - quanteZtl} aree pedonali ($piccole troppo piccole lasciate fuori), '
        '${comuni.length} comuni e ${luoghi.length} luoghi per i nomi, ${testo.length ~/ 1024} kB')
    ..writeln('')
    ..writeln('| Città | ZTL |')
    ..writeln('|---|---|');
  final classifica = citta0.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in classifica.take(40)) {
    stdout.writeln('| ${e.key} | ${e.value} |');
  }
  // Le ZTL col permesso da chiedere: una riga per nome, con quanti pezzi.
  final gruppi = <String, (String, int)>{};
  for (final z in zone.where((z) => z.tipo == TipoZona.ztl)) {
    final g = gruppi[z.chiave];
    gruppi[z.chiave] = (z.etichetta, (g?.$2 ?? 0) + 1);
  }
  stdout
    ..writeln('')
    ..writeln('${gruppi.length} permessi da chiedere, uno per nome:')
    ..writeln('')
    ..writeln('| ZTL | Pezzi |')
    ..writeln('|---|---|');
  for (final g in gruppi.values.toList()..sort((a, b) => a.$1.compareTo(b.$1))) {
    stdout.writeln('| ${g.$1} | ${g.$2} |');
  }
  stdout
    ..writeln('')
    ..writeln('| Orari che non si capiscono (valgono come sempre attiva) |  |')
    ..writeln('|---|---|');
  nonCapiti.forEach(stdout.writeln);
  if (quanteZtl < 30) {
    stdout.writeln('::error title=ZTL::troppo poche, qualcosa non va');
    exitCode = 1;
  }
}
