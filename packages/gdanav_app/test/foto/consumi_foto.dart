/// Le fotografie del confronto con ABRP: la Leapmotor B10, 18 km fra città
/// e tangenziale, partenza al 63%, i dati dell'auto da gdahome. Il pannello
/// della guida e «Dati che arrivano dall'auto».
///
/// Non è una prova: è un attrezzo per **guardare**. Si lancia a mano:
///
/// ```sh
/// cd packages/gdanav_app && FOTO_CONSUMI=/una/cartella \
///   flutter test --update-goldens test/foto/consumi_foto.dart
/// ```
///
/// Senza `FOTO_CONSUMI` le fotografie finiscono in `collaudo/foto/consumi/`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/fonte_dati_auto.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../aiuti.dart';

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

final _dove = Platform.environment['FOTO_CONSUMI'] ?? '../../../../collaudo/foto/consumi';

/// 18 km: un pezzo lento in centro, la città a 50, la tangenziale a 70.
CostruisciPianificatore _viaggioDiAbrp() =>
    (_, profilo, preferenze, _) => PianificatoreViaggio(
      percorsi: (_) async {
        const velocita = [30, 30, 30, 50, 50, 50, 50, 70, 70, 70, 70, 70, 70, 70, 70, 70, 50, 50];
        final punti = [for (var i = 0; i <= velocita.length; i++) Punto(42 + i * 0.009, 12)];
        final linea = Linea(punti);
        return PercorsoCalcolato(
          punti: punti,
          tratti: [
            for (var i = 1; i < punti.length; i++)
              Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: velocita[i - 1].toDouble()),
          ],
          manovre: const [],
        );
      },
      colonnine: ColonnineFinte(),
      profilo: profilo,
      preferenze: preferenze,
    );

void main() {
  setUp(_caratteri);

  testWidgets('la guida e i dati dell\'auto, dopo', (tester) async {
    preparaPiattaforma(portachiavi: {...impostazioniComplete, 'veicolo': 'leapmotor-b10-56'});
    final a = await ambiente(tester, costruisci: _viaggioDiAbrp());
    tester.view
      ..physicalSize = const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = 3;
    // Quello che arriva da gdahome, letto dall'auto due minuti fa.
    a.auto.arbitro.registra(
      StatoAuto(
        sorgente: TipoSorgente.gdahome,
        letto: DateTime.now().subtract(const Duration(minutes: 2)),
        batteria: 63,
        autonomiaKm: 264,
        inCarica: false,
        potenzaCaricaKw: 0,
        temperaturaEsternaC: 15,
        temperaturaBatteriaC: 22,
        velocitaKmh: 0,
        potenzaKw: 0,
        odometroKm: 9159,
        latitudine: 42,
        longitudine: 12,
      ),
    );
    await tester.runAsync(() => a.auto.cambiaModalita(a.auto.modalita));
    await tester.pumpWidget(a.app());
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Casa', posizione: Punto(42.16, 12))));
    await tester.pumpAndSettle();
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    final arrivo = a.guida.batteriaArrivo!;
    // ignore: avoid_print
    print('B10, 18 km, 63% → ${arrivo.toStringAsFixed(2)}% (${a.guida.consumoKwh100!.toStringAsFixed(1)} kWh/100 km)');
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/guida-pannello.png'));

    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: DatiDallAuto(gestore: a.auto, consumo: a.viaggio.consumo),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('$_dove/dati-dall-auto.png'));
    await tester.runAsync(a.guida.ferma);
    await tester.pumpWidget(const SizedBox());
  });
}
