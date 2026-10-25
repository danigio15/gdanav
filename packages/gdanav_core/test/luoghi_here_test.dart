import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Una risposta di HERE Discover, ridotta a quello che si legge.
const _risposta = {
  'items': [
    {
      'title': 'Romeo Gestioni S.p.A.',
      'resultType': 'place',
      'position': {'lat': 40.8605, 'lng': 14.2847},
      'address': {
        'label': 'Romeo Gestioni S.p.A., Napoli',
        'street': 'Centro Direzionale Isola',
        'houseNumber': 'F4',
        'city': 'Napoli'
      },
      'categories': [
        {'id': '700-7400-0000', 'name': 'Servizi alle imprese', 'primary': true},
      ],
    },
    {'title': 'Senza posizione'},
    {
      'title': 'Via Toledo',
      'resultType': 'street',
      'position': {'lat': 40.84, 'lng': 14.25},
      'address': {'city': 'Napoli'},
    },
  ],
};

void main() {
  test('HERE: il nome, la categoria principale, la via col civico e la citta\'', () {
    final l = ClienteHereLuoghi.leggi(_risposta);
    expect(l, hasLength(2));
    expect(l.first.nome, 'Romeo Gestioni S.p.A.');
    expect(l.first.descrizione, 'Servizi alle imprese, Centro Direzionale Isola F4, Napoli');
    expect(l.first.posizione.lat, 40.8605);
    expect(l.last.descrizione, 'Napoli');
  });

  test('HERE: vicino a chi cerca, in italiano; senza posizione in Italia; mai per meno di tre lettere', () async {
    final chieste = <Uri>[];
    final client = MockClient((r) async {
      chieste.add(r.url);
      return http.Response(jsonEncode(_risposta), 200);
    });
    final here = ClienteHereLuoghi('k', client: client);
    expect(await here.cerca('ro'), isEmpty);
    await here.cerca(' romeo gestioni ', vicinoA: const Punto(40.85, 14.27));
    await here.cerca('romeo gestioni');
    expect(chieste, hasLength(2));
    expect(chieste.first.queryParameters, {
      'q': 'romeo gestioni',
      'at': '40.85,14.27',
      'lang': 'it-IT',
      'limit': '15',
      'apiKey': 'k',
    });
    expect(chieste.last.queryParameters['in'], 'countryCode:ITA');
    expect(
      ClienteHereLuoghi('k', client: MockClient((_) async => http.Response('', 401))).cerca('romeo'),
      throwsException,
    );
  });

  test('HERE insieme alle altre: l\'azienda che conosce solo lei arriva in cima', () async {
    final here = ClienteHereLuoghi('k', client: MockClient((_) async => http.Response(jsonEncode(_risposta), 200)));
    const officina = Luogo(nome: 'Alfa Romeo Mec', descrizione: 'Officina, Napoli', posizione: Punto(40.86, 14.28));
    final l = await LuoghiInsieme(
      _Fonte(() async => [officina]),
      _Fonte(() async => throw Exception('400')),
      altre: [here],
    ).cerca('romeo gestioni napoli', vicinoA: const Punto(40.85, 14.27));
    expect(l.first.nome, 'Romeo Gestioni S.p.A.');
    expect(l.map((x) => x.nome), contains('Alfa Romeo Mec'));
  });
}

class _Fonte implements FonteLuoghi {
  _Fonte(this._risposta);
  final Future<List<Luogo>> Function() _risposta;
  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) => _risposta();
}
