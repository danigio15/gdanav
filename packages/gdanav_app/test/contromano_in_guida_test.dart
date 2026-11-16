import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/gestore_guida.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/* ─── Mai contromano, in guida ─────────────────────────────────────────────
 *
 * Il percorso del fornitore va dritto fino a un vertice e scende su un senso
 * unico al contrario; il ramo giusto si stacca prima. Strade inventate,
 * in metri attorno a un'origine qualunque. */

const _origine = Punto(42, 12);
const _mpg = 111195.08;

Punto _a(double est, double nord) =>
    Punto(_origine.lat + nord / _mpg, _origine.lon + est / (_mpg * math.cos(_origine.lat * math.pi / 180)));

List<Punto> _fitta(List<(double, double)> v, {double passo = 8, (double, double) sposta = (0, 0)}) {
  final out = <Punto>[];
  for (var i = 1; i < v.length; i++) {
    final (ax, ay) = v[i - 1];
    final (bx, by) = v[i];
    final n = math.max(1, (math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) / passo).round());
    for (var k = 0; k < n; k++) {
      out.add(_a(ax + (bx - ax) * k / n + sposta.$1, ay + (by - ay) * k / n + sposta.$2));
    }
  }
  out.add(_a(v.last.$1 + sposta.$1, v.last.$2 + sposta.$2));
  return out;
}

TrattoStrada _strada(List<(double, double)> v, {int senso = 0}) =>
    TrattoStrada([for (final (x, y) in v) _a(x, y)], senso: senso, classe: 'minor');

/// Si va verso est; in V il fornitore gira a destra su un senso unico che
/// va verso nord (vietato); il ramo giusto si stacca in W, cento metri prima.
const _w = (-100.0, 0.0), _v = (0.0, 0.0), _n = (0.0, -60.0);
final _strade = [
  _strada([(-600, 0), _w]),
  _strada([_w, _v, (400, 0)]),
  _strada([_w, (-100, -60), _n], senso: 1),
  _strada([_n, _v], senso: 1),
  _strada([_n, (0, -700)]),
];

PercorsoCalcolato _delFornitore() {
  final punti = _fitta([(-600, 0), _w, _v, _n, (0, -700)], sposta: (0, 6));
  final c = Linea(punti).cumulate;
  final iV = punti.indexWhere((p) => distanzaM(p, _a(0, 6)) < 1);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [Tratto(lunghezzaM: c.last, velocitaKmh: 40)],
    limiti: [for (var i = 0; i < punti.length - 1; i++) 50],
    manovre: [
      Manovra(istruzione: 'Parti', voce: 'Parti', lunghezzaM: c[iV], secondi: c[iV] / 11, inizio: 0, tipo: 1),
      Manovra(
        istruzione: 'Gira a destra in Via Sud',
        voce: 'Gira a destra in Via Sud',
        lunghezzaM: c.last - c[iV],
        secondi: (c.last - c[iV]) / 11,
        inizio: iV,
        tipo: 10,
        strada: 'Via Sud',
      ),
      Manovra(istruzione: 'Arrivo', voce: '', lunghezzaM: 0, secondi: 0, inizio: punti.length - 1, tipo: 4),
    ],
  );
}

CostruisciPianificatore _pianificatore() =>
    (_, profilo, preferenze, _) => PianificatoreViaggio(
      percorsi: (_) async => _delFornitore(),
      colonnine: ColonnineFinte(),
      profilo: profilo,
      preferenze: preferenze,
    );

/// Si guida davvero sul ramo giusto: da ovest fino a W, giù, poi a sud.
final _sulRamoGiusto = _fitta([(-600, 0), _w, (-100, -60), _n, (0, -400)], passo: 10);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(Ambiente, GestoreGuida, VoceFinta)> prepara(
    WidgetTester tester,
    Future<List<TrattoStrada>> Function(List<Punto>) strade,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 2, costruisci: _pianificatore());
    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(Luogo(nome: 'Sud', posizione: _a(0, -700))));
    final voce = VoceFinta();
    final guida = GestoreGuida(
      viaggio: a.viaggio,
      auto: a.auto,
      posizioni: () => a.posizioni.stream,
      voce: voce,
      strade: strade,
      stimaInGalleria: false,
    );
    addTearDown(guida.dispose);
    return (a, guida, voce);
  }

  Future<void> guida(WidgetTester tester, Ambiente a, Iterable<Punto> punti) async {
    for (final q in punti) {
      a.posizioni.add(q);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    }
  }

  testWidgets('il percorso si rifà sul ramo giusto prima di arrivarci: freccia, distanza e voce', (tester) async {
    final (a, g, voce) = await prepara(tester, (_) async => _strade);
    final prima = (a.viaggio.stato as ViaggioPronto).viaggio.percorso;
    g.avvia();
    await guida(tester, a, _sulRamoGiusto.take(3));
    final dopo = (a.viaggio.stato as ViaggioPronto).viaggio.percorso;
    expect(identical(dopo, prima), isFalse, reason: 'il percorso contromano va rifatto');
    // Due svolte vere a destra (in W e in N) al posto di quella in V.
    expect(dopo.manovre.map((m) => m.tipo), [1, 10, 10, 4]);
    expect(dopo.manovre.where((m) => distanzaM(dopo.punti[m.inizio], _a(0, 0)) < 15), isEmpty);
    expect(dopo.manovre[2].istruzione, 'Gira a destra in Via Sud');
    expect(distanzaM(dopo.punti[dopo.manovre[2].inizio], _a(0, -60)), lessThan(12));
    // La prossima manovra (quella che vedono telefono, auto e 3D) è al bivio W.
    final prossima = g.avanzamento!.prossima!;
    expect(prossima, same(dopo.manovre[1]));
    final lungo = Linea(dopo.punti).cumulate[prossima.inizio];
    expect(distanzaM(dopo.punti[prossima.inizio], _a(-100, 0)), lessThan(12));
    expect(g.avanzamento!.allaProssimaM, closeTo(lungo - g.avanzamento!.percorsiM, 1));
    // Fino in fondo sul ramo giusto: mai fuori percorso, mai «Ricalcolo».
    await guida(tester, a, _sulRamoGiusto.skip(3));
    expect(voce.frasi, isNot(contains('Ricalcolo il percorso.')));
    expect(voce.frasi.where((f) => f.contains('Via Sud')), isNotEmpty);
    expect(voce.frasi.where((f) => f.contains('Gira a destra in Via Sud') && f.contains('Tra')), isEmpty);
  });

  testWidgets('se le strade non sono arrivate in tempo e si prende il ramo giusto, niente ricalcolo', (tester) async {
    var chiamate = 0;
    final (a, g, voce) = await prepara(tester, (_) async => chiamate++ == 0 ? const <TrattoStrada>[] : _strade);
    final prima = (a.viaggio.stato as ViaggioPronto).viaggio.percorso;
    g.avvia();
    await guida(tester, a, _sulRamoGiusto);
    expect(chiamate, greaterThanOrEqualTo(2));
    expect(identical((a.viaggio.stato as ViaggioPronto).viaggio.percorso, prima), isFalse);
    expect(voce.frasi, isNot(contains('Ricalcolo il percorso.')));
  });

  testWidgets('senza strade da guardare la guida fa come prima', (tester) async {
    final (a, g, _) = await prepara(tester, (_) async => const <TrattoStrada>[]);
    final prima = (a.viaggio.stato as ViaggioPronto).viaggio.percorso;
    g.avvia();
    await guida(tester, a, _sulRamoGiusto.take(5));
    expect(identical((a.viaggio.stato as ViaggioPronto).viaggio.percorso, prima), isTrue);
  });
}
