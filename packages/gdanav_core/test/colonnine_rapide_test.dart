import 'dart:convert';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

import '../tool/colonnine_rapide.dart';

Colonnina colonnina(String id, List<Connettore> prese, {List<String> evse = const []}) => Colonnina(
      id: id,
      nome: 'Area $id',
      operatore: 'Ionity',
      posizione: const Punto(44.5, 11.3),
      connettori: prese,
      fonte: evse.isEmpty ? 'osm' : 'pun',
      evse: evse,
    );

void main() {
  final intero = ArchivioColonnine.scrivi(
    [
      colonnina('rapida', const [
        Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150),
        Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22),
      ], evse: [
        'IT*AAA*E1',
        'IT*AAA*E2'
      ]),
      colonnina('giusta', const [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 50)]),
      colonnina('lenta', const [Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22)]),
      colonnina('quasi', const [Connettore(tipo: TipoConnettore.chademo, potenzaKw: 49.9)]),
    ],
    generato: DateTime.utc(2026, 10, 1),
    coperti: {(89, 22), (90, 22)},
  );

  test('restano le colonnine con una presa da 50 kW in su, con tutte le prese', () {
    final rapide = ArchivioColonnine.leggi(soloRapide(intero));
    expect(rapide.tutte.map((c) => c.id), unorderedEquals(['rapida', 'giusta']));
    final r = rapide.tutte.firstWhere((c) => c.id == 'rapida');
    // Anche la presa lenta accanto, e gli EVSE ID nell'ordine delle prese.
    expect(r.connettori.map((p) => p.potenzaKw), [150, 22]);
    expect(r.evse, ['IT*AAA*E1', 'IT*AAA*E2']);
    expect(r.fonte, 'pun');
  });

  test('la testa è la stessa dell\'archivio intero', () {
    final a = jsonDecode(intero) as Map<String, Object?>;
    final b = jsonDecode(soloRapide(intero)) as Map<String, Object?>;
    expect(b.keys, a.keys);
    for (final k in ['v', 'generato', 'evseInOrdine', 'q']) {
      expect(b[k], a[k], reason: k);
    }
    // Le righe rimaste sono quelle di prima, campo per campo.
    expect((b['c'] as List).first, (a['c'] as List).first);
  });

  test('una riga strana non rompe niente', () {
    List riga(Object? prese) => [44.5, 11.3, 'x', 'x', '', prese];
    expect(rigaRapida([44.5, 11.3, 'x', 'x', '']), isFalse);
    expect(rigaRapida(riga('niente')), isFalse);
    expect(
        rigaRapida(riga([
          const [0, 'tanti', 1]
        ])),
        isFalse);
    expect(
        rigaRapida(riga([
          const [0, 50, 1]
        ])),
        isTrue);
    expect(() => soloRapide('{"v":2,"c":[]}'), throwsFormatException);
  });
}
