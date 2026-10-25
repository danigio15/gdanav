import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import 'luoghi.dart';
import 'luoghi_tomtom.dart';

/// Un tipo di posto che si cerca per quello che e', non per come si chiama:
/// «pub», «farmacia», «aziende».
class Categoria {
  const Categoria(this.etichetta, this.filtri);

  /// Come si scrive sotto il nome: «Pub», «Farmacia».
  final String etichetta;

  /// I filtri di OpenStreetMap, uno o piu': `["amenity"="pub"]`.
  final List<String> filtri;
}

/// Le parole che vogliono dire una categoria, in italiano e in inglese,
/// gia' senza accenti e in minuscolo (vedi [LuoghiInsieme.normalizzato]).
const Map<String, Categoria> categorieConosciute = {
  'pub': Categoria('Pub', ['["amenity"="pub"]']),
  'pubs': Categoria('Pub', ['["amenity"="pub"]']),
  'birreria': Categoria('Birreria', ['["amenity"="pub"]', '["amenity"="biergarten"]', '["craft"="brewery"]']),
  'birrerie': Categoria('Birreria', ['["amenity"="pub"]', '["amenity"="biergarten"]', '["craft"="brewery"]']),
  'bar': Categoria('Bar', ['["amenity"="bar"]', '["amenity"="cafe"]']),
  'caffe': Categoria('Bar', ['["amenity"="cafe"]']),
  'cafe': Categoria('Bar', ['["amenity"="cafe"]']),
  'ristorante': Categoria('Ristorante', ['["amenity"="restaurant"]']),
  'ristoranti': Categoria('Ristorante', ['["amenity"="restaurant"]']),
  'restaurant': Categoria('Ristorante', ['["amenity"="restaurant"]']),
  'trattoria': Categoria('Ristorante', ['["amenity"="restaurant"]']),
  'pizzeria': Categoria(
      'Pizzeria', ['["amenity"="restaurant"]["cuisine"~"pizza"]', '["amenity"="fast_food"]["cuisine"~"pizza"]']),
  'pizzerie': Categoria(
      'Pizzeria', ['["amenity"="restaurant"]["cuisine"~"pizza"]', '["amenity"="fast_food"]["cuisine"~"pizza"]']),
  'pizza': Categoria(
      'Pizzeria', ['["amenity"="restaurant"]["cuisine"~"pizza"]', '["amenity"="fast_food"]["cuisine"~"pizza"]']),
  'paninoteca': Categoria('Paninoteca', ['["amenity"="fast_food"]']),
  'fast food': Categoria('Fast food', ['["amenity"="fast_food"]']),
  'hamburger': Categoria('Hamburgeria', ['["cuisine"~"burger"]']),
  'hamburgeria': Categoria('Hamburgeria', ['["cuisine"~"burger"]']),
  'sushi': Categoria('Sushi', ['["cuisine"~"sushi"]']),
  'gelateria': Categoria('Gelateria', ['["amenity"="ice_cream"]', '["shop"="ice_cream"]']),
  'gelato': Categoria('Gelateria', ['["amenity"="ice_cream"]', '["shop"="ice_cream"]']),
  'pasticceria': Categoria('Pasticceria', ['["shop"="pastry"]', '["shop"="confectionery"]']),
  'panetteria': Categoria('Panetteria', ['["shop"="bakery"]']),
  'forno': Categoria('Panetteria', ['["shop"="bakery"]']),
  'discoteca': Categoria('Discoteca', ['["amenity"="nightclub"]']),
  'disco': Categoria('Discoteca', ['["amenity"="nightclub"]']),
  'farmacia': Categoria('Farmacia', ['["amenity"="pharmacy"]']),
  'farmacie': Categoria('Farmacia', ['["amenity"="pharmacy"]']),
  'ospedale': Categoria('Ospedale', ['["amenity"="hospital"]']),
  'pronto soccorso': Categoria('Ospedale', ['["amenity"="hospital"]["emergency"="yes"]']),
  'supermercato': Categoria('Supermercato', ['["shop"="supermarket"]']),
  'supermercati': Categoria('Supermercato', ['["shop"="supermarket"]']),
  'supermarket': Categoria('Supermercato', ['["shop"="supermarket"]']),
  'benzinaio': Categoria('Distributore', ['["amenity"="fuel"]']),
  'distributore': Categoria('Distributore', ['["amenity"="fuel"]']),
  'parcheggio': Categoria('Parcheggio', ['["amenity"="parking"]']),
  'albergo': Categoria('Albergo', ['["tourism"="hotel"]']),
  'hotel': Categoria('Albergo', ['["tourism"="hotel"]']),
  'banca': Categoria('Banca', ['["amenity"="bank"]']),
  'bancomat': Categoria('Bancomat', ['["amenity"="atm"]']),
  'tabaccheria': Categoria('Tabaccheria', ['["shop"="tobacco"]']),
  'tabacchi': Categoria('Tabaccheria', ['["shop"="tobacco"]']),
  'meccanico': Categoria('Officina', ['["shop"="car_repair"]']),
  'officina': Categoria('Officina', ['["shop"="car_repair"]']),
  'gommista': Categoria('Gommista', ['["shop"="tyres"]']),
  'autolavaggio': Categoria('Autolavaggio', ['["amenity"="car_wash"]']),
  'azienda': Categoria(
      'Azienda', ['["office"="company"]', '["office"]["name"]', '["craft"]["name"]', '["industrial"]["name"]']),
  'aziende': Categoria(
      'Azienda', ['["office"="company"]', '["office"]["name"]', '["craft"]["name"]', '["industrial"]["name"]']),
  'ditta': Categoria(
      'Azienda', ['["office"="company"]', '["office"]["name"]', '["craft"]["name"]', '["industrial"]["name"]']),
  'ditte': Categoria(
      'Azienda', ['["office"="company"]', '["office"]["name"]', '["craft"]["name"]', '["industrial"]["name"]']),
  'fabbrica': Categoria('Azienda', ['["industrial"]["name"]', '["man_made"="works"]']),
  'ufficio': Categoria('Ufficio', ['["office"]["name"]']),
  'uffici': Categoria('Ufficio', ['["office"]["name"]']),
};

/// La categoria detta dal testo, se il testo e' solo quella: «pub», «Pub»,
/// «i pub», «pub vicino». Un nome che contiene la parola («Pub Irlandese
/// Dublino») non lo e': chi scrive un nome cerca quel posto.
Categoria? categoriaDi(String testo) {
  var t = LuoghiInsieme.normalizzato(testo);
  for (final via in ['vicino a me', 'vicino', 'qui', 'aperti', 'aperto', 'nei dintorni']) {
    if (t.endsWith(' $via')) t = t.substring(0, t.length - via.length - 1).trim();
  }
  for (final articolo in ['i ', 'il ', 'la ', 'le ', 'lo ', 'gli ', 'un ', 'una ', 'the ']) {
    if (t.startsWith(articolo)) t = t.substring(articolo.length);
  }
  return categorieConosciute[t.trim()];
}

/// I posti di una categoria nei dintorni, da OpenStreetMap attraverso
/// Overpass: tutti, non i dieci che un motore di ricerca sceglie.
///
/// «I pub non sono completi»: TomTom e Photon rispondono a un testo con una
/// decina di risultati scelti per pertinenza, e «pub» dava qualche pub e
/// qualche posto che aveva «pub» nel nome. Qui si chiedono i posti che sono
/// pub — `amenity=pub` — nel raggio, e si mettono in ordine di distanza.
/// Senza posizione non c'e' un «vicino», e non si chiede niente.
class LuoghiPerCategoria implements FonteLuoghi {
  LuoghiPerCategoria({
    http.Client? client,
    List<Uri>? server,
    this.raggioM = 10000,
    this.quanti = 60,
    this.attesa = const Duration(seconds: 8),
  })  : _http = client ?? http.Client(),
        server = server ??
            [
              Uri.parse('https://overpass-api.de/api/interpreter'),
              Uri.parse('https://overpass.private.coffee/api/interpreter'),
              Uri.parse('https://overpass.kumi.systems/api/interpreter'),
            ];

  final List<Uri> server;
  final int raggioM;
  final int quanti;

  /// La ricerca e' «mentre scrivi»: un server lento non deve tenere ferma
  /// la lista. Passato questo tempo si rinuncia, e restano le altre fonti.
  final Duration attesa;
  final http.Client _http;

  /// La richiesta Overpass per una categoria intorno a un punto.
  static String richiesta(Categoria c, Punto centro, int raggioM) {
    final intorno = '(around:$raggioM,${centro.lat.toStringAsFixed(5)},${centro.lon.toStringAsFixed(5)})';
    final corpo = [for (final f in c.filtri) 'nwr$f$intorno;'].join();
    return '[out:json][timeout:15];($corpo);out center tags;';
  }

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    final categoria = categoriaDi(testo);
    if (categoria == null || vicinoA == null) return const [];
    final corpo = {'data': richiesta(categoria, vicinoA, raggioM)};
    Object? ultimo;
    for (final s in server) {
      try {
        final r = await _http
            .post(s, body: corpo, headers: {'user-agent': 'gdanav (github.com/danigio15/gdanav)'}).timeout(attesa);
        if (r.statusCode != 200) throw Exception('Overpass: ${r.statusCode}');
        final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;
        final avviso = json['remark'];
        if (avviso is String && avviso.contains('error')) throw Exception('Overpass: $avviso');
        return leggi(json, categoria, vicinoA).take(quanti).toList();
      } on TimeoutException catch (e) {
        // Un server lento: non se ne prova un altro, la lista aspetterebbe
        // il doppio. Rispondono le altre fonti.
        ultimo = e;
        break;
      } catch (e) {
        ultimo = e;
      }
    }
    throw Exception('luoghi per categoria: $ultimo');
  }

  /// I posti con un nome, in ordine di distanza da [centro].
  static List<Luogo> leggi(Map<String, Object?> json, Categoria categoria, Punto centro) {
    final luoghi = <Luogo>[];
    final visti = <String>{};
    for (final e in ((json['elements'] as List?) ?? const []).whereType<Map>()) {
      final tag = ((e['tags'] as Map?) ?? const {}).cast<String, Object?>();
      final nome = (tag['name'] ?? tag['brand']) as String?;
      if (nome == null || nome.trim().isEmpty) continue;
      final c = (e['center'] as Map?)?.cast<String, Object?>();
      final lat = ((e['lat'] ?? c?['lat']) as num?)?.toDouble();
      final lon = ((e['lon'] ?? c?['lon']) as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      // Lo stesso posto mappato due volte (il punto e l'edificio).
      final chiave = '${LuoghiInsieme.normalizzato(nome)}@${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
      if (!visti.add(chiave)) continue;
      final via = [tag['addr:street'], tag['addr:housenumber']].whereType<String>().join(' ');
      final comune = (tag['addr:city'] ?? tag['addr:place']) as String?;
      luoghi.add(Luogo(
        nome: nome.trim(),
        descrizione: [categoria.etichetta, if (via.isNotEmpty) via, if (comune != null) comune].join(', '),
        posizione: Punto(lat, lon),
      ));
    }
    luoghi.sort((a, b) => distanzaM(centro, a.posizione).compareTo(distanzaM(centro, b.posizione)));
    return luoghi;
  }
}
