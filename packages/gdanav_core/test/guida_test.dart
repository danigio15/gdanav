import 'dart:convert';
import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  // Il percorso vero di Utrecht (Valhalla 3.9): 14 manovre, 5 km.
  final percorso = PercorsoCalcolato.daValhalla(
    jsonDecode(File('test/dati/valhalla_utrecht.json').readAsStringSync()) as Map<String, Object?>,
  );

  test('le manovre portano tipo, voce e strada', () {
    final m = percorso.manovre[2];
    expect(m.tipo, isNonZero);
    expect(m.voce, isNotEmpty);
    expect(m.strada, 'Pieterstraat');
  });

  test('guidando lungo il percorso si avanza, si annuncia e si arriva', () {
    final g = Guida(percorso);
    final frasi = <String>[];
    Avanzamento? prima;
    for (final p in percorso.punti) {
      final a = g.aggiorna(p);
      if (a.daDire case final f?) frasi.add(f);
      expect(a.fuoriPercorso, isFalse);
      expect(a.lontanoM, lessThan(1));
      if (prima != null) {
        expect(a.percorsiM, greaterThanOrEqualTo(prima.percorsiM - 1e-6));
        expect(a.restante.inSeconds, lessThanOrEqualTo(prima.restante.inSeconds));
      }
      prima = a;
    }
    expect(prima!.arrivato, isTrue);
    expect(prima.restantiM, lessThan(1));
    expect(frasi.last, 'Sei arrivato.');
    // Ogni frase una volta sola.
    expect(frasi.toSet(), hasLength(frasi.length));
    expect(frasi.where((f) => f.startsWith('Tra ')), isNotEmpty);
  });

  test('alla partenza la prossima manovra è la seconda e il tempo è quello di Valhalla', () {
    final a = Guida(percorso).aggiorna(percorso.punti.first);
    expect(a.prossima, same(percorso.manovre[1]));
    expect(a.dopo, same(percorso.manovre[2]));
    expect(a.allaProssimaM, closeTo(percorso.manovre.first.lunghezzaM, 5));
    expect(a.restante.inSeconds, closeTo(percorso.durata.inSeconds, 3));
  });

  test('uscendo di strada, dopo tre letture chiede di ricalcolare', () {
    final g = Guida(percorso);
    g.aggiorna(percorso.punti[40]);
    final lontano = Punto(percorso.punti[40].lat + 0.003, percorso.punti[40].lon); // ~330 m a nord
    expect(g.aggiorna(lontano).fuoriPercorso, isFalse);
    expect(g.aggiorna(lontano).fuoriPercorso, isFalse);
    final a = g.aggiorna(lontano);
    expect(a.fuoriPercorso, isTrue);
    expect(a.lontanoM, greaterThan(100));
    // Tornati sulla strada, tutto a posto.
    expect(g.aggiorna(percorso.punti[41]).fuoriPercorso, isFalse);
  });

  test('distanze da dire e da scrivere', () {
    expect(distanzaParlata(47), '50 metri');
    expect(distanzaParlata(430), '450 metri');
    expect(distanzaParlata(1000), '1 chilometro');
    expect(distanzaParlata(2480), '2,5 chilometri');
    expect(distanzaParlata(3000), '3 chilometri');
    expect(distanzaBreve(84), '80 m');
    expect(distanzaBreve(1234), '1,2 km');
    expect(distanzaBreve(15600), '16 km');
  });
}
