import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';

/// Un posto dove andare.
class Luogo {
  const Luogo({required this.nome, required this.posizione, this.descrizione = ''});

  final String nome;

  /// La riga sotto il nome: via, città, provincia.
  final String descrizione;
  final Punto posizione;
}

abstract interface class FonteLuoghi {
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA});
}

/// Photon (di komoot), costruito su OpenStreetMap: gratis, senza chiave,
/// adatto al «mentre scrivi». Chi lo usa tanto dovrebbe ospitarne uno suo:
/// l'indirizzo si cambia.
class ClientePhoton implements FonteLuoghi {
  ClientePhoton({http.Client? client, Uri? indirizzo})
      : _http = client ?? http.Client(),
        indirizzo = indirizzo ?? Uri.parse('https://photon.komoot.io/api/');

  final Uri indirizzo;
  final http.Client _http;

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    final q = testo.trim();
    if (q.length < 3) return const [];
    final uri = indirizzo.replace(queryParameters: {
      'q': q,
      'limit': '10',
      if (vicinoA != null) ...{'lat': '${vicinoA.lat}', 'lon': '${vicinoA.lon}'},
    });
    final r = await _http.get(uri, headers: {'user-agent': 'gdanav (github.com/danigio15/gdanav)'});
    if (r.statusCode != 200) throw Exception('Photon: ${r.statusCode}');
    return leggi(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>);
  }

  /// Legge la FeatureCollection GeoJSON di Photon.
  static List<Luogo> leggi(Map<String, Object?> json) {
    final luoghi = <Luogo>[];
    for (final f in ((json['features'] as List?) ?? const []).cast<Map<String, Object?>>()) {
      final coord = ((f['geometry'] as Map?)?['coordinates'] as List?)?.cast<num>();
      if (coord == null || coord.length < 2) continue;
      final p = ((f['properties'] as Map?) ?? const {}).cast<String, Object?>();
      final via = [p['street'], p['housenumber']].whereType<String>().join(' ');
      final nome = (p['name'] as String?) ?? (via.isNotEmpty ? via : null) ?? (p['city'] as String?);
      if (nome == null) continue;
      final descrizione = [
        if (p['name'] != null && via.isNotEmpty) via,
        p['city'] ?? p['county'],
        p['state'],
      ].whereType<String>().where((s) => s != nome).toSet().join(', ');
      luoghi
          .add(Luogo(nome: nome, descrizione: descrizione, posizione: Punto(coord[1].toDouble(), coord[0].toDouble())));
    }
    return luoghi;
  }
}
