import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import 'luoghi.dart';

/// La ricerca di TomTom (Fuzzy Search), con la stessa chiave dei percorsi e
/// del traffico.
///
/// Photon conosce un numero civico solo se qualcuno l'ha mappato su
/// OpenStreetMap, e un'attività solo per nome: «Via Roma 10» tornava la via
/// senza il civico, e «farmacia» o «benzinaio» non trovavano niente. TomTom ha
/// i civici (anche quelli ricavati dai tratti di via) e cerca le attività per
/// categoria, in italiano: «farmacia» dà le farmacie vicine.
class ClienteTomTomLuoghi implements FonteLuoghi {
  ClienteTomTomLuoghi(this.chiave, {http.Client? client, Uri? indirizzo})
      : _http = client ?? http.Client(),
        indirizzo = indirizzo ?? Uri.parse('https://api.tomtom.com/search/2/search/');

  final String chiave;
  final Uri indirizzo;
  final http.Client _http;

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    final q = testo.trim();
    if (q.length < 3) return const [];
    // Il testo sta nel percorso: si toglie la barra, che lo spezzerebbe.
    final uri = indirizzo.resolve('${Uri.encodeComponent(q.replaceAll('/', ' '))}.json').replace(queryParameters: {
      'key': chiave,
      'language': 'it-IT',
      'limit': '10',
      // «Mentre scrivi»: «via roma 1» trova anche il 10 e il 12.
      'typeahead': 'true',
      if (vicinoA != null) ...{'lat': '${vicinoA.lat}', 'lon': '${vicinoA.lon}'},
    });
    final r = await _http.get(uri);
    if (r.statusCode != 200) throw Exception('TomTom ricerca: ${r.statusCode}');
    return leggi(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>);
  }

  /// Legge la risposta della Fuzzy Search.
  static List<Luogo> leggi(Map<String, Object?> json) {
    final luoghi = <Luogo>[];
    for (final r in ((json['results'] as List?) ?? const []).whereType<Map>()) {
      final pos = r['position'];
      if (pos is! Map || pos['lat'] is! num || pos['lon'] is! num) continue;
      final a = ((r['address'] as Map?) ?? const {}).cast<String, Object?>();
      final via = a['streetName'] as String?;
      final civico = a['streetNumber'] as String?;
      final viaCivico = [via, civico].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      final comune = (a['municipality'] as String?) ?? (a['localName'] as String?);
      final provincia = a['countrySecondarySubdivision'] as String?;
      final poi = r['poi'] as Map?;
      final String? nome;
      final List<String?> sotto;
      if (r['type'] == 'POI' && poi?['name'] is String) {
        nome = poi!['name'] as String;
        final categoria = ((poi['categories'] as List?) ?? const []).whereType<String>().firstOrNull;
        sotto = [
          if (categoria != null) _maiuscola(categoria),
          viaCivico.isEmpty ? null : viaCivico,
          comune,
        ];
      } else if (viaCivico.isNotEmpty) {
        nome = viaCivico;
        sotto = [comune, provincia];
      } else {
        nome = comune ?? (a['freeformAddress'] as String?);
        sotto = [provincia, a['countrySubdivision'] as String?];
      }
      if (nome == null || nome.isEmpty) continue;
      final descrizione = sotto.whereType<String>().where((s) => s.isNotEmpty && s != nome).toSet().join(', ');
      luoghi.add(Luogo(
        nome: nome,
        descrizione: descrizione,
        posizione: Punto((pos['lat'] as num).toDouble(), (pos['lon'] as num).toDouble()),
      ));
    }
    return luoghi;
  }

  static String _maiuscola(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Prima una fonte, poi l'altra se la prima non risponde o non trova niente.
///
/// TomTom ha un piano gratuito: se finisce, o la rete del momento non lo
/// raggiunge, la ricerca non deve restare muta. Photon fa da riserva.
class LuoghiConRiserva implements FonteLuoghi {
  const LuoghiConRiserva(this.prima, this.riserva);

  final FonteLuoghi prima;
  final FonteLuoghi riserva;

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    try {
      final trovati = await prima.cerca(testo, vicinoA: vicinoA);
      if (trovati.isNotEmpty) return trovati;
    } catch (_) {
      // Si prova con la riserva; se sbaglia anche quella, lo dice lei.
    }
    return riserva.cerca(testo, vicinoA: vicinoA);
  }
}
