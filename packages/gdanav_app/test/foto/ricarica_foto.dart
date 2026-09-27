/// Le fotografie della pagina **Ricarica**, con gli operatori.
///
/// Non è una prova: è un attrezzo per **guardare**. Per questo il nome non
/// finisce in `_test.dart` — `flutter test` da solo non lo prende, e non fa
/// rosso il lavoro per un carattere disegnato mezzo punto più in là. Si lancia
/// a mano:
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/ricarica_foto.dart
/// ```
///
/// Le fotografie finiscono in `collaudo/foto/ricarica/`, che la repository non
/// tiene: non c'è niente da confrontare e niente che possa diventare rosso.
///
/// ## Cosa si guarda
///
/// La riga «Quali colonnine (kW)», che adesso dice di valere anche per quelle
/// intorno; e sotto le pastiglie degli operatori. Due stati, perché la pagina
/// ne ha due e sono diversi da leggere:
///
///  - **tutti accesi**: «Li vedi tutti. Tocca quelli che non vuoi vedere.»;
///  - **due spenti**: le pastiglie spente si distinguono a colpo d'occhio, e
///    la riga sopra conta quante sono.
///
/// Gli operatori sono quelli veri dell'archivio dentro l'app, non un elenco
/// inventato: sono i nomi che si leggono guidando in Italia, ed è su quelli
/// che si giudica se la pastiglia è larga abbastanza.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/ricarica.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../aiuti.dart';

/// Un carattere vero dal sistema: senza, la fotografia esce a quadratini e
/// non si giudica niente. gdanav non ne porta uno suo — usa quello del
/// telefono — e qui si prende il più vicino che c'è su questa macchina.
Future<void> _ilCarattere() async {
  const dove = [
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  ];
  for (final famiglia in ['Roboto', 'packages/gdanav_app/Roboto']) {
    final carica = FontLoader(famiglia);
    var trovato = false;
    for (final via in dove) {
      final file = File(via);
      if (!file.existsSync()) continue;
      carica.addFont(file.readAsBytes().then((b) => b.buffer.asByteData()));
      trovato = true;
      break;
    }
    if (trovato) await carica.load();
  }
  final radice = Platform.environment['FLUTTER_ROOT'];
  if (radice == null || radice.isEmpty) return;
  final icone = File('$radice/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!icone.existsSync()) return;
  await (FontLoader('MaterialIcons')..addFont(icone.readAsBytes().then((b) => b.buffer.asByteData()))).load();
}

/// Gli operatori veri, dall'archivio dentro l'app — letto dal disco e non dal
/// pacchetto: dentro una prova `rootBundle` quel file non ce l'ha, e la
/// pagina uscirebbe senza pastiglie, cioè senza la cosa da guardare.
Future<List<String>> _operatoriVeri() async {
  final file = File('assets/colonnine.json');
  if (!file.existsSync()) return const [];
  final archivio = ArchivioColonnine.leggi(await file.readAsString());
  return operatoriFra(archivio.tutte).take(24).toList();
}

void main() {
  setUp(() async {
    preparaPiattaforma();
    await _ilCarattere();
  });

  /// Un telefono qualunque: 390 punti, come quello con cui si guarda.
  void quantoGrande(WidgetTester tester, {required bool scuro}) {
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3;
    tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  Future<void> scatta(
    WidgetTester tester, {
    required String come,
    required bool scuro,
    required Set<String> spenti,
  }) async {
    quantoGrande(tester, scuro: scuro);
    final archivio = Archivio();
    await archivio.salvaPreferenze(PreferenzeRicarica(potenzaMinimaKw: 100, operatoriEsclusi: spenti));
    /* Il file si legge con `runAsync`: dentro una prova il tempo lo muove il
     * tester, e una lettura dal disco vera resterebbe appesa per sempre. */
    final operatori = await tester.runAsync(_operatoriVeri) ?? const <String>[];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
        home: PreferenzeRicaricaSchermata(archivio: archivio, operatori: () async => operatori),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../../../collaudo/foto/ricarica/$come.png'));
  }

  testWidgets('la pagina Ricarica, chiaro e scuro, con gli operatori', (tester) async {
    await scatta(tester, come: 'ricarica-tutti-chiaro', scuro: false, spenti: const {});
  });

  testWidgets('la pagina Ricarica al buio', (tester) async {
    await scatta(tester, come: 'ricarica-tutti-scuro', scuro: true, spenti: const {});
  });

  testWidgets('con due operatori spenti', (tester) async {
    await scatta(tester, come: 'ricarica-due-spenti-chiaro', scuro: false, spenti: const {'be charge', 'ionity'});
  });

  testWidgets('con due operatori spenti, al buio', (tester) async {
    await scatta(tester, come: 'ricarica-due-spenti-scuro', scuro: true, spenti: const {'be charge', 'ionity'});
  });
}
