/// Le fotografie del **pedaggio**: le strade fra cui scegliere (una a
/// pagamento, una senza), il riepilogo del viaggio, la guida e le opzioni.
///
/// Non è una prova: è un attrezzo per **guardare**, come
/// `navigatore_foto.dart`. Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/pedaggi_foto.dart
/// ```
///
/// Le fotografie finiscono in `collaudo/foto/pedaggi/`, che la repository
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

const _dove = '../../../../collaudo/foto/pedaggi';

/// Una strada dritta di [km] a [kmh], sulla [strada], a pagamento fra i km
/// [pedaggio] se ci sono.
PercorsoCalcolato _strada(int km, double kmh, String strada, {(double, double)? pedaggio}) {
  final punti = [for (var i = 0; i <= km; i++) Punto(42 + i * 0.009, 12)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++) Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: kmh),
    ],
    manovre: [
      Manovra(istruzione: 'Prendi la $strada', lunghezzaM: linea.lunghezzaM, secondi: km / kmh * 3600, inizio: 0, strada: strada),
    ],
    conPedaggi: pedaggio != null,
    conAutostrade: pedaggio != null,
    pedaggi: [if (pedaggio case (final da, final a)) TrattoPedaggio(daM: da * 1000, aM: a * 1000, paese: 'ITA')],
  );
}

/// Torino → Milano: per la A4 (più rapida, ~108 km a pagamento), per la
/// statale (niente pedaggi), e per la A21–A7 (un pezzo a pagamento).
CostruisciPianificatore _treStrade() {
  final a4 = _strada(140, 115, 'A4', pedaggio: (8, 116));
  return (_, profilo, preferenze, _) => PianificatoreViaggio(
    percorsi: (_) async => a4,
    alternative: (da, a) async => [a4, _strada(132, 72, 'SS11'), _strada(168, 105, 'A21', pedaggio: (30, 75))],
    colonnine: ColonnineFinte(),
    profilo: profilo,
    preferenze: preferenze,
  );
}

const _milano = Luogo(nome: 'Milano', descrizione: 'Piazza del Duomo', posizione: Punto(45.4642, 9.19));

void main() {
  setUp(_caratteri);

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';

    Future<Ambiente> pronto(WidgetTester tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, costruisci: _treStrade());
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(a.app());
      a.auto.manuale.imposta(80);
      await tester.pump();
      await tester.runAsync(() => a.viaggio.vaiA(_milano));
      await tester.pumpAndSettle();
      expect(a.viaggio.stato, isA<ViaggioPronto>());
      return a;
    }

    testWidgets('il riepilogo del viaggio col pedaggio ($luce)', (tester) async {
      await pronto(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/riepilogo-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('le strade: con e senza pedaggio ($luce)', (tester) async {
      await pronto(tester);
      await tester.drag(find.byType(ListView).last, const Offset(0, -330));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/strade-$luce.png'));
      // Scelta la statale: «Senza pedaggi» anche nel riepilogo.
      await tester.tap(find.byKey(const Key('strada-1')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, 250));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/riepilogo-senza-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('le opzioni: classe e tariffa ($luce)', (tester) async {
      await pronto(tester);
      await tester.tap(find.byKey(const Key('riga-pedaggio')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/opzioni-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('la guida col pedaggio che resta ($luce)', (tester) async {
      final a = await pronto(tester);
      await tester.tap(find.text('Avvia'));
      await tester.pumpAndSettle();
      a.posizioni.add(const Punto(42 + 20 * 0.009, 12));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/guida-$luce.png'));
      await tester.runAsync(a.guida.ferma);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
