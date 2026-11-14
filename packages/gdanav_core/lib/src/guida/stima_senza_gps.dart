/* ─── In galleria, senza GPS ────────────────────────────────────────────────
 *
 * Dal campo: «le gallerie: gli altri mantengono la direzione della strada
 * usando la velocità che aveva prima di entrarci. Questo invece in galleria
 * si perde, va per un po' nel vuoto e poi si blocca, per poi riprendersi
 * quando si esce». In galleria il GPS tace, o il telefono manda posizioni
 * larghe centinaia di metri (dalle celle). La guida portava avanti l'auto
 * lungo la strada per al più due secondi e sessanta metri e lì la fermava;
 * una posizione larga, lontana dalla linea, la staccava dal percorso, e la
 * mappa la disegnava dove diceva il telefono: nel vuoto.
 *
 * [StimaSenzaGps] è la stima della posizione senza GPS (dead reckoning)
 * lungo il percorso: dall'ultima lettura buona sulla strada, i metri che si
 * fanno alla velocità di prima o, meglio, a quella del tachimetro dell'auto
 * quando la dice (Android Auto, il dongle), che in galleria continua a
 * parlare. Mai fuori dalla strada (sono metri lungo il percorso), e per al
 * più [StimaSenzaGps.alPiu]: oltre ci si ferma e si dice «GPS assente».
 * Quando il GPS torna la stima finisce, e la freccia ([MotoSullaStrada]) si
 * riporta sulla lettura nuova con la sua correzione morbida. */

/// Vedi sopra.
class StimaSenzaGps {
  StimaSenzaGps({
    this.dopo = const Duration(seconds: 2),
    this.alPiu = const Duration(minutes: 3),
    this.precisioneCattivaM = 50,
    this.daMs = 1.5,
  });

  /// Senza letture buone da così, si stima.
  final Duration dopo;

  /// E per al più tanto (dall'ultima lettura buona): poi ci si ferma.
  final Duration alPiu;

  /// Una lettura che dice di sbagliare più di così non è buona: in
  /// galleria il telefono manda quelle delle celle.
  final double precisioneCattivaM;

  /// Sotto questa velocità non si stima niente: fermi in coda in galleria
  /// si resta dove si è.
  final double daMs;

  double? _metri;
  DateTime? _alle;
  double _v = 0;

  /// I metri e il tempo da cui conta la velocità [_v] (il tachimetro li
  /// sposta avanti a ogni sua lettura).
  double _metriV = 0;
  DateTime? _alleV;

  /// Una lettura buona sulla strada: a [metri] lungo il percorso, [alle],
  /// andando a [velocitaMs].
  void lettura({required double metri, required DateTime alle, double? velocitaMs}) {
    _metri = metri;
    _alle = alle;
    _metriV = metri;
    _alleV = alle;
    _v = velocitaMs != null && velocitaMs.isFinite && velocitaMs > 0 ? velocitaMs : 0;
  }

  /// La velocità dell'auto dal suo cruscotto, [ms] letta [alle]: in galleria
  /// conta lei (rallentando in coda la stima rallenta).
  void tachimetro(double ms, DateTime alle) {
    final da = _alleV;
    if (_metri == null || da == null || !ms.isFinite) return;
    if (alle.isAfter(da)) {
      _metriV += _v * _secondi(alle.difference(da), alPiu - _dal(da));
      _alleV = alle;
    }
    _v = ms > 0 ? ms : 0;
  }

  /// Se [precisioneM] dice una lettura buona.
  bool buona(double? precisioneM) => precisioneM == null || precisioneM <= precisioneCattivaM;

  /// Se a [ora] si sta stimando: niente letture buone da [dopo], ma da meno
  /// di [alPiu], e andando.
  bool stima(DateTime ora) {
    final a = _alle;
    if (a == null || _metri == null) return false;
    final d = ora.difference(a);
    return d >= dopo && d <= alPiu && _v >= daMs;
  }

  /// Se la stima è finita: niente letture buone da più di [alPiu].
  bool persa(DateTime ora) {
    final a = _alle;
    return a != null && ora.difference(a) > alPiu;
  }

  /// I metri lungo il percorso a [ora] (mai oltre [lunghezzaM]); `null` se
  /// non si è mai avuta una lettura buona.
  double? metri(DateTime ora, {double? lunghezzaM}) {
    final da = _alleV, m0 = _metri;
    if (da == null || m0 == null) return null;
    var m = _metriV;
    if (ora.isAfter(da) && _v >= daMs) m += _v * _secondi(ora.difference(da), alPiu - _dal(da));
    if (lunghezzaM != null && m > lunghezzaM) m = lunghezzaM;
    return m;
  }

  /// Si ricomincia (un percorso nuovo).
  void dimentica() {
    _metri = null;
    _alle = null;
    _alleV = null;
    _v = 0;
  }

  /// Da [da] a quanto dopo l'ultima lettura buona.
  Duration _dal(DateTime da) => da.difference(_alle ?? da);

  /// [d] in secondi, ma mai oltre [massimo] (la stima si ferma ad [alPiu]).
  static double _secondi(Duration d, Duration massimo) {
    final s = d.inMicroseconds / 1e6, m = massimo.inMicroseconds / 1e6;
    return s < 0 ? 0 : (s > m ? (m < 0 ? 0 : m) : s);
  }
}
