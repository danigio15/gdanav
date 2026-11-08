import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canale = MethodChannel('gdanav/schermo_auto');

  testWidgets("dopo un arrivo senza «Fine», il viaggio nuovo ha la sua linea sull'auto", (tester) async {
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
    a.auto.manuale.imposta(90);

    // Primo viaggio, fino all'arrivo: il riepilogo resta aperto.
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pump();
    a.guida.avvia();
    var punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[3]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    a.posizioni.add(punti.last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(a.guida.attiva, isFalse);
    expect(a.guida.riepilogo, isNotNull);

    // Si riparte verso un'altra meta (come «vai» dall'auto o dal telefono),
    // senza aver chiuso il riepilogo.
    final ok = await tester.runAsync(() => ponte.vaiDallAuto(const Luogo(nome: 'Sud', posizione: Punto(42.0, 12.05))));
    await tester.pump();
    expect(ok, isTrue);
    expect(a.guida.attiva, isTrue);
    punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[3]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();

    // In guida sull'auto: la scheda della manovra c'è...
    expect((chiamate.lastWhere((c) => c.method == 'guida').arguments as Map)['attiva'], isTrue);
    // ...e la linea del percorso deve esserci anche lei.
    final ultima = chiamate.lastWhere(
      (c) => c.method == 'sorgenti' && ((c.arguments as Map)['dati'] as Map).containsKey('gdanav-percorso'),
    );
    final percorso = jsonDecode(((ultima.arguments as Map)['dati'] as Map)['gdanav-percorso'] as String) as Map;
    expect(percorso['features'] as List, hasLength(1), reason: 'linea del percorso vuota sulla mappa dell\'auto');
  });
}
