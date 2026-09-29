import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_app/schermate/diagnosi_auto.dart';
import 'package:gdanav_app/tema.dart';

/// «Il traffico si vedeva sull'app del telefono ma non su Android Auto.»
void main() {
  Map strato(Map<String, Object> stile, String id) =>
      (stile['layers']! as List).cast<Map>().singleWhere((l) => l['id'] == id);
  // La larghezza della linea a zoom 16: l'ultimo valore dell'interpolazione.
  num aZoom16(Map l) => ((l['paint'] as Map)['line-width'] as List).last as num;

  test('sull\'auto lo stesso traffico del telefono, con le linee più spesse', () {
    final telefono = stileMappa(scuro: false, chiaveTraffico: 'prova');
    final auto = stileMappa(scuro: false, chiaveTraffico: 'prova', perAuto: true);
    for (final s in [telefono, auto]) {
      expect((s['sources']! as Map)['traffico'], isNotNull);
    }
    for (final id in [stratoTraffico, stratoTrafficoLocale]) {
      // Stessi dati e stesso filtro: cambia solo lo spessore.
      expect(strato(auto, id)['filter'], strato(telefono, id)['filter']);
      expect(strato(auto, id)['source'], strato(telefono, id)['source']);
      expect(aZoom16(strato(telefono, id)), 5);
      expect(aZoom16(strato(auto, id)), 8);
    }
    // Senza chiave non c'è, né sul telefono né sull'auto.
    expect((stileMappa(scuro: true, perAuto: true)['sources']! as Map)['traffico'], isNull);
  });

  group('la scheda «Android Auto» dice cosa ha visto la mappa dell\'auto', () {
    test('prima di un viaggio in auto: niente da dire', () {
      expect(vociTraffico(null).single.$1, 'Non ancora visto');
      expect(vociTraffico(const {}).single.$1, 'Non ancora visto');
    });

    test('i riquadri non arrivano: l\'errore di TomTom, senza chiave', () {
      final voci = vociTraffico(const {
        'inizio': 1790000000000,
        'strato': true,
        'richiesti': 40,
        'arrivati': 0,
        'errori': 40,
        'ultimo_errore': 'Failed to load tile 16/35000/24000=>16 for source traffico: HTTP status code 403',
        'tratti': 0,
        'massimo': 0,
      });
      final riquadri = voci.singleWhere((v) => v.$1 == 'Riquadri da TomTom');
      expect(riquadri.$2, isFalse);
      expect(riquadri.$3, contains('40 con errore'));
      expect(riquadri.$3, contains('HTTP status code 403'));
      expect(voci.where((v) => v.$1 == 'Code sullo schermo'), isEmpty);
    });

    test('arrivano ma lì non c\'era traffico: lo si dice, e come vederne di più', () {
      final voci = vociTraffico(const {'inizio': 1790000000000, 'strato': true, 'arrivati': 120, 'errori': 0});
      expect(voci.singleWhere((v) => v.$1 == 'Riquadri da TomTom').$2, isTrue);
      final code = voci.singleWhere((v) => v.$1 == 'Code sullo schermo');
      expect(code.$2, isNull);
      expect(code.$3, contains('«−»'));
    });

    test('arrivano e si vedono', () {
      final voci = vociTraffico(const {
        'inizio': 1790000000000,
        'strato': true,
        'arrivati': 120,
        'errori': 0,
        'tratti': 3,
        'massimo': 17,
        'zoom': 16.5,
      });
      final code = voci.singleWhere((v) => v.$1 == 'Code sullo schermo');
      expect(code.$2, isTrue);
      expect(code.$3, 'Fino a 17 tratti insieme; all\'ultimo controllo 3, zoom 16.5');
    });

    test('senza chiave lo strato non c\'è', () {
      expect(vociTraffico(const {'inizio': 1, 'strato': false}).any((v) => v.$2 == false), isTrue);
    });
  });

  testWidgets('nella scheda, sotto il telefono', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: const Scaffold(
          body: DiagnosiAuto(
            dati: {
              'servizio': true,
              'navigazione': true,
              'descrittore': true,
              'androidAuto': '15.2.1',
              'installatore': null,
              'android': '15',
              'telefono': 'samsung SM-S921B',
              'traffico': {'inizio': 1790000000000, 'strato': true, 'arrivati': 64, 'errori': 0, 'massimo': 9},
            },
          ),
        ),
      ),
    );
    expect(find.text('Il traffico sull\'auto'), findsOneWidget);
    expect(find.text('C\'è nella mappa dell\'auto'), findsOneWidget);
    expect(find.text('64 arrivati'), findsOneWidget);
  });
}
