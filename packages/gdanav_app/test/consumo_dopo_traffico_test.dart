import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/* ── La batteria stimata si fermava dopo il primo traffico riletto ───────
 *
 * Il consumo del piano si dice all'auto solo per il viaggio di cui sono i
 * chilometri. Il traffico riletto (ogni cinque minuti) mette un viaggio
 * nuovo — stessa strada, stesso piano, tempi nuovi — e il confronto per
 * identità lo scartava: da lì in poi la stima non scendeva più. */
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la batteria stimata continua a scendere dopo il traffico riletto', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(90);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.cambiaOpzioni(const OpzioniPercorso(ricalcoloAutomatico: false)));
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    await tester.pumpAndSettle();
    final pronto = a.viaggio.stato as ViaggioPronto;
    expect(pronto.soloPercorso, isFalse);
    // Il traffico riletto: la stessa strada, tempi nuovi.
    a.viaggio.trafficoFinto = (p) async => p.conTraffico(const []);
    a.guida.avvia();
    await tester.pump();
    final punti = pronto.viaggio.percorso.punti;
    Future<double> vai(int i) async {
      a.posizioni.add(punti[i]);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      return a.guida.batteriaOra!.valore;
    }

    final b0 = await vai(1);
    final b1 = await vai(8);
    expect(b1, lessThan(b0));
    await tester.runAsync(a.guida.aggiornaTraffico);
    expect(a.viaggio.stato, isNot(same(pronto)), reason: 'il traffico ha dato un ViaggioPronto nuovo');
    final b2 = await vai(12);
    final b3 = await vai(19);
    expect(b2, lessThan(b1));
    expect(b3, lessThan(b2));
    expect(b3, lessThan(b1 - 1), reason: 'undici km dopo la batteria deve essere scesa');
    await tester.runAsync(a.guida.ferma);
  });

  /* ── Il traffico di TomTom riletto in guida si sommava ────────────────── */
  testWidgets('in guida il traffico non si rilegge su un percorso che lo ha già (TomTom)', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final base = dritta(20);
    // Un percorso come quelli di TomTom: tempi col traffico e niente
    // percorso senza traffico da cui ripartire.
    final tomtom = PercorsoCalcolato(
      punti: base.punti,
      tratti: base.tratti,
      manovre: base.manovre,
      trafficoVero: true,
      ritardoTraffico: const Duration(minutes: 3),
    );
    final a = await ambiente(
      tester,
      km: 20,
      costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (_) async => tomtom,
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      ),
    );
    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    final pronto = a.viaggio.stato as ViaggioPronto;
    var chiesto = 0;
    a.viaggio.trafficoFinto = (p) async {
      chiesto++;
      return p.conTraffico([Coda(daM: 2000, aM: 8000, ritardo: const Duration(minutes: 10), livello: 3)]);
    };
    expect(await tester.runAsync(a.viaggio.aggiornaTraffico), isNull);
    expect(chiesto, 0);
    expect(a.viaggio.stato, same(pronto));
    expect(pronto.viaggio.percorso.durata, tomtom.durata);
  });
}
