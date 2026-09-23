import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import '../motore/modello_consumo.dart';

/// Un'istruzione di guida, come la dà Valhalla.
class Manovra {
  const Manovra({required this.istruzione, required this.lunghezzaM, required this.secondi, required this.inizio});

  final String istruzione;
  final double lunghezzaM;
  final double secondi;

  /// Indice in [PercorsoCalcolato.punti] da cui parte.
  final int inizio;
}

/// Un percorso pronto per il motore: la geometria per la mappa e le
/// colonnine, i tratti per i consumi, le manovre per la guida.
class PercorsoCalcolato {
  const PercorsoCalcolato({required this.punti, required this.tratti, required this.manovre});

  final List<Punto> punti;
  final List<Tratto> tratti;
  final List<Manovra> manovre;

  double get lunghezzaM => tratti.fold(0, (s, t) => s + t.lunghezzaM);
  Duration get durata => Duration(seconds: tratti.fold(0.0, (s, t) => s + t.secondi).round());

  /// Quota che Valhalla usa quando non ha il modello del terreno.
  static const _senzaQuota = -400.0;

  /// Legge la risposta di `/route`. Ogni segmento del tracciato diventa un
  /// tratto: velocità dalla sua manovra (lunghezza / tempo), dislivello dal
  /// profilo altimetrico campionato ogni `elevation_interval` metri.
  static PercorsoCalcolato daValhalla(Map<String, Object?> json) {
    final trip = json['trip'] as Map<String, Object?>;
    final punti = <Punto>[];
    final tratti = <Tratto>[];
    final manovre = <Manovra>[];

    for (final leg in (trip['legs'] as List).cast<Map<String, Object?>>()) {
      final base = punti.isEmpty ? 0 : punti.length - 1;
      final forma = decodificaPolyline(leg['shape'] as String);
      punti.addAll(punti.isEmpty ? forma : forma.skip(1));
      final linea = Linea(forma);
      final quota = _Profilo(
        ((leg['elevation'] as List?) ?? const []).map((e) => (e as num).toDouble()).toList(),
        (leg['elevation_interval'] as num?)?.toDouble() ?? 0,
      );

      for (final m in (leg['maneuvers'] as List).cast<Map<String, Object?>>()) {
        final da = m['begin_shape_index'] as int, a = m['end_shape_index'] as int;
        final lunghezza = (m['length'] as num).toDouble() * 1000;
        final secondi = (m['time'] as num).toDouble();
        manovre.add(Manovra(
          istruzione: m['instruction'] as String? ?? '',
          lunghezzaM: lunghezza,
          secondi: secondi,
          inizio: base + da,
        ));
        if (a <= da || lunghezza <= 0 || secondi <= 0) continue;
        final kmh = lunghezza / secondi * 3.6;
        // Le distanze fra i punti non tornano mai al metro con quelle di
        // Valhalla: si scalano perché la manovra misuri quanto dice lui.
        final geometrica = linea.cumulate[a] - linea.cumulate[da];
        final scala = geometrica > 0 ? lunghezza / geometrica : 0.0;
        for (var i = da + 1; i <= a; i++) {
          final metri = (linea.cumulate[i] - linea.cumulate[i - 1]) * scala;
          if (metri <= 0) continue;
          tratti.add(Tratto(
            lunghezzaM: metri,
            velocitaKmh: kmh,
            dislivelloM: quota.a(linea.cumulate[i]) - quota.a(linea.cumulate[i - 1]),
          ));
        }
      }
    }
    return PercorsoCalcolato(punti: punti, tratti: tratti, manovre: manovre);
  }
}

class _Profilo {
  _Profilo(List<double> campioni, this.passoM)
      : _q = campioni.any((q) => q <= PercorsoCalcolato._senzaQuota) ? const [] : campioni;

  final List<double> _q;
  final double passoM;

  double a(double m) {
    if (_q.isEmpty || passoM <= 0) return 0;
    final x = m / passoM;
    final i = x.floor();
    if (i >= _q.length - 1) return _q.last;
    return _q[i] + (x - i) * (_q[i + 1] - _q[i]);
  }
}

class ErroreValhalla implements Exception {
  const ErroreValhalla(this.messaggio, {this.stato});
  final String messaggio;
  final int? stato;

  @override
  String toString() => 'Valhalla: $messaggio';
}

/// Il client di Valhalla, sul server gratuito (vedi `valhalla/`).
class ClienteValhalla {
  ClienteValhalla(this.indirizzo, {http.Client? client, this.chiave}) : _http = client ?? http.Client();

  final Uri indirizzo;

  /// Se il server la chiede (Caddy davanti a Valhalla).
  final String? chiave;
  final http.Client _http;

  Future<PercorsoCalcolato> calcola(List<Punto> tappe, {String lingua = 'it-IT'}) async {
    final corpo = {
      'locations': [
        for (final p in tappe) {'lat': p.lat, 'lon': p.lon},
      ],
      'costing': 'auto',
      'units': 'kilometers',
      'language': lingua,
      'elevation_interval': 30,
    };
    final r = await _http.post(
      indirizzo.resolve('route'),
      headers: {'content-type': 'application/json', if (chiave != null) 'x-gdanav-chiave': chiave!},
      body: jsonEncode(corpo),
    );
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
    if (r.statusCode != 200) {
      throw ErroreValhalla(json['error'] as String? ?? 'errore ${r.statusCode}', stato: r.statusCode);
    }
    return PercorsoCalcolato.daValhalla(json);
  }

  void chiudi() => _http.close();
}
