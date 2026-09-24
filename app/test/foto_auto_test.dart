import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/componenti/scheda_auto.dart';
import 'package:gdanav/mappa/segnaposto.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/foto_auto.dart';
import 'package:gdanav/stato/gestore_auto.dart';
import 'package:gdanav/tema.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'aiuti.dart';

const elenco = {
  'leapmotor-b10-67': {
    'pagina': 'Leapmotor B10',
    'url': 'https://upload.wikimedia.org/x/500px-Leapmotor_B10.jpg',
    'fonte': 'https://commons.wikimedia.org/wiki/File:Leapmotor_B10.jpg',
    'autore': 'Mario Rossi',
    'licenza': 'CC BY-SA 4.0',
  },
  'senza-licenza': {'url': 'https://upload.wikimedia.org/y.jpg'},
};

/// Finché il file non c'è, fino a tre secondi.
Future<File?> quando(GestoreFotoAuto g, String id) async {
  for (var i = 0; i < 60 && g.file(id) == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return g.file(id);
}

void main() {
  late Directory cartella;
  setUp(() => cartella = Directory.systemTemp.createTempSync('foto'));
  tearDown(() => cartella.deleteSync(recursive: true));

  GestoreFotoAuto gestore(List<Uri> chiesti) => GestoreFotoAuto(
    elenco: () async => jsonEncode(elenco),
    cartella: () async => cartella,
    client: MockClient((r) async {
      chiesti.add(r.url);
      return http.Response.bytes([1, 2, 3], 200);
    }),
  );

  test('la foto si scarica una volta e resta sul telefono', () async {
    final chiesti = <Uri>[];
    final g = gestore(chiesti);
    await g.carica();
    expect(g.info('leapmotor-b10-67')!.credito, 'Mario Rossi · CC BY-SA 4.0');
    expect(g.info('senza-licenza'), isNull);
    expect(g.file('leapmotor-b10-67'), isNull); // parte lo scaricamento
    expect(g.file('leapmotor-b10-67'), isNull); // non due volte
    expect((await quando(g, 'leapmotor-b10-67'))!.readAsBytesSync(), [1, 2, 3]);
    expect(chiesti, hasLength(1));

    // Riaperta l'app, il file c'è già: nessuna richiesta.
    final dopo = gestore(chiesti);
    await dopo.carica();
    expect(await quando(dopo, 'leapmotor-b10-67'), isNotNull);
    expect(chiesti, hasLength(1));
  });

  testWidgets('nella scheda la foto del modello, con autore e licenza', (tester) async {
    preparaPiattaforma(portachiavi: {'veicolo': 'leapmotor-b10-67'});
    final auto = GestoreAuto(archivio: Archivio());
    await tester.runAsync(auto.avvia);
    addTearDown(auto.dispose);
    final g = gestore([]);
    await tester.runAsync(() async {
      await g.carica();
      await quando(g, 'leapmotor-b10-67');
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: Scaffold(
          body: SchedaAuto(
            auto: auto,
            segnaposto: Segnaposto.autoBlu,
            onApriAuto: () {},
            onFonte: () {},
            onFoto: () {},
            fotoCatalogo: g,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('foto-modello')), findsOneWidget);
    expect(find.text('Mario Rossi · CC BY-SA 4.0'), findsOneWidget);
  });
}
