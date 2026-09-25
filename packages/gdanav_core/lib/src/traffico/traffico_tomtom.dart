import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import '../percorso/valhalla.dart';

/// Il traffico di adesso sul percorso, da TomTom: il percorso di Valhalla
/// si fa rifare a TomTom passando dagli stessi punti (`supportingPoints`),
/// col traffico; TomTom dice il ritardo e dove sono le code (le sezioni
/// `TRAFFIC`), che si riportano sui metri del nostro percorso. Una richiesta
/// per percorso (piano gratuito: 2.500 al giorno).
class TrafficoTomTom {
  TrafficoTomTom(this.chiave, {http.Client? client}) : _http = client ?? http.Client();

  final String chiave;
  final http.Client _http;

  /// Quanti punti al massimo si mandano: di più TomTom non ne vuole.
  static const massimoPunti = 1500;

  /// Il percorso coi tempi del traffico di adesso e le sue code; se TomTom
  /// non risponde, eccezione (chi chiama tiene il percorso com'era).
  Future<PercorsoCalcolato> applica(PercorsoCalcolato percorso) async {
    final p = percorso.base;
    if (p.punti.length < 2) return p;
    final punti = _dirada(p.punti);
    final da = punti.first, a = punti.last;
    final uri = Uri.parse(
      'https://api.tomtom.com/routing/1/calculateRoute/${da.lat},${da.lon}:${a.lat},${a.lon}/json',
    ).replace(queryParameters: {
      'key': chiave,
      'traffic': 'true',
      'sectionType': 'traffic',
      'routeRepresentation': 'polyline',
      'computeTravelTimeFor': 'all',
      'travelMode': 'car',
    });
    final r = await _http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'supportingPoints': [
              for (final q in punti) {'latitude': q.lat, 'longitude': q.lon},
            ],
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('TomTom traffico: ${r.statusCode}');
    return p.conTraffico(codeDa(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>, p.punti));
  }

  /// Le code della risposta di `calculateRoute`, in metri sul percorso di
  /// [nostri] punti.
  static List<Coda> codeDa(Map<String, Object?> json, List<Punto> nostri) {
    final rotta = ((json['routes'] as List?) ?? const []).whereType<Map>().firstOrNull;
    if (rotta == null) return const [];
    final loro = <Punto>[
      for (final leg in ((rotta['legs'] as List?) ?? const []).whereType<Map>())
        for (final q in ((leg['points'] as List?) ?? const []).whereType<Map>())
          Punto((q['latitude'] as num).toDouble(), (q['longitude'] as num).toDouble()),
    ];
    if (loro.isEmpty) return const [];
    final linea = Linea(nostri);
    double metri(int i) => linea.proietta(loro[i.clamp(0, loro.length - 1)]).lungoM;

    final code = <Coda>[];
    final sezioni = ((rotta['sections'] as List?) ?? const []).whereType<Map>().toList()
      ..sort((x, y) => ((x['startPointIndex'] as num?) ?? 0).compareTo((y['startPointIndex'] as num?) ?? 0));
    for (final s in sezioni) {
      if ('${s['sectionType']}' != 'TRAFFIC') continue;
      final i0 = (s['startPointIndex'] as num?)?.toInt(), i1 = (s['endPointIndex'] as num?)?.toInt();
      if (i0 == null || i1 == null || i1 <= i0) continue;
      final daM = metri(i0);
      final aM = metri(i1);
      if (aM <= daM) continue;
      final categoria = '${s['simpleCategory'] ?? ''}';
      final grandezza = (s['magnitudeOfDelay'] as num?)?.toInt() ?? 0;
      code.add(Coda(
        daM: daM,
        aM: aM,
        ritardo: Duration(seconds: ((s['delayInSeconds'] as num?) ?? 0).round()),
        velocitaKmh: (s['effectiveSpeedInKmh'] as num?)?.toDouble(),
        livello: categoria == 'ROAD_CLOSURE' ? 4 : math.max(1, math.min(3, grandezza)),
        tipo: switch (categoria) {
          'ROAD_WORK' => 'Lavori',
          'ROAD_CLOSURE' => 'Strada chiusa',
          'JAM' => null,
          _ => null,
        },
      ));
    }
    return code;
  }

  /// Un punto ogni tanto, al più [massimoPunti], sempre il primo e l'ultimo.
  static List<Punto> _dirada(List<Punto> p) {
    if (p.length <= massimoPunti) return p;
    final passo = (p.length - 1) / (massimoPunti - 1);
    return [for (var k = 0; k < massimoPunti; k++) p[(k * passo).round().clamp(0, p.length - 1)]];
  }
}
