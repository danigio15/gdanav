import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import 'colonnina.dart';

/// Chi sa dire, adesso, quante prese di una colonnina sono libere.
abstract interface class FonteDisponibilita {
  /// La stessa colonnina con lo stato delle prese; se non si sa, com'era.
  Future<Colonnina> aggiorna(Colonnina c);
}

/// Colonnine libere e occupate in tempo reale da TomTom (piano gratuito:
/// 2.500 richieste al giorno, due per colonnina). La colonnina di
/// OpenStreetMap si ritrova fra quelle di TomTom per posizione.
class DisponibilitaTomTom implements FonteDisponibilita {
  DisponibilitaTomTom(
    this.chiave, {
    http.Client? client,
    this.validita = const Duration(minutes: 2),
    this.pausaDopoIlNo = const Duration(hours: 6),
    DateTime Function()? adesso,
  })  : _http = client ?? http.Client(),
        _adesso = adesso ?? DateTime.now;

  final String chiave;
  final http.Client _http;
  final DateTime Function() _adesso;

  /* Quando il fornitore dice di no per la quota, si smette di chiedere.
   *
   * Il piano gratuito di TomTom dà duemilacinquecento richieste di ricerca al
   * mese, e lo stato di una colonnina ne consuma due: quindici colonnine sullo
   * schermo sono trenta richieste. Finita la quota, ogni richiesta dopo è un
   * rifiuto — costa tempo, batteria e dati, e la colonnina resta «sconosciuta»
   * esattamente come se non l'avessimo chiesta. Nel cruscotto di TomTom si
   * vedeva il tredici per cento di richieste rifiutate.
   *
   * Al primo no si smette per [pausaDopoIlNo], poi si riprova: la quota è
   * mensile, e un'app aperta per giorni deve accorgersi che è tornata. */
  final Duration pausaDopoIlNo;
  DateTime? _dettoDiNo;

  /// Vero finché si sta aspettando dopo un rifiuto per quota.
  bool get inPausa => _dettoDiNo != null && _adesso().difference(_dettoDiNo!) < pausaDopoIlNo;

  /// L'id di disponibilità TomTom per ogni colonnina già cercata (anche
  /// `null`: non c'è).
  final _ids = <String, String?>{};

  /// Lo stato appena letto, per non richiederlo a ogni giro.
  final _recenti = <String, (DateTime, Colonnina)>{};

  /// Quanto vale uno stato letto.
  final Duration validita;

  /// Fra una richiesta e l'altra: il piano gratuito ne regge cinque al
  /// secondo, e oltre risponde 429 (e la colonnina resterebbe «sconosciuta»).
  static const intervallo = Duration(milliseconds: 230);

  static const _base = 'https://api.tomtom.com/search/2/';

  /// Le richieste passano una alla volta, distanziate.
  Future<void> _turno = Future.value();

  Future<Map<String, Object?>> _chiedi(String percorso, Map<String, String> q) async {
    for (var tentativo = 0;; tentativo++) {
      final prima = _turno;
      final fatto = Completer<void>();
      _turno = fatto.future;
      await prima;
      Timer(intervallo, fatto.complete);
      final r = await _http
          .get(Uri.parse('$_base$percorso').replace(queryParameters: {...q, 'key': chiave}))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 429 && tentativo < 2) {
        await Future<void>.delayed(Duration(milliseconds: 800 * (tentativo + 1)));
        continue;
      }
      // 403 è «quota finita» o «prodotto spento»: in tutti e due i casi
      // insistere non serve. 429 dopo i tentativi è lo stesso discorso.
      if (r.statusCode == 403 || r.statusCode == 429) _dettoDiNo = _adesso();
      if (r.statusCode != 200) throw Exception('TomTom: ${r.statusCode}');
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
    }
  }

  /// La colonnina TomTom entro 150 m con le stesse prese (in un'area di
  /// servizio le rapide e le lente sono spesso due punti diversi); a parità,
  /// la più vicina.
  Future<String?> _idDisponibilita(Colonnina c) async {
    if (_ids.containsKey(c.id)) return _ids[c.id];
    final j = await _chiedi('nearbySearch/.json', {
      'lat': '${c.posizione.lat}',
      'lon': '${c.posizione.lon}',
      'radius': '150',
      'categorySet': '7309',
      'limit': '8',
    });
    final nostre = c.connettori.map((x) => x.tipo).toSet();
    String? id;
    var migliore = (-1, double.infinity);
    for (final r in ((j['results'] as List?) ?? const []).cast<Map>()) {
      final p = r['position'] as Map?;
      final d = (r['dataSources'] as Map?)?['chargingAvailability'] as Map?;
      if (p == null || d?['id'] is! String) continue;
      final loro = {
        for (final x in (((r['chargingPark'] as Map?)?['connectors'] as List?) ?? const []).cast<Map>())
          if (_tipo(x['connectorType'] as String?) case final t?) t,
      };
      final comuni = loro.intersection(nostre).length;
      final m = distanzaM(c.posizione, Punto((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()));
      if (comuni > migliore.$1 || (comuni == migliore.$1 && m < migliore.$2)) {
        migliore = (comuni, m);
        id = d!['id'] as String;
      }
    }
    return _ids[c.id] = id;
  }

  static TipoConnettore? _tipo(String? t) => switch (t) {
        'IEC62196Type2CCS' => TipoConnettore.ccs2,
        'Chademo' => TipoConnettore.chademo,
        'IEC62196Type2CableAttached' || 'IEC62196Type2Outlet' => TipoConnettore.tipo2,
        'Tesla' => TipoConnettore.tesla,
        _ => null,
      };

  @override
  Future<Colonnina> aggiorna(Colonnina c) async {
    if (inPausa) return c;
    if (_recenti[c.id] case (final quando, final gia) when _adesso().difference(quando) < validita) return gia;
    final nuova = await _aggiorna(c);
    _recenti[c.id] = (_adesso(), nuova);
    return nuova;
  }

  Future<Colonnina> _aggiorna(Colonnina c) async {
    final id = await _idDisponibilita(c);
    if (id == null) return c;
    final j = await _chiedi('chargingAvailability.json', {'chargingAvailability': id});
    final prese = <Connettore>[];
    for (final g in ((j['connectors'] as List?) ?? const []).cast<Map>()) {
      final tipo = _tipo(g['type'] as String?);
      final ora = ((g['availability'] as Map?)?['current'] as Map?) ?? const {};
      if (tipo == null) continue;
      // La potenza: quella che c'era nella colonnina per quel tipo di presa.
      final kw = c.connettori.where((x) => x.tipo == tipo).fold(0.0, (m, x) => x.potenzaKw > m ? x.potenzaKw : m);
      final potenza = kw > 0 ? kw : (tipo == TipoConnettore.tipo2 ? 22.0 : 50.0);
      void aggiungi(Object? n, StatoPresa s) {
        for (var i = 0; i < ((n as num?)?.toInt() ?? 0); i++) {
          prese.add(Connettore(tipo: tipo, potenzaKw: potenza, stato: s));
        }
      }

      aggiungi(ora['available'], StatoPresa.disponibile);
      aggiungi(ora['occupied'], StatoPresa.occupata);
      aggiungi(ora['reserved'], StatoPresa.occupata);
      aggiungi(ora['outOfService'], StatoPresa.fuoriServizio);
      aggiungi(ora['unknown'], StatoPresa.sconosciuto);
    }
    if (prese.isEmpty) return c;
    // I tipi di presa che TomTom non conosce restano com'erano.
    final tipi = prese.map((p) => p.tipo).toSet();
    return Colonnina(
      id: c.id,
      nome: c.nome,
      operatore: c.operatore,
      posizione: c.posizione,
      fonte: c.fonte,
      connettori: [...prese, ...c.connettori.where((x) => !tipi.contains(x.tipo))],
    );
  }
}
