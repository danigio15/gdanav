import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';

/// Cosa si può segnalare, come in Waze.
enum TipoSegnalazione {
  traffico('Traffico', 'Traffico'),
  polizia('Polizia', 'Polizia segnalata'),
  incidente('Incidente', 'Incidente segnalato'),
  pericolo('Pericolo', 'Pericolo segnalato'),
  lavori('Lavori', 'Lavori in corso'),
  chiusura('Strada chiusa', 'Strada chiusa segnalata'),
  autovelox('Autovelox', 'Autovelox');

  const TipoSegnalazione(this.nome, this.avviso);

  final String nome;

  /// Quello che dice la voce, seguito da «tra 500 metri».
  final String avviso;
}

class Segnalazione {
  const Segnalazione({
    required this.id,
    required this.tipo,
    required this.punto,
    required this.creata,
    this.conferme = 0,
  });

  final String id;
  final TipoSegnalazione tipo;
  final Punto punto;
  final DateTime creata;
  final int conferme;

  static Segnalazione? daJson(Object? j) {
    if (j is! Map) return null;
    final tipo = TipoSegnalazione.values.where((t) => t.name == j['tipo']).firstOrNull;
    final lat = j['lat'], lon = j['lon'], id = j['id'], creata = j['creata'];
    if (tipo == null || lat is! num || lon is! num || id is! String || creata is! num) return null;
    return Segnalazione(
      id: id,
      tipo: tipo,
      punto: Punto(lat.toDouble(), lon.toDouble()),
      creata: DateTime.fromMillisecondsSinceEpoch(creata.toInt()),
      conferme: (j['conferme'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Il servizio delle segnalazioni della comunità, sul relay di gdanav.
class ClienteSegnalazioni {
  ClienteSegnalazioni(this.indirizzo, {http.Client? client}) : _http = client ?? http.Client();

  final Uri indirizzo;
  final http.Client _http;

  Uri _uri(String percorso) => indirizzo.resolve(percorso);

  /// Quelle intorno a [qui], per una ventina di chilometri.
  Future<List<Segnalazione>> vicine(Punto qui) async {
    final r = await _http.get(
      _uri('v1/segnalazioni').replace(queryParameters: {'lat': '${qui.lat}', 'lon': '${qui.lon}'}),
    );
    if (r.statusCode != 200) throw Exception('segnalazioni: ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
    return ((j['segnalazioni'] as List?) ?? const []).map(Segnalazione.daJson).whereType<Segnalazione>().toList();
  }

  Future<Segnalazione> invia(TipoSegnalazione tipo, Punto dove) async {
    final r = await _http.post(
      _uri('v1/segnalazioni'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'tipo': tipo.name, 'lat': dove.lat, 'lon': dove.lon}),
    );
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
    if (r.statusCode != 201) throw Exception(j['errore'] ?? 'segnalazioni: ${r.statusCode}');
    return Segnalazione.daJson(j)!;
  }

  /// Chi passa dice se c'è ancora. Restituisce `null` se è stata tolta.
  Future<Segnalazione?> vota(Segnalazione s, {required bool ancora}) async {
    final r = await _http.post(
      _uri('v1/segnalazioni/${s.id}/voto'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'ancora': ancora}),
    );
    if (r.statusCode != 200) throw Exception('segnalazioni: ${r.statusCode}');
    return Segnalazione.daJson(jsonDecode(utf8.decode(r.bodyBytes)));
  }

  void chiudi() => _http.close();
}
