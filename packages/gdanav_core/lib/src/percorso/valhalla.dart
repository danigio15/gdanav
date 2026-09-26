import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import '../motore/modello_consumo.dart';

/// Dove porta una corsia: le frecce dipinte sull'asfalto.
enum DirezioneCorsia {
  inversioneSinistra('uturn'),
  sinistraStretta('sharp left'),
  sinistra('left'),
  leggeraSinistra('slight left'),
  dritto('straight'),
  leggeraDestra('slight right'),
  destra('right'),
  destraStretta('sharp right'),
  inversioneDestra('uturn right');

  const DirezioneCorsia(this.osrm);

  /// Come la scrive Valhalla nel formato OSRM.
  final String osrm;

  static DirezioneCorsia? da(String s) => switch (s) {
    'uturn' => inversioneSinistra,
    'merge to left' => leggeraSinistra,
    'merge to right' => leggeraDestra,
    'none' || '' => dritto,
    _ => values.where((d) => d.osrm == s).firstOrNull,
  };
}

/// Una corsia prima di uno svincolo: le sue frecce e se è una di quelle
/// giuste per il percorso.
class Corsia {
  const Corsia(this.direzioni, {this.giusta = false, this.consigliata});

  final List<DirezioneCorsia> direzioni;
  final bool giusta;

  /// Fra le frecce della corsia, quella da seguire.
  final DirezioneCorsia? consigliata;

  Map<String, Object?> toJson() => {
    'direzioni': [for (final d in direzioni) d.name],
    'giusta': giusta,
    if (consigliata != null) 'consigliata': consigliata!.name,
  };
}

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
    this.corsie = const [],
    this.uscita = '',
    this.verso = '',
    this.uscitaRotonda,
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

  /// Le corsie arrivando alla manovra, da sinistra a destra; vuota se
  /// OpenStreetMap non le conosce.
  final List<Corsia> corsie;

  /// Il numero d'uscita sul cartello («12»), se c'è.
  final String uscita;

  /// Verso dove, come sul cartello: «A12 · Arnhem, Rotterdam».
  final String verso;

  /// Nelle rotonde: quale uscita prendere.
  final int? uscitaRotonda;

  /// Le corsie servono solo se non vanno bene tutte.
  bool get corsieUtili => corsie.length > 1 && corsie.any((c) => c.giusta) && corsie.any((c) => !c.giusta);

  Manovra conCorsie(List<Corsia> c) => Manovra(
    istruzione: istruzione,
    lunghezzaM: lunghezzaM,
    secondi: secondi,
    inizio: inizio,
    tipo: tipo,
    voce: voce,
    strada: strada,
    corsie: c,
    uscita: uscita,
    verso: verso,
    uscitaRotonda: uscitaRotonda,
  );
}

/// Una coda sul percorso, dal traffico in tempo reale: da dove a dove
/// (metri dall'inizio del percorso), quanto fa perdere e quanto è grave.
class Coda {
  const Coda({
    required this.daM,
    required this.aM,
    required this.ritardo,
    this.livello = 2,
    this.velocitaKmh,
    this.tipo,
  });

  final double daM;
  final double aM;
  final Duration ritardo;

  /// 1 rallentamento, 2 coda, 3 coda ferma, 4 strada chiusa.
  final int livello;

  /// Quanto si va, dentro la coda.
  final double? velocitaKmh;

  /// «Lavori», «Incidente», «Strada chiusa»…, se si sa.
  final String? tipo;

  double get lunghezzaM => aM - daM;
}

/// Un percorso pronto per il motore: la geometria per la mappa e le
/// colonnine, i tratti per i consumi, le manovre per la guida.
class PercorsoCalcolato {
  const PercorsoCalcolato({
    required this.punti,
    required this.tratti,
    required this.manovre,
    this.limiti = const [],
    this.conPedaggi = false,
    this.conAutostrade = false,
    this.conTraghetti = false,
    this.code = const [],
    this.ritardoTraffico = Duration.zero,
    this.trafficoVero = false,
    this.senzaTraffico,
  });

  final List<Punto> punti;
  final List<Tratto> tratti;
  final List<Manovra> manovre;

  /// Il limite di velocità (km/h) di ogni segmento di [punti], `null` dove
  /// OpenStreetMap non lo sa. Vuota se il server non l'ha dato.
  final List<int?> limiti;

  /// Se passa da pedaggi, autostrade, traghetti: per scegliere fra i
  /// percorsi.
  final bool conPedaggi;
  final bool conAutostrade;
  final bool conTraghetti;

  /// Le code di adesso lungo la strada (traffico in tempo reale), e quanto
  /// fanno perdere in tutto: già dentro i tempi dei [tratti].
  final List<Coda> code;
  final Duration ritardoTraffico;

  /// I tempi tengono conto del traffico di adesso (non solo delle velocità
  /// delle strade).
  final bool trafficoVero;

  /// Lo stesso percorso prima del traffico: per rimetterci sopra il traffico
  /// aggiornato (le code sparite non devono restare).
  final PercorsoCalcolato? senzaTraffico;

  /// Il percorso da cui partire per applicare il traffico.
  PercorsoCalcolato get base => senzaTraffico ?? this;

  /// Il limite sul segmento [i], se si conosce.
  int? limiteSul(int i) => i >= 0 && i < limiti.length ? limiti[i] : null;

  PercorsoCalcolato _copia({
    List<Tratto>? tratti,
    List<Manovra>? manovre,
    List<int?>? limiti,
    List<Coda>? code,
    Duration? ritardoTraffico,
    bool? trafficoVero,
    PercorsoCalcolato? senzaTraffico,
  }) => PercorsoCalcolato(
    punti: punti,
    tratti: tratti ?? this.tratti,
    manovre: manovre ?? this.manovre,
    limiti: limiti ?? this.limiti,
    conPedaggi: conPedaggi,
    conAutostrade: conAutostrade,
    conTraghetti: conTraghetti,
    code: code ?? this.code,
    ritardoTraffico: ritardoTraffico ?? this.ritardoTraffico,
    trafficoVero: trafficoVero ?? this.trafficoVero,
    senzaTraffico: senzaTraffico ?? this.senzaTraffico,
  );

  PercorsoCalcolato conLimiti(List<int?> limiti) => _copia(limiti: limiti);

  /// Con le corsie di ogni manovra (dalla risposta OSRM dello stesso
  /// percorso): se le manovre non tornano una a una, niente corsie.
  PercorsoCalcolato conCorsie(List<List<Corsia>> corsie) {
    if (corsie.length != manovre.length) return this;
    return _copia(manovre: [for (var i = 0; i < manovre.length; i++) manovre[i].conCorsie(corsie[i])]);
  }

  /// Col traffico di adesso: dentro ogni coda i tratti vanno piano quanto
  /// basta a perdere il suo ritardo (o alla velocità della coda, se si
  /// sa), così arrivo e consumi ne tengono conto. [code] con le distanze
  /// sui [punti] di questo percorso.
  PercorsoCalcolato conTraffico(List<Coda> code) {
    // Sempre dal percorso senza traffico: le code di prima non si sommano.
    if (senzaTraffico case final b?) return b.conTraffico(code);
    final nuovi = List<Tratto>.of(tratti);
    // Dove comincia ogni tratto, in metri.
    final inizio = <double>[];
    var m = 0.0;
    for (final t in tratti) {
      inizio.add(m);
      m += t.lunghezzaM;
    }
    // Le distanze delle code sono sulla geometria; i tratti sono scalati
    // sulle lunghezze di Valhalla: si riportano sulla stessa misura.
    final geometrica = Linea(punti).lunghezzaM;
    final k = geometrica > 0 ? m / geometrica : 1.0;
    var ritardo = Duration.zero;
    for (final c in code) {
      final da = c.daM * k, a = c.aM * k;
      final dentro = [
        for (var i = 0; i < nuovi.length; i++)
          if (inizio[i] + nuovi[i].lunghezzaM > da && inizio[i] < a) i,
      ];
      if (dentro.isEmpty) continue;
      final secondi = dentro.fold(0.0, (s, i) => s + nuovi[i].secondi);
      final lunghezza = dentro.fold(0.0, (s, i) => s + nuovi[i].lunghezzaM);
      // La velocità nella coda: quella detta, o quella che fa perdere il ritardo.
      final kmh = c.velocitaKmh ?? (lunghezza / (secondi + c.ritardo.inSeconds) * 3.6);
      final v = kmh.clamp(3.0, 130.0);
      for (final i in dentro) {
        final t = nuovi[i];
        if (v < t.velocitaKmh) nuovi[i] = Tratto(lunghezzaM: t.lunghezzaM, velocitaKmh: v, dislivelloM: t.dislivelloM);
      }
      ritardo += c.ritardo;
    }
    return _copia(tratti: nuovi, code: code, ritardoTraffico: ritardo, trafficoVero: true, senzaTraffico: this);
  }

  /// I metri fatti su ogni strada.
  Map<String, double> get _metriPerStrada {
    final metri = <String, double>{};
    for (final m in manovre) {
      final nome = m.strada.split(', ').first.trim();
      if (nome.isEmpty) continue;
      metri[nome] = (metri[nome] ?? 0) + m.lunghezzaM;
    }
    return metri;
  }

  /// La strada fatta più a lungo («A1», «E45»): per chiamare il percorso.
  String get stradaPrincipale {
    final metri = _metriPerStrada;
    if (metri.isEmpty) return '';
    return (metri.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  /// Per distinguerlo dagli [altri] percorsi: la strada più lunga che gli
  /// altri non fanno (se tutti fanno la stessa autostrada, «via A27» non
  /// dice niente).
  String stradaDistintiva(Iterable<PercorsoCalcolato> altri) {
    final loro = {for (final a in altri) ...a._metriPerStrada.keys};
    final mie = _metriPerStrada.entries.where((e) => !loro.contains(e.key) && e.value >= 500).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return mie.isEmpty ? stradaPrincipale : mie.first.key;
  }

  /// Dalle `steps` del formato OSRM di Valhalla: per ogni manovra le corsie
  /// dell'incrocio in cui la si fa.
  static List<List<Corsia>> corsieDaOsrm(Map<String, Object?> json) {
    List<Map> mappe(Object? x) => ((x as List?) ?? const []).whereType<Map>().toList();
    final elenco = <List<Corsia>>[];
    final rotta = mappe(json['routes']).firstOrNull;
    for (final leg in mappe(rotta?['legs'])) {
      for (final passo in mappe(leg['steps'])) {
        final incrocio = mappe(passo['intersections']).firstOrNull;
        elenco.add([
          for (final c in mappe(incrocio?['lanes']))
            Corsia(
              [
                for (final d in ((c['indications'] as List?) ?? const []).whereType<String>())
                  if (DirezioneCorsia.da(d) case final x?) x,
              ],
              giusta: c['valid'] == true,
              consigliata: DirezioneCorsia.da('${c['valid_indication'] ?? ''}'),
            ),
        ]);
      }
    }
    return elenco;
  }

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
        manovre.add(
          Manovra(
            istruzione: m['instruction'] as String? ?? '',
            lunghezzaM: lunghezza,
            secondi: secondi,
            inizio: base + da,
            tipo: m['type'] as int? ?? 0,
            voce: m['verbal_pre_transition_instruction'] as String? ?? m['instruction'] as String? ?? '',
            strada: ((m['street_names'] as List?) ?? const []).cast<String>().join(', '),
            uscita: _testi(m['sign'], 'exit_number_elements'),
            verso: [
              _testi(m['sign'], 'exit_branch_elements'),
              _testi(m['sign'], 'exit_toward_elements'),
            ].where((t) => t.isNotEmpty).join(' · '),
            uscitaRotonda: m['roundabout_exit_count'] as int?,
          ),
        );
        if (a <= da || lunghezza <= 0 || secondi <= 0) continue;
        final kmh = lunghezza / secondi * 3.6;
        // Le distanze fra i punti non tornano mai al metro con quelle di
        // Valhalla: si scalano perché la manovra misuri quanto dice lui.
        final geometrica = linea.cumulate[a] - linea.cumulate[da];
        final scala = geometrica > 0 ? lunghezza / geometrica : 0.0;
        for (var i = da + 1; i <= a; i++) {
          final metri = (linea.cumulate[i] - linea.cumulate[i - 1]) * scala;
          if (metri <= 0) continue;
          tratti.add(
            Tratto(
              lunghezzaM: metri,
              velocitaKmh: kmh,
              dislivelloM: quota.a(linea.cumulate[i]) - quota.a(linea.cumulate[i - 1]),
            ),
          );
        }
      }
    }
    final sommario = (trip['summary'] as Map?) ?? const {};
    return PercorsoCalcolato(
      punti: punti,
      tratti: tratti,
      manovre: manovre,
      conPedaggi: sommario['has_toll'] == true,
      conAutostrade: sommario['has_highway'] == true,
      conTraghetti: sommario['has_ferry'] == true,
    );
  }
}

/// I testi di un elemento del cartello di Valhalla (`sign`).
String _testi(Object? cartello, String chiave) {
  if (cartello is! Map) return '';
  return ((cartello[chiave] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => '${e['text'] ?? ''}')
      .where((t) => t.isNotEmpty)
      .take(3)
      .join(', ');
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
  }) => OpzioniPercorso(
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

  Map<String, String> get _intestazioni => {
    'content-type': 'application/json',
    if (chiave != null) 'x-gdanav-chiave': chiave!,
  };

  Map<String, Object?> _corpo(List<Map<String, Object?>> luoghi, String lingua, OpzioniPercorso opzioni) {
    final costi = opzioni.valhalla;
    return {
      'locations': luoghi,
      'costing': 'auto',
      if (costi.isNotEmpty) 'costing_options': {'auto': costi},
      'units': 'kilometers',
      'language': lingua,
      'elevation_interval': 30,
    };
  }

  Future<Map<String, Object?>> _route(Map<String, Object?> corpo) async {
    final r = await _http
        .post(indirizzo.resolve('route'), headers: _intestazioni, body: jsonEncode(corpo))
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw const ErroreValhalla('il server dei percorsi non risponde'),
        );
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
    return jsonDecode(testo) as Map<String, Object?>;
  }

  /// Il percorso fra le [tappe] (partenza, tappe intermedie, arrivo), con
  /// corsie e limiti di velocità.
  Future<PercorsoCalcolato> calcola(
    List<Punto> tappe, {
    String lingua = 'it-IT',
    OpzioniPercorso opzioni = const OpzioniPercorso(),
  }) => _calcola(
    [
      for (final p in tappe) {'lat': p.lat, 'lon': p.lon},
    ],
    lingua,
    opzioni,
  );

  Future<PercorsoCalcolato> _calcola(List<Map<String, Object?>> luoghi, String lingua, OpzioniPercorso opzioni) async {
    final corpo = _corpo(luoghi, lingua, opzioni);
    final json = await _route(corpo);
    return _arricchisci(PercorsoCalcolato.daValhalla(json), json, corpo);
  }

  /// Fino a [quante] percorsi diversi da [da] ad [a] (il migliore per primo),
  /// senza corsie né limiti: per scegliere. Quello scelto si ricalcola con
  /// [seguendo].
  Future<List<PercorsoCalcolato>> alternative(
    Punto da,
    Punto a, {
    int quante = 2,
    String lingua = 'it-IT',
    OpzioniPercorso opzioni = const OpzioniPercorso(),
  }) async {
    final json = await _route({
      ..._corpo(
        [
          {'lat': da.lat, 'lon': da.lon},
          {'lat': a.lat, 'lon': a.lon},
        ],
        lingua,
        opzioni,
      ),
      'alternates': quante,
    });
    return [
      PercorsoCalcolato.daValhalla(json),
      for (final alt in ((json['alternates'] as List?) ?? const []).whereType<Map>())
        if (alt['trip'] is Map) PercorsoCalcolato.daValhalla({'trip': alt['trip']}),
    ];
  }

  /// Rifà [scelto] (una delle [alternative]) con corsie e limiti: passa da
  /// qualche suo punto, ognuno con la direzione in cui lo si percorre, così
  /// Valhalla non cambia strada né carreggiata.
  Future<PercorsoCalcolato> seguendo(
    PercorsoCalcolato scelto, {
    String lingua = 'it-IT',
    OpzioniPercorso opzioni = const OpzioniPercorso(),
    int passaggi = 8,
  }) {
    final p = scelto.punti;
    final linea = Linea(p);
    final luoghi = <Map<String, Object?>>[
      {'lat': p.first.lat, 'lon': p.first.lon},
    ];
    for (var k = 1; k <= passaggi; k++) {
      final m = linea.lunghezzaM * k / (passaggi + 1);
      final i = linea.cumulate.indexWhere((c) => c >= m).clamp(1, p.length - 1);
      luoghi.add({
        'lat': p[i].lat,
        'lon': p[i].lon,
        'type': 'through',
        'heading': rottaGradi(p[i - 1], p[i]).round(),
        'heading_tolerance': 45,
      });
    }
    luoghi.add({'lat': p.last.lat, 'lon': p.last.lon});
    return _calcola(luoghi, lingua, opzioni);
  }

  Future<PercorsoCalcolato> _arricchisci(
    PercorsoCalcolato percorso,
    Map<String, Object?> json,
    Map<String, Object?> corpo,
  ) async {
    // Le corsie agli svincoli: le dà solo il formato OSRM dello stesso
    // percorso. Sono un di più: se non arrivano si guida lo stesso.
    try {
      final r = await _http
          .post(
            indirizzo.resolve('route'),
            headers: _intestazioni,
            body: jsonEncode({...corpo, 'format': 'osrm', 'elevation_interval': 0}),
          )
          .timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) {
        percorso = percorso.conCorsie(
          PercorsoCalcolato.corsieDaOsrm(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>),
        );
      }
    } catch (_) {}
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
      ultimoErroreLimiti = 'limiti: ${limiti.length} invece di ${percorso.punti.length - 1}';
    } catch (e) {
      ultimoErroreLimiti ??= '$e';
    }
    return percorso;
  }

  /// Chiede a `/trace_attributes` i limiti lungo il tracciato di una tappa:
  /// `edge_walk` segue esattamente le strade del percorso.
  Future<List<int?>> _limitiTratto(String forma, int punti) async {
    // `edge_walk` segue esattamente le strade; se non ci riesce (punti
    // doppi dove si passa per un punto di mezzo), `map_snap` le ritrova.
    Object? errore;
    for (final modo in const ['edge_walk', 'map_snap']) {
      final r = await _http.post(
        indirizzo.resolve('trace_attributes'),
        headers: _intestazioni,
        body: jsonEncode({
          'encoded_polyline': forma,
          'shape_match': modo,
          'costing': 'auto',
          'filters': {
            'attributes': ['edge.speed_limit', 'edge.begin_shape_index', 'edge.end_shape_index'],
            'action': 'include',
          },
        }),
      );
      if (r.statusCode == 200) {
        return limitiDaTraccia(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>, punti);
      }
      errore = 'limiti ($modo): ${r.statusCode} ${utf8.decode(r.bodyBytes)}';
    }
    ultimoErroreLimiti = '$errore';
    throw ErroreValhalla('$errore');
  }

  /// Perché gli ultimi limiti non sono arrivati (per le prove).
  String? ultimoErroreLimiti;

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
