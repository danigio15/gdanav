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
    // Si parte da Domplein verso nord.
    expect(a.rotta, anyOf(lessThan(45), greaterThan(315)));
  });

  test('il limite di velocità è quello del tratto in cui si è', () {
    final limiti = ClienteValhalla.limitiDaTraccia(
      jsonDecode(File('test/dati/valhalla_utrecht_limiti.json').readAsStringSync()) as Map<String, Object?>,
      percorso.punti.length,
    );
    final g = Guida(percorso.conLimiti(limiti));
    final visti = <int?>[for (final p in percorso.punti) g.aggiorna(p).limiteKmh];
    expect(visti.first, limiti.first);
    expect(visti.whereType<int>().toSet(), containsAll([30, 50]));
    expect(Guida(percorso).aggiorna(percorso.punti[10]).limiteKmh, isNull);
    // Su ogni punto del tracciato vale il limite del segmento che parte da lì.
    final g2 = Guida(percorso.conLimiti(limiti));
    for (var i = 0; i < percorso.punti.length - 1; i++) {
      final a = g2.aggiorna(percorso.punti[i]);
      if (a.lontanoM < 0.5 && limiti[i] != null && i > 0 && limiti[i - 1] == null) expect(a.limiteKmh, limiti[i]);
    }
  });

  test('uscendo di strada, dopo due letture chiede di ricalcolare', () {
    /* Erano tre: col ricalcolo dopo, il percorso nuovo arrivava alla traversa
     * successiva. Una lettura storta da sola però non basta ancora. */
    final g = Guida(percorso);
    g.aggiorna(percorso.punti[40]);
    final lontano = Punto(percorso.punti[40].lat + 0.003, percorso.punti[40].lon); // ~330 m a nord
    expect(g.aggiorna(lontano).fuoriPercorso, isFalse);
    final a = g.aggiorna(lontano);
    expect(a.fuoriPercorso, isTrue);
    expect(a.lontanoM, greaterThan(100));
    // Tornati sulla strada, tutto a posto.
    expect(g.aggiorna(percorso.punti[41]).fuoriPercorso, isFalse);
  });

  test("sulla strada il segnaposto si aggancia; fuori no, e non si mente", () {
    /* «Un navigatore normalmente fa map-matching: quando sei in navigazione e
     * il punto cade a pochi metri dalla strada, il segnaposto si posa sulla
     * strada.» L'aggancio c'era gia'; quello che mancava era il suo limite.
     *
     * Era senza condizioni: a trecento metri dalla linea il puntino restava
     * incollato alla strada, e lo restava per tre letture — il tempo che
     * serve al ricalcolo ad accorgersene — proprio mentre chi guida doveva
     * capire di aver sbagliato svolta. «Mentire sarebbe peggio»: adesso
     * fuori tolleranza non c'e' nessun aggancio, e chi disegna torna al punto
     * grezzo. */
    final g = Guida(percorso);
    final sulla = g.aggiorna(percorso.punti[40]);
    expect(sulla.agganciato, isTrue);
    expect(sulla.posizioneSulPercorso, isNotNull);
    expect(distanzaM(sulla.posizioneSulPercorso!, percorso.punti[40]), lessThan(1));
    expect(sulla.rotta, isNotNull);

    // Trecento metri a nord: si e' in un'altra strada, e lo si dice.
    final lontano = Punto(percorso.punti[40].lat + 0.003, percorso.punti[40].lon);
    final via = g.aggiorna(lontano);
    expect(via.agganciato, isFalse);
    expect(via.posizioneSulPercorso, isNull);
    expect(via.rotta, isNull);
    /* Il resto dell'avanzamento continua a esserci: quanto si e' percorso e
     * quanto manca si sanno lo stesso, ed e' giusto — sono la proiezione,
     * non il segnaposto. E la telecamera guarda avanti anche da fuori: e' da
     * li' che si vede dove si sarebbe dovuti andare. */
    expect(via.lontanoM, greaterThan(100));
    expect(via.restantiM, greaterThan(0));
    expect(via.rottaMappa, isNotNull);

    // Tornati in strada, si riaggancia.
    expect(g.aggiorna(percorso.punti[41]).agganciato, isTrue);
  });

  test("fra agganciato e no non si lampeggia: due soglie, non una", () {
    /* Con una soglia sola, stando alla distanza esatta della soglia — e a
     * venti metri dalla mezzeria ci si sta per minuti interi, su una statale
     * larga — una lettura aggancia e la successiva sgancia: il puntino salta
     * fra la strada e il prato accanto. Si aggancia stando vicini, ci si
     * stacca solo andando via davvero.
     *
     * La strada e' dritta verso nord apposta: cosi' spostarsi a est e'
     * spostarsi di traverso, e i metri che si chiedono sono i metri che si
     * misurano. Sul percorso vero di Utrecht non lo sarebbero — li' andando a
     * nord si scorre lungo la linea, e a duecento metri si e' ancora a
     * ventisei dalla strada. */
    const lat = 52.09, lon = 5.12;
    const gradoLat = 1 / 111320; // un metro in gradi di latitudine
    const gradoLon = 1 / 68540; // un metro in gradi di longitudine, a 52°
    final dritta = [for (var i = 0; i <= 40; i++) Punto(lat + i * 20 * gradoLat, lon)];
    final g = Guida(
      PercorsoCalcolato(
        punti: dritta,
        tratti: const [],
        manovre: const [Manovra(istruzione: 'Parti', lunghezzaM: 800, secondi: 60, inizio: 0, tipo: 1)],
      ),
      sogliaAggancioM: 20,
      sogliaSgancioM: 32,
    );
    Punto diLato(double metri) => Punto(dritta[20].lat, lon + metri * gradoLon);
    /* Quanto si chiede e' quanto si misura: se questa cade, e' la prova a
     * essere sbagliata, non l'aggancio. */
    expect(g.aggiorna(diLato(25)).lontanoM, closeTo(25, 1));

    // Arrivando da lontano, a venticinque metri non si aggancia.
    expect(g.aggiorna(diLato(200)).agganciato, isFalse);
    expect(g.aggiorna(diLato(25)).agganciato, isFalse);
    // Avvicinandosi sotto i venti, si'.
    expect(g.aggiorna(diLato(10)).agganciato, isTrue);
    // E a venticinque si resta agganciati: non si e' andati via davvero.
    expect(g.aggiorna(diLato(25)).agganciato, isTrue);
    // A quaranta si'.
    expect(g.aggiorna(diLato(40)).agganciato, isFalse);
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

  /* ── «Se la strada e' dritta la mappa deve seguire la vettura» ───────────
   *
   * Due foto dal campo, la stessa causa: la telecamera guardava sempre
   * centocinquanta metri avanti e, vicino a una manovra, quaranta metri
   * OLTRE la manovra — cioe' gia' sull'altra strada. Su un'uscita che si
   * stacca e curva la mappa ruotava di sessanta gradi mentre l'auto era
   * ancora sul rettilineo, e sembrava un tornante invece di una deviazione.
   *
   * Adesso la mappa resta appesa alla strada sotto le ruote: puo' anticipare,
   * ma non piu' di venticinque gradi, e sbircia oltre la manovra solo negli
   * ultimi sessanta metri. */

  /// 300 m verso nord (un vertice ogni 10 m), poi una curva verso ovest.
  PercorsoCalcolato rampa() => PercorsoCalcolato(
        punti: [
          for (var i = 0; i <= 30; i++) Punto(45 + i * 0.00009, 9),
          for (var i = 1; i <= 20; i++) Punto(45.0027, 9 - i * 0.000127),
        ],
        tratti: const [],
        manovre: const [
          Manovra(istruzione: 'Parti', lunghezzaM: 300, secondi: 20, inizio: 0, tipo: 1),
          Manovra(istruzione: 'Tieni la sinistra', lunghezzaM: 200, secondi: 20, inizio: 30, tipo: 24),
        ],
      );

  /// Di quanto la mappa e' girata rispetto al nord, con segno.
  double giroDi(double? rotta) => (rotta! + 540) % 360 - 180;

  test('sul dritto la mappa segue la vettura, anche col bivio in vista', () {
    final percorso = rampa();
    final g = Guida(percorso);
    // Lontano dalla curva, sul dritto: guarda dritto.
    final lontano = g.aggiorna(percorso.punti[5]);
    expect(giroDi(lontano.rotta), closeTo(0, 1));
    expect(giroDi(lontano.rottaMappa), closeTo(0, 1));
    /* A cento metri dal bivio la strada va ancora a nord: prima qui la mappa
     * era gia' girata verso ovest. Adesso no — e' questa la segnalazione. */
    final centoMetri = g.aggiorna(percorso.punti[20]);
    expect(giroDi(centoMetri.rotta), closeTo(0, 1));
    expect(giroDi(centoMetri.rottaMappa), closeTo(0, 1));
  });

  test('negli ultimi metri la mappa sbircia, ma non piu\' di venticinque gradi', () {
    final percorso = rampa();
    final g = Guida(percorso);
    g.aggiorna(percorso.punti[20]);
    /* A trenta metri dal bivio il punto guardato e' quaranta metri dentro la
     * curva: cinquantatre gradi a ovest. La mappa ne prende venticinque. */
    final gira = giroDi(g.aggiorna(percorso.punti[27]).rottaMappa);
    expect(gira, closeTo(-25, 1));
  });

  test('il tetto si puo\' spostare: a novanta gradi la mappa guarda dove guardava prima', () {
    final percorso = rampa();
    final g = Guida(percorso, anticipoGradi: 90);
    g.aggiorna(percorso.punti[20]);
    final gira = giroDi(g.aggiorna(percorso.punti[27]).rottaMappa);
    expect(gira, lessThan(-45));
    expect(gira, greaterThan(-70));
  });

  /* ── Fuori percorso non e' solo «lontano» ────────────────────────────────
   *
   * Tre foto dal campo, nello stesso viaggio, e una causa sola: il giudizio
   * guardava soltanto la distanza dalla linea. */

  /// Una strada dritta verso nord, un vertice ogni venti metri.
  PercorsoCalcolato dritta({int quanti = 100}) => PercorsoCalcolato(
        punti: [for (var i = 0; i < quanti; i++) Punto(45.0 + i * 0.00018, 9.0)],
        tratti: const [],
        manovre: const [Manovra(istruzione: 'Parti', lunghezzaM: 2000, secondi: 120, inizio: 0, tipo: 1)],
      );

  test('«sto andando in direzione opposta e non ricalcola»', () {
    final percorso = dritta();
    final g = Guida(percorso);
    for (var i = 0; i <= 50; i++) {
      g.aggiorna(percorso.punti[i]);
    }
    /* Inversione a U: si torna indietro sulla stessa carreggiata. La distanza
     * dalla linea resta ZERO — e' per questo che prima non se ne accorgeva
     * nessuno, nemmeno dopo un chilometro. */
    var quando = -1;
    for (var i = 49; i >= 0 && quando < 0; i--) {
      final a = g.aggiorna(percorso.punti[i]);
      expect(a.lontanoM, lessThan(1), reason: 'sulla linea ci si sta, e' ' e' ' il punto');
      if (a.fuoriPercorso) quando = (50 - i) * 20;
    }
    expect(quando, greaterThan(0), reason: 'un chilometro all\'indietro senza dire niente');
    expect(quando, lessThan(120), reason: 'e va detto subito, non dopo mezzo paese');
  });

  test('una traversa a novanta gradi si vede prima di essersene andati', () {
    final percorso = dritta();
    final g = Guida(percorso);
    for (var i = 0; i <= 50; i++) {
      g.aggiorna(percorso.punti[i]);
    }
    /* Si gira a destra: venti metri per lettura, verso est. */
    final da = percorso.punti[50];
    var quando = -1;
    for (var k = 1; k <= 6 && quando < 0; k++) {
      final a = g.aggiorna(Punto(da.lat, da.lon + k * 0.00026));
      if (a.fuoriPercorso) quando = k * 20;
    }
    expect(quando, greaterThan(0));
    expect(quando, lessThan(100), reason: 'in una traversa lo si sa in pochi metri');
  });

  test('allontanandosi dalla strada si ricalcola prima dei trentacinque metri', () {
    /* L'uscita sbagliata che si stacca piano: venticinque, trenta metri, e
     * ogni lettura più lontana. Chi la prende se ne va; il GPS fermo no. */
    final percorso = dritta();
    final g = Guida(percorso);
    for (var i = 0; i <= 50; i++) {
      g.aggiorna(percorso.punti[i]);
    }
    final lati = [0.0001, 0.00022, 0.00034, 0.00042]; // ~8, 17, 27, 33 m a est
    final fuori = <bool>[];
    for (final (k, lato) in lati.indexed) {
      final p = percorso.punti[51 + k];
      final a = g.aggiorna(Punto(p.lat, p.lon + lato));
      expect(a.lontanoM, lessThan(35));
      fuori.add(a.fuoriPercorso);
    }
    expect(fuori, [false, false, false, true]);
  });

  test('fermi a trenta metri dalla linea non si ricalcola per il GPS che balla', () {
    final percorso = dritta();
    final g = Guida(percorso);
    for (var i = 0; i <= 50; i++) {
      g.aggiorna(percorso.punti[i]);
    }
    final da = percorso.punti[50];
    // Fra 26 e 33 metri, avanti e indietro di pochi metri: fermi.
    for (final lato in [0.00034, 0.00037, 0.0004, 0.00042, 0.00038, 0.00041]) {
      expect(g.aggiorna(Punto(da.lat, da.lon + lato)).fuoriPercorso, isFalse);
    }
  });

  test('avanti: il punto più in là lungo la strada, mai oltre l\'arrivo', () {
    final percorso = dritta();
    final g = Guida(percorso);
    final (:punto, :rotta) = g.avanti(100, 30);
    // La dritta va a nord, venti metri ogni punto.
    expect(distanzaM(percorso.punti.first, punto), closeTo(130, 1));
    expect(rotta, anyOf(lessThan(1), greaterThan(359)));
    expect(distanzaM(g.avanti(g.lunghezzaM - 5, 500).punto, percorso.punti.last), lessThan(0.5));
    expect(distanzaM(g.avanti(100, -50).punto, percorso.punti.first), closeTo(100, 1));
  });

  test('fermi al semaforo non si ricalcola: il GPS balla e basta', () {
    final percorso = dritta();
    final g = Guida(percorso);
    for (var i = 0; i <= 50; i++) {
      g.aggiorna(percorso.punti[i]);
    }
    /* Fermi, con letture che saltellano di qualche metro in ogni direzione:
     * la direzione fra due letture e' rumore, e non deve decidere niente. */
    final da = percorso.punti[50];
    const balla = [
      [1.0, 1.0],
      [-1.0, 1.0],
      [-1.0, -1.0],
      [1.0, -1.0],
      [0.5, -1.0],
      [-0.5, 1.0],
    ];
    for (final d in balla) {
      final a = g.aggiorna(Punto(da.lat + d[0] * 0.000018, da.lon + d[1] * 0.000026));
      expect(a.fuoriPercorso, isFalse);
    }
  });

  test('la strada parallela non e\' questa strada', () {
    /* «Anche qua mi da\' la linea nella strada parallela a dove sono.» In un
     * paese italiano due vie parallele stanno a trenta metri: la soglia di
     * prima, quarantacinque, le metteva tutte e due sulla stessa linea. */
    final percorso = dritta();
    final g = Guida(percorso);
    for (var i = 0; i <= 50; i++) {
      g.aggiorna(percorso.punti[i]);
    }
    /* Si prosegue nella stessa direzione ma su una via quaranta metri a lato. */
    var detto = false;
    for (var i = 51; i <= 60 && !detto; i++) {
      final p = percorso.punti[i];
      if (g.aggiorna(Punto(p.lat, p.lon + 0.00051)).fuoriPercorso) detto = true;
    }
    expect(detto, isTrue, reason: 'quaranta metri sono un isolato, non un errore del GPS');
  });

  test('non ci si aggancia a un pezzo di percorso che sta chilometri avanti', () {
    /* Il percorso fa un giro e torna a passare vicino al punto di partenza.
     * Girando in una traversa non ci si deve proiettare sul ritorno: quello
     * faceva saltare il cursore in avanti e diceva che quella strada era gia'
     * stata fatta. */
    final andata = [for (var i = 0; i < 60; i++) Punto(45.0 + i * 0.00018, 9.0)];
    final ritorno = [for (var i = 59; i >= 0; i--) Punto(45.0 + i * 0.00018, 9.00051)];
    final percorso = PercorsoCalcolato(
      punti: [...andata, ...ritorno],
      tratti: const [],
      manovre: const [Manovra(istruzione: 'Parti', lunghezzaM: 4000, secondi: 240, inizio: 0, tipo: 1)],
    );
    final g = Guida(percorso);
    Avanzamento? ultimo;
    for (var i = 0; i <= 20; i++) {
      ultimo = g.aggiorna(andata[i]);
    }
    final primaM = ultimo!.percorsiM;
    /* Ci si sposta sulla corsia del ritorno, che sta a quaranta metri: e' il
     * pezzo di percorso piu' vicino in linea d'aria, ma sta piu' di due
     * chilometri avanti e non ci si puo' essere arrivati in un secondo. */
    final a = g.aggiorna(Punto(andata[20].lat, andata[20].lon + 0.00051));
    expect(a.percorsiM, lessThan(primaM + 200), reason: 'il cursore non salta di due chilometri');
  });
}
