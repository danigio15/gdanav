import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/stato/gestore_luoghi.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/prova_di_guida.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canale = MethodChannel('gdanav/schermo_auto');

  test('la prova percorre il percorso al posto del GPS, e finita torna il GPS', () async {
    final prova = ProvaDiGuida(passo: const Duration(milliseconds: 5), acceleratore: 20);
    addTearDown(prova.chiudi);
    final vere = StreamController<Lettura>.broadcast();
    addTearDown(vere.close);
    final letture = <Lettura>[];
    final iscrizione = prova.letture(() => vere.stream)().listen(letture.add);
    addTearDown(iscrizione.cancel);

    // Un chilometro verso est, a 90 km/h.
    const percorso = PercorsoCalcolato(
      punti: [Punto(45, 9), Punto(45, 9.0127)],
      tratti: [Tratto(lunghezzaM: 1000, velocitaKmh: 90)],
      manovre: [],
    );
    prova.percorri(percorso);
    vere.add(const Lettura(Punto(10, 10)));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(prova.attiva, isTrue);
    expect(letture, isNotEmpty);
    // Il GPS vero tace durante la prova.
    expect(letture.where((l) => l.punto.lat == 10), isEmpty);
    // Si va verso est, alla velocità del tratto.
    expect(letture.last.punto.lon, greaterThan(letture.first.punto.lon));
    expect(letture.first.rotta, closeTo(90, 1));
    expect(letture.first.velocitaMs, closeTo(25, 0.1));

    prova.ferma();
    vere.add(const Lettura(Punto(10, 10)));
    await Future<void>.delayed(Duration.zero);
    expect(letture.last.punto.lat, 10);
  });

  test('il punto a metà strada', () {
    final linea = Linea(const [Punto(45, 9), Punto(45, 9.01), Punto(45.01, 9.01)]);
    final (p, rotta) = ProvaDiGuida.puntoA(linea, linea.cumulate[1] + (linea.cumulate[2] - linea.cumulate[1]) / 2);
    expect(p.lon, closeTo(9.01, 1e-9));
    expect(p.lat, closeTo(45.005, 1e-6));
    expect(rotta, closeTo(0, 1));
  });

  testWidgets("la prova di guida di Android Auto parte verso Casa, si percorre da sola e arriva", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));

    final prova = ProvaDiGuida(passo: const Duration(milliseconds: 10), acceleratore: 400);
    addTearDown(prova.chiudi);
    final a = await ambiente(tester, km: 20, prova: prova);
    a.auto.manuale.imposta(90);
    final luoghi = GestoreLuoghi(a.archivio);
    await tester.runAsync(luoghi.carica);
    await tester.runAsync(
      () => luoghi.salva(Preferito(TipoPreferito.casa, const Luogo(nome: 'Via Roma 1', posizione: Punto(42.18, 12)))),
    );
    final ponte = PonteAuto(
      viaggio: a.viaggio,
      guida: a.guida,
      posizione: a.posizione,
      luoghi: luoghi,
      prova: prova,
      canale: canale,
    )..avvia();
    addTearDown(ponte.ferma);
    a.posizione.avvia();
    await tester.pump();

    // Android Auto accende la prova (onAutoDriveEnabled): si parte verso Casa.
    await tester.runAsync(
      () => messaggero.handlePlatformMessage(
        'gdanav/schermo_auto',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('prova_guida')),
        (_) {},
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    expect(a.guida.attiva, isTrue);
    expect(prova.attiva, isTrue);
    final guida = chiamate.lastWhere((c) => c.method == 'guida').arguments as Map;
    expect(guida['destinazione'], 'Via Roma 1');
    // La posizione finta avanza: la guida conta i metri fatti, il
    // tachimetro la velocità.
    expect(a.guida.avanzamento?.percorsiM, greaterThan(0));
    expect(a.posizione.velocitaKmh, greaterThan(20));

    // Finita la strada si arriva, la guida si ferma e la prova con lei.
    for (var i = 0; i < 60 && a.guida.attiva; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    expect(a.guida.attiva, isFalse);
    expect(prova.attiva, isFalse);
    expect((chiamate.lastWhere((c) => c.method == 'guida').arguments as Map)['attiva'], isFalse);
  });
}
