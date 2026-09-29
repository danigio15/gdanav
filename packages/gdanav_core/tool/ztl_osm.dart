/// Le ZTL e le aree pedonali per l'archivio dentro l'app
/// (`packages/gdanav_app/assets/ztl.json`), dall'estratto d'Italia di
/// OpenStreetMap (Geofabrik) filtrato con osmium:
///
///     osmium tags-filter italy.osm.pbf wr/boundary=limited_traffic_zone \
///         wr/highway=pedestrian wr/area:highway=pedestrian \
///         n/place=city,town,village -o zone.osm.pbf
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
/// Chiaia»: il nome senza la sigla. Vuoto se resta solo quella.
String nomeZtl(String? nome) {
  final n = (nome ?? '').trim().replaceFirst(
        RegExp(r'^(?:z\s*\.?\s*t\s*\.?\s*l\s*\.?|zona\s+a\s+traffico\s+limitato)(?=$|[\s\-–:,.])[\s\-–:,.]*',
            caseSensitive: false),
        '',
      );
  return n.trim();
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

/// La città di una ZTL: dai suoi tag se c'è, se no il paese più vicino.
String? citta(Map<String, Object?> tag, Punto centro, List<(Punto, String, int)> luoghi) {
  for (final chiave in const ['addr:city', 'is_in:city']) {
    final v = tag[chiave];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  final operatore = '${tag['operator'] ?? ''}';
  final comune = RegExp(r'^Comune di\s+(.+)$', caseSensitive: false).firstMatch(operatore.trim());
  if (comune != null) return comune.group(1)!.trim();
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
        final nome = tag['name'];
        if (rango != null && nome is String && nome.isNotEmpty) {
          final c = (g['coordinates'] as List).cast<num>();
          luoghi.add((Punto(c[1].toDouble(), c[0].toDouble()), nome, rango));
        }
        continue;
      }
      final anelli = contorni(g);
      if (anelli.isEmpty) continue;
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
    if (testoOrari != null) conOrari++;
    if (orari != null) orariCapiti++;
    final dove = citta(tag, centroDi(semplici), luoghi);
    citta0[dove ?? '(senza città)'] = (citta0[dove ?? '(senza città)'] ?? 0) + 1;
    final nome = nomeZtl(tag['name'] as String?);
    zone.add(ZonaLimitata(
      id: id,
      tipo: TipoZona.ztl,
      nome: nome.isEmpty ? 'ZTL' : nome,
      citta: dove,
      orari: orari,
      orariTesto: testoOrari?.trim(),
      anelli: semplici,
    ));
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
        '${luoghi.length} luoghi per i nomi, ${testo.length ~/ 1024} kB')
    ..writeln('')
    ..writeln('| Città | ZTL |')
    ..writeln('|---|---|');
  final classifica = citta0.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final e in classifica.take(40)) {
    stdout.writeln('| ${e.key} | ${e.value} |');
  }
  stdout
    ..writeln('')
    ..writeln('| ZTL | Orari scritti | Si capiscono |')
    ..writeln('|---|---|---|');
  for (final z in zone.where((z) => z.tipo == TipoZona.ztl && z.orariTesto != null).take(60)) {
    stdout.writeln('| ${z.etichetta} | `${z.orariTesto}` | ${z.orari == null ? 'no' : 'sì'} |');
  }
  if (quanteZtl < 30) {
    stdout.writeln('::error title=ZTL::troppo poche, qualcosa non va');
    exitCode = 1;
  }
}
