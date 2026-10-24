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

/// Tutte e due le fonti insieme, e prima quello che si chiama come si e'
/// scritto.
///
/// «Esiste come locale ma non lo trovi»: «nonna ma burger» dava solo la
/// pizzeria con lo stesso nome davanti. TomTom e OpenStreetMap conoscono
/// locali diversi — un pub aperto da poco, un ristorante che solo uno dei due
/// ha — e usarne uno e tenere l'altro di riserva voleva dire perdere quelli
/// dell'altro. Adesso si chiedono insieme: i risultati si mettono uno dopo
/// l'altro, quelli doppi (stesso nome, a meno di 150 m) una volta sola, e in
/// testa vanno quelli col nome che contiene tutte le parole scritte, accenti
/// e maiuscole a parte. Se una fonte non risponde, resta l'altra.
class LuoghiInsieme implements FonteLuoghi {
  const LuoghiInsieme(this.prima, this.seconda, {this.quanti = 12});

  final FonteLuoghi prima;
  final FonteLuoghi seconda;
  final int quanti;

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    Future<List<Luogo>?> da(FonteLuoghi f) async {
      try {
        return await f.cerca(testo, vicinoA: vicinoA);
      } catch (_) {
        return null;
      }
    }

    final risposte = await Future.wait([da(prima), da(seconda)]);
    if (risposte.every((r) => r == null)) {
      // Nessuna delle due ha risposto: lo dice la seconda, col suo errore.
      return seconda.cerca(testo, vicinoA: vicinoA);
    }
    final tutti = <Luogo>[];
    for (final l in [...?risposte[0], ...?risposte[1]]) {
      final doppio =
          tutti.any((g) => normalizzato(g.nome) == normalizzato(l.nome) && distanzaM(g.posizione, l.posizione) < 150);
      if (!doppio) tutti.add(l);
    }
    return ordinatiPerNome(tutti, testo).take(quanti).toList();
  }

  /// Minuscole, senza accenti e senza segni: «Nonna Mà» e «nonna ma» sono la
  /// stessa cosa.
  static String normalizzato(String s) {
    const accenti = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n'
    };
    final minuscolo = s.toLowerCase();
    final b = StringBuffer();
    for (final c in minuscolo.split('')) {
      b.write(accenti[c] ?? c);
    }
    return b.toString().replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();
  }

  /// I luoghi in ordine di quante parole scritte hanno nel nome (contano
  /// anche quelle a meta': «burg» vale «burger»); a parita', l'ordine delle
  /// fonti, che sanno gia' cosa e' vicino.
  static List<Luogo> ordinatiPerNome(List<Luogo> luoghi, String testo) {
    final parole = normalizzato(testo).split(' ').where((p) => p.length >= 2).toList();
    if (parole.isEmpty) return luoghi;
    int punti(Luogo l) {
      final nome = normalizzato(l.nome).split(' ');
      final trovate = parole.where((p) => nome.any((n) => n.startsWith(p))).length;
      return trovate == parole.length ? trovate + 100 : trovate;
    }

    final conPunti = [for (var i = 0; i < luoghi.length; i++) (i, punti(luoghi[i]), luoghi[i])];
    conPunti.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
    return [for (final c in conPunti) c.$3];
  }
}
