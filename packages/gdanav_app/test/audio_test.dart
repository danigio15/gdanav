import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_guida.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/voce.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// L'audio della guida a tre stati: la voce di guida e gli avvisi si
/// spengono separati.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('il tasto gira: Tutto, Solo avvisi, Silenzio, e di nuovo Tutto', () {
    expect(ModoAudio.tutto.dopo, ModoAudio.soloAvvisi);
    expect(ModoAudio.soloAvvisi.dopo, ModoAudio.silenzio);
    expect(ModoAudio.silenzio.dopo, ModoAudio.tutto);
    expect([for (final m in ModoAudio.values) m.senzaGuida], [false, true, true]);
    expect([for (final m in ModoAudio.values) m.senzaAvvisi], [false, false, true]);
  });

  test('chi aveva silenziato la voce la ritrova spenta, con gli avvisi accesi', () async {
    // L'archivio di prima conosceva solo «voce_muta».
    preparaPiattaforma(portachiavi: {'voce_muta': 'sì'});
    final archivio = Archivio();
    expect(await archivio.modoAudio(), ModoAudio.soloAvvisi);

    await archivio.salvaModoAudio(ModoAudio.silenzio);
    expect(await archivio.modoAudio(), ModoAudio.silenzio);
    expect(await archivio.voceMuta(), isTrue);

    await archivio.salvaModoAudio(ModoAudio.tutto);
    expect(await archivio.modoAudio(), ModoAudio.tutto);
    expect(await archivio.voceMuta(), isFalse);

    preparaPiattaforma();
    expect(await Archivio().modoAudio(), ModoAudio.tutto);
  });

  Future<Ambiente> inGuida(WidgetTester tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    return a;
  }

  testWidgets('con «Solo avvisi» le manovre tacciono e gli avvisi si sentono; col silenzio niente', (tester) async {
    final a = await inGuida(tester);
    a.guida.avvia();
    a.guida.alternaVoce();
    expect(a.guida.audio, ModoAudio.soloAvvisi);
    final prima = a.voce.frasi.length;
    a.guida.annuncia('Traffico più avanti.');
    a.guida.annunciaAvviso('Autovelox tra 300 metri.');
    expect(a.voce.frasi.skip(prima), ['Autovelox tra 300 metri.']);

    a.guida.alternaVoce();
    expect(a.guida.audio, ModoAudio.silenzio);
    a.guida.annunciaAvviso('Autovelox tra 300 metri.');
    expect(a.voce.frasi.length, prima + 1);
    // Si ricorda: la prossima guida parte in silenzio.
    expect(await tester.runAsync(a.archivio.modoAudio), ModoAudio.silenzio);
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets('oltre il limite per più di tre secondi lo si dice, una volta per tratto, anche con «Solo avvisi»', (
    tester,
  ) async {
    final a = await inGuida(tester);
    var ora = DateTime(2026, 10, 9, 10);
    final posizioni = StreamController<Punto>.broadcast();
    addTearDown(posizioni.close);
    final guida = GestoreGuida(
      viaggio: a.viaggio,
      auto: a.auto,
      posizioni: () => posizioni.stream,
      voce: a.voce,
      audioIniziale: ModoAudio.soloAvvisi,
      orologio: () => ora,
    );
    addTearDown(guida.dispose);
    guida.avvia();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    // Il primo tratto è a 50 all'ora; si va a 72 (20 m/s).
    Future<void> lettura(Punto p, double ms) async {
      posizioni.add(PuntoInMoto(p.lat, p.lon, velocitaMs: ms, rotta: 0));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }

    int dette() => a.voce.frasi.where((f) => f.contains('limite è 50')).length;
    final inMezzo = Punto((punti[1].lat + punti[2].lat) / 2, punti[1].lon);
    await lettura(inMezzo, 20);
    expect(guida.avanzamento?.limiteKmh, 50);
    ora = ora.add(const Duration(seconds: 2));
    await lettura(inMezzo, 20);
    expect(dette(), 0, reason: 'un sorpasso non è un avviso');
    ora = ora.add(const Duration(seconds: 2));
    await lettura(inMezzo, 20);
    expect(dette(), 1);
    // Sempre oltre, sempre sullo stesso tratto: non lo si ripete.
    ora = ora.add(const Duration(seconds: 10));
    await lettura(inMezzo, 20);
    expect(dette(), 1);
    await tester.runAsync(guida.ferma);
  });
}
