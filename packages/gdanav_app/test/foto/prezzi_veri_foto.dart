/// Le fotografie dei **prezzi veri**: la Tangenziale di Napoli al suo prezzo
/// (1,05 €, senza «~») e le impostazioni aperte da gdahome in auto.
///
/// Non è una prova: è un attrezzo per **guardare**, come
/// `navigatore_foto.dart`. Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && flutter test --update-goldens test/foto/prezzi_veri_foto.dart
/// ```
///
/// Le fotografie finiscono in `collaudo/foto/prezzi_veri/`, che la repository
/// non tiene. La mappa è il fondo grigio delle prove.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';
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

const _dove = '../../../../collaudo/foto/prezzi_veri';

/// Corso Malta → Centro Direzionale per la Tangenziale: la barriera sulla
/// rampa d'ingresso, una volta.
PercorsoCalcolato _tangenziale() {
  final punti = [for (var i = 0; i <= 9; i++) Punto(40.86 + i * 0.009, 14.27)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++) Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 70),
    ],
    manovre: [
      Manovra(istruzione: 'Prendi Corso Malta', lunghezzaM: 1000, secondi: 80, inizio: 0, strada: 'Corso Malta'),
      Manovra(istruzione: 'Prendi la Tangenziale', lunghezzaM: 7000, secondi: 360, inizio: 1, strada: 'Tangenziale di Napoli', verso: 'A56'),
    ],
    conPedaggi: true,
    conAutostrade: true,
    pedaggi: [TrattoPedaggio(daM: linea.cumulate[1], aM: linea.cumulate[2])],
  );
}

CostruisciPianificatore _perLaTangenziale() {
  final t = _tangenziale();
  return (_, profilo, preferenze, _) => PianificatoreViaggio(
    percorsi: (_) async => t,
    alternative: (da, a) async => [t],
    colonnine: ColonnineFinte(),
    profilo: profilo,
    preferenze: preferenze,
  );
}

const _centro = Luogo(nome: 'Centro Direzionale', descrizione: 'Napoli', posizione: Punto(40.94, 14.27));

void main() {
  setUp(_caratteri);

  for (final scuro in [false, true]) {
    final luce = scuro ? 'scuro' : 'chiaro';

    Future<Ambiente> pronto(WidgetTester tester) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, costruisci: _perLaTangenziale());
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      tester.platformDispatcher.platformBrightnessTestValue = scuro ? Brightness.dark : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      return a;
    }

    testWidgets('la Tangenziale al suo prezzo ($luce)', (tester) async {
      final a = await pronto(tester);
      await tester.pumpWidget(a.app());
      a.auto.manuale.imposta(80);
      await tester.pump();
      await tester.runAsync(() => a.viaggio.vaiA(_centro));
      await tester.pumpAndSettle();
      expect(find.textContaining('1,05 €'), findsWidgets);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/tangenziale-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('le impostazioni da gdahome, in auto ($luce)', (tester) async {
      final a = await pronto(tester);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: GdanavDentro(
            app: a.app() as GdanavApp,
            soloImpostazioni: true,
            chiudiImpostazioni: () {},
            vociOspite: [
              VoceOspite(
                icona: Icons.bolt_rounded,
                titolo: 'Comandi rapidi in auto',
                sotto: 'Crea e scegli i tasti di casa da usare in auto',
                apri: () {},
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/impostazioni-$luce.png'));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
