import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import 'colonnina.dart';
import 'overpass.dart';

/// Le colonnine di OpenStreetMap attraverso il relay di gdanav, a riquadri
/// di mezzo grado che il relay tiene in cache per una settimana: lo stesso
/// tratto di strada si chiede a Overpass una volta sola, per tutti.
class ClienteColonnineRelay implements FonteColonnine {
  ClienteColonnineRelay(this.relay, {http.Client? client, this.insieme = 6}) : _http = client ?? http.Client();

  final Uri relay;
  final http.Client _http;

  /// Quanti riquadri si chiedono alla volta.
  final int insieme;

  static const lato = 0.5;

  /// I riquadri che toccano la striscia di [distanzaKm] intorno al percorso.
  static Set<(int, int)> riquadri(List<Punto> percorso, double distanzaKm) {
    final margine = distanzaKm / 111.0 + 0.01;
    final r = <(int, int)>{};
    for (final p in semplifica(percorso, 1000)) {
      final m = margine / math.cos(p.lat * math.pi / 180).abs().clamp(0.2, 1.0);
      for (final lat in [p.lat - margine, p.lat + margine]) {
        for (final lon in [p.lon - m, p.lon + m]) {
          r.add(((lat / lato).floor(), (lon / lato).floor()));
        }
      }
    }
    return r;
  }

  Uri _indirizzo((int, int) q) {
    final base = relay.path.endsWith('/') ? relay.path : '${relay.path}/';
    return relay.replace(path: '${base}v1/colonnine/${q.$1}/${q.$2}');
  }

  Future<List<Colonnina>> _riquadro((int, int) q) async {
    Object? ultimo;
    for (var tentativo = 0; tentativo < 2; tentativo++) {
      try {
        final r = await _http.get(_indirizzo(q)).timeout(const Duration(seconds: 45));
        if (r.statusCode == 200) {
          return ClienteOverpass.leggi(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>);
        }
        ultimo = 'relay ${r.statusCode}';
      } catch (e) {
        ultimo = e;
      }
    }
    throw Exception('colonnine: riquadro ${q.$1}/${q.$2}: $ultimo');
  }

  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async {
    final coda = riquadri(percorso, distanzaKm).toList();
    final trovate = <String, Colonnina>{};
    var prossimo = 0;
    Future<void> lavora() async {
      while (prossimo < coda.length) {
        for (final c in await _riquadro(coda[prossimo++])) {
          trovate[c.id] = c;
        }
      }
    }

    await Future.wait([for (var i = 0; i < math.min(insieme, coda.length); i++) lavora()]);
    return trovate.values.toList();
  }
}
