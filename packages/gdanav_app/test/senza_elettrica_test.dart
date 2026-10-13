import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// «Nel caso non trova vettura elettrica devi mostrare avviso: non trovo
/// auto elettrica configurata, passiamo ad auto termica?»
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nord = Luogo(nome: 'Municipio', posizione: Punto(42.18, 12));

  /// Un'auto scelta in «La tua auto»: l'elettrica è configurata.
  final conAuto = {...impostazioniComplete, 'veicolo': ProfiloVeicolo.esempio.id};

  testWidgets('senza auto elettrica configurata: si propone la termica, e si passa subito', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    expect(a.auto.elettricaConfigurata, isFalse);

    await tester.runAsync(() => a.viaggio.vaiA(nord));
    await tester.pumpAndSettle();
    final errore = a.viaggio.stato as ErroreViaggio;
    expect(errore.senzaBatteria, SenzaBatteria.nessunaElettrica);
    expect(find.text("Non trovo un'auto elettrica configurata. Passiamo all'auto termica?"), findsOneWidget);
    expect(find.byKey(const Key('usa-termica')), findsOneWidget);
    expect(find.byKey(const Key('scrivi-batteria')), findsOneWidget);
    expect(find.byKey(const Key('configura-auto')), findsOneWidget);
    // La termica è la proposta: il tasto pieno.
    expect(find.ancestor(of: find.text('Usa auto termica'), matching: find.byType(FilledButton)), findsOneWidget);
    expect(find.text('Riprova'), findsNothing);

    await tester.tap(find.byKey(const Key('usa-termica')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(a.auto.elettrica, isFalse);
    expect(await tester.runAsync(a.archivio.elettrica), isFalse);
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.termica, isTrue);
    expect(pronto.destinazione.nome, 'Municipio');
    expect(pronto.viaggio.piano, isNull);
    expect(find.byKey(const Key('durata-termica')), findsOneWidget);
  });

  testWidgets("con l'auto elettrica ma senza batteria: prima scriverla, la termica accanto", (tester) async {
    preparaPiattaforma(portachiavi: conAuto);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    expect(a.auto.elettricaConfigurata, isTrue);

    await tester.runAsync(() => a.viaggio.vaiA(nord));
    await tester.pumpAndSettle();
    expect((a.viaggio.stato as ErroreViaggio).senzaBatteria, SenzaBatteria.batteriaIgnota);
    expect(find.textContaining('Non so quanta batteria hai'), findsOneWidget);
    expect(find.ancestor(of: find.text('Scrivi la batteria'), matching: find.byType(FilledButton)), findsOneWidget);
    expect(find.ancestor(of: find.text('Usa auto termica'), matching: find.byType(OutlinedButton)), findsOneWidget);
    expect(find.byKey(const Key('configura-auto')), findsNothing);
    expect(find.text('Riprova'), findsOneWidget);

    // «Scrivi la batteria» apre il foglio della batteria a mano; scritta e
    // chiuso il foglio, il viaggio si rifà con le soste.
    await tester.tap(find.byKey(const Key('scrivi-batteria')));
    await tester.pumpAndSettle();
    expect(find.text('Fonte dati auto'), findsOneWidget);
    a.auto.manuale.imposta(80);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.tapAt(const Offset(20, 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.termica, isFalse);
    expect(pronto.batteriaPartenza, 80);
    expect(a.auto.elettrica, isTrue);
  });

  testWidgets("scelta un'auto in «La tua auto», l'elettrica è configurata", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    expect(a.auto.elettricaConfigurata, isFalse);
    await tester.runAsync(() => a.auto.scegliVeicolo(ProfiloVeicolo.esempio));
    expect(a.auto.elettricaConfigurata, isTrue);
    expect(await tester.runAsync(a.archivio.veicoloScelto), isTrue);
  });

  testWidgets("sull'auto: la proposta della termica col tasto, e dall'auto si passa e si parte", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    const canale = MethodChannel('gdanav/schermo_auto');
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester, km: 20);
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, auto: a.auto, canale: canale)
      ..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();

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

    expect(await dallAuto('vai', {'nome': 'Municipio', 'lat': 42.18, 'lon': 12.0}), isFalse);
    final m = chiamate.lastWhere((c) => c.method == 'messaggio').arguments as Map;
    expect(m['testo'], SenzaBatteria.nessunaElettrica.inAuto);
    expect(m['termica'], isA<String>());
    expect(m['termica_primaria'], isTrue);

    // Una risposta vecchia non vale.
    expect(await dallAuto('termica', {'id': 'termica-0'}), isFalse);
    expect(a.auto.elettrica, isTrue);

    expect(await dallAuto('termica', {'id': m['termica']}), isTrue);
    expect(a.auto.elettrica, isFalse);
    expect((a.viaggio.stato as ViaggioPronto).termica, isTrue);
    expect(a.guida.attiva, isTrue);
    // Il messaggio dopo non ha più la proposta.
    expect((chiamate.lastWhere((c) => c.method == 'messaggio').arguments as Map)['termica'], isNull);
    await tester.runAsync(a.guida.ferma);
  });
}
