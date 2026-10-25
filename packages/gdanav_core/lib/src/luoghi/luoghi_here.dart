import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import 'luoghi.dart';

/// La ricerca di HERE (Discover), con la stessa chiave dei pedaggi.
///
/// «Romeo Gestioni Napoli» non la conoscevano ne' TomTom ne' OpenStreetMap:
/// le aziende che non hanno un negozio o un'insegna stanno nei registri
/// delle imprese, e HERE li ha. Si chiede accanto alle altre fonti
/// ([LuoghiInsieme]), mai da sola.
class ClienteHereLuoghi implements FonteLuoghi {
  ClienteHereLuoghi(this.chiave, {http.Client? client, Uri? indirizzo, this.quanti = 15})
      : _http = client ?? http.Client(),
        indirizzo = indirizzo ?? Uri.parse('https://discover.search.hereapi.com/v1/discover');

  final String chiave;
  final Uri indirizzo;
  final int quanti;
  final http.Client _http;

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    final q = testo.trim();
    if (q.length < 3) return const [];
    final uri = indirizzo.replace(queryParameters: {
      'q': q,
      // HERE vuole sapere dove cercare: vicino a chi cerca, o almeno in Italia.
      if (vicinoA != null) 'at': '${vicinoA.lat},${vicinoA.lon}' else 'in': 'countryCode:ITA',
      'lang': 'it-IT',
      'limit': '$quanti',
      'apiKey': chiave,
    });
    final r = await _http.get(uri);
    if (r.statusCode != 200) throw Exception('HERE ricerca: ${r.statusCode}');
    return leggi(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>);
  }

  /// Legge la risposta di Discover: il nome, la categoria principale, la via
  /// col civico e la citta'.
  static List<Luogo> leggi(Map<String, Object?> json) {
    final luoghi = <Luogo>[];
    for (final it in ((json['items'] as List?) ?? const []).whereType<Map>()) {
      final pos = it['position'];
      if (pos is! Map || pos['lat'] is! num || pos['lng'] is! num) continue;
      final nome = (it['title'] as String?)?.trim();
      if (nome == null || nome.isEmpty) continue;
      final a = ((it['address'] as Map?) ?? const {}).cast<String, Object?>();
      final via = [a['street'], a['houseNumber']].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      final categorie = ((it['categories'] as List?) ?? const []).whereType<Map>().toList();
      final principale = categorie.where((c) => c['primary'] == true).firstOrNull ?? categorie.firstOrNull;
      final categoria = principale?['name'] as String?;
      final descrizione = [
        categoria,
        if (via.isNotEmpty) via,
        a['city'] as String?,
      ].whereType<String>().where((s) => s.isNotEmpty && s != nome).toSet().join(', ');
      luoghi.add(Luogo(
        nome: nome,
        descrizione: descrizione,
        posizione: Punto((pos['lat'] as num).toDouble(), (pos['lng'] as num).toDouble()),
      ));
    }
    return luoghi;
  }
}
