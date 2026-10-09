// «Quando apre il navigatore non deve calcolare il percorso ma mostrare dove
// è sulla mappa. Se ci sono più persone nella casa, la mappa di gdanav mostra
// la posizione delle persone della casa.»
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_app/schermate/scheda_punto.dart';
import 'package:gdanav_app/stato/gestore_persone.dart' show datiPersone;

const anna = PersonaSullaMappa(
  id: 'person.anna',
  nome: 'Anna Rossi',
  posizione: Punto(40.86, 14.28),
  dove: 'Via Toledo 12, Napoli',
);
const luca = PersonaSullaMappa(id: 'person.luca', nome: 'Luca', posizione: Punto(41.9, 12.5));

void main() {
  test('le persone si mettono, e cambiando niente non si avvisa nessuno', () {
    final g = GestorePersone();
    var avvisi = 0;
    g.addListener(() => avvisi++);
    g.aggiorna([anna, luca, const PersonaSullaMappa(id: 'x', nome: 'x', posizione: Punto(200, 0))]);
    expect(g.persone.map((p) => p.id), ['person.anna', 'person.luca'], reason: 'fuori scala non si mette');
    g.aggiorna([anna, luca]);
    expect(avvisi, 1);
  });

  test('«mostra» porta la mappa sulla persona, senza viaggio', () {
    final g = GestorePersone()..aggiorna([luca]);
    g.mostra(anna);
    expect(g.richiesteMostra, 1);
    expect(g.daMostrare, anna);
    expect(g.persona('person.anna'), anna, reason: 'chi non c\'era si aggiunge');
    final spostata = PersonaSullaMappa(id: luca.id, nome: luca.nome, posizione: const Punto(42, 12));
    g.mostra(spostata);
    expect(g.persone, hasLength(2));
    expect(g.persona(luca.id)?.posizione.lat, 42);
    g.mostraTutte();
    expect(g.richiesteMostra, 3);
    expect(g.daMostrare, isNull);
  });

  test('sul segnaposto le iniziali', () {
    expect(anna.iniziali, 'AR');
    expect(luca.iniziali, 'L');
  });

  test('sulla mappa: un punto per persona, toccabile, con la sua scheda', () {
    final dati = datiPersone([anna]);
    final f = (dati['features']! as List).single as Map<String, Object?>;
    expect((f['geometry']! as Map)['coordinates'], [14.28, 40.86]);
    final toccata = PuntoToccato.daElemento(f);
    expect(toccata?.tipo, 'persona');
    expect(toccata?.nome, 'Anna Rossi');
    expect(toccata?.proprieta['dove'], 'Via Toledo 12, Napoli');
    final stile = stileMappa(scuro: false);
    expect((stile['sources']! as Map).containsKey(sorgentePersone), isTrue);
    final strati = [for (final s in stile['layers']! as List) (s as Map)['id']];
    expect(strati, containsAll(['persone', 'persone-iniziali', 'persone-nome']));
    expect(stratiToccabili, contains('persone'));
  });
}
