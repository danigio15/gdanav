import '../geo/geo.dart';
import 'colonnina.dart';

/// Le `Location` di OCPI 2.2.1, il formato con cui i punti di accesso
/// nazionali previsti dal regolamento AFIR (in Italia la PUN) pubblicano
/// stato e caratteristiche delle colonnine.
abstract final class Ocpi {
  static List<Colonnina> leggiLocations(List<Object?> json) => [
    for (final l in json.cast<Map<String, Object?>>())
      if (_location(l) case final c?) c,
  ];

  static Colonnina? _location(Map<String, Object?> l) {
    final coord = l['coordinates'] as Map<String, Object?>?;
    // In OCPI le coordinate sono stringhe.
    final lat = double.tryParse('${coord?['latitude']}');
    final lon = double.tryParse('${coord?['longitude']}');
    if (lat == null || lon == null) return null;
    final connettori = <Connettore>[];
    for (final evse in ((l['evses'] as List?) ?? const []).cast<Map<String, Object?>>()) {
      final stato = _stato(evse['status'] as String?);
      if (stato == null) continue;
      for (final c in ((evse['connectors'] as List?) ?? const []).cast<Map<String, Object?>>()) {
        connettori.add(Connettore(tipo: _tipo(c['standard'] as String?), potenzaKw: _kw(c), stato: stato));
      }
    }
    return Colonnina(
      id: 'ocpi:${l['country_code'] ?? ''}${l['party_id'] ?? ''}:${l['id']}',
      nome: l['name'] as String? ?? l['address'] as String? ?? 'Colonnina',
      posizione: Punto(lat, lon),
      connettori: connettori,
      operatore: (l['operator'] as Map?)?['name'] as String?,
      fonte: 'ocpi',
    );
  }

  /// `null` per le prese che non esistono ancora o non più.
  static StatoPresa? _stato(String? s) => switch (s) {
    'AVAILABLE' => StatoPresa.disponibile,
    'CHARGING' || 'RESERVED' || 'BLOCKED' => StatoPresa.occupata,
    'INOPERATIVE' || 'OUTOFORDER' => StatoPresa.fuoriServizio,
    'PLANNED' || 'REMOVED' => null,
    _ => StatoPresa.sconosciuto,
  };

  static TipoConnettore _tipo(String? s) => switch (s) {
    'IEC_62196_T2_COMBO' => TipoConnettore.ccs2,
    'IEC_62196_T2' => TipoConnettore.tipo2,
    'CHADEMO' => TipoConnettore.chademo,
    'TESLA_S' || 'TESLA_R' => TipoConnettore.tesla,
    _ => TipoConnettore.altro,
  };

  /// `max_electric_power` in watt se c'è, altrimenti tensione × corrente
  /// (per tre, in trifase: in OCPI la tensione è fase-neutro).
  static double _kw(Map<String, Object?> c) {
    final w = (c['max_electric_power'] as num?)?.toDouble();
    if (w != null && w > 0) return w / 1000;
    final v = (c['max_voltage'] as num?)?.toDouble() ?? 0;
    final a = (c['max_amperage'] as num?)?.toDouble() ?? 0;
    final fasi = c['power_type'] == 'AC_3_PHASE' ? 3 : 1;
    return v * a * fasi / 1000;
  }
}

/// Unisce l'anagrafica (Open Charge Map, più completa) con lo stato in
/// tempo reale (OCPI): se c'è una location OCPI entro [raggioM], le sue
/// prese sostituiscono quelle dell'anagrafica. Le location OCPI senza
/// corrispondenza si aggiungono.
List<Colonnina> unisciColonnine(List<Colonnina> anagrafica, List<Colonnina> tempoReale, {double raggioM = 60}) {
  final usate = <Colonnina>{};
  final risultato = <Colonnina>[];
  for (final a in anagrafica) {
    Colonnina? vicina;
    var migliore = raggioM;
    for (final t in tempoReale) {
      final d = distanzaM(a.posizione, t.posizione);
      if (d <= migliore && !usate.contains(t)) {
        migliore = d;
        vicina = t;
      }
    }
    if (vicina != null && vicina.connettori.isNotEmpty) {
      usate.add(vicina);
      risultato.add(
        Colonnina(
          id: a.id,
          nome: a.nome,
          posizione: a.posizione,
          connettori: vicina.connettori,
          operatore: vicina.operatore ?? a.operatore,
          fonte: '${a.fonte}+${vicina.fonte}',
        ),
      );
    } else {
      risultato.add(a);
    }
  }
  risultato.addAll(tempoReale.where((t) => !usate.contains(t)));
  return risultato;
}
