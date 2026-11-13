import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/* ── Gli indici delle risposte di TomTom ───────────────────────────────────
 *
 * Manovre e corsie stanno sui punti della rotta per indice (`pointIndex`,
 * `startPointIndex`, `endPointIndex`): un indice letto storto è una svolta
 * disegnata all'incrocio sbagliato, o le corsie di un'altra manovra. */

/// [n] punti verso nord da (41.9, 12.5), uno ogni cento metri circa.
List<Map<String, Object?>> nord(int da, int a) => [
      for (var i = da; i <= a; i++) {'latitude': 41.9 + i * 0.0009, 'longitude': 12.5},
    ];

void main() {
  test('le corsie di un tratto che COMINCIA alla manovra non sono della manovra', () {
    final rotta = <String, Object?>{
      'legs': [
        {'points': nord(0, 10)},
      ],
      'summary': {'lengthInMeters': 1100, 'travelTimeInSeconds': 80},
      'guidance': {
        'instructions': [
          {
            'pointIndex': 0,
            'routeOffsetInMeters': 0,
            'travelTimeInSeconds': 0,
            'maneuver': 'DEPART',
            'message': 'Parti'
          },
          // Svolta a destra al punto 4: TomTom non dà corsie per questa.
          {
            'pointIndex': 4,
            'routeOffsetInMeters': 440,
            'travelTimeInSeconds': 32,
            'maneuver': 'TURN_RIGHT',
            'message': 'Gira a destra',
          },
          {
            'pointIndex': 7,
            'routeOffsetInMeters': 770,
            'travelTimeInSeconds': 56,
            'maneuver': 'KEEP_LEFT',
            'message': 'Tieni la sinistra',
          },
          {
            'pointIndex': 10,
            'routeOffsetInMeters': 1100,
            'travelTimeInSeconds': 80,
            'maneuver': 'ARRIVE',
            'message': 'Arrivo',
          },
        ],
      },
      'sections': [
        // Le corsie dopo la svolta (dal punto 4 al 6), restando a sinistra
        // passando un'uscita: non sono della svolta a destra.
        {
          'sectionType': 'LANES',
          'startPointIndex': 4,
          'endPointIndex': 6,
          'lanes': [
            {
              'directions': ['STRAIGHT'],
              'follow': 'STRAIGHT',
            },
            {
              'directions': ['RIGHT'],
            },
          ],
        },
        // Queste sì: finiscono sulla manovra del punto 7.
        {
          'sectionType': 'LANES',
          'startPointIndex': 6,
          'endPointIndex': 7,
          'lanes': [
            {
              'directions': ['SLIGHT_LEFT'],
              'follow': 'SLIGHT_LEFT',
            },
            {
              'directions': ['STRAIGHT'],
            },
          ],
        },
      ],
    };
    final p = ClienteTomTom.leggi(rotta);
    expect(p.manovre[1].corsie, isEmpty);
    expect(p.manovre[2].corsie.map((c) => c.giusta), [true, false]);
  });

  test('la manovra d\'arrivo di TomTom non ha lunghezza né tempo negativi', () {
    final json = jsonDecode(File('test/dati/tomtom_pedaggi.json').readAsStringSync()) as Map<String, Object?>;
    final p = ClienteTomTom.leggiTutte(json).first;
    expect(p.manovre.every((m) => m.lunghezzaM >= 0 && m.secondi >= 0), isTrue);
    expect(p.manovre.last.lunghezzaM, 0);
    expect(p.manovre.last.secondi, 0);
  });

  group('con le tappe, il punto ripetuto fra un pezzo e l\'altro', () {
    /* Due pezzi: dal punto 0 al 5 (la tappa), poi dal 5 al 10. TomTom
     * ripete la tappa in testa al secondo pezzo: undici punti diversi,
     * dodici nella risposta. La svolta dopo la tappa è sul punto 8 della
     * strada vera. */
    Map<String, Object?> rotta({required bool contaIRipetuti}) {
      // Il punto 8 della strada, coi ripetuti contati, è il 9 della risposta.
      int i(int strada) => contaIRipetuti && strada >= 5 ? strada + 1 : strada;
      return {
        'legs': [
          {'points': nord(0, 5)},
          {'points': nord(5, 10)},
        ],
        'summary': {'lengthInMeters': 1000, 'travelTimeInSeconds': 72},
        'guidance': {
          'instructions': [
            {'pointIndex': 0, 'routeOffsetInMeters': 0, 'travelTimeInSeconds': 0, 'maneuver': 'DEPART'},
            {'pointIndex': i(5), 'routeOffsetInMeters': 500, 'travelTimeInSeconds': 36, 'maneuver': 'WAYPOINT_REACHED'},
            {'pointIndex': i(8), 'routeOffsetInMeters': 800, 'travelTimeInSeconds': 58, 'maneuver': 'TURN_RIGHT'},
            {'pointIndex': i(10), 'routeOffsetInMeters': 1000, 'travelTimeInSeconds': 72, 'maneuver': 'ARRIVE'},
          ],
        },
        'sections': [
          {
            'sectionType': 'LANES',
            'startPointIndex': i(7),
            'endPointIndex': i(8),
            'lanes': [
              {
                'directions': ['STRAIGHT'],
              },
              {
                'directions': ['RIGHT'],
                'follow': 'RIGHT',
              },
            ],
          },
          {'sectionType': 'SPEED_LIMIT', 'startPointIndex': i(8), 'endPointIndex': i(10), 'maxSpeedLimitInKmh': 30},
        ],
      };
    }

    final svolta = Punto(41.9 + 8 * 0.0009, 12.5);

    for (final conta in [true, false]) {
      test(conta ? 'indici che lo contano' : 'indici che non lo contano', () {
        final p = ClienteTomTom.leggi(rotta(contaIRipetuti: conta));
        final destra = p.manovre[2];
        expect(distanzaM(p.punti[destra.inizio], svolta), lessThan(1),
            reason: 'la svolta va disegnata sull\'incrocio dove si gira');
        expect(destra.corsie.map((c) => c.giusta), [false, true]);
        expect(distanzaM(p.punti[p.manovre.last.inizio], p.punti.last), lessThan(1));
        // Il limite comincia alla svolta, non un punto prima.
        final primoA30 = p.limiti.indexOf(30);
        expect(distanzaM(p.punti[primoA30], svolta), lessThan(1));
        expect(Linea(p.punti).lunghezzaM, closeTo(1000, 5));
      });
    }
  });
}
