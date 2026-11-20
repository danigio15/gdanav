import 'dart:math' as math;

/* ─── Frenate e ripartenze, subito: l'accelerometro del telefono ──────────────
 *
 * «Deve avere la posizione reale sempre: non deve tornare indietro e non deve
 * stare avanti.» Il GPS del telefono dice dove si è e quanto si va con un
 * ritardo di quasi un secondo, e una volta al secondo. Per non restare
 * indietro andando, la freccia si porta avanti di quel ritardo; ma frenando,
 * per quel secondo, si porta avanti con la velocità di prima e va oltre
 * dove l'auto si ferma. Senza sapere la frenata quando succede non c'è modo
 * di avere le due cose insieme.
 *
 * I navigatori dei telefoni lo sanno dai sensori di movimento: l'accelerometro
 * sente la frenata nell'istante in cui comincia. Il guaio è che misura nel
 * riferimento del telefono, non dell'auto: il telefono sta nel supporto come
 * capita, inclinato, girato. Qui l'asse di marcia si impara da solo: si
 * confronta l'accelerazione del telefono con quella che dicono le velocità
 * (del cruscotto se ci sono, se no del GPS): dove il telefono accelera quando
 * l'auto accelera, lì è l'avanti. Una regressione ai minimi quadrati, con
 * memoria che sfuma (due minuti), più una costante (lo zero dell'accelerometro
 * non è mai zero). Finché non è tarata, o se il telefono si sposta nel
 * supporto (la gravità cambia direzione), non dice niente e si fa come prima.
 *
 * In uscita: l'accelerazione lungo la strada adesso ([adesso]) e la strada
 * fatta da un istante a un altro partendo da una velocità ([strada]): con
 * quelle la freccia frena quando frena l'auto. */

/// Vedi sopra.
class AccelerazioneDiMarcia {
  AccelerazioneDiMarcia({
    this.memoria = const Duration(minutes: 2),
    this.ritardiGps = const [
      Duration(milliseconds: 200),
      Duration(milliseconds: 400),
      Duration(milliseconds: 600),
      Duration(milliseconds: 800),
      Duration(milliseconds: 1000),
      Duration(milliseconds: 1200),
    ],
    this.ritardoCruscotto = const Duration(milliseconds: 100),
  });

  /// Quanto conta il passato nella taratura: dopo così pesa un terzo.
  final Duration memoria;

  /// I ritardi della velocità del GPS sull'auto che si provano: il filtro del
  /// fornitore della posizione la liscia, e quanto dipende dal telefono. Vince
  /// quello che spiega meglio le frenate ([ritardoGpsMisurato]).
  final List<Duration> ritardiGps;

  /// Il ritardo della velocità del cruscotto.
  final Duration ritardoCruscotto;

  /// Quanto liscia l'accelerometro (s): il motore e la strada lo fanno
  /// vibrare, una frenata dura più di un secondo.
  static const _liscia = 0.25;

  /// Un campione al più ogni tanto nella storia (ms), e per quanto (ms).
  static const _passoStoria = 40, _durataStoria = 30000;

  /// Oltre questa rotazione della gravità il telefono si è spostato (gradi).
  static const _spostatoGradi = 12.0;

  // L'accelerometro lisciato, nel riferimento del telefono.
  int? _ultimoMs;
  var _f = const [0.0, 0.0, 0.0];
  final _storia = <_Campione>[];

  // La gravità, lisciata: se gira, il telefono si è mosso nel supporto.
  List<double>? _g;
  List<double>? _gTaratura;

  // Una regressione per ogni ritardo del GPS e una per il cruscotto.
  late final _gps = [for (final r in ritardiGps) _Regressione(r)];
  late final _cruscotto = _Regressione(ritardoCruscotto);
  _Regressione? _scelta;

  // Le ultime velocità, per farne accelerazioni.
  ({int ms, double v})? _ultimaGps, _ultimoCruscotto;

  /// Un campione dell'accelerometro senza la gravità (m/s², nel riferimento
  /// del telefono), letto a [t].
  void campione(DateTime t, double x, double y, double z) {
    if (!x.isFinite || !y.isFinite || !z.isFinite) return;
    final ms = t.millisecondsSinceEpoch;
    final prima = _ultimoMs;
    if (prima == null || ms - prima > 1000 || ms < prima) {
      _f = [x, y, z];
    } else {
      final k = 1 - math.exp(-((ms - prima) / 1000) / _liscia);
      _f = [_f[0] + (x - _f[0]) * k, _f[1] + (y - _f[1]) * k, _f[2] + (z - _f[2]) * k];
    }
    _ultimoMs = ms;
    // Nella storia con l'ora di quando è successo: lisciare vuol dire
    // arrivare in ritardo di [_liscia] (una frenata misurata tardi di un
    // quarto di secondo, a 50 all'ora, sono quattro metri di troppo).
    final quando = ms - (_liscia * 1000).round();
    if (_storia.isEmpty || quando - _storia.last.ms >= _passoStoria) {
      _storia.add(_Campione(quando, _f[0], _f[1], _f[2]));
      while (_storia.length > 2 && quando - _storia.first.ms > _durataStoria) {
        _storia.removeAt(0);
      }
    }
  }

  /// La gravità nel riferimento del telefono (m/s²: l'accelerometro meno
  /// [campione]): serve solo a capire se il telefono si è spostato.
  void gravita(DateTime t, double x, double y, double z) {
    if (!x.isFinite || !y.isFinite || !z.isFinite) return;
    final g = _g;
    _g = g == null ? [x, y, z] : [g[0] + (x - g[0]) * 0.02, g[1] + (y - g[1]) * 0.02, g[2] + (z - g[2]) * 0.02];
    final rif = _gTaratura;
    final ora = _g!;
    if (rif == null) {
      _gTaratura = List.of(ora);
      return;
    }
    if (_angolo(rif, ora) > _spostatoGradi) {
      // Il telefono si è mosso: quello imparato non vale più.
      azzera();
      _gTaratura = List.of(ora);
    }
  }

  /// Una velocità ([ms] m/s) letta a [t]: dal cruscotto dell'auto
  /// ([cruscotto]) o dal GPS.
  void velocita(DateTime t, double ms, {required bool cruscotto}) {
    if (!ms.isFinite || ms < 0) return;
    final ora = t.millisecondsSinceEpoch;
    final prima = cruscotto ? _ultimoCruscotto : _ultimaGps;
    if (cruscotto) {
      _ultimoCruscotto = (ms: ora, v: ms);
    } else {
      _ultimaGps = (ms: ora, v: ms);
    }
    if (prima == null) return;
    final dt = (ora - prima.ms) / 1000;
    if (dt < 0.25 || dt > 3) return;
    final rif = (ms - prima.v) / dt;
    if (rif.abs() > 8) return; // un salto della lettura, non una frenata
    for (final r in cruscotto ? [_cruscotto] : _gps) {
      final ritardo = r.ritardo.inMilliseconds;
      final media = _media(prima.ms - ritardo, ora - ritardo);
      if (media != null) r.impara(media, rif, ora, memoria);
    }
    _scegli();
  }

  void _scegli() {
    // Il cruscotto non ha il ritardo da indovinare: se è tarato, vince lui.
    if (_cruscotto.u != null) {
      _scelta = _cruscotto;
      return;
    }
    _Regressione? meglio;
    for (final r in _gps) {
      if (r.u != null && (meglio == null || r.r2 > meglio.r2)) meglio = r;
    }
    _scelta = meglio;
  }

  /// Se si sa dov'è l'avanti.
  bool get tarata => _scelta?.u != null;

  /// Quanto la taratura spiega le accelerazioni dell'auto (0–1).
  double get qualita => _scelta?.r2 ?? 0;

  /// Il ritardo della velocità del GPS che spiega meglio le frenate, se la
  /// taratura viene dal GPS: quanto questo telefono dice tardi quanto si va.
  Duration? get ritardoGpsMisurato {
    final s = _scelta;
    return s == null || identical(s, _cruscotto) ? null : s.ritardo;
  }

  /// Quello imparato non vale più (il telefono si è spostato).
  void azzera() {
    for (final r in [..._gps, _cruscotto]) {
      r.azzera();
    }
    _scelta = null;
  }

  /// L'accelerazione lungo la strada adesso (m/s², positiva accelerando), se
  /// tarata e se l'accelerometro parla: `null` altrimenti.
  double? adesso(DateTime ora) {
    final u = _scelta?.u, ms = _ultimoMs;
    if (u == null || ms == null || ora.millisecondsSinceEpoch - ms > 400) return null;
    return _lungo(u, _f[0], _f[1], _f[2]);
  }

  /// La strada fatta da [da] ad [a] partendo a [v0] m/s, con le accelerazioni
  /// misurate: mai all'indietro (fermi si resta fermi). `null` se non è
  /// tarata o se l'accelerometro non copre l'intervallo.
  double? strada(DateTime da, DateTime a, double v0) {
    final u = _scelta?.u;
    final t0 = da.millisecondsSinceEpoch, t1 = a.millisecondsSinceEpoch;
    if (u == null || t1 <= t0 || _storia.isEmpty) return u == null ? null : 0;
    if (_storia.first.ms > t0 + 100 || _storia.last.ms < t1 - 700) return null;
    var v = math.max(0.0, v0), s = 0.0, t = t0;
    var k = 0;
    while (k < _storia.length - 1 && _storia[k + 1].ms <= t0) {
      k++;
    }
    while (t < t1) {
      final c = _storia[k];
      final fine = k + 1 < _storia.length ? math.min(_storia[k + 1].ms, t1) : t1;
      final h = (fine - t) / 1000;
      if (h > 0) {
        final acc = _lungo(u, c.x, c.y, c.z);
        final v1 = math.max(0.0, v + acc * h);
        s += (v + v1) / 2 * h;
        v = v1;
      }
      t = fine;
      if (k + 1 < _storia.length) k++;
    }
    return s;
  }

  double _lungo(List<double> u, double x, double y, double z) =>
      (u[0] * x + u[1] * y + u[2] * z + u[3]).clamp(-10.0, 6.0).toDouble();

  /// La media dell'accelerometro lisciato fra [da] e [a] (ms).
  List<double>? _media(int da, int a) {
    var n = 0;
    final s = [0.0, 0.0, 0.0];
    for (final c in _storia) {
      if (c.ms < da || c.ms > a) continue;
      s[0] += c.x;
      s[1] += c.y;
      s[2] += c.z;
      n++;
    }
    if (n < 3) return null;
    return [s[0] / n, s[1] / n, s[2] / n];
  }

  static double _angolo(List<double> a, List<double> b) {
    final la = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
    final lb = math.sqrt(b[0] * b[0] + b[1] * b[1] + b[2] * b[2]);
    if (la < 1e-6 || lb < 1e-6) return 0;
    final c = ((a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) / (la * lb)).clamp(-1.0, 1.0);
    return math.acos(c) * 180 / math.pi;
  }
}

/// Una regressione ai minimi quadrati con memoria che sfuma: caratteristiche
/// `[x, y, z, 1]` (l'accelerometro e la costante) → l'accelerazione di
/// marcia dalle velocità lette con [ritardo].
class _Regressione {
  _Regressione(this.ritardo);
  final Duration ritardo;

  final _m = List.generate(4, (_) => List.filled(4, 0.0));
  final _b = List.filled(4, 0.0);
  var _s = 0.0; // somma dei quadrati delle accelerazioni di riferimento
  var _eccitazione = 0.0; // quante volte si è accelerato o frenato davvero
  int? _ultimoMs;

  /// `[ux, uy, uz, costante]`, quando è tarata.
  List<double>? u;
  var r2 = 0.0;

  void impara(List<double> f, double rif, int ora, Duration memoria) {
    final prima = _ultimoMs;
    if (prima != null && ora > prima) {
      final k = math.exp(-(ora - prima) / memoria.inMilliseconds);
      for (var i = 0; i < 4; i++) {
        for (var j = 0; j < 4; j++) {
          _m[i][j] *= k;
        }
        _b[i] *= k;
      }
      _s *= k;
      _eccitazione *= k;
    }
    _ultimoMs = ora;
    final x = [f[0], f[1], f[2], 1.0];
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        _m[i][j] += x[i] * x[j];
      }
      _b[i] += x[i] * rif;
    }
    _s += rif * rif;
    if (rif.abs() > 0.6) _eccitazione += 1;
    _risolvi();
  }

  void _risolvi() {
    if (_eccitazione < 6 || _s <= 0) {
      u = null;
      return;
    }
    var traccia = 0.0;
    for (var i = 0; i < 4; i++) {
      traccia += _m[i][i];
    }
    final a = List.generate(4, (i) => [..._m[i], _b[i]]);
    for (var i = 0; i < 4; i++) {
      a[i][i] += traccia * 1e-4;
    }
    final x = _gauss(a);
    if (x == null) {
      u = null;
      return;
    }
    // Quanto spiega: 1 − residuo / totale.
    var xMx = 0.0, xb = 0.0;
    for (var i = 0; i < 4; i++) {
      xb += x[i] * _b[i];
      for (var j = 0; j < 4; j++) {
        xMx += x[i] * _m[i][j] * x[j];
      }
    }
    r2 = 1 - math.max(0, _s - 2 * xb + xMx) / _s;
    final scala = math.sqrt(x[0] * x[0] + x[1] * x[1] + x[2] * x[2]);
    // Tarata se spiega bene le frenate e l'asse è credibile (un'accelerazione
    // del telefono vale quella dell'auto, più o meno).
    u = r2 >= 0.6 && scala > 0.6 && scala < 1.6 ? x : null;
  }

  void azzera() {
    for (var i = 0; i < 4; i++) {
      _m[i].fillRange(0, 4, 0);
    }
    _b.fillRange(0, 4, 0);
    _s = 0;
    _eccitazione = 0;
    _ultimoMs = null;
    u = null;
    r2 = 0;
  }

  /// Gauss con pivot su [a] (n righe, n+1 colonne): la soluzione o `null`.
  static List<double>? _gauss(List<List<double>> a) {
    final n = a.length;
    for (var c = 0; c < n; c++) {
      var p = c;
      for (var r = c + 1; r < n; r++) {
        if (a[r][c].abs() > a[p][c].abs()) p = r;
      }
      if (a[p][c].abs() < 1e-12) return null;
      final t = a[c];
      a[c] = a[p];
      a[p] = t;
      for (var r = 0; r < n; r++) {
        if (r == c) continue;
        final k = a[r][c] / a[c][c];
        for (var j = c; j <= n; j++) {
          a[r][j] -= k * a[c][j];
        }
      }
    }
    return [for (var i = 0; i < n; i++) a[i][n] / a[i][i]];
  }
}

class _Campione {
  const _Campione(this.ms, this.x, this.y, this.z);
  final int ms;
  final double x, y, z;
}
