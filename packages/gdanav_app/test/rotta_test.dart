/* Verso dove guarda il segnaposto.
 *
 * Tutte queste prove nascono da una guida vera, di sera, in citta': la
 * macchinina girava su se stessa ferma al semaforo.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Dieci metri circa, alla latitudine di Aversa.
const _dieciMetri = 0.00009;

void main() {
  late List<Lettura> daMandare;
  late DateTime adesso;

  GestorePosizione costruisci({double? Function()? auto}) {
    final controllo = Stream<Lettura>.fromIterable(daMandare);
    return GestorePosizione(
      archivio: Archivio(),
      letture: () => controllo,
      velocitaDellAuto: auto,
      orologio: () => adesso,
    );
  }

  setUp(() {
    adesso = DateTime(2026, 9, 26, 19, 31);
    daMandare = [];
  });

  test('ferma al semaforo, il GPS balla e il segnaposto non si muove', () async {
    /* E' la sera del 26 settembre. Fermi, e il GPS salta di una decina di
     * metri a destra e poi a sinistra: prima bastava a far girare la
     * macchinina, perche' il ramo dei due punti non guardava la velocita'. */
    daMandare = [
      const Lettura(Punto(40.9700, 14.2060)),
      const Lettura(Punto(40.9700 + _dieciMetri, 14.2060)),
      const Lettura(Punto(40.9700 - _dieciMetri, 14.2060)),
      const Lettura(Punto(40.9700, 14.2060 + _dieciMetri)),
    ];
    final p = costruisci(auto: () => 0);
    p.avvia();
    await Future<void>.delayed(Duration.zero);

    expect(p.rotta, 0, reason: 'da fermi la direzione non si tocca');
  });

  test("l'auto dice che si va, e allora il segnaposto segue", () async {
    daMandare = [
      const Lettura(Punto(40.9700, 14.2060), rotta: 90, velocitaMs: 10),
      const Lettura(Punto(40.9701, 14.2060), rotta: 90, velocitaMs: 10),
    ];
    final p = costruisci(auto: () => 50);
    p.avvia();
    await Future<void>.delayed(Duration.zero);

    expect(p.rotta, 90);
  });

  test("senza l'auto si torna al GPS, e da fermi resta fermo", () async {
    /* gdanav si usa anche a piedi, o con un'auto che la velocita' non la dice:
     * li' decide il GPS, come prima. Con letture a dieci metri e mezzo secondo
     * l'una dall'altra si va a 72 km/h, e allora la direzione si prende. */
    daMandare = [const Lettura(Punto(40.9700, 14.2060)), const Lettura(Punto(40.9700 + _dieciMetri, 14.2060))];
    final p = GestorePosizione(
      archivio: Archivio(),
      letture: () => Stream<Lettura>.fromIterable(daMandare),
      orologio: () {
        adesso = adesso.add(const Duration(milliseconds: 500));
        return adesso;
      },
    );
    p.avvia();
    await Future<void>.delayed(Duration.zero);

    expect(p.rotta, closeTo(0, 1), reason: 'si sta andando verso nord');
    expect(p.velocitaKmh, greaterThan(2));
  });

  test('la prima direzione non si smorza: se no si guarda a nord fino alla curva', () async {
    daMandare = [const Lettura(Punto(40.9700, 14.2060), rotta: 270, velocitaMs: 10)];
    final p = costruisci(auto: () => 50);
    p.avvia();
    await Future<void>.delayed(Duration.zero);

    expect(p.rotta, 270, reason: 'intera, non il 60% di 270');
  });

  test('una lettura storta da sola non gira il segnaposto', () async {
    /* Lo smorzamento: in corsa una bussola sbagliata di 40 gradi ne sposta
     * ventiquattro, non quaranta. Alla lettura dopo, se era rumore, si torna
     * indietro; se era una curva, si arriva. */
    daMandare = [
      const Lettura(Punto(40.9700, 14.2060), rotta: 0, velocitaMs: 10),
      const Lettura(Punto(40.9701, 14.2060), rotta: 40, velocitaMs: 10),
    ];
    final p = costruisci(auto: () => 50);
    p.avvia();
    await Future<void>.delayed(Duration.zero);

    expect(p.rotta, closeTo(24, 0.01));
  });

  test('i gradi tornano a zero, e lo smorzamento lo sa', () {
    /* Da 350 a 10 ci sono venti gradi a destra. Una sottrazione secca direbbe
     * trecentoquaranta a sinistra, e il segnaposto farebbe il giro largo. */
    expect(diQuantoSiGira(350, 10), closeTo(20, 0.001));
    expect(diQuantoSiGira(10, 350), closeTo(-20, 0.001));
    /* Mezzo giro e' ambiguo di suo: 180 a destra e 180 a sinistra portano
     * nello stesso posto, e non esiste una risposta piu' giusta dell'altra.
     * Quello che conta e' che la quantita' sia mezzo giro. */
    expect(diQuantoSiGira(0, 180).abs(), closeTo(180, 0.001));
    expect(versoDiLa(0, 180, 1), closeTo(180, 0.001));
    expect(versoDiLa(350, 10, 0.5), closeTo(0, 0.001));
    expect(versoDiLa(350, 10, 1), closeTo(10, 0.001));
    expect(versoDiLa(350, 10, 0), closeTo(350, 0.001));
  });
}
