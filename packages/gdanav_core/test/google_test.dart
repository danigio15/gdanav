import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

class _Fonte implements FonteLuoghi {
  final chiesti = <String>[];
  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    chiesti.add(testo);
    if (testo.contains('Nessuno')) return const [];
    return [Luogo(nome: testo, descrizione: 'Roma RM', posizione: const Punto(41.9, 12.5))];
  }
}

void main() {
  test('il GeoJSON di «Maps (i tuoi luoghi)»: nuovo e vecchio formato, [0,0] vuol dire «non so»', () {
    final testo = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'geometry': {
            'coordinates': [12.4922, 41.8902],
            'type': 'Point',
          },
          'properties': {
            'date': '2023-05-01T10:00:00Z',
            'google_maps_url': 'http://maps.google.com/?cid=123',
            'location': {'address': 'Piazza del Colosseo, 1, Roma', 'country_code': 'IT', 'name': 'Colosseo'},
          },
          'type': 'Feature',
        },
        {
          'geometry': {
            'coordinates': [0, 0],
            'type': 'Point',
          },
          'properties': {
            'google_maps_url': 'https://www.google.com/maps/search/45.4642,9.19',
            'location': {'name': 'Duomo di Milano'},
          },
          'type': 'Feature',
        },
        {
          'geometry': {
            'coordinates': [11.25, 43.77],
            'type': 'Point',
          },
          'properties': {
            'Title': 'Ponte Vecchio',
            'Location': {'Address': 'Firenze FI', 'Business Name': 'Ponte Vecchio'},
          },
          'type': 'Feature',
        },
      ],
    });
    final posti = ImportaGoogle.leggi('﻿$testo', nomeFile: 'Takeout/Maps (i tuoi luoghi)/Luoghi salvati.json');
    expect(posti, hasLength(3));
    expect(posti[0].nome, 'Colosseo');
    expect(posti[0].indirizzo, 'Piazza del Colosseo, 1, Roma');
    expect(posti[0].posizione, const Punto(41.8902, 12.4922));
    expect(posti[0].lista, 'Luoghi salvati');
    expect(posti[1].posizione, const Punto(45.4642, 9.19));
    expect(posti[2].nome, 'Ponte Vecchio');
    expect(posti[2].indirizzo, 'Firenze FI');
  });

  test('gli elenchi CSV di «Salvati»: virgolette, righe vuote, coordinate nel link', () {
    const testo = 'Title,Note,URL,Tags,Comment\r\n'
        ',,,,\r\n'
        '"Trattoria da Mario, Firenze","la ribollita ""buona""",https://www.google.com/maps/place/Trattoria+da+Mario/data=!4m2!3m1!1s0x0:0x1,,\r\n'
        'Spiaggia,,https://www.google.com/maps/place/Spiaggia/@40.63,14.60,17z/data=!3d40.6301!4d14.6021,,\r\n'
        ',,https://www.google.com/maps/place/Castel+dell%27Ovo/data=!4m2,,\r\n';
    final posti = ImportaGoogle.leggi(testo, nomeFile: 'Voglio andarci.csv');
    expect(posti, hasLength(3));
    expect(posti[0].nome, 'Trattoria da Mario, Firenze');
    expect(posti[0].nota, 'la ribollita "buona"');
    expect(posti[0].posizione, isNull);
    expect(posti[0].lista, 'Voglio andarci');
    expect(posti[1].posizione, const Punto(40.6301, 14.6021));
    expect(posti[2].nome, "Castel dell'Ovo");
  });

  test('le intestazioni in italiano vanno bene', () {
    final posti = ImportaGoogle.csv('Titolo,Nota,URL\nPizzeria,,https://maps.google.com/?q=40.85,14.26\n');
    expect(posti.single.posizione, const Punto(40.85, 14.26));
  });

  test('i posti senza coordinate si cercano per nome; quelli non trovati si dicono', () async {
    final fonte = _Fonte();
    final r = await ImportaGoogle.risolvi(const [
      LuogoGoogle(nome: 'Colosseo', posizione: Punto(41.89, 12.49)),
      LuogoGoogle(nome: 'Trattoria'),
      LuogoGoogle(nome: 'Nessuno sa'),
    ], fonte);
    expect(fonte.chiesti, ['Trattoria', 'Nessuno sa']);
    expect(r.trovati.map((t) => t.$2.nome), ['Colosseo', 'Trattoria']);
    expect(r.trovati.last.$2.posizione, const Punto(41.9, 12.5));
    expect(r.mancanti.single.nome, 'Nessuno sa');
  });
}
