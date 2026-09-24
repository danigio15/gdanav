import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/auto/ponte_auto.dart';
import 'package:gdanav/stato/gestore_luoghi.dart';
import 'package:gdanav/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canale = MethodChannel('gdanav/schermo_auto');

  testWidgets("lo schermo dell'auto riceve stile, viaggio, guida e segnaposto; «Fine» dall'auto ferma", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));

    final a = await ambiente(tester, km: 20);
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, canale: canale)..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();
    final stili = chiamate.firstWhere((c) => c.method == 'stili').arguments as Map;
    expect((jsonDecode(stili['chiaro'] as String) as Map)['name'], 'gdanav chiaro');
    expect((jsonDecode(stili['scuro'] as String) as Map)['name'], 'gdanav scuro');

    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pump();
    final sorgenti = chiamate.lastWhere((c) => c.method == 'sorgenti').arguments as Map;
    final percorso = jsonDecode((sorgenti['dati'] as Map)['gdanav-percorso'] as String) as Map;
    expect((percorso['features'] as List), hasLength(1));

    a.guida.avvia();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[3]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    final guida = chiamate.lastWhere((c) => c.method == 'guida').arguments as Map;
    expect(guida['attiva'], isTrue);
    expect(guida['destinazione'], 'Nord');
    expect(guida['restanti'] as double, lessThan(Linea(punti).lunghezzaM));
    final pos = chiamate.lastWhere((c) => c.method == 'posizione').arguments as Map;
    expect(pos['lat'], isNotNull);
    final io = chiamate.lastWhere(
      (c) => c.method == 'sorgenti' && ((c.arguments as Map)['dati'] as Map).containsKey('gdanav-io'),
    );
    expect(((io.arguments as Map)['dati'] as Map)['gdanav-io'], contains('auto_blu'));

    // L'auto preme «Fine».
    await tester.runAsync(
      () => messaggero.handlePlatformMessage(
        'gdanav/schermo_auto',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('ferma')),
        (_) {},
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(a.guida.attiva, isFalse);
    expect((chiamate.lastWhere((c) => c.method == 'guida').arguments as Map)['attiva'], isFalse);
  });

  testWidgets("dall'auto si cerca, si sceglie Casa o un risultato e la guida parte da sola", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));

    final a = await ambiente(tester, km: 20);
    final luoghi = GestoreLuoghi(a.archivio);
    await tester.runAsync(luoghi.carica);
    await tester.runAsync(
      () => luoghi.salva(Preferito(TipoPreferito.casa, const Luogo(nome: 'Via Roma 1', posizione: Punto(42.1, 12)))),
    );
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, luoghi: luoghi, canale: canale)
      ..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();
    final elenco = (chiamate.lastWhere((c) => c.method == 'luoghi').arguments as Map)['elenco'] as List;
    expect(elenco.first, containsPair('etichetta', 'Casa'));
    expect(elenco.first, containsPair('tipo', 'casa'));

    Future<Object?> dallAuto(String metodo, Object? argomenti) async {
      Object? risposta;
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(MethodCall(metodo, argomenti)),
          (dati) => risposta = dati == null ? null : const StandardMethodCodec().decodeEnvelope(dati),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      return risposta;
    }

    final trovati = await dallAuto('cerca', {'testo': 'bologna'}) as List;
    expect(trovati.single, containsPair('nome', 'Bologna'));

    a.auto.manuale.imposta(90);
    await dallAuto('vai', elenco.first);
    expect(a.viaggio.destinazione!.nome, 'Via Roma 1');
    expect(a.guida.attiva, isTrue);
    expect((chiamate.lastWhere((c) => c.method == 'guida').arguments as Map)['attiva'], isTrue);
    expect(
      chiamate.where((c) => c.method == 'messaggio').map((c) => (c.arguments as Map)['testo']),
      contains('Calcolo il percorso per Via Roma 1…'),
    );

    await dallAuto('ferma', null);
    expect(a.guida.attiva, isFalse);
    expect(a.viaggio.stato, isA<NessunViaggio>());
  });

  testWidgets('senza Android Auto si tace', (tester) async {
    preparaPiattaforma();
    final a = await ambiente(tester);
    // Nessun gestore sul canale: MissingPluginException, e basta.
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione)..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();
  });
}
