import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/auto/richiesta_navigazione.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canale = MethodChannel('gdanav/schermo_auto');

  group('le richieste di navigazione', () {
    test('solo da cercare', () {
      final r = RichiestaNavigazione.leggi('geo:0,0?q=Via+Roma+1%2C+Milano')!;
      expect(r.testo, 'Via Roma 1, Milano');
      expect(r.punto, isNull);
      expect(r.tappa, isFalse);
    });

    test('con le coordinate e il nome', () {
      final r = RichiestaNavigazione.leggi('geo:45.4642,9.19?q=Duomo&mode=d&intent=navigation')!;
      expect(r.punto, const Punto(45.4642, 9.19));
      expect(r.testo, 'Duomo');
    });

    test('le coordinate nella domanda', () {
      final r = RichiestaNavigazione.leggi('geo:0,0?q=45.07,7.68(Mole Antonelliana)')!;
      expect(r.punto, const Punto(45.07, 7.68));
      expect(r.testo, 'Mole Antonelliana');
    });

    test('una tappa', () {
      final r = RichiestaNavigazione.leggi('geo:0,0?q=1600+Amphitheatre+parkway&mode=b&intent=add_a_stop')!;
      expect(r.tappa, isTrue);
      expect(r.testo, '1600 Amphitheatre parkway');
    });

    test('google.navigation', () {
      final r = RichiestaNavigazione.leggi('google.navigation:q=Stazione+Centrale&mode=d')!;
      expect(r.testo, 'Stazione Centrale');
    });

    test('niente da fare', () {
      expect(RichiestaNavigazione.leggi('geo:0,0'), isNull);
      expect(RichiestaNavigazione.leggi('https://example.com'), isNull);
      expect(RichiestaNavigazione.leggi('geo:0,0?q='), isNull);
    });
  });

  testWidgets("«Ok Google, naviga verso Bologna»: si cerca, si calcola e la guida parte", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));

    final a = await ambiente(tester, km: 20);
    a.auto.manuale.imposta(90);
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, canale: canale)..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();

    Future<void> dallAuto(String uri) async {
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(MethodCall('naviga', {'uri': uri})),
          (_) {},
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
    }

    await dallAuto('geo:0,0?q=bologna&mode=d');
    expect(a.guida.attiva, isTrue);
    expect(a.viaggio.destinazione?.nome, 'Bologna');

    // Con le coordinate si parte verso quel punto, anche in guida.
    await dallAuto('geo:42.18,12?q=Nord');
    expect(a.guida.attiva, isTrue);
    expect((a.viaggio.stato as ViaggioPronto).destinazione.nome, 'Nord');

    // Una richiesta che non si capisce: lo si dice sull'auto.
    await dallAuto('geo:0,0');
    expect(
      (chiamate.lastWhere((c) => c.method == 'messaggio').arguments as Map)['testo'],
      'Non ho capito dove andare.',
    );
  });
}
