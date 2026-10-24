/// Le fotografie della pagina **Avvisi in guida**: ogni avviso a voce, solo
/// a schermo o spento. Non è una prova: è un attrezzo per guardare.
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/avvisi_foto.dart
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/avvisi_in_guida.dart';
import 'package:gdanav_app/schermate/avvisi_guida.dart';
import 'package:gdanav_app/stato/scelte_avvisi.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

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

final _dove = Platform.environment['FOTO_AVVISI'] ?? '../../../../collaudo/foto/avvisi';

void main() {
  setUp(_caratteri);

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';
    for (final (nome, scelte) in [
      ('tutti-a-voce', <Avviso, ComeAvvisare>{}),
      (
        'scelti',
        {
          Avviso.polizia: ComeAvvisare.spento,
          Avviso.traffico: ComeAvvisare.schermo,
          Avviso.lavori: ComeAvvisare.schermo,
          Avviso.limite: ComeAvvisare.schermo,
        },
      ),
    ]) {
      testWidgets('avvisi $nome ($luce)', (tester) async {
        tester.view
          ..physicalSize = const Size(390 * 3, 1660 * 3)
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
            home: AvvisiGuidaSchermata(scelte: ScelteAvvisi(scelte)),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/avvisi-$nome-$luce.png'));
      });
    }
  }

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';
    testWidgets('riquadri del Tutor e senza percorso ($luce)', (tester) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 620 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      const tratto = TrattoTutor(id: 't', inizio: Punto(44, 11), fine: Punto(44.1, 11), limiteKmh: 130);
      Widget titolo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Text(
          t,
          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569)),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
          home: Scaffold(
            backgroundColor: scuro ? const Color(0xFF1F2937) : const Color(0xFFDCE3EA),
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titolo('Il Tutor si avvicina'),
                  const AvvisoTutor(stato: TutorDavanti(tratto, 850)),
                  titolo('Dentro il Tutor, media sotto il limite'),
                  const AvvisoTutor(stato: DentroTutor(tratto, mediaKmh: 124, restantiM: 5200)),
                  titolo('Dentro il Tutor, media sopra il limite'),
                  const AvvisoTutor(stato: DentroTutor(tratto, mediaKmh: 138, restantiM: 3400)),
                  titolo('Senza percorso: l\'autovelox davanti'),
                  AvvisoSegnalazione(
                    segnalazione: Segnalazione(
                      id: 'a',
                      tipo: TipoSegnalazione.autovelox,
                      punto: const Punto(44, 11),
                      creata: DateTime(2026),
                      fissa: true,
                      limiteKmh: 90,
                    ),
                    metri: 700,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/riquadri-$luce.png'));
    });
  }
}
