import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/schermate/cerca_destinazione.dart';
import 'package:gdanav/schermate/importa_google.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_luoghi.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<int> zipTakeout() {
    final json = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'geometry': {
            'coordinates': [12.4922, 41.8902],
            'type': 'Point',
          },
          'properties': {
            'location': {'name': 'Colosseo', 'address': 'Roma'},
          },
          'type': 'Feature',
        },
      ],
    });
    const csv =
        'Title,Note,URL\n'
        'Trattoria,,https://www.google.com/maps/place/Trattoria/data=!4m2\n'
        'Spiaggia,,"https://www.google.com/maps/place/Spiaggia/@40.63,14.60,17z"\n';
    final a = Archive()
      ..add(ArchiveFile.bytes('Takeout/Maps (i tuoi luoghi)/Luoghi salvati.json', utf8.encode(json)))
      ..add(ArchiveFile.bytes('Takeout/Salvati/Voglio andarci.csv', utf8.encode(csv)))
      ..add(ArchiveFile.bytes('Takeout/archive_browser.html', utf8.encode('<html></html>')));
    return ZipEncoder().encode(a);
  }

  testWidgets('dallo zip di Google Takeout ai preferiti, e poi nella ricerca', (tester) async {
    preparaPiattaforma();
    final luoghi = GestoreLuoghi(Archivio());
    await tester.runAsync(luoghi.carica);
    await tester.pumpWidget(
      MaterialApp(
        home: ImportaGoogleMaps(
          luoghi: luoghi,
          fonte: LuoghiFinti(),
          scegliFile: () async => [(nome: 'takeout-20260925.zip', byte: zipTakeout())],
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('scegli-file-google')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('3 posti trovati'), findsOneWidget);
    expect(find.textContaining('Voglio andarci: 2'), findsOneWidget);
    expect(find.textContaining('1 senza coordinate'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('importa-google')), 200);
    await tester.tap(find.byKey(const Key('importa-google')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('importati')), 200);
    expect(find.text('3 posti nuovi nei preferiti'), findsOneWidget);
    expect(luoghi.altri.map((p) => p.etichetta), containsAll(['Colosseo', 'Trattoria', 'Spiaggia']));
    expect(luoghi.altri.firstWhere((p) => p.etichetta == 'Spiaggia').lista, 'Voglio andarci');

    // Importare di nuovo non li raddoppia.
    expect(await tester.runAsync(() => luoghi.aggiungiTanti(luoghi.altri.toList())), 0);

    // Nella ricerca: scrivendo, i salvati che corrispondono vengono prima.
    await tester.pumpWidget(
      MaterialApp(
        home: CercaDestinazione(luoghi: LuoghiFinti(), salvati: luoghi),
      ),
    );
    await tester.enterText(find.byType(TextField), 'spiag');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Spiaggia'), findsOneWidget);
    expect(find.textContaining('Voglio andarci'), findsOneWidget);
  });
}
