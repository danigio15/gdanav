import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// Scritto sul formato documentato di Overpass (`out center tags`): da qui il
// servizio vero non si raggiunge.
Map<String, Object?> _pub(int id, String? nome, double lat, double lon, {bool via = false}) => {
      'type': via ? 'way' : 'node',
      'id': id,
      if (via) 'center': {'lat': lat, 'lon': lon} else ...{'lat': lat, 'lon': lon},
      'tags': {
        'amenity': 'pub',
        if (nome != null) 'name': nome,
        if (nome == 'The Dubliner') ...{'addr:street': 'Via Roma', 'addr:housenumber': '12', 'addr:city': 'Napoli'},
      },
    };

const _qui = Punto(40.8400, 14.2500);

class _Fonte implements FonteLuoghi {
  _Fonte(this.risposta);
  final List<Luogo> risposta;
  var chiamate = 0;

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    chiamate++;
    return risposta;
  }
}

void main() {
  test('una categoria si riconosce, un nome che la contiene no', () {
    expect(categoriaDi('pub')?.etichetta, 'Pub');
    expect(categoriaDi('  Pub ')?.etichetta, 'Pub');
    expect(categoriaDi('i pub vicino')?.etichetta, 'Pub');
    expect(categoriaDi('Farmacie')?.etichetta, 'Farmacia');
    expect(categoriaDi('aziende')?.etichetta, 'Azienda');
    expect(categoriaDi('caffè')?.etichetta, 'Bar');
    expect(categoriaDi('pronto soccorso')?.etichetta, 'Ospedale');
    expect(categoriaDi('Pub Irlandese Dublino'), isNull);
    expect(categoriaDi('via roma'), isNull);
  });

  test('la richiesta: tutti i filtri della categoria, nel raggio, coi centri degli edifici', () {
    final q = LuoghiPerCategoria.richiesta(categorieConosciute['birreria']!, _qui, 10000);
    expect(q, startsWith('[out:json]'));
    expect(q, contains('nwr["amenity"="pub"](around:10000,40.84000,14.25000);'));
    expect(q, contains('nwr["amenity"="biergarten"](around:10000,40.84000,14.25000);'));
    expect(q, contains('nwr["craft"="brewery"](around:10000,40.84000,14.25000);'));
    expect(q, endsWith('out center tags;'));
  });

  test('tutti i pub dei dintorni, in ordine di distanza, senza quelli senza nome e senza doppi', () async {
    final chieste = <String>[];
    final client = MockClient((r) async {
      chieste.add(r.bodyFields['data']!);
      return http.Response(
        jsonEncode({
          'elements': [
            _pub(1, 'Lontano Pub', 40.90, 14.30),
            _pub(2, 'The Dubliner', 40.8410, 14.2510),
            _pub(3, null, 40.8401, 14.2501),
            _pub(4, 'Birrificio di Quartiere', 40.85, 14.26, via: true),
            // Lo stesso pub mappato come punto e come edificio.
            _pub(5, 'The Dubliner', 40.84102, 14.25101, via: true),
          ],
        }),
        200,
      );
    });
    final l = await LuoghiPerCategoria(client: client).cerca('pub', vicinoA: _qui);
    expect(l.map((x) => x.nome), ['The Dubliner', 'Birrificio di Quartiere', 'Lontano Pub']);
    expect(l.first.descrizione, 'Pub, Via Roma 12, Napoli');
    expect(l[1].descrizione, 'Pub');
    expect(chieste.single, contains('nwr["amenity"="pub"](around:10000'));
  });

  test('senza categoria o senza posizione non si chiede niente', () async {
    var chiamate = 0;
    final client = MockClient((r) async {
      chiamate++;
      return http.Response('{"elements":[]}', 200);
    });
    final f = LuoghiPerCategoria(client: client);
    expect(await f.cerca('the dubliner', vicinoA: _qui), isEmpty);
    expect(await f.cerca('pub'), isEmpty);
    expect(chiamate, 0);
  });

  test('se un server sbaglia si chiede al prossimo; se sbagliano tutti si dice', () async {
    var n = 0;
    final client = MockClient((r) async {
      n++;
      if (r.url.host == 'overpass-api.de') return http.Response('occupato', 429);
      return http.Response(
          jsonEncode({
            'elements': [_pub(1, 'Il Pub', 40.84, 14.25)]
          }),
          200);
    });
    expect((await LuoghiPerCategoria(client: client).cerca('pub', vicinoA: _qui)).single.nome, 'Il Pub');
    expect(n, 2);
    final rotto = MockClient((r) async => http.Response('no', 500));
    expect(LuoghiPerCategoria(client: rotto).cerca('pub', vicinoA: _qui), throwsException);
  });

  test("cercando una categoria: tutte le fonti, la lista lunga e in ordine di distanza", () async {
    // TomTom e Photon danno qualche pub e un posto che ha «pub» nel nome;
    // OpenStreetMap li da' tutti.
    const vicino = Luogo(nome: 'The Dubliner', posizione: Punto(40.8410, 14.2510));
    const medio = Luogo(nome: 'Birrificio di Quartiere', posizione: Punto(40.85, 14.26));
    const lontano = Luogo(nome: 'Pub Street', posizione: Punto(40.95, 14.40));
    final pub = [for (var i = 0; i < 30; i++) Luogo(nome: 'Pub $i', posizione: Punto(40.86 + i / 1000, 14.27))];
    final tomtom = _Fonte([lontano]);
    final photon = _Fonte([const Luogo(nome: 'the dubliner', posizione: Punto(40.84101, 14.25101))]);
    final osm = _Fonte([vicino, medio, ...pub]);
    final trovati = await LuoghiInsieme(tomtom, photon, categorie: osm).cerca('pub', vicinoA: _qui);
    expect(trovati.length, 33);
    expect(trovati.take(2).map((l) => l.nome), ['The Dubliner', 'Birrificio di Quartiere']);
    expect(trovati.last.nome, 'Pub Street');
    expect(osm.chiamate, 1);

    // Un nome non e' una categoria: la fonte delle categorie non si chiede.
    await LuoghiInsieme(tomtom, photon, categorie: osm).cerca('the dubliner', vicinoA: _qui);
    expect(osm.chiamate, 1);
  });

  test('senza TomTom (nessuna chiave) le categorie e OpenStreetMap restano', () async {
    const vicino = Luogo(nome: 'Farmacia Centrale', posizione: Punto(40.8410, 14.2510));
    final trovati = await LuoghiInsieme(const NessunLuogo(), _Fonte(const []), categorie: _Fonte([vicino]))
        .cerca('farmacia', vicinoA: _qui);
    expect(trovati, [vicino]);
  });
}
