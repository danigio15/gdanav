import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import '../motore/modello_consumo.dart';
import '../ztl/ztl.dart';
import 'valhalla.dart';

/// I percorsi da TomTom, al posto di Valhalla.
///
/// Perché: il server che usavamo (`valhalla1.openstreetmap.de`) è quello
/// pubblico e gratuito di FOSSGIS, tenuto in piedi per prova, senza nessuna
/// promessa verso chi ci appoggia sopra un'app distribuita. TomTom invece
/// dà 20.000 percorsi al mese sul piano gratuito, e soprattutto **conosce
/// il traffico**: il tempo che risponde è quello di adesso, non quello
/// delle velocità scritte sulla strada.
///
/// Cosa si guadagna, rispetto a Valhalla:
///  * il tempo di arrivo tiene già conto delle code, senza una seconda
///    chiamata;
///  * le code lungo il percorso arrivano nella stessa risposta
///    (`sectionType=traffic`), con quanto si va dentro e quanto si perde;
///  * le manovre hanno l'angolo vero (`turnAngleInDecimalDegrees`) e il
///    cartello (`roadNumbers`, `signpostText`), così lo svincolo disegnato
///    somiglia a quello che si ha davanti;
///  * i limiti di velocità arrivano nella stessa risposta
///    (`sectionType=speedLimit`), dove Valhalla voleva una chiamata a parte;
///  * una sola chiamata dà anche le alternative complete: non serve più
///    rifare il percorso scelto.
///
/// Le corsie non stanno nelle istruzioni: TomTom le dà come sezioni a parte
/// (`sectionType=lanes`), da sinistra a destra, con la freccia di ognuna e
/// quella da seguire, e ogni tratto finisce sul punto della manovra. Al
/// Sottopasso Malta dice tre corsie, le due di sinistra da seguire: il
/// «tieni la sinistra» del popup dello svincolo.
///
/// Cosa si perde, e va detto: l'altimetria. I tratti escono piatti e il
/// dislivello lo recupera il consumo vero misurato dall'auto.
class ClienteTomTom {
  ClienteTomTom(this.chiave, {http.Client? client, Uri? indirizzo})
      : _http = client ?? http.Client(),
        indirizzo = indirizzo ?? Uri.parse('https://api.tomtom.com/routing/1/calculateRoute/');

  /// La chiave del piano gratuito.
  final String chiave;
  final Uri indirizzo;
  final http.Client _http;

  /// Quanti punti al massimo si rimandano a TomTom per rifare un percorso
  /// già calcolato: il corpo della richiesta non deve diventare enorme.
  static const puntiDiAppoggio = 500;

  /// Le sezioni che si chiedono a TomTom. `speedLimit` è quella che ridà il
  /// disco del limite in guida, che con Valhalla arrivava da una chiamata a
  /// parte (`/locate`); le altre dicono com'è la strada, per scegliere fra i
  /// percorsi. Vanno ripetute: separate da virgole TomTom risponde 400.
  static const sezioniChieste = ['traffic', 'speedLimit', 'tollRoad', 'motorway', 'ferry', 'carTrain', 'lanes'];

  Map<String, List<String>> _parametri(String lingua, OpzioniPercorso opzioni, {int alternative = 0}) => {
        'key': [chiave],
        'routeType': const ['fastest'],
        'traffic': const ['true'],
        'travelMode': const ['car'],
        'instructionsType': const ['tagged'],
        'language': [lingua],
        'computeTravelTimeFor': const ['all'],
        'sectionType': sezioniChieste,
        if (alternative > 0) 'maxAlternatives': ['$alternative'],
        if (opzioni.modo.velocitaMassima case final v?) 'vehicleMaxSpeed': ['$v'],
        if (_daEvitare(opzioni) case final a when a.isNotEmpty) 'avoid': [a.join(',')],
      };

  static List<String> _daEvitare(OpzioniPercorso o) => [
        if (o.evitaPedaggi) 'tollRoads',
        if (o.evitaAutostrade) 'motorways',
        if (o.evitaTraghetti) 'ferries',
      ];

  static String _luogo(Punto p) => '${p.lat},${p.lon}';

  /// Le coordinate hanno i due punti in mezzo («lat,lon:lat,lon»), e
  /// `Uri.resolve` li scambierebbe per uno schema: l'indirizzo si scrive e
  /// si rilegge intero.
  Uri _via(List<Punto> tappe, Map<String, List<String>> parametri) {
    final radice = indirizzo.toString().endsWith('/') ? '$indirizzo' : '$indirizzo/';
    return Uri.parse('$radice${tappe.map(_luogo).join(':')}/json').replace(queryParameters: parametri);
  }

  /// Legge la risposta, o dice perché non si può.
  Future<Map<String, Object?>> _chiedi(Uri via, {Map<String, Object?>? corpo}) async {
    final http.Response r;
    try {
      r = await (corpo == null
              ? _http.get(via)
              : _http.post(via, headers: const {'content-type': 'application/json'}, body: jsonEncode(corpo)))
          .timeout(const Duration(seconds: 60),
              onTimeout: () => throw const ErrorePercorso('il server dei percorsi non risponde'));
    } on http.ClientException catch (e) {
      throw ErrorePercorso(e.message);
    }
    final testo = utf8.decode(r.bodyBytes);
    if (r.statusCode != 200) {
      // TomTom risponde `{"detailedError":{"message":"…"}}`, ma non sempre:
      // un 403 dal contatore esaurito arriva anche come testo semplice.
      String? messaggio;
      try {
        final j = jsonDecode(testo);
        if (j is Map) {
          messaggio = ((j['detailedError'] as Map?)?['message'] ?? (j['error'] as Map?)?['description'])?.toString();
        }
      } on FormatException {
        messaggio = testo.trim().isEmpty ? null : testo.trim();
      }
      throw ErrorePercorso(messaggio ?? 'errore ${r.statusCode}', stato: r.statusCode);
    }
    final letto = jsonDecode(testo);
    if (letto is! Map<String, Object?>) throw const ErrorePercorso('risposta non capita');
    return letto;
  }

  /// Le aree da evitare, nel corpo della richiesta: TomTom le vuole lì, e
  /// allora la richiesta diventa un POST. Senza, `null`: resta un GET.
  static Map<String, Object?>? _corpo(List<Rettangolo> evita, [Map<String, Object?> altro = const {}]) =>
      evita.isEmpty && altro.isEmpty
          ? null
          : {
              ...altro,
              if (evita.isNotEmpty)
                'avoidAreas': {
                  'rectangles': [for (final r in evita) r.perTomTom()]
                },
            };

  /// Il percorso fra le [tappe] (partenza, tappe intermedie, arrivo), lontano
  /// dai rettangoli di [evita] (le ZTL senza permesso).
  Future<PercorsoCalcolato> calcola(
    List<Punto> tappe, {
    String lingua = 'it-IT',
    OpzioniPercorso opzioni = const OpzioniPercorso(),
    List<Rettangolo> evita = const [],
  }) async {
    if (tappe.length < 2) throw const ErrorePercorso('servono almeno partenza e arrivo');
    final j = await _chiedi(_via(tappe, _parametri(lingua, opzioni)), corpo: _corpo(evita));
    final rotte = leggiTutte(j);
    if (rotte.isEmpty) throw const ErrorePercorso('nessun percorso fra questi punti');
    return rotte.first;
  }

  /// Fino a [quante] alternative da [da] ad [a], la migliore per prima.
  ///
  /// A differenza di Valhalla queste sono già complete (manovre e code):
  /// [seguendo] non deve rifare niente.
  Future<List<PercorsoCalcolato>> alternative(
    Punto da,
    Punto a, {
    int quante = 2,
    String lingua = 'it-IT',
    OpzioniPercorso opzioni = const OpzioniPercorso(),
    List<Rettangolo> evita = const [],
  }) async {
    final j = await _chiedi(_via([da, a], _parametri(lingua, opzioni, alternative: quante)), corpo: _corpo(evita));
    final rotte = leggiTutte(j);
    if (rotte.isEmpty) throw const ErrorePercorso('nessun percorso fra questi punti');
    return rotte;
  }

  /// Il percorso [scelto] fra le [alternative], pronto per la guida.
  ///
  /// Con TomTom di solito non c'è niente da rifare — le alternative
  /// arrivano già con le manovre — e allora non si spende una chiamata. Se
  /// però quella scelta è arrivata senza manovre, si richiede passando dai
  /// suoi punti, così TomTom non cambia strada.
  Future<PercorsoCalcolato> seguendo(
    PercorsoCalcolato scelto, {
    String lingua = 'it-IT',
    OpzioniPercorso opzioni = const OpzioniPercorso(),
  }) async {
    if (scelto.manovre.isNotEmpty) return scelto;
    final punti = scelto.punti;
    if (punti.length < 2) return scelto;
    final j = await _chiedi(
      _via([punti.first, punti.last], _parametri(lingua, opzioni)),
      corpo: {
        'supportingPoints': [
          for (final p in _diradati(punti, puntiDiAppoggio)) {'latitude': p.lat, 'longitude': p.lon},
        ],
      },
    );
    final rotte = leggiTutte(j);
    // Rifatto dai suoi punti, è la stessa strada: quello che fa con le ZTL
    // resta vero.
    return rotte.isEmpty ? scelto : rotte.first.conZtl(scelto.ztl);
  }

  /// [punti] ridotti ad al massimo [quanti], tenendoli distanziati uguale e
  /// tenendo sempre il primo e l'ultimo.
  static List<Punto> _diradati(List<Punto> punti, int quanti) {
    if (punti.length <= quanti) return punti;
    final passo = (punti.length - 1) / (quanti - 1);
    return [
      for (var k = 0; k < quanti - 1; k++) punti[(k * passo).round()],
      punti.last,
    ];
  }

  /// Tutte le rotte della risposta, la migliore per prima.
  static List<PercorsoCalcolato> leggiTutte(Map<String, Object?> json) => [
        for (final r in ((json['routes'] as List?) ?? const []).whereType<Map>()) leggi(r.cast<String, Object?>()),
      ];

  /// Una rotta di TomTom (`routes[i]`) nel percorso che usa il motore.
  static PercorsoCalcolato leggi(Map<String, Object?> rotta) {
    final punti = <Punto>[];
    for (final leg in ((rotta['legs'] as List?) ?? const []).whereType<Map>()) {
      final forma = [
        for (final p in ((leg['points'] as List?) ?? const []).whereType<Map>())
          Punto((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble()),
      ];
      // Fra un pezzo e l'altro l'ultimo punto è ripetuto.
      punti.addAll(punti.isEmpty ? forma : forma.skip(1));
    }
    final linea = punti.length > 1 ? Linea(punti) : null;
    final istruzioni = (((rotta['guidance'] as Map?)?['instructions'] as List?) ?? const [])
        .whereType<Map>()
        .map((i) => i.cast<String, Object?>())
        .toList();
    final sommario = (rotta['summary'] as Map?)?.cast<String, Object?>() ?? const {};
    final sezioni = ((rotta['sections'] as List?) ?? const []).whereType<Map>().toList();

    final manovre = <Manovra>[];
    final tratti = <Tratto>[];
    for (var k = 0; k < istruzioni.length; k++) {
      final i = istruzioni[k];
      final dopo = k + 1 < istruzioni.length ? istruzioni[k + 1] : null;
      final da = (i['pointIndex'] as num?)?.toInt() ?? 0;
      final a = (dopo?['pointIndex'] as num?)?.toInt() ?? (punti.isEmpty ? 0 : punti.length - 1);
      final metri = _num(dopo?['routeOffsetInMeters']) - _num(i['routeOffsetInMeters']);
      final secondi = _num(dopo?['travelTimeInSeconds']) - _num(i['travelTimeInSeconds']);
      manovre.add(_manovra(i, lunghezzaM: metri, secondi: secondi, inizio: da, corsie: _corsie(sezioni, da)));
      if (linea == null || a <= da || metri <= 0 || secondi <= 0) continue;
      final kmh = metri / secondi * 3.6;
      // Le distanze di TomTom non tornano al metro con quelle fra i punti:
      // si scalano perché la manovra misuri quanto dice lui.
      final fine = math.min(a, punti.length - 1);
      final geometrica = linea.cumulate[fine] - linea.cumulate[da];
      final scala = geometrica > 0 ? metri / geometrica : 0.0;
      for (var n = da + 1; n <= fine; n++) {
        final passo = (linea.cumulate[n] - linea.cumulate[n - 1]) * scala;
        // Niente quote: TomTom non dà l'altimetria, il dislivello resta 0 e
        // il consumo lo corregge quello vero misurato dall'auto.
        if (passo > 0) tratti.add(Tratto(lunghezzaM: passo, velocitaKmh: kmh));
      }
    }

    final code = linea == null ? const <Coda>[] : _code(sezioni, linea);
    return PercorsoCalcolato(
      punti: punti,
      tratti: tratti,
      manovre: manovre,
      limiti: _limiti(sezioni, punti.length),
      conPedaggi: _haSezione(sezioni, 'TOLL_ROAD') || _haSezione(sezioni, 'TOLL_VIGNETTE'),
      conAutostrade: _haSezione(sezioni, 'MOTORWAY') || manovre.any((m) => m.tipo == 25),
      conTraghetti: _haSezione(sezioni, 'FERRY') || _haSezione(sezioni, 'CAR_TRAIN'),
      code: code,
      ritardoTraffico: Duration(seconds: _ritardo(sommario, code)),
      // Il tempo di TomTom è quello di adesso: il traffico è già dentro.
      trafficoVero: true,
    );
  }

  /// Quanto si perde in tutto per il traffico. TomTom dà
  /// `trafficDelayInSeconds` solo per gli eventi segnalati; il rallentamento
  /// normale sta nella differenza col tempo senza traffico.
  static int _ritardo(Map<String, Object?> sommario, List<Coda> code) {
    final conTraffico = _num(sommario['travelTimeInSeconds']);
    final senza = _num(sommario['noTrafficTravelTimeInSeconds']);
    final differenza = conTraffico > 0 && senza > 0 ? conTraffico - senza : 0.0;
    final dichiarato = _num(sommario['trafficDelayInSeconds']);
    final dalleCode = code.fold(0.0, (s, c) => s + c.ritardo.inSeconds);
    return math.max(differenza, math.max(dichiarato, dalleCode)).round();
  }

  /// Il limite di velocità di ogni segmento del tracciato, `null` dove non
  /// si sa. TomTom lo dà a pezzi di strada (`SPEED_LIMIT`, da un punto a un
  /// altro); qui diventa la stessa lista che dava Valhalla, così il disco
  /// del tachimetro non si accorge del cambio di motore.
  static List<int?> _limiti(List<Map> sezioni, int quantiPunti) {
    if (quantiPunti < 2) return const [];
    final trovati = sezioni.where((s) => '${s['sectionType']}'.toUpperCase() == 'SPEED_LIMIT');
    if (trovati.isEmpty) return const [];
    final limiti = List<int?>.filled(quantiPunti - 1, null);
    for (final s in trovati) {
      final kmh = (s['maxSpeedLimitInKmh'] as num?)?.round();
      final da = (s['startPointIndex'] as num?)?.toInt();
      final a = (s['endPointIndex'] as num?)?.toInt();
      if (kmh == null || kmh <= 0 || da == null || a == null) continue;
      for (var i = math.max(0, da); i < math.min(a, limiti.length); i++) {
        limiti[i] = kmh;
      }
    }
    return limiti;
  }

  /// Le corsie arrivando alla manovra che parte dal punto [punto], da
  /// sinistra a destra. Il tratto `LANES` che le descrive finisce sul punto
  /// della manovra; se sono più d'uno, vale quello che finisce più vicino.
  /// Un tratto senza manovra dentro — resta in corsia passando un'uscita —
  /// non si attacca a niente.
  static List<Corsia> _corsie(List<Map> sezioni, int punto) {
    Map? scelto;
    var distanza = 1 << 30;
    for (final s in sezioni) {
      if ('${s['sectionType']}'.toUpperCase() != 'LANES') continue;
      final da = (s['startPointIndex'] as num?)?.toInt();
      final a = (s['endPointIndex'] as num?)?.toInt();
      if (da == null || a == null || punto < da || punto > a) continue;
      if (a - punto < distanza) {
        scelto = s;
        distanza = a - punto;
      }
    }
    if (scelto == null) return const [];
    return [
      for (final l in ((scelto['lanes'] as List?) ?? const []).whereType<Map>())
        () {
          final frecce = [
            for (final d in ((l['directions'] as List?) ?? const []))
              if (_freccia('$d') case final f?) f,
          ];
          final segui = l['follow'] == null ? null : _freccia('${l['follow']}');
          return Corsia(frecce.isEmpty ? const [DirezioneCorsia.dritto] : frecce,
              giusta: segui != null, consigliata: segui);
        }(),
    ];
  }

  static DirezioneCorsia? _freccia(String d) => switch (d.toUpperCase()) {
        'STRAIGHT' => DirezioneCorsia.dritto,
        'SLIGHT_RIGHT' => DirezioneCorsia.leggeraDestra,
        'RIGHT' => DirezioneCorsia.destra,
        'SHARP_RIGHT' => DirezioneCorsia.destraStretta,
        'RIGHT_U_TURN' => DirezioneCorsia.inversioneDestra,
        'SLIGHT_LEFT' => DirezioneCorsia.leggeraSinistra,
        'LEFT' => DirezioneCorsia.sinistra,
        'SHARP_LEFT' => DirezioneCorsia.sinistraStretta,
        'LEFT_U_TURN' => DirezioneCorsia.inversioneSinistra,
        _ => null,
      };

  static bool _haSezione(List<Map> sezioni, String tipo) =>
      sezioni.any((s) => '${s['sectionType']}'.toUpperCase() == tipo);

  static List<Coda> _code(List<Map> sezioni, Linea linea) {
    final code = <Coda>[];
    for (final s in sezioni) {
      if ('${s['sectionType']}'.toUpperCase() != 'TRAFFIC') continue;
      final da = (s['startPointIndex'] as num?)?.toInt();
      final a = (s['endPointIndex'] as num?)?.toInt();
      if (da == null || a == null || a <= da) continue;
      final categoria = '${s['simpleCategory'] ?? ''}'.toUpperCase();
      final gravita = (s['magnitudeOfDelay'] as num?)?.toInt() ?? 0;
      final velocita = (s['effectiveSpeedInKmh'] as num?)?.toDouble();
      code.add(Coda(
        daM: linea.cumulate[da.clamp(0, linea.cumulate.length - 1)],
        aM: linea.cumulate[a.clamp(0, linea.cumulate.length - 1)],
        ritardo: Duration(seconds: ((s['delayInSeconds'] as num?) ?? 0).round()),
        livello: categoria == 'ROAD_CLOSURE' ? 4 : _livello(gravita),
        // 0 km/h vuol dire fermi, non «non si sa».
        velocitaKmh: velocita != null && velocita >= 0 ? velocita : null,
        tipo: switch (categoria) {
          'JAM' => 'Coda',
          'ROAD_WORK' => 'Lavori',
          'ROAD_CLOSURE' => 'Strada chiusa',
          _ => null,
        },
      ));
    }
    return code;
  }

  /// `magnitudeOfDelay` di TomTom (0 non si sa, 1 lieve, 2 medio, 3 grave,
  /// 4 indefinito) nei livelli del navigatore.
  static int _livello(int gravita) => switch (gravita) {
        1 => 1,
        2 => 2,
        3 || 4 => 3,
        _ => 2,
      };

  static double _num(Object? x) => x is num ? x.toDouble() : 0;

  static Manovra _manovra(
    Map<String, Object?> i, {
    required double lunghezzaM,
    required double secondi,
    required int inizio,
    List<Corsia> corsie = const [],
  }) {
    final unisci = i['possibleCombineWithNext'] == true && i['combinedMessage'] != null;
    final frase = _senzaEtichette('${(unisci ? i['combinedMessage'] : null) ?? i['message'] ?? ''}');
    final numeri = ((i['roadNumbers'] as List?) ?? const []).whereType<String>().toList();
    final rotonda = (i['roundaboutExitNumber'] as num?)?.toInt();
    return Manovra(
      istruzione: frase,
      lunghezzaM: lunghezzaM,
      secondi: secondi,
      inizio: inizio,
      tipo: tipoDellaManovra('${i['maneuver'] ?? ''}', drittaADestra: '${i['drivingSide'] ?? 'RIGHT'}' != 'LEFT'),
      voce: frase,
      strada: '${i['street'] ?? ''}',
      uscita: '${i['exitNumber'] ?? ''}',
      verso: [
        if (numeri.isNotEmpty) numeri.join('/'),
        if ('${i['signpostText'] ?? ''}'.isNotEmpty) '${i['signpostText']}',
      ].join(' · '),
      uscitaRotonda: rotonda != null && rotonda > 0 ? rotonda : null,
      corsie: corsie,
    );
  }

  /// I messaggi arrivano con i pezzi marcati (`instructionsType=tagged`):
  /// «Gira a sinistra in &lt;street&gt;Corso Malta&lt;/street&gt;». Le
  /// etichette servono solo a chi vuole scriverle in grassetto: qui si
  /// tolgono, il testo resta quello.
  static String _senzaEtichette(String s) => s.replaceAll(RegExp(r'</?[a-zA-Z]+>'), '').trim();

  /// La manovra di TomTom nel numero di Valhalla, che è quello che l'app usa
  /// per scegliere l'icona e disegnare lo svincolo. Si tiene la numerazione
  /// di prima apposta: cambiando motore non deve cambiare niente sopra.
  static int tipoDellaManovra(String manovra, {bool drittaADestra = true}) => switch (manovra.toUpperCase()) {
        'DEPART' || 'WAYPOINT_REACHED' => 1,
        'ARRIVE' => 4,
        'ARRIVE_RIGHT' || 'WAYPOINT_RIGHT' => 5,
        'ARRIVE_LEFT' || 'WAYPOINT_LEFT' => 6,
        'STRAIGHT' || 'FOLLOW' || 'SWITCH_PARALLEL_ROAD' || 'SWITCH_MAIN_ROAD' => 8,
        'BEAR_RIGHT' => 9,
        'TURN_RIGHT' => 10,
        'SHARP_RIGHT' => 11,
        // In Italia si inverte a sinistra; dove si guida a sinistra, a destra.
        'MAKE_UTURN' || 'TRY_MAKE_UTURN' => drittaADestra ? 13 : 12,
        'SHARP_LEFT' => 14,
        'TURN_LEFT' => 15,
        'BEAR_LEFT' => 16,
        'ENTRANCE_RAMP' => drittaADestra ? 18 : 19,
        'MOTORWAY_EXIT_RIGHT' => 20,
        'MOTORWAY_EXIT_LEFT' => 21,
        // L'uscita: da che parte la dice il paese, se TomTom non lo specifica.
        'TAKE_EXIT' => drittaADestra ? 20 : 21,
        'KEEP_RIGHT' => 23,
        'KEEP_LEFT' => 24,
        'ENTER_MOTORWAY' || 'ENTER_FREEWAY' || 'ENTER_HIGHWAY' => 25,
        'ROUNDABOUT_RIGHT' || 'ROUNDABOUT_LEFT' || 'ROUNDABOUT_CROSS' || 'ROUNDABOUT_BACK' => 26,
        'TAKE_FERRY' => 28,
        _ => 0,
      };
}
