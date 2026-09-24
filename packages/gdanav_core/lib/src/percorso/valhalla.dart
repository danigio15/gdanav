import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import '../motore/modello_consumo.dart';

/// Un'istruzione di guida, come la dà Valhalla.
class Manovra {
  const Manovra({
    required this.istruzione,
    required this.lunghezzaM,
    required this.secondi,
    required this.inizio,
    this.tipo = 0,
    this.voce = '',
    this.strada = '',
  });

  final String istruzione;

  /// Il tipo di Valhalla (10 destra, 15 sinistra, 26 rotonda…): decide
  /// l'icona.
  final int tipo;

  /// La frase da dire prima della manovra.
  final String voce;

  /// Il nome della strada in cui si entra, se c'è.
  final String strada;
  final double lunghezzaM;
  final double secondi;

  /// Indice in [PercorsoCalcolato.punti] da cui parte.
  final int inizio;
}

/// Un percorso pronto per il motore: la geometria per la mappa e le
/// colonnine, i tratti per i consumi, le manovre per la guida.
class PercorsoCalcolato {
  const PercorsoCalcolato({required this.punti, required this.tratti, required this.manovre, this.limiti = const []});

  final List<Punto> punti;
  final List<Tratto> tratti;
  final List<Manovra> manovre;

  /// Il limite di velocità (km/h) di ogni segmento di [punti], `null` dove
  /// OpenStreetMap non lo sa. Vuota se il server non l'ha dato.
  final List<int?> limiti;

  /// Il limite sul segmento [i], se si conosce.
  int? limiteSul(int i) => i >= 0 && i < limiti.length ? limiti[i] : null;

  PercorsoCalcolato conLimiti(List<int?> limiti) =>
      PercorsoCalcolato(punti: punti, tratti: tratti, manovre: manovre, limiti: limiti);

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
          tipo: m['type'] as int? ?? 0,
          voce: m['verbal_pre_transition_instruction'] as String? ?? m['instruction'] as String? ?? '',
          strada: ((m['street_names'] as List?) ?? const []).cast<String>().join(', '),
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

/// Come guidare: più veloce, o più piano per consumare meno. Come la
/// «velocità di riferimento» di ABRP: Valhalla sceglie strade e tempi con
/// quel massimo, e il consumo si stima su quelle velocità.
enum ModoGuida {
  veloce('Più veloce', null),
  equilibrato('Equilibrato', 120),
  risparmio('Risparmio', 100);

  const ModoGuida(this.nome, this.velocitaMassima);

  final String nome;

  /// km/h; `null`: quelle della strada.
  final int? velocitaMassima;
}

/// Le scelte del percorso, come in ogni navigatore.
class OpzioniPercorso {
  const OpzioniPercorso({
    this.modo = ModoGuida.veloce,
    this.evitaPedaggi = false,
    this.evitaAutostrade = false,
    this.evitaTraghetti = false,
    this.ricalcoloAutomatico = true,
  });

  factory OpzioniPercorso.daJson(Map<String, Object?> j) => OpzioniPercorso(
        modo: ModoGuida.values.where((m) => m.name == j['modo']).firstOrNull ?? ModoGuida.veloce,
        evitaPedaggi: j['evita_pedaggi'] as bool? ?? false,
        evitaAutostrade: j['evita_autostrade'] as bool? ?? false,
        evitaTraghetti: j['evita_traghetti'] as bool? ?? false,
        ricalcoloAutomatico: j['ricalcolo_automatico'] as bool? ?? true,
      );

  final ModoGuida modo;
  final bool evitaPedaggi;
  final bool evitaAutostrade;
  final bool evitaTraghetti;

  /// In guida, se il consumo vero si allontana dal previsto: ricalcolare da
  /// soli le soste, o chiederlo prima. Fuori percorso si ricalcola sempre.
  final bool ricalcoloAutomatico;

  OpzioniPercorso copia({
    ModoGuida? modo,
    bool? evitaPedaggi,
    bool? evitaAutostrade,
    bool? evitaTraghetti,
    bool? ricalcoloAutomatico,
  }) =>
      OpzioniPercorso(
        modo: modo ?? this.modo,
        evitaPedaggi: evitaPedaggi ?? this.evitaPedaggi,
        evitaAutostrade: evitaAutostrade ?? this.evitaAutostrade,
        evitaTraghetti: evitaTraghetti ?? this.evitaTraghetti,
        ricalcoloAutomatico: ricalcoloAutomatico ?? this.ricalcoloAutomatico,
      );

  Map<String, Object?> toJson() => {
        'modo': modo.name,
        'evita_pedaggi': evitaPedaggi,
        'evita_autostrade': evitaAutostrade,
        'evita_traghetti': evitaTraghetti,
        'ricalcolo_automatico': ricalcoloAutomatico,
      };

  /// I `costing_options.auto` di Valhalla: 0 vuol dire «solo se non c'è
  /// altro modo».
  Map<String, Object> get valhalla => {
        if (modo.velocitaMassima case final v?) 'top_speed': v,
        if (evitaPedaggi) 'use_tolls': 0.0,
        if (evitaAutostrade) 'use_highways': 0.0,
        if (evitaTraghetti) 'use_ferry': 0.0,
      };

  /// «Risparmio · senza pedaggi»: per dire in breve com'è calcolato.
  String get riassunto => [
        modo.nome,
        if (evitaPedaggi) 'senza pedaggi',
        if (evitaAutostrade) 'senza autostrade',
        if (evitaTraghetti) 'senza traghetti',
      ].join(' · ');
}

/// Il client di Valhalla, sul server gratuito (vedi `valhalla/`).
class ClienteValhalla {
  ClienteValhalla(this.indirizzo, {http.Client? client, this.chiave}) : _http = client ?? http.Client();

  final Uri indirizzo;

  /// Se il server la chiede (Caddy davanti a Valhalla).
  final String? chiave;
  final http.Client _http;

  Future<PercorsoCalcolato> calcola(
    List<Punto> tappe, {
    String lingua = 'it-IT',
    OpzioniPercorso opzioni = const OpzioniPercorso(),
  }) async {
    final costi = opzioni.valhalla;
    final corpo = {
      'locations': [
        for (final p in tappe) {'lat': p.lat, 'lon': p.lon},
      ],
      'costing': 'auto',
      if (costi.isNotEmpty) 'costing_options': {'auto': costi},
      'units': 'kilometers',
      'language': lingua,
      'elevation_interval': 30,
    };
    final r = await _http
        .post(
          indirizzo.resolve('route'),
          headers: {'content-type': 'application/json', if (chiave != null) 'x-gdanav-chiave': chiave!},
          body: jsonEncode(corpo),
        )
        .timeout(const Duration(seconds: 60),
            onTimeout: () => throw const ErroreValhalla('il server dei percorsi non risponde'));
    final testo = utf8.decode(r.bodyBytes);
    if (r.statusCode != 200) {
      // Valhalla risponde in JSON; Caddy davanti (chiave sbagliata) no.
      String? messaggio;
      try {
        messaggio = (jsonDecode(testo) as Map<String, Object?>)['error'] as String?;
      } on FormatException {
        messaggio = testo.trim().isEmpty ? null : testo.trim();
      }
      throw ErroreValhalla(messaggio ?? 'errore ${r.statusCode}', stato: r.statusCode);
    }
    final json = jsonDecode(testo) as Map<String, Object?>;
    final percorso = PercorsoCalcolato.daValhalla(json);
    // I limiti di velocità sono un di più: se il server non li dà, si guida
    // lo stesso.
    try {
      final limiti = <int?>[];
      for (final leg in ((json['trip'] as Map)['legs'] as List).cast<Map<String, Object?>>()) {
        final forma = leg['shape'] as String;
        final n = decodificaPolyline(forma).length;
        limiti.addAll(await _limitiTratto(forma, n));
      }
      if (limiti.length == percorso.punti.length - 1) return percorso.conLimiti(limiti);
    } catch (_) {}
    return percorso;
  }

  /// Chiede a `/trace_attributes` i limiti lungo il tracciato di una tappa:
  /// `edge_walk` segue esattamente le strade del percorso.
  Future<List<int?>> _limitiTratto(String forma, int punti) async {
    final r = await _http.post(
      indirizzo.resolve('trace_attributes'),
      headers: {'content-type': 'application/json', if (chiave != null) 'x-gdanav-chiave': chiave!},
      body: jsonEncode({
        'encoded_polyline': forma,
        'shape_match': 'edge_walk',
        'costing': 'auto',
        'filters': {
          'attributes': ['edge.speed_limit', 'edge.begin_shape_index', 'edge.end_shape_index'],
          'action': 'include',
        },
      }),
    );
    if (r.statusCode != 200) throw ErroreValhalla('limiti: ${r.statusCode}', stato: r.statusCode);
    return limitiDaTraccia(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>, punti);
  }

  /// Da `edges` di `/trace_attributes` a un limite per segmento.
  static List<int?> limitiDaTraccia(Map<String, Object?> json, int punti) {
    final limiti = List<int?>.filled(punti - 1 < 0 ? 0 : punti - 1, null);
    for (final e in ((json['edges'] as List?) ?? const []).cast<Map<String, Object?>>()) {
      final v = e['speed_limit'];
      final da = e['begin_shape_index'], a = e['end_shape_index'];
      if (v is! num || v <= 0 || v > 200 || da is! int || a is! int) continue;
      for (var i = da; i < a && i < limiti.length; i++) {
        limiti[i] = v.round();
      }
    }
    return limiti;
  }

  void chiudi() => _http.close();
}
