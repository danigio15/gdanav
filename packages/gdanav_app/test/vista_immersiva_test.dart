import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// La vista immersiva: le corsie della manovra disegnate sulla strada, e lo
/// stile con le strade in metri e gli edifici sopra il percorso.
void main() {
  // Dritto verso nord per ~330 m, poi a destra verso est.
  final punti = [
    for (var i = 0; i <= 30; i++) Punto(45 + i * 0.0001, 9),
    for (var i = 1; i <= 30; i++) Punto(45.003, 9 + i * 0.00014),
  ];
  final dritta = Corsia(const [DirezioneCorsia.dritto]);
  final giusta = Corsia(const [DirezioneCorsia.dritto], giusta: true);
  Viaggio viaggioCon(Manovra m) => Viaggio(
    percorso: PercorsoCalcolato(punti: punti, tratti: const [], manovre: [m]),
    colonnine: const [],
    piano: null,
  );

  test('le corsie sulla strada: una striscia per corsia, la giusta segnata, le righe fra l\'una e l\'altra', () {
    final uscita = Manovra(
      istruzione: 'Esci a destra',
      lunghezzaM: 300,
      secondi: 20,
      inizio: 30,
      tipo: 20,
      corsie: [dritta, dritta, dritta, giusta],
    );
    final elementi = (datiCorsie(viaggioCon(uscita), uscita)['features']! as List).cast<Map>();
    final corsie = [
      for (final e in elementi)
        if ((e['properties'] as Map)['tipo'] == 'corsia') e['properties'] as Map,
    ];
    expect(corsie, hasLength(4));
    // Da sinistra a destra, centrate sul percorso; la giusta è l'ultima.
    expect([for (final c in corsie) c['spostamento']], [-5.25, -1.75, 1.75, 5.25]);
    expect([for (final c in corsie) c['giusta']], [false, false, false, true]);
    final righe = [for (final e in elementi) (e['properties'] as Map)['tipo']].where((t) => t != 'corsia').toList();
    expect(righe, ['bordo', 'riga', 'riga', 'riga', 'bordo']);
    // Il tratto finisce sulla manovra e comincia prima, sulla strada verso nord.
    final linea = ((elementi.first['geometry'] as Map)['coordinates'] as List);
    expect((linea.last as List)[1], closeTo(45.003, 1e-9));
    expect((linea.first as List)[1], lessThan(45.0016));
  });

  test("nell'immersiva la freccia della manovra parte dalla corsia giusta, e dopo lo svincolo rientra", () {
    // Tre corsie, giusta quella di destra: sta una corsia (3,5 m) a destra
    // della linea del percorso, che va verso nord.
    final uscita = Manovra(
      istruzione: 'Esci a destra',
      lunghezzaM: 300,
      secondi: 20,
      inizio: 30,
      tipo: 20,
      corsie: [dritta, dritta, giusta],
    );
    final elementi = (datiManovra(viaggioCon(uscita), uscita)['features']! as List).cast<Map>();
    final linee = [
      for (final e in elementi)
        if ((e['geometry'] as Map)['type'] == 'LineString') e,
    ];
    expect(linee, hasLength(2));
    // Quella sulla linea resta per le altre viste; l'immersiva prende l'altra.
    expect((linee.first['properties'] as Map)['sostituibile'], isTrue);
    expect((linee.last['properties'] as Map)['vista'], 'immersiva');
    final sulLato = ((linee.last['geometry'] as Map)['coordinates'] as List).cast<List>();
    final sullaLinea = ((linee.first['geometry'] as Map)['coordinates'] as List).cast<List>();
    // All'inizio, 3,5 m a est (a destra di chi va a nord).
    final est = ((sulLato.first[0] as double) - 9) * 111195.08 * 0.7071;
    expect(est, closeTo(3.5, 0.15));
    // Alla fine è di nuovo sulla linea, dove sta la punta.
    expect(sulLato.last[0] as double, closeTo(sullaLinea.last[0] as double, 1e-7));
    expect(sulLato.last[1] as double, closeTo(sullaLinea.last[1] as double, 1e-7));

    // Con la corsia giusta in mezzo non c'è niente da spostare.
    final inMezzo = Manovra(
      istruzione: 'Esci a destra',
      lunghezzaM: 300,
      secondi: 20,
      inizio: 30,
      tipo: 20,
      corsie: [dritta, giusta, dritta],
    );
    final solo = (datiManovra(viaggioCon(inMezzo), inMezzo)['features']! as List).cast<Map>();
    expect(solo.where((e) => (e['geometry'] as Map)['type'] == 'LineString'), hasLength(1));
  });

  test("lo stile: l'immersiva disegna la freccia dalla corsia, le altre quella sulla linea", () {
    Map strato(bool immersiva, String id) => (stileMappa(scuro: false, immersiva: immersiva)['layers']! as List)
        .cast<Map>()
        .firstWhere((l) => l['id'] == id);
    for (final id in ['manovra', 'manovra-bordo']) {
      expect(strato(true, id)['filter'].toString(), contains('sostituibile'));
      expect(strato(false, id)['filter'].toString(), contains('immersiva'));
    }
  });

  test('se le corsie vanno bene tutte, o non si sanno, non si disegna niente', () {
    final tutte = Manovra(
      istruzione: 'Esci a destra',
      lunghezzaM: 300,
      secondi: 20,
      inizio: 30,
      tipo: 20,
      corsie: [giusta, giusta],
    );
    expect(datiCorsie(viaggioCon(tutte), tutte)['features'], isEmpty);
    const senza = Manovra(istruzione: 'Esci a destra', lunghezzaM: 300, secondi: 20, inizio: 30, tipo: 20);
    expect(datiCorsie(viaggioCon(senza), senza)['features'], isEmpty);
    expect(datiCorsie(null, null)['features'], isEmpty);
  });

  test('lo stile immersivo: strade in metri, corsie, edifici sopra il percorso', () {
    List<String> idDi(Map<String, Object> s) => [for (final l in s['layers']! as List) (l as Map)['id'] as String];
    final normale = stileMappa(scuro: false);
    final immersivo = stileMappa(scuro: false, immersiva: true);
    expect(idDi(normale), isNot(contains(stratoEdificiImmersivi)));
    final strati = idDi(immersivo);
    // Le corsie sopra il percorso e sopra la freccia della manovra, gli
    // edifici sopra le corsie, il segnaposto sopra tutto.
    expect(strati.indexOf('corsie'), greaterThan(strati.indexOf('percorso')));
    expect(strati.indexOf('corsie'), greaterThan(strati.indexOf('manovra')));
    expect(strati.indexOf(stratoEdificiImmersivi), greaterThan(strati.indexOf('corsie')));
    expect(strati.indexOf('io'), greaterThan(strati.indexOf(stratoEdificiImmersivi)));
    expect((immersivo['sources']! as Map).containsKey(sorgenteCorsie), isTrue);
    // L'autostrada larga 14 metri: a zoom 18 sono 14 × pixel per metro.
    final autostrada = (immersivo['layers']! as List).cast<Map>().firstWhere((l) => l['id'] == 'autostrade');
    final larghezza = (autostrada['paint'] as Map)['line-width'] as List;
    expect(larghezza[1], ['exponential', 2]);
    expect(larghezza[4], closeTo(14 * pixelPerMetro(12), 1e-9));
  });
}
