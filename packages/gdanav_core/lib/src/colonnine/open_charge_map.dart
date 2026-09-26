import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import 'colonnina.dart';

/// Open Charge Map: l'anagrafica delle colonnine, gratis con una chiave.
/// I dati vanno citati («© Open Charge Map contributors»).
///
/// Si chiede per `polyline`: una sola richiesta per tutto il percorso.
class ClienteOpenChargeMap implements FonteColonnine {
  ClienteOpenChargeMap({required this.chiave, http.Client? client, Uri? indirizzo})
    : _http = client ?? http.Client(),
      indirizzo = indirizzo ?? Uri.parse('https://api.openchargemap.io/v3/poi');

  final String chiave;
  final Uri indirizzo;
  final http.Client _http;

  /// Oltre questo le polyline non stanno più in un URL: i percorsi lunghi si
  /// semplificano a un punto ogni qualche chilometro.
  static const _massimoCaratteri = 6000;

  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async {
    var passo = 500.0;
    var polyline = codificaPolyline(semplifica(percorso, passo));
    while (polyline.length > _massimoCaratteri) {
      passo *= 2;
      polyline = codificaPolyline(semplifica(percorso, passo));
    }
    final uri = indirizzo.replace(
      queryParameters: {
        'output': 'json',
        'compact': 'true',
        'verbose': 'false',
        'maxresults': '1000',
        'polyline': polyline,
        'distance': '$distanzaKm',
        'distanceunit': 'KM',
      },
    );
    final r = await _http
        .get(uri, headers: {if (chiave.isNotEmpty) 'X-API-Key': chiave})
        .timeout(const Duration(seconds: 45));
    if (r.statusCode != 200) throw Exception('colonnine: Open Charge Map ${r.statusCode}');
    return leggi(jsonDecode(utf8.decode(r.bodyBytes)) as List);
  }

  static List<Colonnina> leggi(List<Object?> json) => [
    for (final p in json.cast<Map<String, Object?>>())
      if (_colonnina(p) case final c?) c,
  ];

  static Colonnina? _colonnina(Map<String, Object?> p) {
    final stato = p['StatusTypeID'] as int?;
    // Pianificate e rimosse non esistono per chi guida.
    if (stato == 150 || stato == 200) return null;
    final indirizzo = p['AddressInfo'] as Map<String, Object?>?;
    final lat = (indirizzo?['Latitude'] as num?)?.toDouble();
    final lon = (indirizzo?['Longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final connettori = <Connettore>[
      for (final c in ((p['Connections'] as List?) ?? const []).cast<Map<String, Object?>>())
        for (var i = 0; i < ((c['Quantity'] as int?) ?? 1).clamp(1, 20); i++)
          Connettore(
            tipo: _tipo(c['ConnectionTypeID'] as int?),
            potenzaKw: (c['PowerKW'] as num?)?.toDouble() ?? 0,
            stato: _stato(c['StatusTypeID'] as int? ?? stato),
          ),
    ];
    return Colonnina(
      id: 'ocm:${p['ID']}',
      nome: indirizzo?['Title'] as String? ?? 'Colonnina',
      posizione: Punto(lat, lon),
      connettori: connettori,
      operatore: (p['OperatorInfo'] as Map?)?['Title'] as String?,
      fonte: 'ocm',
    );
  }

  /// Gli ID di `ConnectionType` di Open Charge Map.
  static TipoConnettore _tipo(int? id) => switch (id) {
    33 => TipoConnettore.ccs2,
    2 => TipoConnettore.chademo,
    25 || 1036 => TipoConnettore.tipo2,
    27 => TipoConnettore.tesla,
    _ => TipoConnettore.altro,
  };

  /// Gli ID di `StatusType`.
  static StatoPresa _stato(int? id) => switch (id) {
    10 => StatoPresa.disponibile,
    20 => StatoPresa.occupata,
    30 || 100 => StatoPresa.fuoriServizio,
    _ => StatoPresa.sconosciuto,
  };
}
