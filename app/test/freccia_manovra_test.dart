import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/mappa/dati_viaggio.dart';
import 'package:gdanav/mappa/stile.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  // Dritto verso nord per ~330 m, poi a destra verso est.
  final punti = [
    for (var i = 0; i <= 30; i++) Punto(45 + i * 0.0001, 9),
    for (var i = 1; i <= 30; i++) Punto(45.003, 9 + i * 0.00014),
  ];
  const uscita = Manovra(istruzione: 'Esci a destra', lunghezzaM: 300, secondi: 20, inizio: 30, tipo: 20);
  final viaggio = Viaggio(
    percorso: PercorsoCalcolato(punti: punti, tratti: const [], manovre: const [uscita]),
    colonnine: const [],
    piano: null,
  );

  test('allo svincolo la freccia sul percorso: il tratto giusto e la punta verso dove si va', () {
    final dati = datiManovra(viaggio, uscita);
    final elementi = dati['features']! as List;
    expect(elementi, hasLength(2));
    final linea = ((elementi[0] as Map)['geometry'] as Map)['coordinates'] as List;
    // Comincia prima della manovra (sulla strada verso nord) e finisce dopo (verso est).
    expect((linea.first as List)[0], closeTo(9, 1e-9));
    expect((linea.first as List)[1], lessThan(45.003));
    expect((linea.last as List)[0], greaterThan(9.0004));
    expect((linea.last as List)[1], closeTo(45.003, 1e-9));
    // La punta è un triangolo che punta a est.
    final punta = (((elementi[1] as Map)['geometry'] as Map)['coordinates'] as List).first as List;
    expect(punta, hasLength(4));
    expect(((punta[1] as List)[0] as double), greaterThan((linea.last as List)[0] as double));
  });

  test('la freccia solo vicino alla manovra, e non per partenza o «prosegui»', () {
    expect(chiaveFreccia(viaggio, uscita, 400), isNotNull);
    expect(chiaveFreccia(viaggio, uscita, 1500), isNull);
    expect(chiaveFreccia(viaggio, uscita, 400, ricalcolo: true), isNull);
    const prosegui = Manovra(istruzione: 'Prosegui', lunghezzaM: 300, secondi: 20, inizio: 30, tipo: 8);
    expect(datiManovra(viaggio, prosegui)['features'], isEmpty);
    expect(datiManovra(null, null)['features'], isEmpty);
  });

  test('lo stile ha la sorgente e gli strati della freccia, sopra il percorso', () {
    final stile = stileMappa(scuro: false);
    expect((stile['sources']! as Map).containsKey(sorgenteManovra), isTrue);
    final ids = [for (final l in stile['layers']! as List) (l as Map)['id']];
    expect(ids.indexOf('manovra'), greaterThan(ids.indexOf('percorso')));
    expect(ids, containsAll(['manovra-bordo', 'manovra-punta', 'manovra-punta-bordo']));
  });
}
