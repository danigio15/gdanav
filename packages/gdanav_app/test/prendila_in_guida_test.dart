import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Una strada finta lungo [punti], che dura [minuti] e consuma [kwh].
PercorsoCalcolato strada(List<Punto> punti, int minuti, double kwh) {
  final metri = Linea(punti).lunghezzaM;
  return PercorsoCalcolato(
    punti: punti,
    tratti: [Tratto(lunghezzaM: metri, velocitaKmh: metri / (minuti * 60) * 3.6)],
    manovre: const [],
    consumoTomTom: kwh,
  );
}

/// Da [a] a [b], un punto ogni cinquecento metri circa.
List<Punto> dritto(Punto a, Punto b) {
  final n = (distanzaM(a, b) / 500).ceil().clamp(1, 1000);
  return [for (var i = 0; i <= n; i++) Punto(a.lat + (b.lat - a.lat) * i / n, a.lon + (b.lon - a.lon) * i / n)];
}

/* ── «Prendila» in guida toglieva il viaggio dallo schermo ─────────────────
 *
 * La strada proposta, presa, rifaceva il viaggio da capo: lo stato passava
 * da «Calcolo», e in quel momento sul telefono sparivano linea e scheda, e
 * sull'auto restava «Calcolo il percorso…». Adesso si calcola tenendo il
 * viaggio di prima, che lascia il posto al nuovo solo quando c'è; se il
 * calcolo non riesce, resta lui. */
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nord = Luogo(nome: 'Nord', posizione: Punto(42.18, 12));

  /// TomTom finto: la strada di adesso rifatta (4 kWh) e una che gira a
  /// ovest e consuma meno (3,4 kWh, tre minuti in più).
  Future<List<PercorsoCalcolato>> strade(
    List<Punto> davanti, {
    required bool eco,
    ModelloConsumoTomTom? consumo,
    List<Rettangolo> evita = const [],
    OpzioniPercorso opzioni = const OpzioniPercorso(),
  }) async {
    final da = davanti.first, a = davanti.last;
    final adesso = strada(davanti, 10, 4);
    Punto via(double dLon) => Punto((da.lat + a.lat) / 2, da.lon + dLon);
    final giro = [...dritto(da, via(eco ? -0.02 : 0.02)), ...dritto(via(eco ? -0.02 : 0.02), a).skip(1)];
    return [adesso, eco ? strada(giro, 13, 3.4) : strada(giro, 4, 4.3)];
  }

  Future<Ambiente> inGuida(WidgetTester tester, {CostruisciPianificatore? costruisci}) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20, strade: strade, costruisci: costruisci);
    await tester.pumpWidget(a.app());
    a.auto.manuale.imposta(80);
    await tester.pump();
    await tester.runAsync(() => a.viaggio.vaiA(nord));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avvia'));
    await tester.pumpAndSettle();
    a.posizioni.add(const Punto(42.0, 12));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(a.guida.avanzamento, isNotNull);
    await tester.runAsync(a.guida.controllaStrade);
    await tester.pump();
    expect(a.risparmio!.proposta, isNotNull);
    return a;
  }

  testWidgets('«Prendila» in guida non passa da «Calcolo» e mette la strada nuova', (tester) async {
    final a = await inGuida(tester);
    final prima = a.viaggio.stato as ViaggioPronto;
    final stati = <StatoViaggio>[];
    void ascolta() => stati.add(a.viaggio.stato);
    a.viaggio.addListener(ascolta);
    await tester.runAsync(a.guida.prendiStrada);
    a.viaggio.removeListener(ascolta);
    expect(stati.whereType<Calcolo>(), isEmpty, reason: 'in guida il viaggio non deve sparire dallo schermo');
    final dopo = a.viaggio.stato as ViaggioPronto;
    expect(dopo, isNot(same(prima)));
    expect(dopo.viaggio.percorso.punti, isNot(prima.viaggio.percorso.punti));
    expect(a.guida.attiva, isTrue);
    expect(a.guida.ricalcolando, isFalse);
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets('«Prendila» che non si calcola lascia il viaggio e la guida di prima', (tester) async {
    var rotto = false;
    final a = await inGuida(
      tester,
      costruisci: (i, profilo, preferenze, o) {
        if (rotto) throw StateError('il server dei percorsi non risponde');
        return pianificatoreFinto(20)(i, profilo, preferenze, o);
      },
    );
    final prima = a.viaggio.stato as ViaggioPronto;
    final linea = a.guida.strada;
    rotto = true;
    await tester.runAsync(a.guida.prendiStrada);
    expect(a.viaggio.stato, same(prima), reason: 'niente «Errore» né «Calcolo»: resta il viaggio di prima');
    expect(a.guida.strada, same(linea), reason: 'la guida resta sulla strada di prima');
    expect(a.guida.attiva, isTrue);
    expect(a.guida.ricalcolando, isFalse);
    await tester.runAsync(a.guida.ferma);
  });
}
