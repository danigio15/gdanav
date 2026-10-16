import 'dart:math' as math;

import '../geo/geo.dart';

/* ─── L'auto che scorre, fra una posizione e l'altra ────────────────────────
 *
 * Dal campo: «la freccia sulla mappa non è fluida, prende pause e poi
 * cammina». Il GPS dà una posizione al secondo (a volte 1,2 s, a volte 0,8),
 * e lo schermo dell'auto ne riceveva una ogni tanto: fra l'una e l'altra la
 * freccia andava in linea retta fino all'ultima arrivata, in un tempo pari
 * all'intervallo di prima, e lì **si fermava** ad aspettare la prossima. Con
 * una posizione in ritardo, la pausa; con una in anticipo, uno scatto.
 *
 * Qui il conto, uguale per il telefono, Android Auto e CarPlay (che lo rifanno
 * in Kotlin e Swift, `RendererMappa` e `MappaCarPlay`, coi numeri di qui):
 *
 *  - fra due posizioni l'auto **va avanti da sola**: dalla velocità e dalla
 *    direzione dell'ultima, e da quanto stava girando (curva costante:
 *    l'angolo fra le ultime due direzioni diviso il tempo). Mai più in là di
 *    [MotoFluido.oltreAlPiu] dall'ultima posizione: un GPS che tace non deve
 *    far correre la freccia da sola;
 *  - quello che si disegna insegue quel punto **a ogni fotogramma**,
 *    avvicinandosi con una costante di tempo [MotoFluido.tau]: una posizione
 *    nuova un po' diversa dalla previsione diventa una correzione morbida,
 *    non un salto;
 *  - **mai indietro**: andando, la parte della correzione che tornerebbe
 *    indietro lungo la strada si lascia cadere (la freccia rallenta e la
 *    previsione, che va avanti, la raggiunge); di lato invece si corregge;
 *  - da fermi la previsione è la posizione stessa, e quando la freccia ci è
 *    arrivata [MotoFluido.fermo] dice che non servono più fotogrammi: chi
 *    disegna spegne il suo orologio fino alla posizione dopo. */

/// Dove disegnare l'auto a ogni fotogramma, fra una posizione e l'altra.
///
/// I tempi sono [Duration] di un orologio che va solo avanti (quello dei
/// fotogrammi), non ore del giorno.
class MotoFluido {
  MotoFluido({
    this.tau = const Duration(milliseconds: 200),
    this.oltreAlPiu = const Duration(milliseconds: 1500),
    this.saltoM = 120,
  });

  /// Quanto ci mette la freccia a recuperare due terzi della distanza dalla
  /// previsione.
  final Duration tau;

  /// Oltre questo tempo dall'ultima posizione la previsione si ferma.
  final Duration oltreAlPiu;

  /// Più lontano di così si salta: un ricalcolo, un GPS che torna.
  final double saltoM;

  /// Sotto questa velocità si è fermi: niente previsione, e la freccia può
  /// anche tornare un poco indietro (il GPS da fermo balla).
  static const fermoSottoMs = 0.5;

  /// Quanto si gira al massimo, in gradi al secondo, per la previsione: oltre
  /// è rumore della direzione, non una curva.
  static const giraAlPiuGradiS = 45.0;

  Punto? _fix;
  double _rottaFix = 0, _velocita = 0, _gira = 0;
  Duration _alle = Duration.zero;

  Punto? _mostrata;
  double _rottaMostrata = 0;
  Duration? _ultimoFotogramma;
  var _fermo = true;

  /// Dove è disegnata l'auto adesso; `null` prima della prima posizione.
  Punto? get mostrata => _mostrata;

  /// La direzione della freccia adesso, in gradi da nord.
  double get rottaMostrata => _rottaMostrata;

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
    if (m == null || ultimo == null || distanzaM(m, obiettivo.punto) > saltoM) {
      _mostrata = obiettivo.punto;
      _rottaMostrata = obiettivo.rotta;
      _fermo = _velocita < fermoSottoMs || _oltre(adesso);
      return (punto: obiettivo.punto, rotta: obiettivo.rotta);
    }
    var dt = (adesso - ultimo).inMicroseconds / 1e6;
    if (dt < 0) dt = 0;
    // Un fotogramma saltato (l'app dietro, la mappa occupata) non diventa
    // un salto: al più un decimo di secondo alla volta.
    if (dt > 0.1) dt = 0.1;
    final k = 1 - math.exp(-dt / (tau.inMicroseconds / 1e6));
    final (dx, dy) = _metri(m, obiettivo.punto);
    var passoEst = dx * k, passoNord = dy * k;
    if (_velocita >= fermoSottoMs) {
      // Mai indietro lungo la strada: quella parte del passo si toglie.
      final r = obiettivo.rotta * math.pi / 180;
      final ve = math.sin(r), vn = math.cos(r);
      final lungo = passoEst * ve + passoNord * vn;
      if (lungo < 0) {
        passoEst -= lungo * ve;
        passoNord -= lungo * vn;
      }
    }
    _mostrata = _sposta(m, passoEst, passoNord);
    _rottaMostrata = versoDiLa(_rottaMostrata, obiettivo.rotta, k);
    final arrivata =
        distanzaM(_mostrata!, obiettivo.punto) < 0.3 && diQuantoSiGira(_rottaMostrata, obiettivo.rotta).abs() < 0.5;
    _fermo = arrivata && (_velocita < fermoSottoMs || _oltre(adesso));
    return (punto: _mostrata!, rotta: _rottaMostrata);
  }

  /// Si ricomincia: la prossima posizione si disegna dov'è, senza inseguirla
  /// (la mappa è stata spostata col dito, o rifatta).
  void dimentica() {
    _mostrata = null;
    _ultimoFotogramma = null;
  }

  bool _oltre(Duration adesso) => adesso - _alle >= oltreAlPiu;

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
