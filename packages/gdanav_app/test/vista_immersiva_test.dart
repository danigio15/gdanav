import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// La vista immersiva: il percorso e la freccia della manovra sulle strade
/// della mappa, e lo stile con le strade in metri e gli edifici sopra.
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

  test('con la linea sulle strade della mappa, freccia e percorso stanno lì e non dove dice il fornitore', () {
    // «Linee fuori strada»: la strada della mappa sta otto metri a ovest
    // della linea del fornitore. La linea da disegnare è spostata lì, coi
    // metri del percorso: freccia e percorso la seguono.
    final uscita = Manovra(
      istruzione: 'Esci a destra',
      lunghezzaM: 300,
      secondi: 20,
      inizio: 30,
      tipo: 20,
      corsie: [dritta, giusta],
    );
    final v = viaggioCon(uscita);
    final l = Linea(punti);
    const ovest = 8 / (111195.08 * 0.7071);
    final spostata = Linea.conMetri([for (final p in punti) Punto(p.lat, p.lon - ovest)], l.cumulate);
    List<List> linee(Map<String, Object?> dati) => [
      for (final e in (dati['features']! as List).cast<Map>())
        if ((e['geometry'] as Map)['type'] == 'LineString') ((e['geometry'] as Map)['coordinates'] as List),
    ];
    for (final c in [...linee(datiManovra(v, uscita, sullaMappa: spostata))]) {
      for (final xy in c.cast<List>()) {
        if ((xy[1] as double) < 45.0029) expect(xy[0] as double, closeTo(9 - ovest, 1e-7));
      }
    }
    // La freccia è larga quanto la linea blu anche nell'immersiva («la linea
    // bianca non ha la stessa dimensione della blu»): in pixel, come lei.
    Map strato(String id) =>
        (stileMappa(scuro: false, immersiva: true)['layers']! as List).cast<Map>().firstWhere((l) => l['id'] == id);
    expect(
      (strato('manovra-bordo')['paint'] as Map)['line-width'],
      (strato('percorso-bordo')['paint'] as Map)['line-width'],
    );
    final percorso = datiViaggio(v, sullaMappa: spostata)[sorgentePercorso]!;
    expect((linee(percorso).single.first as List)[0], closeTo(9 - ovest, 1e-9));
    // Di un altro percorso (un'altra lunghezza) non si usa.
    final altra = Linea.conMetri(spostata.punti, [for (final c in l.cumulate) c * 2]);
    expect((linee(datiViaggio(v, sullaMappa: altra)[sorgentePercorso]!).single.first as List)[0], 9);
  });

  test("la freccia della manovra sta sulla linea blu, anche nell'immersiva e anche con le corsie", () {
    // «La linea bianca non combacia con quella blu, e sul continuo del
    // percorso»: «mantieni la sinistra» a un bivio, la corsia giusta tutta a
    // sinistra. Prima la freccia partiva da lì, spostata di lato, e correva
    // parallela al percorso; adesso è una sola, sulla linea.
    final bivio = Manovra(
      istruzione: 'Mantieni la sinistra',
      lunghezzaM: 300,
      secondi: 20,
      inizio: 30,
      tipo: 18,
      corsie: [giusta, dritta, dritta],
    );
    final v = viaggioCon(bivio);
    final elementi = (datiManovra(v, bivio)['features']! as List).cast<Map>();
    final linee = [
      for (final e in elementi)
        if ((e['geometry'] as Map)['type'] == 'LineString')
          ((e['geometry'] as Map)['coordinates'] as List).cast<List>(),
    ];
    expect(linee, hasLength(1));
    // Ogni punto della freccia sta sul percorso: sul tratto verso nord (lon
    // 9) o su quello verso est (lat 45,003), mai di lato.
    for (final c in linee.single) {
      final sulTratto = ((c[0] as double) - 9).abs() < 1e-9 || ((c[1] as double) - 45.003).abs() < 1e-9;
      expect(sulTratto, isTrue, reason: 'il punto $c è fuori dal percorso');
    }
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

  test("a un'uscita la freccia arriva fin dove la rampa gira, e la punta guarda lì", () {
    // «Deve esserci la freccia che esce»: la rampa corre dritta accanto alla
    // strada per 90 m, poi gira a destra. Prima la freccia finiva 45 m dopo
    // e puntava dritta.
    final rampa = [
      for (var i = 0; i <= 28; i++) Punto(45 + i * 0.0001, 9),
      for (var i = 1; i <= 20; i++) Punto(45.0028, 9 + i * 0.00014),
    ];
    const esci = Manovra(istruzione: 'Esci a destra', lunghezzaM: 300, secondi: 20, inizio: 20, tipo: 20);
    final v = Viaggio(
      percorso: PercorsoCalcolato(punti: rampa, tratti: const [], manovre: [esci]),
      colonnine: const [],
      piano: null,
    );
    final elementi = (datiManovra(v, esci)['features']! as List).cast<Map>();
    final punta = elementi.firstWhere((e) => (e['geometry'] as Map)['type'] == 'Point');
    // La punta guarda verso est (la rampa che gira), non a nord.
    expect(((punta['properties'] as Map)['rotta'] as num).toDouble(), greaterThan(20));
    // E sta oltre l'inizio della curva, non 45 m dopo la manovra.
    final dove = ((punta['geometry'] as Map)['coordinates'] as List).cast<double>();
    expect(dove[1], greaterThan(45.0027));
    // A una svolta vera (girata subito) la freccia resta corta.
    const gira = Manovra(istruzione: 'Gira a destra', lunghezzaM: 300, secondi: 20, inizio: 28, tipo: 10);
    final v2 = Viaggio(
      percorso: PercorsoCalcolato(punti: rampa, tratti: const [], manovre: [gira]),
      colonnine: const [],
      piano: null,
    );
    final corta =
        ((datiManovra(v2, gira)['features']! as List).cast<Map>().firstWhere(
                  (e) => (e['geometry'] as Map)['type'] == 'Point',
                )['geometry']
                as Map)['coordinates']
            as List;
    expect(((corta[0] as double) - 9) * 111195.08 * 0.7071, lessThan(50));
  });

  test('lo stile immersivo: strade in metri, corsie, edifici sopra il percorso', () {
    List<String> idDi(Map<String, Object> s) => [for (final l in s['layers']! as List) (l as Map)['id'] as String];
    final normale = stileMappa(scuro: false);
    final immersivo = stileMappa(scuro: false, immersiva: true);
    expect(idDi(normale), isNot(contains(stratoEdificiImmersivi)));
    final strati = idDi(immersivo);
    // Niente corsie disegnate sopra il percorso («sono due linee
    // completamente diverse»): una linea sola, la freccia sopra, gli edifici
    // sopra, il segnaposto sopra tutto.
    expect(strati.where((id) => id.startsWith('corsie')), isEmpty);
    expect((immersivo['sources']! as Map).containsKey('gdanav-corsie'), isFalse);
    expect(strati.indexOf('manovra'), greaterThan(strati.indexOf('percorso')));
    expect(strati.indexOf(stratoEdificiImmersivi), greaterThan(strati.indexOf('manovra')));
    expect(strati.indexOf('io'), greaterThan(strati.indexOf(stratoEdificiImmersivi)));
    // L'autostrada larga 14 metri: a zoom 18 sono 14 × pixel per metro.
    final autostrada = (immersivo['layers']! as List).cast<Map>().firstWhere((l) => l['id'] == 'autostrade');
    final larghezza = (autostrada['paint'] as Map)['line-width'] as List;
    expect(larghezza[1], ['exponential', 2]);
    expect(larghezza[4], closeTo(14 * pixelPerMetro(12), 1e-9));
  });
  test("nell'immersiva il traffico sta sopra il percorso, stretto come la coda", () {
    // «Nella visuale immersiva non si vede il traffico: la linea è sovrapposta
    // da quella del percorso.»
    List<Map> strati(bool immersiva) =>
        (stileMappa(scuro: false, chiaveTraffico: 'CHIAVE', immersiva: immersiva)['layers']! as List).cast<Map>();
    List<String> idDi(List<Map> s) => [for (final l in s) l['id'] as String];
    final normale = idDi(strati(false)), immersivo = idDi(strati(true));
    for (final id in [stratoTraffico, stratoTrafficoLocale]) {
      // Nelle altre viste resta sotto, con le strade.
      expect(normale.indexOf(id), lessThan(normale.indexOf('percorso-bordo')));
      // Nell'immersiva sopra la linea, sotto le code del percorso e le frecce.
      expect(immersivo.where((x) => x == id), hasLength(1));
      expect(immersivo.indexOf(id), greaterThan(immersivo.indexOf('percorso')));
      expect(immersivo.indexOf(id), lessThan(immersivo.indexOf('code')));
      expect(immersivo.indexOf(id), lessThan(immersivo.indexOf('percorso-frecce')));
      // Stretto come la striscia della coda: ai lati resta il celeste.
      final larghezza = (strati(true).singleWhere((l) => l['id'] == id)['paint'] as Map)['line-width'] as List;
      expect(larghezza[4], larghezzaCoda.$1);
      expect(larghezza[6], larghezzaCoda.$2);
    }
  });
}
