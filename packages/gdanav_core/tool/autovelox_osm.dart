/// Gli autovelox fissi e i Tutor di OpenStreetMap per l'archivio dentro
/// l'app (`packages/gdanav_app/assets/autovelox.json`):
///
///     osmium tags-filter italy.osm.pbf n/highway=speed_camera r/type=enforcement -o av.osm.pbf
///     osmium cat av.osm.pbf -f opl -o av.opl
///     dart run tool/autovelox_osm.dart autovelox.json av.opl [altri…]
///
/// Dagli autovelox (`highway=speed_camera`) e dalle relazioni dei controlli
/// (`type=enforcement`): `enforcement=maxspeed` aggiunge quelli segnati solo
/// così, e dice verso dove guardano (da `from` a `to`); `average_speed` sono
/// i Tutor, da `from` a `to`. `osmium tags-filter` si porta dietro i membri
/// delle relazioni, coi loro punti.
///
/// Si leggono anche gli estratti in `.geojsonseq` della versione di prima
/// (solo i punti, senza relazioni).
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

typedef Autovelox = (double, double, int?, double?);
typedef Tutor = (double, double, double, double, int?);

/// Quello che serve di un estratto OPL: i punti, le strade (come elenco di
/// punti) e le relazioni dei controlli.
class EstrattoOsm {
  final punti = <int, (Punto, Map<String, String>)>{};
  final strade = <int, List<int>>{};
  final relazioni = <(Map<String, String>, List<(String, int, String)>)>[];

  /// Le righe di `osmium cat -f opl`: `n1 v1 … Tchiave=valore x9.1 y45.4`,
  /// `w2 … Nn1,n2`, `r3 … Ttype=enforcement Mn1@device,n2@from`.
  void leggi(String riga) {
    if (riga.isEmpty) return;
    final campi = <String, String>{};
    for (final c in riga.split(' ').skip(1)) {
      if (c.isNotEmpty) campi[c[0]] = c.substring(1);
    }
    final id = int.tryParse(riga.split(' ').first.substring(1));
    if (id == null) return;
    final tag = _tag(campi['T'] ?? '');
    switch (riga[0]) {
      case 'n':
        final x = double.tryParse(campi['x'] ?? ''), y = double.tryParse(campi['y'] ?? '');
        if (x != null && y != null) punti[id] = (Punto(y, x), tag);
      case 'w':
        strade[id] = [
          for (final n in (campi['N'] ?? '').split(','))
            if (n.length > 1) int.tryParse(n.substring(1)),
        ].nonNulls.toList();
      case 'r':
        final membri = <(String, int, String)>[];
        for (final m in (campi['M'] ?? '').split(',')) {
          final chiocciola = m.indexOf('@');
          if (m.length < 3 || chiocciola < 2) continue;
          final mid = int.tryParse(m.substring(1, chiocciola));
          if (mid != null) membri.add((m[0], mid, _testo(m.substring(chiocciola + 1))));
        }
        relazioni.add((tag, membri));
    }
  }

  /// `chiave=valore,altra=valore`, coi caratteri speciali come `%2c%`.
  static Map<String, String> _tag(String t) => {
        for (final kv in t.split(','))
          if (kv.indexOf('=') case final i when i > 0) _testo(kv.substring(0, i)): _testo(kv.substring(i + 1)),
      };

  static String _testo(String s) =>
      s.replaceAllMapped(RegExp('%([0-9a-fA-F]+)%'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));

  /// Dov'è un membro: un punto, o il mezzo di una strada.
  Punto? dove(String tipo, int id) {
    if (tipo == 'n') return punti[id]?.$1;
    if (tipo != 'w') return null;
    final ps = [for (final n in strade[id] ?? const <int>[]) punti[n]?.$1].nonNulls.toList();
    if (ps.isEmpty) return null;
    return Punto(ps.map((p) => p.lat).reduce((a, b) => a + b) / ps.length,
        ps.map((p) => p.lon).reduce((a, b) => a + b) / ps.length);
  }

  /// Gli autovelox e i Tutor.
  (List<Autovelox>, List<Tutor>) risolvi() {
    final autovelox = <Autovelox>[];
    final tutor = <Tutor>[];
    // I punti già detti da una relazione: non si ripetono da soli.
    final usati = <int>{};
    for (final (tag, membri) in relazioni) {
      if (tag['type'] != 'enforcement') continue;
      Punto? primo(String ruolo) => [
            for (final (t, id, r) in membri)
              if (r == ruolo) dove(t, id),
          ].nonNulls.firstOrNull;
      final dispositivi = [
        for (final (t, id, r) in membri)
          if (r == 'device' && t == 'n') id,
      ];
      final quale = tag['enforcement'] ?? '';
      int? limiteDi() =>
          limite(tag['maxspeed']) ??
          [for (final id in dispositivi) limite(punti[id]?.$2['maxspeed'])].nonNulls.firstOrNull;
      if (quale == 'average_speed') {
        final posti = [for (final id in dispositivi) punti[id]?.$1].nonNulls.toList();
        final da = primo('from') ?? posti.firstOrNull, a = primo('to') ?? (posti.length > 1 ? posti.last : null);
        usati.addAll(dispositivi);
        if (da == null || a == null) continue;
        final lungo = distanzaM(da, a);
        if (lungo < 300 || lungo > 80000) continue;
        tutor.add((da.lat, da.lon, a.lat, a.lon, limiteDi()));
      } else if (quale == 'maxspeed') {
        final dispositivo = dispositivi.map((id) => punti[id]?.$1).nonNulls.firstOrNull;
        final da = primo('from'), a = primo('to');
        final qui = a ?? dispositivo;
        if (qui == null) continue;
        usati.addAll(dispositivi);
        // Verso dove si va: dal punto dove comincia il controllo a quello
        // misurato (o all'apparecchio). Abbastanza lontani da fidarsi.
        final verso = switch ((da, a ?? dispositivo)) {
          (final x?, final y?) when distanzaM(x, y) >= 10 => rottaGradi(x, y),
          _ => direzione(dispositivi.map((id) => punti[id]?.$2['direction']).nonNulls.firstOrNull),
        };
        autovelox.add((qui.lat, qui.lon, limiteDi(), verso));
      }
    }
    for (final MapEntry(key: id, value: (p, tag)) in punti.entries) {
      if (tag['highway'] != 'speed_camera' || usati.contains(id)) continue;
      autovelox.add((p.lat, p.lon, limite(tag['maxspeed']), direzione(tag['direction'])));
    }
    return (autovelox, tutor);
  }
}

/// Un autovelox dell'estratto `.geojsonseq` della versione di prima.
Autovelox? daGeojson(String riga) {
  final testo = riga.replaceAll('\u001e', '').trim();
  if (testo.isEmpty) return null;
  final f = jsonDecode(testo) as Map<String, Object?>;
  final tag = ((f['properties'] as Map?) ?? const {}).cast<String, Object?>();
  final g = (f['geometry'] as Map?)?.cast<String, Object?>();
  if (tag['highway'] != 'speed_camera' || g?['type'] != 'Point') return null;
  final c = (g!['coordinates'] as List).cast<num>();
  return (c[1].toDouble(), c[0].toDouble(), limite(tag['maxspeed']), direzione(tag['direction']));
}

/// Lo stesso autovelox da due paesi vicini (gli estratti si sovrappongono
/// al confine): uno solo.
List<Autovelox> senzaDoppi(List<Autovelox> tutti) {
  final visti = <String>{};
  return [
    for (final a in tutti)
      if (visti.add('${a.$1.toStringAsFixed(5)},${a.$2.toStringAsFixed(5)}')) a,
  ];
}

Future<void> main(List<String> argomenti) async {
  final autovelox = <Autovelox>[];
  final tutor = <Tutor>[];
  for (final percorso in argomenti.skip(1)) {
    final righe = File(percorso).openRead().transform(utf8.decoder).transform(const LineSplitter());
    if (percorso.endsWith('.opl')) {
      final estratto = EstrattoOsm();
      await for (final riga in righe) {
        estratto.leggi(riga);
      }
      final (a, t) = estratto.risolvi();
      autovelox.addAll(a);
      tutor.addAll(t);
    } else {
      await for (final riga in righe) {
        if (daGeojson(riga) case final a?) autovelox.add(a);
      }
    }
  }
  final tutti = senzaDoppi(autovelox);
  final visti = <String>{};
  final tratti = [
    for (final t in tutor)
      if (visti.add([t.$1, t.$2, t.$3, t.$4].map((v) => v.toStringAsFixed(4)).join(','))) t,
  ];
  final testo = ArchivioAutovelox.scrivi(tutti, tutor: tratti);
  await File(argomenti.first).writeAsString(testo);
  final conLimite = tutti.where((a) => a.$3 != null).length;
  final conDirezione = tutti.where((a) => a.$4 != null).length;
  stdout.writeln('::notice title=Autovelox::${tutti.length} fissi, $conLimite col limite, '
      '$conDirezione con la direzione, ${tratti.length} Tutor, ${testo.length ~/ 1024} kB');
  if (tutti.length < 100) {
    stdout.writeln('::error title=Autovelox::troppo pochi, qualcosa non va');
    exitCode = 1;
  }
}
