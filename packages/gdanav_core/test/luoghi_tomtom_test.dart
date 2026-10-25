import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// Scritto sul formato documentato della Fuzzy Search di TomTom: da qui il
// servizio vero non si raggiunge.
const _risposta = {
  'results': [
    {
      'type': 'Point Address',
      'address': {
        'streetName': 'Via Roma',
        'streetNumber': '10',
        'municipality': 'Milano',
        'countrySecondarySubdivision': 'Milano',
        'countrySubdivision': 'Lombardia',
        'freeformAddress': 'Via Roma 10, 20121 Milano',
      },
      'position': {'lat': 45.4642, 'lon': 9.19},
    },
    {
      'type': 'POI',
      'poi': {
        'name': 'Farmacia Centrale',
        'categories': ['farmacia', 'salute'],
      },
      'address': {'streetName': 'Corso Buenos Aires', 'streetNumber': '3', 'municipality': 'Milano'},
      'position': {'lat': 45.47, 'lon': 9.2},
    },
    {
      'type': 'Street',
      'address': {'streetName': 'Via Garibaldi', 'municipality': 'Torino', 'countrySecondarySubdivision': 'Torino'},
      'position': {'lat': 45.07, 'lon': 7.68},
    },
    {
      'type': 'Geography',
      'address': {
        'municipality': 'Bologna',
        'countrySecondarySubdivision': 'Bologna',
        'countrySubdivision': 'Emilia-Romagna'
      },
      'position': {'lat': 44.49, 'lon': 11.34},
    },
    {
      'type': 'POI',
      'poi': {'name': 'Senza posizione'}
    },
  ],
};

class _Fonte implements FonteLuoghi {
  _Fonte(this.risposta);
  final Future<List<Luogo>> Function() risposta;
  var chiamate = 0;

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) {
    chiamate++;
    return risposta();
  }
}

void main() {
  test('il civico, l\'attività con la sua categoria, la via, la città', () {
    final l = ClienteTomTomLuoghi.leggi(_risposta);
    expect(l.map((x) => x.nome), ['Via Roma 10', 'Farmacia Centrale', 'Via Garibaldi', 'Bologna']);
    expect(l[0].descrizione, 'Milano');
    expect(l[0].posizione, const Punto(45.4642, 9.19));
    expect(l[1].descrizione, 'Farmacia, Corso Buenos Aires 3, Milano');
    expect(l[2].descrizione, 'Torino');
    expect(l[3].descrizione, 'Emilia-Romagna');
  });

  test('cerca in italiano, vicino alla posizione, e non per meno di tre lettere', () async {
    final chieste = <Uri>[];
    final client = MockClient((r) async {
      chieste.add(r.url);
      return http.Response(jsonEncode(_risposta), 200);
    });
    final t = ClienteTomTomLuoghi('chiave', client: client);
    expect(await t.cerca('vi'), isEmpty);
    expect(chieste, isEmpty);
    final l = await t.cerca(' via roma 10/b ', vicinoA: const Punto(45, 9));
    // Le due ricerche rispondono le stesse cose: una volta sola.
    expect(l, hasLength(4));
    expect(chieste, hasLength(2));
    final u = chieste.firstWhere((u) => u.path.startsWith('/search/2/search/'));
    expect(u.path, '/search/2/search/via%20roma%2010%20b.json');
    expect(u.queryParameters, {
      'key': 'chiave',
      'language': 'it-IT',
      'limit': '10',
      'typeahead': 'true',
      'lat': '45.0',
      'lon': '9.0',
    });
    // Accanto, la ricerca delle sole attivita' nei dintorni.
    final a = chieste.firstWhere((u) => u.path.startsWith('/search/2/poiSearch/'));
    expect(a.path, '/search/2/poiSearch/via%20roma%2010%20b.json');
    expect(a.queryParameters, {
      'key': 'chiave',
      'language': 'it-IT',
      'limit': '20',
      'lat': '45.0',
      'lon': '9.0',
      'radius': '50000',
    });
  });

  test("l'azienda che la ricerca «mentre scrivi» lascia fuori la trova la ricerca delle attivita'", () async {
    // La Fuzzy da' le vie che cominciano come il nome; l'azienda c'e' solo
    // fra le attivita'.
    final client = MockClient((r) async {
      if (r.url.path.startsWith('/search/2/poiSearch/')) {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'type': 'POI',
                'poi': {
                  'name': 'Officine Meccaniche Esposito Srl',
                  'categories': ['company'],
                },
                'address': {'streetName': 'Via Industriale', 'municipality': 'Caivano'},
                'position': {'lat': 40.95, 'lon': 14.30},
              },
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'results': [
            {
              'type': 'Street',
              'address': {'streetName': 'Via Officine', 'municipality': 'Napoli'},
              'position': {'lat': 40.85, 'lon': 14.27},
            },
          ],
        }),
        200,
      );
    });
    final l =
        await ClienteTomTomLuoghi('chiave', client: client).cerca('officine mecc', vicinoA: const Punto(40.9, 14.3));
    expect(l.map((x) => x.nome), ['Via Officine', 'Officine Meccaniche Esposito Srl']);
    expect(l.last.descrizione, 'Azienda, Via Industriale, Caivano');
  });

  test("se la ricerca delle attivita' non risponde resta l'altra; se non risponde la Fuzzy, si dice", () async {
    final soloFuzzy = MockClient((r) async => r.url.path.startsWith('/search/2/poiSearch/')
        ? http.Response('limite', 429)
        : http.Response(jsonEncode(_risposta), 200));
    expect(await ClienteTomTomLuoghi('chiave', client: soloFuzzy).cerca('via roma'), hasLength(4));
    final fuzzyRotta = MockClient((r) async => r.url.path.startsWith('/search/2/poiSearch/')
        ? http.Response(jsonEncode(_risposta), 200)
        : http.Response('limite', 429));
    expect(ClienteTomTomLuoghi('chiave', client: fuzzyRotta).cerca('via roma'), throwsException);
  });

  test('se TomTom non risponde, o non trova niente, cerca la riserva', () async {
    const qui = Luogo(nome: 'Via Roma 10', posizione: Punto(45, 9));
    final riserva = _Fonte(() async => [qui]);
    expect(await LuoghiConRiserva(_Fonte(() async => throw Exception('429')), riserva).cerca('via roma'), [qui]);
    expect(await LuoghiConRiserva(_Fonte(() async => const []), riserva).cerca('via roma'), [qui]);
    expect(riserva.chiamate, 2);

    final buona = _Fonte(() async => [qui]);
    final altra = _Fonte(() async => const []);
    expect(await LuoghiConRiserva(buona, altra).cerca('via roma'), [qui]);
    expect(altra.chiamate, 0);
  });

  test("le due fonti insieme: il locale che conosce solo l'altra, in testa se si chiama come si e' scritto", () async {
    // «nonna ma burger»: TomTom conosce la pizzeria, OpenStreetMap il burger.
    const pizzeria = Luogo(
      nome: 'Nonna Mà Pizzeria Trattoria',
      descrizione: 'Italian, Via Biancardi 47, Frattamaggiore',
      posizione: Punto(40.9410, 14.2740),
    );
    const burger = Luogo(nome: 'Nonna Mà Burger', descrizione: 'Frattamaggiore', posizione: Punto(40.9420, 14.2750));
    // La stessa pizzeria anche in OpenStreetMap: una volta sola.
    const pizzeriaOsm = Luogo(nome: 'Nonna Ma Pizzeria Trattoria', posizione: Punto(40.94105, 14.27405));
    final tomtom = _Fonte(() async => [pizzeria]);
    final osm = _Fonte(() async => [pizzeriaOsm, burger]);
    final trovati = await LuoghiInsieme(tomtom, osm).cerca('nonna ma burger');
    expect(trovati.map((l) => l.nome), ['Nonna Mà Burger', 'Nonna Mà Pizzeria Trattoria']);
    expect(tomtom.chiamate, 1);
    expect(osm.chiamate, 1);
  });

  test('le due fonti insieme: se una non risponde resta l\'altra, se nessuna risponde si dice', () async {
    const qui = Luogo(nome: 'Via Roma 10', posizione: Punto(45.46, 9.18));
    final rotta = _Fonte(() async => throw Exception('429'));
    expect(await LuoghiInsieme(rotta, _Fonte(() async => [qui])).cerca('via roma'), [qui]);
    expect(await LuoghiInsieme(_Fonte(() async => [qui]), rotta).cerca('via roma'), [qui]);
    expect(LuoghiInsieme(rotta, rotta).cerca('via roma'), throwsException);
  });

  test("l'ordine per nome: accenti e maiuscole a parte, anche a meta' parola, a parita' come arrivano", () {
    const a = Luogo(nome: 'Bar Centrale', posizione: Punto(0, 0));
    const b = Luogo(nome: "Pub L'Ancora", posizione: Punto(0, 0));
    const c = Luogo(nome: 'Ancora Pub & Grill', posizione: Punto(0, 0));
    expect(LuoghiInsieme.ordinatiPerNome([a, b, c], 'ancora pub').map((l) => l.nome), [
      "Pub L'Ancora",
      'Ancora Pub & Grill',
      'Bar Centrale',
    ]);
    expect(LuoghiInsieme.ordinatiPerNome([a, c], 'ANCO').first, c);
    expect(LuoghiInsieme.normalizzato('Nonna Mà  Burger!'), 'nonna ma burger');
  });

  test("la citta' scritta conta: «verdi servizi napoli» mette prima quelli di Napoli, poi i piu' vicini", () {
    const napoli = Punto(40.85, 14.27);
    const roma = Luogo(nome: 'Pb Servizi', descrizione: 'Ufficio, Roma', posizione: Punto(41.9, 12.5));
    const officina = Luogo(nome: 'Garage Verdi Mec', descrizione: 'Officina, Napoli', posizione: Punto(40.86, 14.28));
    const vicina =
        Luogo(nome: 'Garage Verdi Pit Stop', descrizione: 'Officina, Napoli', posizione: Punto(40.851, 14.271));
    const giusta = Luogo(nome: 'Verdi Servizi S.p.A.', descrizione: 'Azienda, Napoli', posizione: Punto(40.86, 14.29));
    expect(
      LuoghiInsieme.ordinatiPerNome([roma, officina, vicina, giusta], 'verdi servizi napoli', vicinoA: napoli)
          .map((l) => l.nome),
      ['Verdi Servizi S.p.A.', 'Garage Verdi Pit Stop', 'Garage Verdi Mec', 'Pb Servizi'],
    );
  });

  test('le categorie di TomTom in italiano', () {
    expect(ClienteTomTomLuoghi.categoriaInItaliano('General car repair servicing'), 'officina');
    expect(ClienteTomTomLuoghi.categoriaInItaliano('company'), 'azienda');
    expect(ClienteTomTomLuoghi.categoriaInItaliano('farmacia'), 'farmacia');
  });

  test("lontano piu' di 300 km resta solo chi si chiama come si e' scritto", () async {
    const napoli = Punto(40.85, 14.27);
    const cipro = Luogo(nome: 'Verdi Court', posizione: Punto(34.7, 33.0));
    const vicino = Luogo(nome: 'Garage Verdi Mec', descrizione: 'Officina, Napoli', posizione: Punto(40.86, 14.28));
    const giusto = Luogo(nome: 'Verdi Servizi', descrizione: 'Azienda, Roma', posizione: Punto(41.9, 12.5));
    const lontanoGiusto = Luogo(nome: 'Verdi Servizi Milano', posizione: Punto(45.46, 9.18));
    final l = await LuoghiInsieme(
      _Fonte(() async => [cipro, vicino]),
      _Fonte(() async => [giusto, lontanoGiusto]),
    ).cerca('verdi servizi', vicinoA: napoli);
    expect(l.map((x) => x.nome), ['Verdi Servizi', 'Verdi Servizi Milano', 'Garage Verdi Mec']);
  });

  test('la forma della societa\' non si cerca', () {
    expect(LuoghiInsieme.senzaSigla('Verdi Servizi S.p.A.'), 'Verdi Servizi');
    expect(LuoghiInsieme.senzaSigla('rossi srl'), 'rossi');
    expect(LuoghiInsieme.senzaSigla('Bianchi & C. s.n.c.'), 'Bianchi & C.');
    expect(LuoghiInsieme.senzaSigla('Spaccanapoli'), 'Spaccanapoli');
    expect(LuoghiInsieme.senzaSigla('spa'), 'spa');
    expect(LuoghiInsieme.senzaSigla('verdi servizi spa napoli'), 'verdi servizi napoli');
    expect(LuoghiInsieme.senzaSigla('Verdi S.p.A., Napoli'), 'Verdi Napoli');
    expect(LuoghiInsieme.senzaSigla('terme spa napoli'), 'terme spa napoli');
  });
}
