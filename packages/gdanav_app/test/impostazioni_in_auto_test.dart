import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/mappa/controllo_mappa.dart';
import 'package:gdanav_app/mappa/segnaposto.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/scelte_avvisi.dart';
import 'package:gdanav_app/stato/voce.dart';

import 'aiuti.dart';

/// «Dall'auto devi dare la possibilità di comandare di più le impostazioni:
/// gli avvisi non si possono modificare, idem il simbolo dell'auto.» Le
/// impostazioni arrivano all'auto e tornano indietro come sul telefono.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canale = MethodChannel('gdanav/schermo_auto');

  testWidgets("gli avvisi, il simbolo e il 3D aumentato si scelgono dall'auto", (tester) async {
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

    Map<Object?, Object?> opzioni() => chiamate.lastWhere((c) => c.method == 'opzioni').arguments as Map;

    final a = await ambiente(tester, km: 20);
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, canale: canale)..avvia();
    addTearDown(ponte.ferma);
    await aspetta();

    // All'auto arrivano tutti gli avvisi col loro modo, e i simboli.
    final avvisi = (opzioni()['avvisi'] as List).cast<Map<Object?, Object?>>();
    expect(avvisi.map((x) => x['id']), [for (final av in Avviso.values) av.name]);
    expect(avvisi.firstWhere((x) => x['id'] == 'polizia')['come'], 'voce');
    expect(avvisi.firstWhere((x) => x['id'] == 'polizia')['segnalazione'], isTrue);
    expect(avvisi.firstWhere((x) => x['id'] == 'limite')['solo_voce'], isTrue);
    expect((opzioni()['segnaposti'] as List).length, Segnaposto.values.length);
    expect(opzioni()['segnaposto'], 'freccia');

    // L'autovelox col beep, dall'auto: cambia sul telefono e torna all'auto.
    await dallAuto('scelta', {'avviso': 'autovelox', 'come': 'beep'});
    await aspetta();
    expect(a.guida.avvisi.di(Avviso.autovelox), ComeAvvisare.beep);
    expect((opzioni()['avvisi'] as List).cast<Map<Object?, Object?>>().first['come'], 'beep');

    // L'auto bianca come simbolo.
    await dallAuto('scelta', {'segnaposto': 'autoBianca'});
    await aspetta();
    expect(a.posizione.segnaposto, Segnaposto.autoBianca);
    expect(opzioni()['segnaposto'], 'autoBianca');

    // L'audio, scelto diretto, e la voce più bassa e più lenta.
    expect((opzioni()['audio_modi'] as List).length, ModoAudio.values.length);
    await dallAuto('scelta', {'audio': 'avvisi'});
    await aspetta();
    expect(a.guida.audio, ModoAudio.soloAvvisi);
    expect(opzioni()['audio'], 'avvisi');
    await dallAuto('scelta', {'voce_volume': 'basso', 'voce_velocita': 'lenta'});
    await aspetta();
    expect(regolazioniVoce.value, (VolumeVoce.basso, VelocitaVoce.lenta));
    expect(opzioni()['voce_volume'], 'basso');
    expect(await tester.runAsync(a.archivio.regolazioniDellaVoce), (VolumeVoce.basso, VelocitaVoce.lenta));
    regolazioniVoce.value = (VolumeVoce.alto, VelocitaVoce.normale);

    // Il 3D aumentato acceso dall'auto: vale anche sul telefono.
    await dallAuto('scelta', {'aumentato': true});
    await aspetta();
    expect(Archivio.vistaScelta.value, VistaMappa.aumentata);
    expect(opzioni()['aumentato'], isTrue);
    await dallAuto('scelta', {'aumentato': false});
    await aspetta();
    expect(Archivio.vistaScelta.value, isNot(VistaMappa.aumentata));
  });
}
