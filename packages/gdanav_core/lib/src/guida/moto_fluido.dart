import 'dart:math' as math;

import '../geo/geo.dart';

/* ─── L'auto che scorre, fra una posizione e l'altra ────────────────────────
 *
 * Dal campo, la prima volta: «la freccia sulla mappa non è fluida, prende
 * pause e poi cammina». Il GPS dà una posizione al secondo (a volte 1,2 s, a
 * volte 0,8), e fra l'una e l'altra la freccia andava fino all'ultima arrivata
 * e lì si fermava ad aspettare la prossima.
 *
 * Dal campo, la seconda: «non è ancora fluido il movimento della freccia, ha
 * ancora dei piccoli frame lag, deve essere continuo con il movimento
 * dell'auto». La freccia inseguiva un punto previsto avvicinandosi ogni
 * fotogramma di una parte della distanza, e la parte che sarebbe tornata
 * indietro lungo la strada si buttava. Ogni posizione nuova un metro dietro la
 * previsione (succede a ogni frenata, e a ogni lettura un po' in ritardo)
 * voleva dire un passo zero: la freccia si fermava per qualche fotogramma e
 * poi ripartiva, tre volte al secondo. Le piccole pause.
 *
 * Adesso la freccia ha una **velocità sua**, che cambia piano:
 *
 *  - fra due posizioni l'auto va avanti da sola, come prima: dalla velocità e
 *    dalla direzione dell'ultima, e da quanto stava girando. Mai più in là di
 *    [MotoFluido.oltreAlPiu] dall'ultima posizione;
 *  - **lungo la strada** la freccia va alla velocità dell'auto, più o meno
 *    quanto serve a recuperare lo scarto dalla previsione in
 *    [MotoFluido.tauLungo]: davanti di tre metri va un po' più piano, dietro
 *    un po' più forte. Mai sotto un quarto della velocità dell'auto: andando
 *    non si ferma, e non torna indietro. Quella velocità poi cambia morbida
 *    ([MotoFluido.tauVelocita]): una posizione nuova non è uno scatto;
 *  - **di lato** si corregge con la costante [MotoFluido.tau] (una curva, un
 *    aggancio alla strada accanto);
 *  - da fermi (o col GPS muto da troppo) la freccia rallenta fino al punto e
 *    lì si ferma; se il punto è appena dietro (l'auto si è fermata prima di
 *    quanto si prevedeva) resta dov'è: solo un punto davvero lontano dietro,
 *    più di [MotoFluido.indietroAlPiuM], la riporta indietro.
 *
 * Il conto è uguale per il telefono, Android Auto e CarPlay (che lo rifanno in
 * Kotlin e Swift, `MotoAuto.kt` e `MappaCarPlay.swift`, coi numeri di qui). */

/// Dove disegnare l'auto a ogni fotogramma, fra una posizione e l'altra.
///
/// I tempi sono [Duration] di un orologio che va solo avanti (quello dei
/// fotogrammi), non ore del giorno.
class MotoFluido {
  MotoFluido({
    this.tau = const Duration(milliseconds: 200),
    this.tauLungo = const Duration(milliseconds: 1000),
    this.tauVelocita = const Duration(milliseconds: 250),
    this.oltreAlPiu = const Duration(milliseconds: 1500),
    this.saltoM = 120,
  });

  /// Di lato e nella direzione: quanto ci mette la freccia a recuperare due
  /// terzi dello scarto.
  final Duration tau;

  /// Lungo la strada: in quanto tempo la velocità della freccia vuole
  /// recuperare lo scarto dalla previsione.
  final Duration tauLungo;

  /// Quanto ci mette la velocità della freccia a cambiare: senza, una
  /// posizione nuova cambierebbe la velocità di colpo.
  final Duration tauVelocita;

  /// Oltre questo tempo dall'ultima posizione la previsione si ferma.
  final Duration oltreAlPiu;

  /// Più lontano di così si salta: un ricalcolo, un GPS che torna.
  final double saltoM;

  /// Sotto questa velocità si è fermi: niente previsione.
  static const fermoSottoMs = 0.5;

  /// Quanto si gira al massimo, in gradi al secondo, per la previsione: oltre
  /// è rumore della direzione, non una curva.
  static const giraAlPiuGradiS = 45.0;

  /// Andando, la freccia non va mai più piano di così (una parte della
  /// velocità dell'auto): rallenta, ma non si ferma.
  static const almenoDellaVelocita = 0.25;

  /// Da fermi un punto dietro la freccia più vicino di così non la fa tornare
  /// indietro: si era andati un poco oltre, e lì si resta.
  static const indietroAlPiuM = 8.0;

  /// Un fotogramma che arriva tardi conta al più tanto: oltre, la freccia
  /// recupera dopo invece di saltare.
  static const fotogrammaAlPiuS = 0.25;

  Punto? _fix;
  double _rottaFix = 0, _velocita = 0, _gira = 0;
  Duration _alle = Duration.zero;

  Punto? _mostrata;
  double _rottaMostrata = 0;
  double _velocitaMostrata = 0;
  Duration? _ultimoFotogramma;
  var _fermo = true;

  /// Dove è disegnata l'auto adesso; `null` prima della prima posizione.
  Punto? get mostrata => _mostrata;

  /// La direzione della freccia adesso, in gradi da nord.
  double get rottaMostrata => _rottaMostrata;

  /// La velocità della freccia adesso, in m/s.
  double get velocitaMostrata => _velocitaMostrata;

  /// Non servono più fotogrammi finché non arriva una posizione nuova: fermi,
  /// o col GPS muto da più di [oltreAlPiu], e con la freccia già arrivata.
  bool get fermo => _fermo;

  /// Una posizione nuova: [rotta] in gradi da nord, [velocitaMs] la velocità
  /// lungo la strada, [alle] sull'orologio dei fotogrammi.
  void posizione(Punto p, {required double rotta, required double velocitaMs, required Duration alle}) {
    final prima = _fix;
    final passo = (alle - _alle).inMicroseconds / 1e6;
    // Quanto si sta girando: dalle ultime due direzioni, se sono vicine nel
    // tempo e ci si muove (da fermi la direzione del GPS non vuol dire niente).
    if (prima != null && velocitaMs >= 2 && passo >= 0.2 && passo <= 3) {
      _gira = (diQuantoSiGira(_rottaFix, rotta) / passo).clamp(-giraAlPiuGradiS, giraAlPiuGradiS).toDouble();
    } else if (passo > 0.2 || prima == null) {
      _gira = 0;
    }
    _fix = p;
    _rottaFix = rotta;
    _velocita = velocitaMs.isFinite && velocitaMs > 0 ? velocitaMs : 0;
    _alle = alle;
    _fermo = false;
  }

  /// Dove l'auto dovrebbe essere a [adesso], e girata come: la previsione
  /// dall'ultima posizione. `null` prima della prima.
  ({Punto punto, double rotta})? previsione(Duration adesso) {
    final f = _fix;
    if (f == null) return null;
    if (_velocita < fermoSottoMs) return (punto: f, rotta: _rottaFix);
    var t = (adesso - _alle).inMicroseconds / 1e6;
    if (t < 0) t = 0;
    final massimo = oltreAlPiu.inMicroseconds / 1e6;
    if (t > massimo) t = massimo;
    final (est, nord) = _avanti(_rottaFix, _gira, _velocita, t);
    return (punto: _sposta(f, est, nord), rotta: (_rottaFix + _gira * t + 360) % 360);
  }

  /// Un fotogramma: dove disegnare l'auto a [adesso], e girata come.
  ({Punto punto, double rotta})? fotogramma(Duration adesso) {
    final obiettivo = previsione(adesso);
    if (obiettivo == null) return null;
    final m = _mostrata;
    final ultimo = _ultimoFotogramma;
    _ultimoFotogramma = adesso;
    final andando = _velocita >= fermoSottoMs && !_oltre(adesso);
    if (m == null || ultimo == null || distanzaM(m, obiettivo.punto) > saltoM) {
      _mostrata = obiettivo.punto;
      _rottaMostrata = obiettivo.rotta;
      _velocitaMostrata = andando ? _velocita : 0;
      _fermo = !andando;
      return (punto: obiettivo.punto, rotta: obiettivo.rotta);
    }
    var dt = (adesso - ultimo).inMicroseconds / 1e6;
    if (dt < 0) dt = 0;
    if (dt > fotogrammaAlPiuS) dt = fotogrammaAlPiuS;
    final (dx, dy) = _metri(m, obiettivo.punto);
    final s = _passo(
      dx: dx,
      dy: dy,
      rottaObiettivo: obiettivo.rotta,
      dt: dt,
      andando: andando,
    );
    _mostrata = _sposta(m, s.est, s.nord);
    _rottaMostrata = versoDiLa(_rottaMostrata, obiettivo.rotta, s.k);
    _fermo = !andando && s.arrivata && diQuantoSiGira(_rottaMostrata, obiettivo.rotta).abs() < 0.5;
    return (punto: _mostrata!, rotta: _rottaMostrata);
  }

  /// Il passo di un fotogramma lungo [dt] secondi, con lo scarto ([dx] verso
  /// est, [dy] verso nord, in metri) fra la freccia e la previsione.
  ({double est, double nord, double k, bool arrivata}) _passo({
    required double dx,
    required double dy,
    required double rottaObiettivo,
    required double dt,
    required bool andando,
  }) {
    final r = rottaObiettivo * math.pi / 180;
    final ve = math.sin(r), vn = math.cos(r);
    // Lo scarto lungo la strada (avanti positivo) e di lato (a destra positivo).
    final lungo = dx * ve + dy * vn;
    final lato = dx * vn - dy * ve;
    final k = dt <= 0 ? 0.0 : 1 - math.exp(-dt / _secondi(tau));
    final kv = dt <= 0 ? 0.0 : 1 - math.exp(-dt / _secondi(tauVelocita));
    double avanti;
    var arrivata = false;
    if (andando) {
      final minima = _velocita * almenoDellaVelocita;
      final massima = math.max(_velocita * 2, _velocita + 10);
      // Lo scarto dopo questo passo, se la freccia tenesse la sua velocità:
      // la previsione intanto è già andata avanti di un fotogramma.
      final scarto = lungo - _velocitaMostrata * dt;
      final voluta = (_velocita + scarto / _secondi(tauLungo)).clamp(minima, massima).toDouble();
      _velocitaMostrata += (voluta - _velocitaMostrata) * kv;
      if (_velocitaMostrata < minima) _velocitaMostrata = minima;
      avanti = _velocitaMostrata * dt;
    } else if (lungo < 0 && lungo > -indietroAlPiuM) {
      // Fermi, e il punto è appena dietro: si resta, rallentando di colpo no.
      _velocitaMostrata = 0;
      avanti = 0;
      arrivata = lato.abs() < 0.3;
    } else if (lungo < 0) {
      // Molto dietro: il GPS ha corretto davvero, si torna (piano).
      _velocitaMostrata = 0;
      avanti = lungo * k;
    } else {
      // Fermi (o GPS muto) e il punto davanti: si rallenta fino a lì.
      final voluta = lungo / _secondi(tauLungo) * 2;
      _velocitaMostrata += (voluta - _velocitaMostrata) * kv;
      if (_velocitaMostrata < 0) _velocitaMostrata = 0;
      avanti = math.min(_velocitaMostrata * dt, lungo);
      arrivata = lungo - avanti < 0.3 && lato.abs() < 0.3;
      if (arrivata) _velocitaMostrata = 0;
    }
    final diLato = lato * k;
    return (est: avanti * ve + diLato * vn, nord: avanti * vn - diLato * ve, k: k, arrivata: arrivata);
  }

  /// Si ricomincia: la prossima posizione si disegna dov'è, senza inseguirla
  /// (la mappa è stata spostata col dito, o rifatta).
  void dimentica() {
    _mostrata = null;
    _ultimoFotogramma = null;
    _velocitaMostrata = 0;
  }

  bool _oltre(Duration adesso) => adesso - _alle >= oltreAlPiu;

  static double _secondi(Duration d) => d.inMicroseconds / 1e6;

  /// Quanti metri verso est e verso nord si fanno in [t] secondi partendo
  /// con [rotta], girando di [gira] gradi al secondo, a [v] m/s.
  static (double, double) _avanti(double rotta, double gira, double v, double t) {
    final r0 = rotta * math.pi / 180;
    final w = gira * math.pi / 180;
    if (w.abs() < 1e-4) return (v * t * math.sin(r0), v * t * math.cos(r0));
    final r1 = r0 + w * t;
    return (v / w * (math.cos(r0) - math.cos(r1)), v / w * (math.sin(r1) - math.sin(r0)));
  }

  static const _metriPerGrado = 111195.08;

  static (double, double) _metri(Punto da, Punto a) {
    final coslat = math.cos(da.lat * math.pi / 180);
    return ((a.lon - da.lon) * _metriPerGrado * coslat, (a.lat - da.lat) * _metriPerGrado);
  }

  static Punto _sposta(Punto p, double est, double nord) {
    final coslat = math.cos(p.lat * math.pi / 180);
    return Punto(p.lat + nord / _metriPerGrado, p.lon + (coslat.abs() < 1e-9 ? 0 : est / (_metriPerGrado * coslat)));
  }
}

/* ─── Sulla strada, non accanto ────────────────────────────────────────────
 *
 * Dal campo: «il navigatore continua a non essere preciso, non segue la
 * strada agli svincoli e alle rotonde, l'auto va fuori strada». [MotoFluido]
 * fa andare la freccia dritta nella direzione della strada e la riporta sulla
 * linea di lato, piano: su un rettilineo non si vede, ma in una rotonda (una
 * curva di quindici metri di raggio) o su un'uscita a novanta gradi la
 * freccia tagliava la curva. Sullo schermo dell'auto era peggio: fra una
 * posizione e l'altra la previsione andava avanti fino a un secondo e mezzo
 * con la curva che si stava facendo, e allo svincolo tirava dritto nel prato.
 *
 * In guida però la strada si conosce. [MotoSullaStrada] fa scorrere la
 * freccia **lungo la linea del percorso**: insegue un numero, i metri fatti,
 * con la stessa velocità sua di [MotoFluido], e disegna il punto della linea
 * a quei metri. Fuori dalla linea non può andare; la direzione è quella della
 * linea lì ([sullaStrada]), che in una rotonda gira insieme alla strada.
 *
 * Sul telefono la linea è tutto il percorso; sullo schermo dell'auto un pezzo
 * ([trattoDiStrada]), mandato con ogni posizione. */

/// Il punto della [linea] a [metri] dalla sua partenza, e la direzione della
/// strada lì in gradi da nord: quella fra un poco prima e un poco dopo
/// ([mezzaCordaM]), che a uno svincolo gira piano invece che di colpo.
({Punto punto, double rotta}) sullaStrada(Linea linea, double metri) {
  final punto = _puntoA(linea, metri);
  final l = linea.lunghezzaM;
  var da = metri - mezzaCordaM, a = metri + mezzaCordaM;
  // In fondo (o in cima) la corda si sposta indietro (o avanti): stessa lunghezza.
  if (a > l) {
    da -= a - l;
    a = l;
  }
  if (da < 0) {
    a = math.min(l, a - da);
    da = 0;
  }
  final p = _puntoA(linea, da), q = _puntoA(linea, a);
  if (distanzaM(p, q) < 0.01) return (punto: punto, rotta: 0);
  return (punto: punto, rotta: rottaGradi(p, q));
}

/// Metà della corda con cui si misura la direzione della strada.
const mezzaCordaM = 6.0;

Punto _puntoA(Linea linea, double metri) {
  final c = linea.cumulate, p = linea.punti;
  if (p.length < 2) return p.isEmpty ? const Punto(0, 0) : p.first;
  final m = metri.clamp(0.0, linea.lunghezzaM);
  // Il primo vertice oltre [m]: per bisezione, il percorso intero sono migliaia.
  var basso = 1, alto = c.length - 1;
  while (basso < alto) {
    final mezzo = (basso + alto) >> 1;
    if (c[mezzo] < m) {
      basso = mezzo + 1;
    } else {
      alto = mezzo;
    }
  }
  final j = basso;
  final f = c[j] == c[j - 1] ? 0.0 : ((m - c[j - 1]) / (c[j] - c[j - 1])).clamp(0.0, 1.0);
  final a = p[j - 1], b = p[j];
  return Punto(a.lat + f * (b.lat - a.lat), a.lon + f * (b.lon - a.lon));
}

/// Il pezzo della [linea] da [daM] ad [aM] (metri dalla sua partenza): i due
/// capi e i vertici in mezzo. Per lo schermo dell'auto, che fa scorrere la
/// freccia sopra senza avere tutto il percorso.
List<Punto> trattoDiStrada(Linea linea, double daM, double aM) {
  final l = linea.lunghezzaM;
  final da = daM.clamp(0.0, l), a = aM.clamp(0.0, l);
  final c = linea.cumulate;
  final out = [_puntoA(linea, da)];
  for (var i = 0; i < c.length; i++) {
    if (c[i] > da && c[i] < a) out.add(linea.punti[i]);
  }
  out.add(_puntoA(linea, a));
  return out;
}

/// Dove disegnare l'auto a ogni fotogramma, in guida: lungo la linea del
/// percorso, mai accanto. Vedi sopra.
class MotoSullaStrada {
  MotoSullaStrada({
    this.tau = const Duration(milliseconds: 200),
    this.tauLungo = const Duration(milliseconds: 1000),
    this.tauVelocita = const Duration(milliseconds: 250),
    this.oltreAlPiu = const Duration(milliseconds: 1500),
    this.saltoM = 120,
  });

  /// Quanto ci mette a tornare indietro, quando deve (un GPS che corregge).
  final Duration tau;

  /// Come in [MotoFluido]: in quanto tempo la velocità della freccia vuole
  /// recuperare lo scarto, quanto ci mette a cambiare, fin quando si prevede
  /// e oltre quanto si salta.
  final Duration tauLungo;
  final Duration tauVelocita;
  final Duration oltreAlPiu;
  final double saltoM;

  /// Su una linea nuova la freccia si ritrova se ci sta a meno di così; se
  /// no si ricomincia da dove dice la guida.
  static const ritrovataEntroM = 15.0;

  Linea? _linea;
  double _meta = 0, _velocita = 0;
  Duration _alle = Duration.zero;
  var _haMeta = false;

  double? _mostrataM;
  double _velocitaMostrata = 0;
  Duration? _ultimoFotogramma;
  var _fermo = true;

  /// I metri della linea a cui è disegnata l'auto; `null` prima del primo.
  double? get mostrataM => _mostrataM;

  /// La velocità della freccia adesso, in m/s.
  double get velocitaMostrata => _velocitaMostrata;

  /// Come [MotoFluido.fermo].
  bool get fermo => _fermo;

  /// La linea su cui si scorre. Se cambia (il percorso ricalcolato, un
  /// pezzo nuovo per l'auto) la freccia si ritrova sulla nuova dov'era.
  void strada(Linea linea) {
    final prima = _linea, m = _mostrataM;
    if (identical(linea, prima)) return;
    _linea = linea;
    if (prima == null || m == null) return;
    final qui = _puntoA(prima, m);
    final p = linea.proietta(qui);
    if (p.lontanoM > ritrovataEntroM) {
      dimentica();
    } else {
      _mostrataM = p.lungoM;
    }
  }

  /// Dove l'auto è, in [metri] lungo la linea, a [alle]; [velocitaMs] lungo
  /// la strada.
  void posizione(double metri, {required double velocitaMs, required Duration alle}) {
    _meta = metri;
    _velocita = velocitaMs.isFinite && velocitaMs > 0 ? velocitaMs : 0;
    _alle = alle;
    _haMeta = true;
    _fermo = false;
  }

  /// Dove l'auto dovrebbe essere a [adesso], in metri lungo la linea.
  double? previsioneM(Duration adesso) {
    final l = _linea;
    if (!_haMeta || l == null) return null;
    if (_velocita < MotoFluido.fermoSottoMs) return _meta.clamp(0.0, l.lunghezzaM);
    var t = (adesso - _alle).inMicroseconds / 1e6;
    if (t < 0) t = 0;
    final massimo = oltreAlPiu.inMicroseconds / 1e6;
    if (t > massimo) t = massimo;
    return (_meta + _velocita * t).clamp(0.0, l.lunghezzaM);
  }

  /// Un fotogramma: dove disegnare l'auto a [adesso], e girata come.
  ({Punto punto, double rotta})? fotogramma(Duration adesso) {
    final l = _linea, meta = previsioneM(adesso);
    if (l == null || meta == null) return null;
    final m = _mostrataM, ultimo = _ultimoFotogramma;
    _ultimoFotogramma = adesso;
    final andando = _velocita >= MotoFluido.fermoSottoMs && adesso - _alle < oltreAlPiu;
    if (m == null || ultimo == null || (meta - m).abs() > saltoM) {
      _mostrataM = meta;
      _velocitaMostrata = andando ? _velocita : 0;
      _fermo = !andando;
      return sullaStrada(l, meta);
    }
    var dt = (adesso - ultimo).inMicroseconds / 1e6;
    if (dt < 0) dt = 0;
    if (dt > MotoFluido.fotogrammaAlPiuS) dt = MotoFluido.fotogrammaAlPiuS;
    final lungo = meta - m;
    final k = dt <= 0 ? 0.0 : 1 - math.exp(-dt / _secondi(tau));
    final kv = dt <= 0 ? 0.0 : 1 - math.exp(-dt / _secondi(tauVelocita));
    double avanti;
    var arrivata = false;
    if (andando) {
      final minima = _velocita * MotoFluido.almenoDellaVelocita;
      final massima = math.max(_velocita * 2, _velocita + 10);
      final scarto = lungo - _velocitaMostrata * dt;
      final voluta = (_velocita + scarto / _secondi(tauLungo)).clamp(minima, massima).toDouble();
      _velocitaMostrata += (voluta - _velocitaMostrata) * kv;
      if (_velocitaMostrata < minima) _velocitaMostrata = minima;
      avanti = _velocitaMostrata * dt;
    } else if (lungo < 0 && lungo > -MotoFluido.indietroAlPiuM) {
      _velocitaMostrata = 0;
      avanti = 0;
      arrivata = true;
    } else if (lungo < 0) {
      _velocitaMostrata = 0;
      avanti = lungo * k;
    } else {
      final voluta = lungo / _secondi(tauLungo) * 2;
      _velocitaMostrata += (voluta - _velocitaMostrata) * kv;
      if (_velocitaMostrata < 0) _velocitaMostrata = 0;
      avanti = math.min(_velocitaMostrata * dt, lungo);
      arrivata = lungo - avanti < 0.3;
      if (arrivata) _velocitaMostrata = 0;
    }
    final nuova = (m + avanti).clamp(0.0, l.lunghezzaM).toDouble();
    _mostrataM = nuova;
    _fermo = !andando && arrivata;
    return sullaStrada(l, nuova);
  }

  /// Si ricomincia: la prossima posizione si disegna dov'è, senza inseguirla.
  void dimentica() {
    _mostrataM = null;
    _ultimoFotogramma = null;
    _velocitaMostrata = 0;
  }

  static double _secondi(Duration d) => d.inMicroseconds / 1e6;
}

/* ─── La mappa senza percorso ──────────────────────────────────────────────
 *
 * Dal campo: «quando non attivo il percorso ed è in semplice mappa deve
 * aumentare lo zoom e mostrare 3D ma più vicino, non così lontano». Senza
 * percorso lo zoom era fisso a 15,5, con l'auto in mezzo allo schermo: in 3D
 * si vedevano chilometri di quartieri fino all'orizzonte, e l'auto era un
 * puntino. Adesso è come in guida: vicino (17,5 in città), l'auto più in
 * basso per vedere la strada davanti, e un poco più lontano solo andando
 * forte, mai quanto prima. */

/// Come la mappa segue l'auto senza un percorso: lo [zoom], l'[inclinazione]
/// in gradi e [sopra], la parte dell'altezza libera tenuta sopra l'auto come
/// margine (l'auto più in basso, la strada davanti in vista).
typedef TelecameraLibera = ({double zoom, double inclinazione, double sopra});

/// Lo zoom senza percorso fino a [lentoSottoKmh], e quello da [veloceSopraKmh]
/// in su; in mezzo si passa piano.
const zoomLiberoLento = 17.5;
const zoomLiberoVeloce = 16.2;
const lentoSottoKmh = 30.0;
const veloceSopraKmh = 110.0;

/// L'inclinazione in 3D, come in guida.
const inclinazioneLibera = 55.0;

/// La telecamera senza percorso a [velocitaMs]; [tridimensionale] la vista
/// scelta; [scarto] quanto l'hanno cambiata i tasti + e − (in livelli di zoom).
TelecameraLibera telecameraLibera({required double velocitaMs, required bool tridimensionale, double scarto = 0}) {
  final kmh = velocitaMs.isFinite && velocitaMs > 0 ? velocitaMs * 3.6 : 0.0;
  final t = ((kmh - lentoSottoKmh) / (veloceSopraKmh - lentoSottoKmh)).clamp(0.0, 1.0);
  // Morbido ai due capi: niente gradino a 30 né a 110 all'ora.
  final s = t * t * (3 - 2 * t);
  final zoom = (zoomLiberoLento + (zoomLiberoVeloce - zoomLiberoLento) * s + scarto).clamp(10.0, 19.5).toDouble();
  return (
    zoom: zoom,
    inclinazione: tridimensionale ? inclinazioneLibera : 0.0,
    sopra: tridimensionale ? 0.3 : 0.0,
  );
}

/* ─── In guida, lontano dalla prossima svolta ───────────────────────────────
 *
 * Dal campo: «quando sono su autostrada o strade statali, dove la prima
 * girata è dopo molti chilometri, allunga lo zoom: lo hai messo troppo
 * zoomato». In guida lo zoom era fisso (17 sul telefono, 16,5 sull'auto) e
 * si avvicinava solo arrivando a una svolta: a 130 all'ora si vedevano un
 * paio di centinaia di metri di asfalto. Andando su una strada veloce e con
 * la prossima manovra lontana la mappa si allontana, fino a
 * [zoomLontanoAlPiu] livelli; arrivando alla manovra torna vicina, piano,
 * prima che cominci l'avvicinamento della svolta (600 metri).
 *
 * E poi, sempre dal campo: «zoom in e out durante la navigazione,
 * soprattutto su autostrade e statali, sono frequenti: non farlo sulla
 * velocità dell'auto ma capisci il percorso». La velocità dell'auto in
 * autostrada va su e giù (un camion, un cantiere, una coda), e la mappa con
 * lei. Adesso conta la strada che si sta facendo, dal percorso
 * ([Avanzamento.velocitaStradaKmh]): finché si resta in autostrada la mappa
 * resta larga, e cambia solo cambiando strada o avvicinandosi all'uscita. */

/// Di quanti livelli al più si allontana la mappa in guida.
const zoomLontanoAlPiu = 2.0;

/// Su strade previste sotto questa velocità non ci si allontana; da
/// [lontanoTuttoSopraKmh] del tutto (una statale veloce, un'autostrada).
const lontanoDaKmh = 50.0;
const lontanoTuttoSopraKmh = 95.0;

/// Con la prossima manovra più vicina di così non ci si allontana; da
/// [lontanoTuttoOltreM] del tutto.
const lontanoDaM = 800.0;
const lontanoTuttoOltreM = 2500.0;

/// Quanto togliere allo zoom della guida (un numero da 0 a −[zoomLontanoAlPiu])
/// su una strada da [velocitaStradaKmh] (quella prevista dal percorso, non
/// quella dell'auto), con la prossima manovra ad [allaProssimaM] metri.
double zoomLontanoInGuida({required double velocitaStradaKmh, required double allaProssimaM}) {
  final kmh = velocitaStradaKmh.isFinite && velocitaStradaKmh > 0 ? velocitaStradaKmh : 0.0;
  double morbido(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  final v = morbido((kmh - lontanoDaKmh) / (lontanoTuttoSopraKmh - lontanoDaKmh));
  final d = allaProssimaM.isFinite ? morbido((allaProssimaM - lontanoDaM) / (lontanoTuttoOltreM - lontanoDaM)) : 1.0;
  return -zoomLontanoAlPiu * v * d;
}
