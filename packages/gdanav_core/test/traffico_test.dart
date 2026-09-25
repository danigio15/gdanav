import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Una strada dritta verso nord: un punto ogni ~1 km, a 120 km/h.
PercorsoCalcolato dritta(int km, {double kmh = 120}) {
  final punti = [for (var i = 0; i <= km; i++) Punto(42 + i * 0.009, 12)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: kmh),
    ],
    manovre: const [],
  );
}

void main() {
  test('una coda allunga il viaggio del suo ritardo, solo dove sta', () {
    final p = dritta(100);
    final linea = Linea(p.punti);
    final coda = Coda(daM: linea.cumulate[40], aM: linea.cumulate[50], ritardo: const Duration(minutes: 10));
    final t = p.conTraffico([coda]);
    expect(t.trafficoVero, isTrue);
    expect(t.ritardoTraffico, const Duration(minutes: 10));
    expect((t.durata - p.durata).inSeconds, closeTo(600, 30));
    // Fuori dalla coda si va come prima.
    expect(t.tratti[10].velocitaKmh, 120);
    expect(t.tratti[45].velocitaKmh, lessThan(60));
  });

  test('la velocità detta da TomTom vale dentro la coda', () {
    final p = dritta(20);
    final linea = Linea(p.punti);
    final t = p.conTraffico([
      Coda(daM: linea.cumulate[5], aM: linea.cumulate[10], ritardo: Duration.zero, velocitaKmh: 20),
    ]);
    expect(t.tratti[7].velocitaKmh, 20);
  });

  test('le sezioni TRAFFIC di TomTom diventano code sui metri del nostro percorso', () {
    final p = dritta(50);
    final json = {
      'routes': [
        {
          'legs': [
            {
              'points': [
                for (var i = 0; i <= 100; i++) {'latitude': 42 + i * 0.0045, 'longitude': 12.0001},
              ],
            },
          ],
          'sections': [
            {'sectionType': 'TRAVEL_MODE', 'startPointIndex': 0, 'endPointIndex': 100},
            // Chiusa per TomTom, ma ci si passa a 86 km/h senza perdere tempo:
            // non si colora.
            {
              'sectionType': 'TRAFFIC',
              'startPointIndex': 40,
              'endPointIndex': 45,
              'simpleCategory': 'ROAD_CLOSURE',
              'magnitudeOfDelay': 4,
              'delayInSeconds': 0,
              'effectiveSpeedInKmh': 86,
            },
            {
              'sectionType': 'TRAFFIC',
              'startPointIndex': 20,
              'endPointIndex': 30,
              'simpleCategory': 'JAM',
              'magnitudeOfDelay': 3,
              'delayInSeconds': 420,
              'effectiveSpeedInKmh': 18,
            },
            {
              'sectionType': 'TRAFFIC',
              'startPointIndex': 60,
              'endPointIndex': 62,
              'simpleCategory': 'ROAD_WORK',
              'magnitudeOfDelay': 1,
              'delayInSeconds': 60,
            },
            {
              'sectionType': 'TRAFFIC',
              'startPointIndex': 80,
              'endPointIndex': 84,
              'simpleCategory': 'ROAD_CLOSURE',
              'magnitudeOfDelay': 4,
              'delayInSeconds': 900,
              'effectiveSpeedInKmh': 0,
            },
          ],
        },
      ],
    };
    final code = TrafficoTomTom.codeDa(json, p.punti);
    expect(code, hasLength(3));
    expect(code.first.daM, closeTo(10000, 200));
    expect(code.first.aM, closeTo(15000, 200));
    expect(code.first.livello, 3);
    expect(code.first.ritardo, const Duration(minutes: 7));
    expect(code[1].tipo, 'Lavori');
    expect(code.last.tipo, 'Strada chiusa');
    expect(code.last.livello, 4);
  });

  test('TomTom riceve i punti del percorso e il ritardo entra nel viaggio', () async {
    Map<String, Object?>? corpo;
    Uri? chiesto;
    final t = TrafficoTomTom(
      'chiave',
      client: MockClient((r) async {
        chiesto = r.url;
        corpo = jsonDecode(r.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'routes': [
              {
                'legs': [
                  {
                    'points': [
                      for (var i = 0; i <= 10; i++) {'latitude': 42 + i * 0.009, 'longitude': 12},
                    ],
                  },
                ],
                'sections': [
                  {
                    'sectionType': 'TRAFFIC',
                    'startPointIndex': 2,
                    'endPointIndex': 4,
                    'simpleCategory': 'JAM',
                    'magnitudeOfDelay': 2,
                    'delayInSeconds': 300,
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    );
    final p = await t.applica(dritta(10));
    expect(chiesto!.queryParameters['traffic'], 'true');
    expect(chiesto!.queryParameters['sectionType'], 'traffic');
    expect((corpo!['supportingPoints'] as List), hasLength(11));
    expect(p.code, hasLength(1));
    expect(p.ritardoTraffico, const Duration(minutes: 5));
  });

  group('alternative e passaggi', () {
    Map<String, Object?> trip(double lat) => {
          'summary': {'has_toll': lat > 45.05},
          'legs': [
            {
              'shape': codificaPolyline([const Punto(45, 9), Punto(lat, 9.01), const Punto(45.1, 9)], precisione: 6),
              'maneuvers': [
                {
                  'instruction': 'Parti',
                  'length': 12.0,
                  'time': 600,
                  'begin_shape_index': 0,
                  'end_shape_index': 2,
                  'street_names': ['A${(lat * 100).round() % 10}'],
                },
              ],
            },
          ],
        };

    test('Valhalla dà il migliore e le alternative, coi pedaggi e la strada', () async {
      Map<String, Object?>? corpo;
      final v = ClienteValhalla(
        Uri.parse('http://x/'),
        client: MockClient((r) async {
          corpo = jsonDecode(r.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode({
              'trip': trip(45.05),
              'alternates': [
                {'trip': trip(45.06)},
              ],
            }),
            200,
          );
        }),
      );
      final scelte = await v.alternative(const Punto(45, 9), const Punto(45.1, 9));
      expect(corpo!['alternates'], 2);
      expect(scelte, hasLength(2));
      expect(scelte.first.conPedaggi, isFalse);
      expect(scelte.last.conPedaggi, isTrue);
      expect(scelte.first.stradaPrincipale, isNotEmpty);
      // Ognuna col nome della strada che la distingue.
      expect(scelte.first.stradaDistintiva([scelte.last]), 'A5');
      expect(scelte.last.stradaDistintiva([scelte.first]), 'A6');
    });

    test('lo scelto si rifà passando dai suoi punti, ognuno con la sua direzione', () async {
      final corpi = <Map<String, Object?>>[];
      final v = ClienteValhalla(
        Uri.parse('http://x/'),
        client: MockClient((r) async {
          if (r.url.path.endsWith('route')) corpi.add(jsonDecode(r.body) as Map<String, Object?>);
          return http.Response(jsonEncode({'trip': trip(45.05)}), 200);
        }),
      );
      final scelto = PercorsoCalcolato.daValhalla({'trip': trip(45.06)});
      await v.seguendo(scelto, passaggi: 3);
      final luoghi = (corpi.first['locations'] as List).cast<Map>();
      expect(luoghi, hasLength(5));
      expect(luoghi[1]['type'], 'through');
      expect(luoghi[1]['heading'], isA<int>());
      expect(luoghi.first['type'], isNull);
    });
  });

  test('col traffico, fra le scelte il più veloce va primo', () async {
    final lento = dritta(50), corto = dritta(40);
    final p = PianificatoreViaggio(
      percorsi: (_) async => lento,
      colonnine: _Nessuna(),
      profilo: ProfiloVeicolo.esempio,
      alternative: (da, a) async => [corto, lento],
      traffico: (x) async => identical(x, corto)
          ? x.conTraffico([Coda(daM: 0, aM: 30000, ritardo: const Duration(minutes: 30))])
          : x.conTraffico(const []),
    );
    final scelte = await p.scelte(partenza: const Punto(42, 12), arrivo: const Punto(42.5, 12));
    expect(scelte.first.lunghezzaM, closeTo(lento.lunghezzaM, 1));
    expect(scelte.last.ritardoTraffico, const Duration(minutes: 30));
  });

  test('con le tappe il percorso passa da tutte, e le soste si fanno sul viaggio intero', () async {
    List<Punto>? chiesti;
    final p = PianificatoreViaggio(
      percorsi: (t) async {
        chiesti = t;
        return dritta(500);
      },
      colonnine: _Colonnine(),
      profilo: ProfiloVeicolo.esempio,
    );
    final v = await p.pianifica(
      partenza: const Punto(42, 12),
      tappe: const [Punto(43, 12), Punto(44, 12)],
      arrivo: const Punto(46.5, 12),
      batteria: 80,
    );
    expect(chiesti, hasLength(4));
    expect(chiesti![1], const Punto(43, 12));
    expect(v.piano!.soste, isNotEmpty);
  });
}

class _Nessuna implements FonteColonnine {
  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async => const [];
}

class _Colonnine implements FonteColonnine {
  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async => [
        for (var km = 60; km < 500; km += 60)
          Colonnina(
            id: 'c$km',
            nome: 'Area $km',
            posizione: Punto(42 + km * 0.009, 12.002),
            connettori: const [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150)],
          ),
      ];
}
