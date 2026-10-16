import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/sorgenti/sorgente_gdahome.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Un giro in città: cinque chilometri a 40 km/h, dove il modello consuma
/// poco più di 7 kWh/100 km.
CostruisciPianificatore _inCitta() =>
    (_, profilo, preferenze, _) => PianificatoreViaggio(
      percorsi: (_) async {
        final punti = [for (var i = 0; i <= 5; i++) Punto(42 + i * 0.009, 12)];
        final linea = Linea(punti);
        return PercorsoCalcolato(
          punti: punti,
          tratti: [
            for (var i = 1; i < punti.length; i++)
              Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 40),
          ],
          manovre: const [],
        );
      },
      colonnine: ColonnineFinte(),
      profilo: profilo,
      preferenze: preferenze,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la lettura vecchia si porta alla batteria di adesso col rapporto dell\'auto', () {
    final ora = DateTime(2026, 10, 8, 12);
    final vecchia = StatoAuto(
      sorgente: TipoSorgente.homeAssistant,
      letto: ora.subtract(const Duration(hours: 2)),
      batteria: 60,
      autonomiaKm: 250,
    );
    // 250 km al 60%, e adesso il 54%: 225 km.
    expect(autonomiaDellAuto(vecchia, batteriaAdesso: 54, ora: ora), closeTo(225, 1e-9));
    // Senza una batteria di adesso resta com'è.
    expect(autonomiaDellAuto(vecchia, ora: ora), 250);
    // Fresca, com'è.
    expect(autonomiaDellAuto(vecchia, batteriaAdesso: 54, ora: vecchia.letto.add(const Duration(minutes: 5))), 250);
    // La stima e la batteria scritta a mano non sono l'auto; e senza autonomia niente.
    for (final s in [TipoSorgente.stima, TipoSorgente.manuale]) {
      expect(
        autonomiaDellAuto(
          StatoAuto(sorgente: s, letto: ora, batteria: 60, autonomiaKm: 250),
          ora: ora,
        ),
        isNull,
      );
    }
    expect(
      autonomiaDellAuto(
        StatoAuto(sorgente: TipoSorgente.gdahome, letto: ora, batteria: 60),
        ora: ora,
      ),
      isNull,
    );
  });

  testWidgets('auto ferma da ore, 53% e 227 km dalla casa: in guida e sull\'auto 227 km, non la stima del piano', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    const canale = MethodChannel('gdanav/schermo_auto');
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
    // Home Assistant data la lettura con l'ultimo cambio: ferma in garage,
    // tre ore fa.
    a.auto.arbitro.registra(
      StatoAuto(
        sorgente: TipoSorgente.gdahome,
        letto: DateTime.now().subtract(const Duration(hours: 3)),
        batteria: 53,
        autonomiaKm: 227,
      ),
    );
    await tester.runAsync(() => a.auto.cambiaModalita(a.auto.modalita));
    expect(a.auto.stato?.batteria, 53);
    // Sulla schermata principale.
    expect(a.auto.autonomiaKm(), closeTo(227, 1e-9));

    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    a.guida.avvia();
    final autonomia = a.guida.autonomiaOra!;
    expect(autonomia.km, closeTo(227, 0.5));
    expect(autonomia.dallAuto, isTrue);

    // Andando, la batteria del piano scende e l'autonomia dell'auto con lei,
    // coi suoi chilometri per punto.
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[15]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    final adesso = a.guida.batteriaOra!;
    expect(adesso.misurata, isFalse);
    expect(adesso.valore, lessThan(53));
    expect(a.guida.autonomiaOra!.km, closeTo(227 * adesso.valore / 53, 0.01));

    // Lo schermo dell'auto dice lo stesso: col segnaposto arriva il cruscotto.
    final cruscotto = chiamate.lastWhere((c) => c.method == 'cruscotto').arguments as Map;
    expect(cruscotto['autonomia_km'], closeTo(a.guida.autonomiaOra!.km, 0.01));
    expect(cruscotto['autonomia_auto'], isTrue);
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets('senza l\'autonomia dell\'auto, un giro in città da 7 kWh/100 km non promette troppo', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, costruisci: _inCitta());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Centro', posizione: Punto(42.045, 12))));
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    a.guida.avvia();

    final piano = a.guida.consumoKwh100!;
    final riferimento = a.auto.consumoDiRiferimentoKwh100();
    // Il piano conta le partenze e le frenate (non più 6-8 kWh/100 km), ma
    // in città resta sotto il riferimento a 90 km/h.
    expect(piano, inInclusiveRange(8.5, 12));
    expect(piano, lessThan(riferimento));
    // Ma l'autonomia si fa col riferimento del modello, non con lui.
    final autonomia = a.guida.autonomiaOra!;
    expect(autonomia.dallAuto, isFalse);
    expect(autonomia.km, closeTo(80 / 100 * a.auto.veicolo.capacitaUtileKwh / riferimento * 100, 0.5));
    expect(autonomia.km, lessThan(80 / 100 * a.auto.veicolo.capacitaUtileKwh / piano * 100));
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets('dal campo: l\'auto dice 23% e 95 km, e in guida (telefono e auto) si vede 23% e 95 km, non la stima', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final chiamate = <MethodCall>[];
    const canale = MethodChannel('gdanav/schermo_auto');
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final casa = SorgenteGdahome();
    addTearDown(casa.dispose);
    final a = await ambiente(tester, km: 20, gdahome: casa);
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, auto: a.auto, canale: canale)
      ..avvia();
    addTearDown(ponte.ferma);
    StatoAuto daCasa(double batteria, double km, Duration fa) => StatoAuto(
      sorgente: TipoSorgente.gdahome,
      letto: DateTime.now().subtract(fa),
      batteria: batteria,
      autonomiaKm: km,
    );

    // Prima di partire: 25% e 103 km, datati mezz'ora fa.
    casa.manda(daCasa(25, 103, const Duration(minutes: 30)));
    await tester.pump();
    expect(a.auto.stato?.batteria, 25);
    // Qui si guarda la batteria, non le soste: niente ricalcoli a metà prova.
    await tester.runAsync(() => a.viaggio.cambiaOpzioni(const OpzioniPercorso(ricalcoloAutomatico: false)));
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    a.guida.avvia();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[15]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    // Fra due letture: la stima, dalla lettura vera, coi km dell'auto.
    final stimata = a.guida.batteriaOra!;
    expect(stimata.misurata, isFalse);
    expect(stimata.valore, lessThan(25));
    expect(a.guida.autonomiaOra!.km, closeTo(103 * stimata.valore / 25, 0.01));

    // Arriva il dato nuovo dalla casa: Home Assistant lo data col suo ultimo
    // cambio, prima della partenza e più di dieci minuti fa.
    casa.manda(daCasa(23, 95, const Duration(minutes: 12)));
    await tester.pump();
    a.posizioni.add(punti[16]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    final adesso = a.guida.batteriaOra!;
    expect(adesso.misurata, isTrue);
    expect(adesso.valore, 23);
    expect(a.guida.autonomiaOra!.km, 95);
    expect(a.guida.autonomiaOra!.dallAuto, isTrue);
    // Lo stesso sullo schermo dell'auto, senza il segno della stima.
    final cruscotto = chiamate.lastWhere((c) => c.method == 'cruscotto').arguments as Map;
    expect(cruscotto['batteria'], 23);
    expect(cruscotto['autonomia_km'], 95);
    expect(cruscotto['batteria_stimata'], isFalse);
    await tester.runAsync(a.guida.ferma);
  });
}
