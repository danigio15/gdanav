import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/itinerario.dart';
import 'package:gdanav_app/stato/dimostrazione.dart';
import 'package:gdanav_core/gdanav_core.dart';

/* «Quando c'è il calcolo percorso questo non esce su Android Auto e
 * CarPlay.» Le strade fra cui scegliere vanno all'auto con le stesse voci
 * delle carte del telefono: [vociStrade] le fa una volta sola per tutti e
 * due. */
void main() {
  final scelte = Dimostrazione.strade.scelte();

  test('tre strade, coi nomi delle carte e da dove passano', () {
    final voci = vociStrade(scelte, scelta: 0, consumo: (p) => p.lunghezzaM / 1000 * 0.15);
    expect(voci, hasLength(3));
    expect(voci.first.etichetta, EtichettaStrada.piuRapida);
    expect(nomeStrada(voci.first.etichetta, 'kWh'), 'Più rapida');
    // La prima ha la coda: lo si dice.
    expect(voci.first.traffico, '+7 min traffico');
    for (final v in voci) {
      expect(v.consumo, isNotNull);
      expect(v.via, isNotEmpty);
    }
  });

  test("la batteria all'arrivo delle altre si sposta di quello che consumano in più o in meno", () {
    final voci = vociStrade(scelte, scelta: 0, consumo: (p) => p.lunghezzaM / 1000 * 0.15, arrivo: 50, capacitaKwh: 60);
    expect(voci.first.arrivo, 50);
    for (final v in voci.skip(1)) {
      final dkwh = v.consumo! - voci.first.consumo!;
      expect(v.arrivo, closeTo(50 - dkwh / 60 * 100, 0.001));
    }
  });

  test('«Senza pedaggi» solo se un\'altra strada paga', () {
    CostoPedaggio costo(PercorsoCalcolato p) =>
        p.conAutostrade ? const CostoPedaggio(euro: 4.2, km: 30) : const CostoPedaggio(euro: 0, km: 0);
    final voci = vociStrade(scelte, scelta: 0, pedaggio: costo);
    expect(voci.first.pedaggio!.senzaPedaggi, isFalse);
    expect(voci[1].pedaggio!.breve, 'Senza pedaggi');
    // Nessuna paga: niente pastiglie.
    final gratis = vociStrade(scelte.skip(1).toList(), scelta: 0, pedaggio: costo);
    expect(gratis.every((v) => v.pedaggio == null), isTrue);
  });
}
