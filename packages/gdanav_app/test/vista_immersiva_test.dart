import 'dart:convert';

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

  test('le corsie sulla strada: la linea del percorso entra nella corsia giusta, le righe fra l\'una e l\'altra', () {
    // «Secondo te è corretto?»: prima un riquadro a parte, tre strisce grigie
    // bordate di bianco e la giusta stretta, di lato alla linea larga. Adesso
    // la linea stessa si stringe ed entra nella corsia giusta.
    final uscita = Manovra(
      istruzione: 'Esci a destra',
      lunghezzaM: 300,
      secondi: 20,
      inizio: 30,
      tipo: 20,
      corsie: [dritta, dritta, dritta, giusta],
    );
    final elementi = (datiCorsie(viaggioCon(uscita), uscita)['features']! as List).cast<Map>();
    Iterable<Map> di(String tipo) => elementi.where((e) => (e['properties'] as Map)['tipo'] == tipo);
    // Niente strisce delle corsie né bordi: la copertura sotto, la linea, le righe.
    expect({for (final e in elementi) (e['properties'] as Map)['tipo']}, {'copertura', 'raccordo', 'riga'});
    expect([for (final e in di('riga')) (e['properties'] as Map)['spostamento']], [-3.5, 0.0, 3.5]);
    // La linea: da larga come il percorso (f 0) a larga una corsia (f 1), e ritorno.
    final f = [for (final e in di('raccordo')) (e['properties'] as Map)['f'] as double];
    expect(f.first, lessThan(0.05));
    expect(f.last, lessThan(0.05));
    expect(f, contains(1.0));
    for (var i = 1; i < f.indexOf(1.0); i++) {
      expect(f[i], greaterThan(f[i - 1]));
    }
    expect({for (final e in di('raccordo')) (e['properties'] as Map)['largo']}, {3.5});
    // Nel tratto delle corsie la linea sta nella corsia giusta (l'ultima, a
    // 5,25 m a destra del mezzo); verso nord la destra è a est.
    final dentro = di('raccordo').firstWhere((e) => (e['properties'] as Map)['f'] == 1.0);
    const est = 5.25 / (111195.08 * 0.70711);
    for (final xy in ((dentro['geometry'] as Map)['coordinates'] as List).cast<List>()) {
      if ((xy[1] as double) < 45.0029) expect(xy[0] as double, closeTo(9 + est, 2e-7));
    }
    // E finisce sulla manovra (lat 45,003: lì la corsia è spostata di lato
    // anche verso sud, perché lì il percorso gira), comincia prima, verso nord.
    final linea = ((dentro['geometry'] as Map)['coordinates'] as List);
    expect((linea.last as List)[1], closeTo(45.003, 6e-5));
    expect((linea.first as List)[1], lessThan(45.0016));
  });

  test('con le corsie la freccia della manovra parte dalla corsia giusta e torna sul percorso', () {
    final uscita = Manovra(
      istruzione: 'Esci a destra',
      lunghezzaM: 300,
      secondi: 20,
      inizio: 30,
      tipo: 20,
      corsie: [dritta, dritta, giusta],
    );
    final v = viaggioCon(uscita);
    final c =
        ((datiManovra(v, uscita, corsie: true)['features']! as List).cast<Map>().first['geometry']
                as Map)['coordinates']
            as List;
    const est = 3.5 / (111195.08 * 0.70711);
    // Sessanta metri prima della manovra: nella corsia giusta, a destra.
    expect(((c.first as List)[0] as double), closeTo(9 + est, 2e-7));
    // In fondo, passata la manovra, di nuovo sul percorso (verso est, lat 45,003).
    expect(((c.last as List)[1] as double), closeTo(45.003, 1e-7));
    // Senza corsie (le altre viste) sulla linea, come sempre.
    final senza = ((datiManovra(v, uscita)['features']! as List).cast<Map>().first['geometry'] as Map)['coordinates'];
    expect((((senza as List).first as List)[0] as double), closeTo(9, 1e-9));
  });

  test('con la linea sulle strade della mappa, corsie, freccia e percorso stanno lì e non dove dice il fornitore', () {
    // «Linee fuori strada»: la strada della mappa sta otto metri a ovest
    // della linea del fornitore. La linea da disegnare è spostata lì, coi
    // metri del percorso: corsie, freccia e percorso la seguono.
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
    List<List> senzaRaccordo(Map<String, Object?> dati) => [
      for (final e in (dati['features']! as List).cast<Map>())
        if ((e['properties'] as Map)['tipo'] != 'raccordo') ((e['geometry'] as Map)['coordinates'] as List),
    ];
    for (final c in [
      ...senzaRaccordo(datiCorsie(v, uscita, sullaMappa: spostata)),
      ...linee(datiManovra(v, uscita, sullaMappa: spostata)),
    ]) {
      for (final xy in c.cast<List>()) {
        if ((xy[1] as double) < 45.0029) expect(xy[0] as double, closeTo(9 - ovest, 1e-7));
      }
    }
    // Le corsie prendono la classe della strada su cui stanno: lo stile le
    // colora come lei, e non sono più una lastra chiara sopra l'autostrada.
    final classi = {
      for (final e
          in (datiCorsie(v, uscita, sullaMappa: spostata, classe: (_) => 'motorway')['features']! as List).cast<Map>())
        if ((e['properties'] as Map)['tipo'] == 'copertura') (e['properties'] as Map)['classe'],
    };
    expect(classi, {'motorway'});
    final strato = (stileMappa(scuro: false, immersiva: true)['layers']! as List).cast<Map>().firstWhere(
      (l) => l['id'] == 'corsie',
    );
    expect(jsonEncode((strato['paint'] as Map)['line-color']), contains('motorway'));
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
    // Le corsie sopra il percorso (lo coprono e lo stringono nella corsia
    // giusta), la freccia della manovra sopra le corsie, gli edifici sopra,
    // il segnaposto sopra tutto.
    expect(strati.indexOf('corsie'), greaterThan(strati.indexOf('percorso')));
    expect(strati.indexOf('corsie-percorso'), greaterThan(strati.indexOf('corsie')));
    expect(strati.indexOf('manovra'), greaterThan(strati.indexOf('corsie-righe')));
    expect(strati, isNot(contains('corsie-bordi')));
    expect(strati.indexOf(stratoEdificiImmersivi), greaterThan(strati.indexOf('manovra')));
    expect(strati.indexOf('io'), greaterThan(strati.indexOf(stratoEdificiImmersivi)));
    expect((immersivo['sources']! as Map).containsKey(sorgenteCorsie), isTrue);
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
