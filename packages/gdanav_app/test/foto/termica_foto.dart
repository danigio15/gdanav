/// Le fotografie di **«Passiamo all'auto termica?»**: la scheda quando
/// manca un'auto elettrica configurata, quella quando l'elettrica c'è ma la
/// batteria no, e il riepilogo dopo «Usa auto termica».
///
/// Non è una prova: è un attrezzo per **guardare**, come
/// `pedaggi_foto.dart`. Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/termica_foto.dart
/// ```
///
/// Le fotografie finiscono in `collaudo/foto/termica/`, che la repository
/// non tiene. La mappa è il fondo grigio delle prove.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../aiuti.dart';

/// Roboto e le icone di Material, dalla cartella di Flutter.
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

const _dove = '../../../../collaudo/foto/termica';

const _municipio = Luogo(nome: 'Municipio', descrizione: 'Piazza del Municipio', posizione: Punto(42.18, 12));

void main() {
  setUp(_caratteri);

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';

    Future<Ambiente> senzaBatteria(WidgetTester tester, {required bool conAuto}) async {
      preparaPiattaforma(portachiavi: {...impostazioniComplete, if (conAuto) 'veicolo': ProfiloVeicolo.esempio.id});
      final a = await ambiente(tester, km: 20);
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(a.app());
      await tester.pump();
      await tester.runAsync(() => a.viaggio.vaiA(_municipio));
      await tester.pumpAndSettle();
      expect(a.viaggio.stato, isA<ErroreViaggio>());
      return a;
    }

    testWidgets('nessuna auto elettrica: passiamo alla termica? ($luce)', (tester) async {
      await senzaBatteria(tester, conAuto: false);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/senza-elettrica-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets("l'elettrica c'è, la batteria no ($luce)", (tester) async {
      await senzaBatteria(tester, conAuto: true);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/batteria-ignota-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('dopo «Usa auto termica»: il percorso, senza soste ($luce)', (tester) async {
      final a = await senzaBatteria(tester, conAuto: false);
      await tester.tap(find.byKey(const Key('usa-termica')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect((a.viaggio.stato as ViaggioPronto).termica, isTrue);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/termica-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });
  }

  // BOZZA: come appaiono sull'auto. Non è il rendering vero di Android Auto
  // o di CarPlay (lo disegnano loro): una bozza dei loro modelli, coi testi
  // e i tasti che manda il telefono.
  for (final (perche, nome) in [
    (SenzaBatteria.nessunaElettrica, 'senza-elettrica'),
    (SenzaBatteria.batteriaIgnota, 'batteria-ignota'),
  ]) {
    final primaria = perche == SenzaBatteria.nessunaElettrica;
    final titolo = primaria ? 'Nessuna auto elettrica' : 'Batteria sconosciuta';
    testWidgets('BOZZA Android Auto: $nome', (tester) async {
      await _bozza(tester, _BozzaAndroidAuto(titolo: titolo, testo: perche.inAuto, primaria: primaria));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/bozza-android-auto-$nome.png'));
    });
    testWidgets('BOZZA CarPlay: $nome', (tester) async {
      await _bozza(tester, _BozzaCarPlay(testo: perche.inAuto, primaria: primaria));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/bozza-carplay-$nome.png'));
    });
  }
}

Future<void> _bozza(WidgetTester tester, Widget schermo) async {
  tester.view
    ..physicalSize = const Size(800 * 2, 480 * 2)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Roboto'),
      home: Material(
        child: Stack(
          children: [
            Positioned.fill(child: schermo),
            const Positioned(
              right: 12,
              top: 8,
              child: Text(
                'BOZZA',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'Roboto',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Il MessageTemplate di `SchermoTermica.kt`: titolo con «indietro», testo,
/// due tasti.
class _BozzaAndroidAuto extends StatelessWidget {
  const _BozzaAndroidAuto({required this.titolo, required this.testo, required this.primaria});
  final String titolo, testo;
  final bool primaria;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF1F1F1F),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.arrow_back, color: Colors.white, size: 30),
              const SizedBox(width: 20),
              Text(titolo, style: const TextStyle(color: Colors.white, fontSize: 26)),
            ],
          ),
          const Spacer(),
          Text(
            testo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 24),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _tasto(
                'Usa auto termica',
                primaria ? const Color(0xFF8AB4F8) : const Color(0xFF3C3C3C),
                primaria ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 16),
              _tasto('Annulla', const Color(0xFF3C3C3C), Colors.white),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Il CPAlertTemplate di `GdanavCarPlay.swift`: sopra la mappa, testo e due tasti.
class _BozzaCarPlay extends StatelessWidget {
  const _BozzaCarPlay({required this.testo, required this.primaria});
  final String testo;
  final bool primaria;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF606060),
    child: Center(
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              testo,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // .default è pieno, .cancel è grigio.
                _tasto('Usa auto termica', primaria ? const Color(0xFF0A84FF) : const Color(0xFF48484A), Colors.white),
                const SizedBox(width: 14),
                _tasto('Annulla', primaria ? const Color(0xFF48484A) : const Color(0xFF0A84FF), Colors.white),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _tasto(String testo, Color fondo, Color colore) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
  decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(30)),
  child: Text(
    testo,
    style: TextStyle(color: colore, fontSize: 20, fontWeight: FontWeight.w600),
  ),
);
