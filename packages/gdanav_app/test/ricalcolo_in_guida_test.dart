import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Una strada dritta verso nord di [km] che parte da [da].
PercorsoCalcolato dallaPosizione(Punto da, int km) {
  final punti = [for (var i = 0; i <= km; i++) Punto(da.lat + i * 0.009, da.lon)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 120),
    ],
    manovre: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /* ── Dopo un ricalcolo la freccia saltava avanti di chilometri ───────────
   *
   * La guida nuova arrivava, l'avanzamento restava quello del percorso
   * vecchio (dieci chilometri fatti) e la stima della posizione li portava
   * sul nuovo, che parte da dove si è: fino alla lettura dopo, telefono e
   * auto disegnavano la freccia dieci chilometri più avanti. */
  testWidgets('dopo un ricalcolo la freccia non salta in avanti sul percorso nuovo', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(
      tester,
      km: 20,
      costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (t) async => dallaPosizione(t.first, 20),
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      ),
    );
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    a.guida.avvia();
    await tester.pump();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    // In marcia a 50 km/h, al km 10.
    final qui = PuntoInMoto(punti[10].lat, punti[10].lon, rotta: 0, velocitaMs: 14, alle: DateTime.now());
    a.posizioni.add(qui);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(a.guida.avanzamento!.percorsiM, greaterThan(9000));

    unawaited(a.guida.ricalcolaOra());
    for (var i = 0; i < 40 && (a.guida.ricalcolando || i == 0); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    final nuovo = (a.viaggio.stato as ViaggioPronto).viaggio.percorso;
    expect(nuovo.punti.first, qui, reason: 'il percorso nuovo parte da dove si è');
    // Nessuna posizione nuova ancora: l'avanzamento è già quello del nuovo.
    expect(a.guida.avanzamento!.percorsiM, lessThan(100));
    final dopo = a.guida.posizioneStimata()!;
    expect(distanzaM(dopo.punto, qui), lessThan(100));
    await tester.runAsync(a.guida.ferma);
  });

  /* ── «Passa da» in guida senza togliere il viaggio ─────────────────────
   *
   * Un distributore scelto in guida (anche a voce, «aggiungi una tappa»)
   * rifaceva il viaggio da capo passando da «Calcolo»: la linea e la scheda
   * sparivano, e sull'auto restava «Calcolo il percorso…». */
  testWidgets('«passa da» in guida non passa da «Calcolo»', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    final prima = a.viaggio.stato as ViaggioPronto;
    a.guida.avvia();
    a.posizioni.add(prima.viaggio.percorso.punti[1]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

    final stati = <StatoViaggio>[];
    void ascolta() => stati.add(a.viaggio.stato);
    a.viaggio.addListener(ascolta);
    const eni = Luogo(nome: 'Eni Nord', posizione: Punto(42.05, 12.001));
    await tester.runAsync(() => a.guida.passaDa(eni));
    a.viaggio.removeListener(ascolta);
    expect(stati.whereType<Calcolo>(), isEmpty);
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    expect(a.viaggio.stato, isNot(same(prima)), reason: 'il viaggio nuovo è arrivato');
    expect(a.viaggio.tappa, eni);
    expect(a.guida.attiva, isTrue);
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets('«passa da» che non si calcola lascia la guida di prima, senza la tappa', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    var rotto = false;
    final a = await ambiente(
      tester,
      km: 20,
      costruisci: (i, profilo, preferenze, o) {
        if (rotto) throw StateError('il server dei percorsi non risponde');
        return pianificatoreFinto(20)(i, profilo, preferenze, o);
      },
    );
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    final prima = a.viaggio.stato as ViaggioPronto;
    a.guida.avvia();
    a.posizioni.add(prima.viaggio.percorso.punti[1]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

    rotto = true;
    await tester.runAsync(() => a.guida.passaDa(const Luogo(nome: 'Eni Nord', posizione: Punto(42.05, 12.001))));
    expect(a.viaggio.stato, same(prima), reason: 'niente errore sullo schermo: si continua sulla strada di prima');
    expect(a.viaggio.tappa, isNull);
    expect(a.guida.attiva, isTrue);
    expect(a.guida.ricalcolando, isFalse);
    await tester.runAsync(a.guida.ferma);
  });

  /* ── La proposta di ricalcolo di un viaggio non vale per il prossimo ── */
  testWidgets('la proposta di ricalcolo si chiude alla fine della guida e non torna al viaggio dopo', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    a.guida.avvia();
    a.guida.proposta = 'Consumi più del previsto: ricalcolo le soste?';
    await tester.runAsync(a.guida.ferma);
    expect(a.guida.proposta, isNull);

    a.guida.proposta = 'Consumi meno del previsto: ricalcolo le soste?';
    a.guida.avvia();
    expect(a.guida.proposta, isNull);
    await tester.runAsync(a.guida.ferma);
  });
}
