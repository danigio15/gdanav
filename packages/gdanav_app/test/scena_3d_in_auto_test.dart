import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';

import 'aiuti.dart';

/// «Certo, voglio la scena reale anche in macchina.» Col 3D aumentato sul
/// telefono l'auto mostra la pagina 3D in una WebView sua (Scena3dAuto); la
/// regia è quella del telefono e passa per il ponte.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canale = MethodChannel('gdanav/schermo_auto');

  testWidgets("col 3D aumentato l'auto vuole la scena, e la regia le parla come sul telefono", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    Future<void> dallAuto(String metodo, [Object? argomenti]) => messaggero.handlePlatformMessage(
      canale.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(metodo, argomenti)),
      (_) {},
    );
    Future<void> aspetta() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    final a = await ambiente(tester, km: 20);
    await tester.runAsync(() => a.archivio.salvaVistaMappa(VistaMappa.aumentata));
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, canale: canale)..avvia();
    addTearDown(ponte.ferma);
    await aspetta();
    expect((chiamate.lastWhere((c) => c.method == 'web3d_vuoi').arguments as Map)['si'], isTrue);

    // L'auto dice come la vede (di notte, immersiva, la scheda a sinistra), poi
    // la pagina dice che è caricata: la regia manda le opzioni e lo stile.
    await dallAuto('stato3d', {'notte': true, 'vista': 'immersiva', 'sopra': 0.0, 'sinistra': 320.0});
    await dallAuto('dalla3d', {'testo': '{"tipo":"caricata"}'});
    await aspetta();
    final js = [for (final c in chiamate.where((c) => c.method == 'web3d')) (c.arguments as Map)['js'] as String];
    Map<String, Object?> messaggio(String tipo) {
      final uno = js.firstWhere((j) => j.contains('"tipo":"$tipo"'));
      final dentro = uno.substring(uno.indexOf('ricevi(') + 7, uno.lastIndexOf(');'));
      return (jsonDecode(dentro) as Map).cast<String, Object?>();
    }

    expect(messaggio('opzioni')['notte'], isTrue);
    expect(messaggio('opzioni')['vista'], 'immersiva');
    expect(messaggio('stile'), contains('stile'));

    // La pagina non ce la fa: l'auto lo sa, e non la vuole più.
    await dallAuto('dalla3d', {'testo': '{"tipo":"errore","motivo":"webgl2"}'});
    await aspetta();
    expect((chiamate.lastWhere((c) => c.method == 'web3d_no').arguments as Map)['motivo'], 'webgl2');
    expect((chiamate.lastWhere((c) => c.method == 'web3d_vuoi').arguments as Map)['si'], isFalse);

    // Ma se a non farcela era la scena nel suo processo (Scena3dLontana),
    // l'auto chiede di riprovare con quella dentro l'app: il telefono
    // dimentica il «non va» e la vuole di nuovo, con una regia nuova.
    await dallAuto('chiusa3d');
    await dallAuto('riprova3d');
    await aspetta();
    expect((chiamate.lastWhere((c) => c.method == 'web3d_vuoi').arguments as Map)['si'], isTrue);
    chiamate.clear();
    await dallAuto('dalla3d', {'testo': '{"tipo":"caricata"}'});
    await aspetta();
    expect(chiamate.where((c) => c.method == 'web3d'), isNotEmpty, reason: 'la regia nuova manda opzioni e stile');
    // La scena si chiude: la regia si ferma coi suoi tempi.
    await dallAuto('chiusa3d');
    await aspetta();
  });

  testWidgets("senza il 3D aumentato l'auto non vuole la scena", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester, km: 20);
    await tester.runAsync(() => a.archivio.salvaVistaMappa(VistaMappa.inclinata));
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, canale: canale)..avvia();
    addTearDown(ponte.ferma);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
    expect(chiamate.where((c) => c.method == 'web3d_vuoi' && (c.arguments as Map)['si'] == true), isEmpty);
  });
}
