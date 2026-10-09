import 'dart:math' as math;

import '../geo/geo.dart';
import '../percorso/valhalla.dart';

/// Dove si è lungo il percorso, e cosa viene dopo.
class Avanzamento {
  const Avanzamento({
    required this.percorsiM,
    required this.restantiM,
    required this.restante,
    required this.lontanoM,
    required this.prossima,
    required this.allaProssimaM,
    required this.dopo,
    required this.fuoriPercorso,
    required this.arrivato,
    required this.posizioneSulPercorso,
    required this.rotta,
    double? rottaMappa,
    this.limiteKmh,
    this.daDire,
  }) : _rottaMappa = rottaMappa;

  final double percorsiM;
  final double restantiM;
  final Duration restante;

  /// Quanto si è lontani dalla linea del percorso.
  final double lontanoM;

  /// La prossima manovra, e quanto manca. `null` solo all'arrivo.
  final Manovra? prossima;
  final double allaProssimaM;

  /// Quella dopo ancora, per il «poi».
  final Manovra? dopo;

  /// Si è usciti di strada da qualche lettura: si ricalcola.
  final bool fuoriPercorso;
  final bool arrivato;

  /// Il punto del percorso su cui posare il segnaposto, **o niente**.
  ///
  /// Un navigatore aggancia: se sei in strada, il puntino sta in strada, e
  /// non balla insieme al GPS fra i palazzi. Ma agganciare e' una bugia utile
  /// solo finche' e' vera. A quaranta metri dalla linea — che e' un'altra via,
  /// o il parcheggio accanto — un puntino incollato alla strada racconta un
  /// viaggio che non si sta facendo, e lo racconta proprio nel momento in cui
  /// chi guida deve capire che ha sbagliato. Quindi fuori tolleranza qui non
  /// c'e' niente, e chi disegna torna al punto grezzo:
  ///
  /// ```dart
  /// final qui = avanzamento?.posizioneSulPercorso ?? posizione.qui;
  /// ```
  final Punto? posizioneSulPercorso;

  /// Vero quando il segnaposto sta sulla strada e non dove dice il GPS.
  bool get agganciato => posizioneSulPercorso != null;

  /// La direzione della strada in quel punto, in gradi da nord in senso
  /// orario: per girare l'auto e la mappa. Niente quando non si e'
  /// agganciati, per la stessa ragione del punto.
  final double? rotta;

  /// Dove guarda la mappa: un po' più avanti lungo il percorso, così su una
  /// rampa in curva la prossima manovra resta in vista invece di finire di
  /// lato. Sul dritto è uguale a [rotta].
  double? get rottaMappa => _rottaMappa ?? rotta;
  final double? _rottaMappa;

  /// Il limite di velocità dove si è, se si conosce.
  final int? limiteKmh;

  /// Una frase nuova da dire ad alta voce, se è il momento.
  final String? daDire;
}

/// Segue chi guida lungo un percorso di Valhalla: a ogni posizione GPS dice
/// a che punto si è, la prossima manovra e se è ora di annunciarla.
class Guida {
  Guida(
    this.percorso, {
    this.sogliaFuoriM = 35,
    this.lettureFuori = 2,
    this.sogliaPrestoM = 25,
    this.sogliaAggancioM = 20,
    this.sogliaSgancioM = 32,
    this.sogliaControManoGradi = 75,
    this.lettureContromano = 3,
    this.movimentoCheContaM = 8,
    this.guardaAvantiM = 80,
    this.anticipaDaM = 60,
    this.anticipoGradi = 25,
  }) : _linea = Linea(percorso.punti) {
    _secondi = _secondiCumulati();
  }

  final PercorsoCalcolato percorso;

  /* Quanto lontani dalla linea per dire «non sei su questa strada».
   *
   * Erano quarantacinque metri, ed erano troppi: in un paese italiano due
   * strade parallele stanno a trenta, e da quarantacinque la plancia disegnava
   * la linea sulla via accanto a quella dove si era davvero senza avere niente
   * da ridire. Trentacinque sta sopra l'errore del GPS in mezzo alla strada e
   * sotto la larghezza di un isolato. Sotto non si scende: fra i palazzi alti
   * il telefono sbaglia di quanto basta a gridare al lupo. */
  final double sogliaFuoriM;

  /* Quante letture fuori di fila prima di ricalcolare. Erano tre: con una
   * lettura al secondo, più il ricalcolo, il percorso nuovo arrivava quando
   * si era già alla traversa dopo. Due bastano: una lettura storta da sola resta fuori, e
   * oltre trentacinque metri il GPS non sbaglia due volte di fila. */
  final int lettureFuori;

  /* Prima ancora: oltre [sogliaPrestoM] e ALLONTANANDOSI, lettura dopo
   * lettura, mentre ci si muove davvero. Il GPS fermo fra i palazzi balla
   * intorno alla strada, avanti e indietro; chi ha preso l'uscita sbagliata
   * se ne va, e ogni secondo è più lontano. Due letture così e si ricalcola,
   * senza aspettare di essere a un isolato di distanza. */
  final double sogliaPrestoM;

  /* Di quanto la direzione in cui si va può discostarsi da quella della strada
   * prima di dire che non è quella strada. Settantacinque gradi: una traversa
   * la si prende a novanta, un'inversione a centottanta, e una curva presa
   * larga non ci arriva mai. */
  final double sogliaControManoGradi;
  final int lettureContromano;

  /// Sotto questo passo fra due letture la direzione è rumore del GPS.
  final double movimentoCheContaM;

  /* Come guarda avanti la telecamera.
   *
   * Tre foto dal campo, una richiesta sola: «se la strada è dritta la mappa
   * deve seguire la vettura», e «non è che mi propone un tornante quando è
   * una semplice deviazione».
   *
   * [guardaAvantiM] è fin dove si guarda sul dritto. Erano centocinquanta
   * metri: una curva a centocinquanta metri faceva girare la mappa mentre si
   * era ancora sul rettilineo. A ottanta, su una strada dritta il punto che
   * si guarda sta sul dritto, e la mappa non gira.
   *
   * [anticipaDaM] è da quanto vicino si sbircia oltre la manovra, per far
   * vedere da che parte si va. Prima si sbirciava da centocinquanta metri:
   * quaranta metri oltre l'uscita si è già sull'altra strada, e la mappa
   * girava come per un tornante mentre l'auto era ancora sul dritto.
   *
   * [anticipoGradi] è il tetto: comunque vada, la mappa non può guardare più
   * di venticinque gradi fuori dalla strada che si sta percorrendo. Il resto
   * lo recupera girando, insieme all'auto — che è quello che fa una
   * telecamera che segue, invece di indovinare. */
  final double guardaAvantiM;
  final double anticipaDaM;
  final double anticipoGradi;

  /* Quanto vicini alla linea per posare il segnaposto sulla strada, e quanto
   * lontani per toglierlo.
   *
   * Sono due numeri e non uno perche' uno solo fa lampeggiare. Con una soglia
   * sola, a venti metri esatti — e a venti metri ci si sta per interi minuti,
   * su una statale larga — una lettura aggancia e la successiva sgancia, e il
   * puntino salta avanti e indietro fra la strada e il prato accanto. Con due
   * ci si aggancia stando vicini e ci si stacca solo andando via davvero.
   *
   * E sono piu' stretti dei quarantacinque metri del «fuori percorso», perche'
   * le due domande sono diverse: quella chiede «devo ricalcolare?» e se ne
   * puo' permettere la calma, questa chiede «dove disegno l'auto?» e un
   * errore si vede subito. A quaranta metri dalla linea si e' in un'altra
   * strada, e un puntino incollato a quella giusta racconta un viaggio che non
   * si sta facendo. */
  final double sogliaAggancioM;
  final double sogliaSgancioM;
  final Linea _linea;
  late final List<double> _secondi;

  var _segmento = 0;
  var _fuori = 0;
  var _siAllontana = 0;
  double? _lontanoPrima;
  var _controMano = 0;
  var _agganciato = false;
  Punto? _precedente;
  final _annunciate = <String>{};

  /// Le distanze a cui si annuncia una manovra: da lontano e all'ultimo.
  static const _lontano = 800.0, _vicino = 150.0;

  double get lunghezzaM => _linea.lunghezzaM;

  /// La stessa strada con tempi nuovi (il traffico aggiornato): si resta a
  /// che punto si era, e le manovre già dette non si ripetono.
  Guida conTempi(PercorsoCalcolato nuovo) {
    final g = Guida(
      nuovo,
      sogliaFuoriM: sogliaFuoriM,
      lettureFuori: lettureFuori,
      sogliaPrestoM: sogliaPrestoM,
      sogliaControManoGradi: sogliaControManoGradi,
      lettureContromano: lettureContromano,
      movimentoCheContaM: movimentoCheContaM,
      guardaAvantiM: guardaAvantiM,
      anticipaDaM: anticipaDaM,
      anticipoGradi: anticipoGradi,
    );
    if (nuovo.punti.length != percorso.punti.length) return g;
    g._segmento = _segmento;
    g._agganciato = _agganciato;
    /* Anche l'ultima posizione: senza, la prima lettura dopo un traffico
     * aggiornato non avrebbe da che parte si sta andando, e il controllo della
     * direzione si prenderebbe un secondo di pausa a ogni giro. */
    g._precedente = _precedente;
    g._annunciate.addAll(_annunciate);
    return g;
  }

  Avanzamento aggiorna(Punto qui) {
    /* Si cerca poco indietro e solo fin dove si poteva davvero arrivare: su
     * una strada che torna su se stessa si resta dalla parte giusta, e non ci
     * si aggancia a un pezzo di percorso che sta chilometri più avanti.
     *
     * Prima la finestra era di quattrocento segmenti fissi, che su un percorso
     * cittadino sono chilometri. In città il percorso ripassa vicino di
     * continuo, e bastava girare in una traversa per proiettarsi su un tratto
     * lontanissimo: la distanza restava piccola, il cursore saltava in avanti,
     * e il navigatore diceva che quella strada l'avevi già fatta. */
    final p = _linea.proiettaTra(qui, math.max(0, _segmento - 3), _segmento + _quantiAvanti(qui));
    final passo = _precedente == null ? null : distanzaM(_precedente!, qui);
    if (p.lontanoM <= sogliaFuoriM) {
      _segmento = p.segmento;
      _fuori = 0;
    } else {
      _fuori++;
    }
    _guardaDoveSiVa(qui, p, passo);
    _guardaSeCiSiAllontana(p, passo);
    _precedente = qui;
    final percorsi = p.lungoM;
    final restanti = math.max(0.0, _linea.lunghezzaM - percorsi);
    final i = p.segmento;
    final secondiQui = _secondi[i] + p.t * (_secondi[math.min(i + 1, _secondi.length - 1)] - _secondi[i]);
    final restante = Duration(seconds: math.max(0, _secondi.last - secondiQui).round());

    final manovre = percorso.manovre;
    var k = manovre.indexWhere((m) => _linea.cumulate[_indice(m)] > percorsi + 1);
    final prossima = k < 0 ? null : manovre[k];
    final dopo = k < 0 || k + 1 >= manovre.length ? null : manovre[k + 1];
    final alla = prossima == null ? 0.0 : _linea.cumulate[_indice(prossima)] - percorsi;
    final arrivato = restanti < 25;

    /* Si aggancia stando vicini, ci si stacca solo andando via davvero. */
    _agganciato = p.lontanoM <= (_agganciato ? sogliaSgancioM : sogliaAggancioM);
    final sulla = _agganciato ? _punto(i, p.t) : null;

    return Avanzamento(
      percorsiM: percorsi,
      restantiM: restanti,
      restante: restante,
      lontanoM: p.lontanoM,
      prossima: prossima,
      allaProssimaM: alla,
      dopo: dopo,
      fuoriPercorso: _fuori >= lettureFuori || _siAllontana >= 2 || _controMano >= lettureContromano,
      arrivato: arrivato,
      posizioneSulPercorso: sulla,
      rotta: _agganciato ? _rotta(i) : null,
      /* La telecamera guarda avanti anche da fuori percorso — e' da li' che
       * si vede dove si sarebbe dovuti andare — ma sempre restando appesa
       * alla strada che si sta percorrendo: vedi _rottaAvanti. */
      rottaMappa: _rottaAvanti(_punto(i, p.t), percorsi, prossima == null ? null : alla, _rotta(i)),
      // In fondo a un segmento si è già all'inizio del prossimo.
      limiteKmh: percorso.limiteSul(p.t > 0.999 ? i + 1 : i),
      daDire: arrivato ? _una('arrivo', 'Sei arrivato.') : _annuncio(prossima, alla),
    );
  }

  String? _annuncio(Manovra? m, double alla) {
    if (m == null || m.voce.isEmpty) return null;
    final id = '${m.inizio}';
    if (alla <= _vicino) return _una('$id-vicino', m.voce);
    if (alla <= _lontano) return _una('$id-lontano', 'Tra ${distanzaParlata(alla)}, ${_minuscola(m.voce)}');
    return null;
  }

  /// Ogni frase si dice una volta sola.
  String? _una(String chiave, String frase) => _annunciate.add(chiave) ? frase : null;

  int _indice(Manovra m) => math.min(m.inizio, _linea.punti.length - 1);

  Punto _punto(int i, double t) {
    final a = _linea.punti[i], b = _linea.punti[math.min(i + 1, _linea.punti.length - 1)];
    return Punto(a.lat + t * (b.lat - a.lat), a.lon + t * (b.lon - a.lon));
  }

  /// La direzione del segmento [i]; se è cortissimo, quella dei successivi.
  /* Fin dove ha senso cercarsi sul percorso.
   *
   * Fra due letture GPS passa un secondo: anche a duecento all'ora sono
   * cinquantacinque metri. Si guarda quanto ci si è spostati davvero e si
   * lascia larghezza — il triplo, e mai meno di duecento metri, per i buchi di
   * segnale sotto un cavalcavia — poi si contano i segmenti che ci stanno.
   * Oltre non si può essere arrivati, e cercarsi oltre vuol dire trovarsi. */
  int _quantiAvanti(Punto qui) {
    /* Alla prima lettura non si sa da dove si arriva, e allora non si sa
     * nemmeno quanto lontano si possa essere: si guarda tutto il percorso.
     * Senza questa riga, chi riapre il navigatore a metà viaggio — o chi si
     * mette in strada dopo un ricalcolo — non riuscirebbe a trovarsi, perché
     * si cercherebbe solo nei primi duecento metri. */
    if (_precedente == null) return _linea.punti.length;
    final passo = distanzaM(_precedente!, qui);
    final quanti = math.max(200.0, passo * 3);
    final da = _linea.cumulate[math.min(_segmento, _linea.cumulate.length - 1)];
    var j = _segmento;
    while (j + 1 < _linea.cumulate.length && _linea.cumulate[j + 1] - da <= quanti) {
      j++;
    }
    /* Almeno una manciata: su un percorso coi vertici radi, contare i metri
     * potrebbe non farne entrare nemmeno uno. */
    return math.max(8, j - _segmento + 1);
  }

  /* Andare in una direzione che quella strada non ha è fuori percorso, anche
   * standoci sopra.
   *
   * «Sto andando in direzione opposta e non ricalcola.» Ed era vero, sempre:
   * il giudizio guardava solo QUANTO SI È LONTANI dalla linea, e facendo
   * inversione sulla stessa carreggiata da quella linea non ci si allontana di
   * un metro. Provato a tavolino: un chilometro all'indietro sulla stessa
   * strada, distanza zero a ogni lettura, mai una volta «fuori percorso» — e i
   * metri percorsi che tornavano indietro come se fosse previsto.
   *
   * La direzione però ce l'abbiamo già, e non serve la bussola: due posizioni
   * di fila dicono da che parte si sta andando. Se quella direzione litiga con
   * la strada su cui ci si è proiettati, non si è su quella strada — si è su
   * un'altra che le passa vicino, o sulla stessa al contrario.
   *
   * ── Le tre prudenze ─────────────────────────────────────────────────────
   *
   * · **fermi non si decide.** Sotto i passi brevi la direzione fra due letture
   *   è il rumore del GPS, che gira su se stesso: al semaforo si inventerebbe
   *   un'inversione a ogni secondo;
   * · **lontani dalla linea non si decide.** Se si è già oltre la soglia se ne
   *   occupa il conto della distanza, che è il giudice giusto per quel caso;
   * · **e si aspetta comunque.** Tre letture come per la distanza: una curva
   *   stretta presa larga, o un vertice raro del percorso, fanno litigare le
   *   due direzioni per un attimo senza che nessuno abbia sbagliato strada. */
  void _guardaDoveSiVa(Punto qui, Proiezione p, double? passo) {
    if (passo == null || passo < movimentoCheContaM || p.lontanoM > sogliaFuoriM) {
      _controMano = 0;
      return;
    }
    final siVa = rottaGradi(_precedente!, qui);
    final laStrada = _rotta(p.segmento);
    if (diQuantoSiGira(laStrada, siVa).abs() >= sogliaControManoGradi) {
      _controMano++;
    } else {
      _controMano = 0;
    }
  }

  /// Vedi [sogliaPrestoM]: fermi (passi più corti di [movimentoCheContaM])
  /// non si decide niente, come per la direzione.
  void _guardaSeCiSiAllontana(Proiezione p, double? passo) {
    final prima = _lontanoPrima;
    _lontanoPrima = p.lontanoM;
    if (p.lontanoM <= sogliaPrestoM) {
      _siAllontana = 0;
    } else if (prima != null && passo != null && passo >= movimentoCheContaM && p.lontanoM > prima + 2) {
      _siAllontana++;
    } else if (prima != null && p.lontanoM < prima - 2) {
      // Si torna verso la strada: non ci si sta allontanando.
      _siAllontana = 0;
    }
  }

  /// Il punto [metri] più avanti di [percorsiM] lungo il percorso, con la
  /// direzione della strada lì; mai oltre l'arrivo.
  ///
  /// Serve a chi disegna: il GPS dice dov'era l'auto quando l'ha letta, e
  /// fra quella lettura e il disegno passano centinaia di millisecondi — a
  /// novanta all'ora una trentina di metri. Sulla strada si sa dove si va,
  /// e il segnaposto ci si può portare.
  ({Punto punto, double rotta}) avanti(double percorsiM, double metri) {
    final c = _linea.cumulate, punti = _linea.punti;
    if (punti.length < 2) return (punto: punti.isEmpty ? const Punto(0, 0) : punti.first, rotta: 0);
    final meta = (percorsiM + math.max(0.0, metri)).clamp(0.0, _linea.lunghezzaM);
    var j = 1;
    while (j < c.length - 1 && c[j] < meta) {
      j++;
    }
    final f = c[j] == c[j - 1] ? 0.0 : ((meta - c[j - 1]) / (c[j] - c[j - 1])).clamp(0.0, 1.0);
    final a = punti[j - 1], b = punti[j];
    return (punto: Punto(a.lat + f * (b.lat - a.lat), a.lon + f * (b.lon - a.lon)), rotta: _rotta(j - 1));
  }

  double _rotta(int i) {
    final n = _linea.punti.length;
    var j = math.min(i + 1, n - 1);
    while (j < n - 1 && distanzaM(_linea.punti[i], _linea.punti[j]) < 8) {
      j++;
    }
    return rottaGradi(_linea.punti[math.min(i, n - 1)], _linea.punti[j]);
  }

  /// La direzione verso un punto più avanti sul percorso: di solito 150 m;
  /// vicino a una manovra, poco oltre la manovra, per vederne l'uscita.
  /* Dove guarda la telecamera: avanti, ma appesa alla strada che si percorre.
   *
   * Si sceglie un punto piu' avanti sul percorso e si guarda quello. Fin dove
   * lo si sceglie lo dicono [guardaAvantiM] e [anticipaDaM]; di quanto la
   * mappa puo' allontanarsi dalla strada sotto le ruote lo dice
   * [anticipoGradi]. Il tetto e' la parte che conta: senza, su un'uscita che
   * si stacca e curva bastava un punto quaranta metri oltre lo svincolo — gia'
   * sull'altra strada — per far ruotare la mappa di sessanta gradi mentre
   * l'auto era ancora sul rettilineo, e sembrava di dover fare un tornante. */
  double? _rottaAvanti(Punto qui, double percorsi, double? alla, double strada) {
    final vicina = alla != null && alla <= anticipaDaM;
    final avanti = vicina ? math.max(40.0, alla + 40) : guardaAvantiM;
    final meta = math.min(percorsi + avanti, _linea.lunghezzaM);
    if (meta - percorsi < 20) return null;
    final punti = _linea.punti, c = _linea.cumulate;
    for (var j = 1; j < punti.length; j++) {
      if (c[j] >= meta) {
        final f = c[j] == c[j - 1] ? 0.0 : (meta - c[j - 1]) / (c[j] - c[j - 1]);
        final a = punti[j - 1], b = punti[j];
        final verso = rottaGradi(qui, Punto(a.lat + f * (b.lat - a.lat), a.lon + f * (b.lon - a.lon)));
        final scarto = diQuantoSiGira(strada, verso);
        if (scarto.abs() <= anticipoGradi) return verso;
        return versoDiLa(strada, verso, anticipoGradi / scarto.abs());
      }
    }
    return null;
  }

  /// Il tempo cumulato a ogni punto, con la velocità della manovra a cui il
  /// segmento appartiene.
  /// I secondi dall'inizio a ogni punto: dai tempi dei tratti (che hanno
  /// dentro il traffico), o, senza tratti, da quelli delle manovre.
  List<double> _secondiCumulati() {
    final tratti = percorso.tratti;
    final n = _linea.punti.length;
    if (tratti.isNotEmpty && n > 1 && _linea.lunghezzaM > 0) {
      final totale = tratti.fold(0.0, (s, t) => s + t.lunghezzaM);
      final k = totale / _linea.lunghezzaM;
      final s = <double>[0];
      var j = 0;
      var inizioM = 0.0, inizioS = 0.0;
      for (var i = 1; i < n; i++) {
        final m = _linea.cumulate[i] * k;
        while (j < tratti.length - 1 && inizioM + tratti[j].lunghezzaM < m) {
          inizioM += tratti[j].lunghezzaM;
          inizioS += tratti[j].secondi;
          j++;
        }
        final t = tratti[j];
        final dentro = (m - inizioM).clamp(0.0, t.lunghezzaM);
        s.add(math.max(s.last, inizioS + dentro / (t.velocitaKmh / 3.6)));
      }
      return s;
    }
    return _secondiDaManovre();
  }

  List<double> _secondiDaManovre() {
    final n = _linea.punti.length;
    final velocita = List<double>.filled(math.max(n - 1, 0), 13.9);
    final manovre = percorso.manovre;
    for (var k = 0; k < manovre.length; k++) {
      final m = manovre[k];
      final fine = k + 1 < manovre.length ? manovre[k + 1].inizio : n - 1;
      final v = m.secondi > 0 && m.lunghezzaM > 0 ? m.lunghezzaM / m.secondi : 13.9;
      for (var i = m.inizio; i < fine && i < n - 1; i++) {
        velocita[i] = v;
      }
    }
    final s = <double>[0];
    for (var i = 0; i < n - 1; i++) {
      s.add(s.last + (_linea.cumulate[i + 1] - _linea.cumulate[i]) / velocita[i]);
    }
    return s;
  }

  static String _minuscola(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
}

/// «300 metri», «1 chilometro», «2,5 chilometri»: come si dice guidando.
String distanzaParlata(double metri) {
  if (metri < 1000) {
    final m = metri < 100 ? (metri / 10).round() * 10 : (metri / 50).round() * 50;
    return '$m metri';
  }
  final km = (metri / 100).round() / 10;
  if (km == 1) return '1 chilometro';
  final testo = km == km.roundToDouble() ? '${km.round()}' : km.toStringAsFixed(1).replaceAll('.', ',');
  return '$testo chilometri';
}

/// «300 m», «1,2 km»: come si scrive sullo schermo.
String distanzaBreve(double metri) {
  if (metri < 1000) {
    final m = metri < 100 ? (metri / 10).round() * 10 : (metri / 50).round() * 50;
    return '$m m';
  }
  return metri < 10000
      ? '${(metri / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
      : '${(metri / 1000).round()} km';
}
