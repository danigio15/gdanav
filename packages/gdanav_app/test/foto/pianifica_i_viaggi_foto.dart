/// Le fotografie di «Pianifica i viaggi» sulla mappa: col prossimo viaggio,
/// senza viaggi e senza Premium, su un telefono grande e su uno piccolo.
///
/// Non è una prova: è un attrezzo per **guardare** (il nome non finisce in
/// `_test.dart`, e `flutter test` da solo non lo prende). Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/pianifica_i_viaggi_foto.dart
/// ```
///
/// Le fotografie finiscono in `collaudo/foto/pianifica-i-viaggi/`, che la
/// repository non tiene (o dove dice `FOTO_PIANIFICA`). La mappa è un
/// riquadro grigio: quella vera vuole il codice nativo.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/schermata_principale.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_premium.dart';
import 'package:gdanav_app/stato/viaggi_pianificati.dart';
import 'package:gdanav_app/tema.dart';

import '../aiuti.dart';

/// Roboto e le icone di Material, dalla cartella di Flutter: senza, la
/// fotografia esce a quadratini.
Future<void> _caratteri() async {
  final radice = Platform.environment['FLUTTER_ROOT'];
  if (radice == null || radice.isEmpty) return;
  final cartella = '$radice/bin/cache/artifacts/material_fonts';
  Future<ByteData> leggi(String nome) => File('$cartella/$nome').readAsBytes().then((b) => b.buffer.asByteData());
  for (final famiglia in ['Roboto', 'packages/gdanav_app/Roboto']) {
    final f = FontLoader(famiglia);
    for (final peso in ['Regular', 'Medium', 'Bold', 'Black']) {
      if (File('$cartella/Roboto-$peso.ttf').existsSync()) f.addFont(leggi('Roboto-$peso.ttf'));
    }
    await f.load();
  }
  if (File('$cartella/MaterialIcons-Regular.otf').existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(leggi('MaterialIcons-Regular.otf'))).load();
  }
}

final _dove = Platform.environment['FOTO_PIANIFICA'] ?? '../../../../collaudo/foto/pianifica-i-viaggi';

final _giovedi = DateTime(2026, 10, 15, 21);

Map<String, Object?> _lavoro() => {
  'id': 'v_1',
  'utente': 'u1',
  'tipo': 'settimana',
  'nome': 'Casa – Lavoro',
  'da': null,
  'tappe': [
    {'nome': 'Ufficio', 'lat': 41.9, 'lon': 12.5},
  ],
  'quando': {
    'modo': 'arrivo',
    'ora': '08:30',
    'giorno': null,
    'giorni': [1, 2, 3, 4, 5],
  },
  'avviso': {'acceso': true, 'minuti': 10},
  'prepara': {'clima': null, 'garage': null},
  'prossima': {
    'giorno': '2026-10-16',
    'partenza': DateTime(2026, 10, 16, 7, 59).millisecondsSinceEpoch,
    'arrivo': DateTime(2026, 10, 16, 8, 30).millisecondsSinceEpoch,
    'stimata': true,
  },
  'creatoIl': 1,
  'modificatoIl': 1,
};

Map<String, Object?> _napoli() => {
  ..._lavoro(),
  'id': 'v_2',
  'tipo': 'una',
  'nome': 'Napoli – Caserta',
  'quando': {'modo': 'arrivo', 'ora': '09:00', 'giorno': '2026-10-17', 'giorni': <int>[]},
  'prossima': {
    'giorno': '2026-10-17',
    'partenza': DateTime(2026, 10, 17, 8, 12).millisecondsSinceEpoch,
    'arrivo': DateTime(2026, 10, 17, 9).millisecondsSinceEpoch,
    'stimata': true,
  },
};

void main() {
  setUp(_caratteri);

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';
    for (final (nome, viaggi, premium, schermo) in [
      ('con-viaggi', [_lavoro(), _napoli()], true, const Size(390, 844)),
      ('senza-viaggi', <Map<String, Object?>>[], true, const Size(390, 844)),
      ('senza-premium', [_lavoro()], false, const Size(390, 844)),
      ('telefono-piccolo', [_lavoro(), _napoli()], true, const Size(360, 640)),
    ]) {
      testWidgets('la scheda sulla mappa: $nome ($luce)', (tester) async {
        preparaPiattaforma(portachiavi: impostazioniComplete);
        final a = await ambiente(tester, km: 20);
        tester.view
          ..physicalSize = schermo * 3
          ..devicePixelRatio = 3;
        tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final g = GestoreViaggiPianificati(
          FonteViaggiDellaCasa((c) async => {'sbloccato': true, 'viaggi': viaggi}),
          orologio: () => _giovedi,
        );
        await tester.runAsync(g.carica);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
            home: SchermataPrincipale(
              auto: a.auto,
              viaggio: a.viaggio,
              archivio: a.archivio,
              guida: a.guida,
              posizione: a.posizione,
              segnalazioni: a.segnalazioni,
              pianificati: g,
              premium: premium ? null : GestorePremium(archivio: Archivio(), tuttoSbloccato: false),
              mappa: (_, _) => ColoredBox(color: scuro ? const Color(0xFF263238) : const Color(0xFFDDE3EA)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/$nome-$luce.png'));
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
