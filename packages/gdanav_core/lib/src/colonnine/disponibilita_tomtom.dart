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
  DisponibilitaTomTom(this.chiave, {http.Client? client}) : _http = client ?? http.Client();

  final String chiave;
  final http.Client _http;

  /// L'id di disponibilità TomTom per ogni colonnina già cercata (anche
  /// `null`: non c'è).
  final _ids = <String, String?>{};

  static const _base = 'https://api.tomtom.com/search/2/';

  Future<Map<String, Object?>> _chiedi(String percorso, Map<String, String> q) async {
    final r = await _http
        .get(Uri.parse('$_base$percorso').replace(queryParameters: {...q, 'key': chiave}))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw Exception('TomTom: ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
  }

  /// La colonnina TomTom più vicina, entro 150 m.
  Future<String?> _idDisponibilita(Colonnina c) async {
    if (_ids.containsKey(c.id)) return _ids[c.id];
    final j = await _chiedi('nearbySearch/.json', {
      'lat': '${c.posizione.lat}',
      'lon': '${c.posizione.lon}',
      'radius': '150',
      'categorySet': '7309',
      'limit': '5',
    });
    String? id;
    var migliore = double.infinity;
    for (final r in ((j['results'] as List?) ?? const []).cast<Map>()) {
      final p = r['position'] as Map?;
      final d = (r['dataSources'] as Map?)?['chargingAvailability'] as Map?;
      if (p == null || d?['id'] is! String) continue;
      final m = distanzaM(c.posizione, Punto((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()));
      if (m < migliore) {
        migliore = m;
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
