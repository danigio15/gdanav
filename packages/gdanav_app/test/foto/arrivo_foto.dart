/// Il riepilogo all'arrivo sul telefono: «Sei arrivato», durata, distanza,
/// consumo e costo. Con l'elettrica e con la termica, chiaro e scuro.
///
/// Non è una prova: si lancia a mano.
///
/// ```sh
/// cd packages/gdanav_app && GDANAV_FOTO=/tmp/foto FLUTTER_ROOT=... flutter test --update-goldens test/foto/arrivo_foto.dart
/// ```
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/schermata_guida.dart';
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

void main() {
  setUp(_caratteri);
  final dove = Platform.environment['GDANAV_FOTO'] ?? '../../../../collaudo/foto/arrivo';

  // Partiti al 100% dalla ricarica di casa (60 kWh, 24 col sole, 7,20 € di
  // rete), una sosta a Ionity: 38,1 kWh consumati, tutti dalla batteria.
  final casa = RicaricaDiCasa(finitaIl: DateTime(2026, 10, 19, 23), kwh: 60, socA: 100, kwhSole: 24, euroRete: 7.2);
  const sosta = RicaricaInViaggio(dove: 'Ionity Caianello', kwh: 22.4, euroStimati: 15.46, euroPagati: 15.2);
  final conLeRicariche = RiepilogoViaggio(
    destinazione: 'Napoli, Piazza del Plebiscito',
    durata: const Duration(hours: 3, minutes: 12),
    metri: 263400,
    elettrica: true,
    kwh: 52.5,
    consumoStimato: false,
    pedaggio: const CostoPedaggio(euro: 18.6, km: 230),
    energia: costoDellEnergia(consumatiKwh: 52.5, partenzaKwh: 40, casa: casa, soste: const [sosta]),
    soste: const [sosta],
  );
  const elettrica = RiepilogoViaggio(
    destinazione: 'Napoli, Piazza del Plebiscito',
    durata: Duration(hours: 2, minutes: 41),
    metri: 263400,
    elettrica: true,
    kwh: 38.1,
    consumoStimato: false,
    euroAlKwh: 0.30,
    pedaggio: CostoPedaggio(euro: 18.6, km: 230),
  );
  const termica = RiepilogoViaggio(
    destinazione: 'Caserta',
    durata: Duration(minutes: 34),
    metri: 28700,
    elettrica: false,
    litri: 1.9,
    euroAlLitro: 1.80,
  );

  // Le schede da posare sopra la mappa vera (sfondo trasparente).
  for (final scuro in [false, true]) {
    testWidgets('arrivo sulla mappa ${scuro ? 'scuro' : 'chiaro'}', (tester) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          color: Colors.transparent,
          theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(children: [RiepilogoArrivo(riepilogo: elettrica, onFine: () {})]),
          ),
        ),
      );
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$dove/scheda-arrivo-${scuro ? 'scuro' : 'chiaro'}.png'));
    });
  }

  for (final scuro in [false, true]) {
    for (final (nome, r) in [('elettrica', elettrica), ('termica', termica), ('ricariche', conLeRicariche)]) {
      testWidgets('arrivo $nome ${scuro ? 'scuro' : 'chiaro'}', (tester) async {
        tester.view
          ..physicalSize = const Size(390 * 3, 844 * 3)
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: scuro ? const Color(0xFF1B2130) : const Color(0xFFE8ECEF))),
                  RiepilogoArrivo(riepilogo: r, onFine: () {}, onRicarica: (_) {}),
                ],
              ),
            ),
          ),
        );
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('$dove/arrivo-$nome-${scuro ? 'scuro' : 'chiaro'}.png'));
      });
    }
  }

  for (final scuro in [false, true]) {
    testWidgets('quanto hai speso ${scuro ? 'scuro' : 'chiaro'}', (tester) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 300 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaGdanav(scuro ? Brightness.dark : Brightness.light),
          home: Scaffold(
            backgroundColor: scuro ? const Color(0xFF1B2130) : const Color(0xFFE8ECEF),
            body: SafeArea(
              child: Column(
                children: [
                  QuantoHaiSpeso(
                    ricarica: const RicaricaInViaggio(dove: 'Ionity Caianello', kwh: 22.4, euroStimati: 15.46),
                    onSalva: (_) {},
                    onDopo: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$dove/quanto-hai-speso-${scuro ? 'scuro' : 'chiaro'}.png'));
    });
  }
}
