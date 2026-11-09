import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/* «Se calcoli il percorso e io cambio strada, dopo il ricalcolo la linea
 * riparte da quel punto e non si vede il percorso già fatto.» La strada fatta
 * resta: una traccia da quando parte la guida, che il ricalcolo non tocca. */
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canale = MethodChannel('gdanav/schermo_auto');

  test('lo stile ha la strada fatta, sotto il percorso', () {
    final strati = (stileMappa(scuro: false)['layers']! as List).cast<Map>();
    final fatto = strati.indexWhere((l) => l['id'] == 'percorso-fatto');
    final percorso = strati.indexWhere((l) => l['id'] == 'percorso-alone');
    expect(fatto, greaterThanOrEqualTo(0));
    expect(fatto, lessThan(percorso));
    expect(strati[fatto]['source'], sorgenteFatto);
  });

  testWidgets('la strada fatta resta dopo un ricalcolo, e arriva all\'auto', (tester) async {
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
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pump();
    a.guida.avvia();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    for (final i in [1, 3, 5, 7]) {
      a.posizioni.add(punti[i]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await tester.pump();
    final fatti = a.guida.traccia.length;
    expect(fatti, greaterThanOrEqualTo(3));

    // Si cambia strada: un punto lontano dal percorso, e il ricalcolo.
    a.posizioni.add(Punto(punti[7].lat, punti[7].lon + 0.01));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.runAsync(() => a.guida.ricalcolaOra());
    await tester.pump();
    // Il percorso nuovo parte da dove si è; la strada fatta c'è ancora tutta.
    expect(a.guida.traccia.length, greaterThan(fatti));
    expect(a.guida.traccia.first, punti[1]);

    final dati = datiTraccia(a.guida.traccia);
    final linea = ((dati['features']! as List).single as Map)['geometry'] as Map;
    expect((linea['coordinates'] as List).length, a.guida.traccia.length);

    // L'auto la riceve, nella sua sorgente.
    final mandata = chiamate.lastWhere(
      (c) => c.method == 'sorgenti' && ((c.arguments as Map)['dati'] as Map).containsKey(sorgenteFatto),
    );
    final json = jsonDecode(((mandata.arguments as Map)['dati'] as Map)[sorgenteFatto] as String) as Map;
    expect((json['features'] as List), isNotEmpty);

    // Fine: la strada fatta se ne va.
    await tester.runAsync(() => a.guida.ferma());
    expect(a.guida.traccia, isEmpty);
  });
}
