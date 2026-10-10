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
    expect(l, hasLength(4));
    final u = chieste.single;
    expect(u.path, '/search/2/search/via%20roma%2010%20b.json');
    expect(u.queryParameters, {
      'key': 'chiave',
      'language': 'it-IT',
      'limit': '10',
      'typeahead': 'true',
      'lat': '45.0',
      'lon': '9.0',
    });
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
}
