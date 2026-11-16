import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../geo/geo.dart';
import '../guida/aggancio_strada.dart';
import 'pedaggi.dart';
import 'valhalla.dart';

/* ─── Mai contromano, anche se lo dice il fornitore del percorso ────────────
 *
 * Dal campo, al bivio fra Strada San Michele e Via Nobel: un triangolo di
 * due sensi unici. Il ramo che si stacca per primo porta a Via Nobel («al
 * bivio tieni la destra»); l'altro parte più avanti ed è a senso unico
 * all'incontrario, da Via Nobel verso la strada. Il percorso di TomTom
 * tirava dritto fino al vertice e girava stretto sul secondo ramo:
 * contromano. La geometria è la sua (nella sua mappa quel ramo è a doppio
 * senso, si suppone), e agganciare la linea alle strade non la sposta di
 * ramo: lì sotto c'è proprio il ramo sbagliato.
 *
 * [correggiContromano] la rifà da noi, sulle strade di OpenStreetMap che la
 * mappa ha già (le tessere vettoriali, vedi `stradeDaTessera`):
 *
 *  1. **Dove va contromano.** Si percorre la linea a passi di due metri; a
 *     ogni passo si guardano le strade lì vicino ([RegoleContromano.raggioM])
 *     che vanno nella stessa direzione della linea (in un verso o
 *     nell'altro). Se almeno una ci si può percorrere in quel verso, il passo
 *     è buono; se ci sono solo sensi unici al contrario, è contromano. Se non
 *     c'è niente (una strada che la mappa non ha, un parcheggio) non si dice
 *     niente: si corregge solo dove la mappa dice chiaro che è vietato.
 *     Bastano [RegoleContromano.minimoM] metri di fila.
 *  2. **La strada giusta.** Da un punto un po' prima ad uno un po' dopo,
 *     entrambi su strade percorribili nel verso del percorso, la via più breve
 *     sulle strade vere rispettando i sensi unici (Dijkstra, senza inversioni
 *     agli incroci). Si prova prima stretto, poi allargando fino a
 *     [RegoleContromano.indietroM] metri prima: il primo pezzo che va bene
 *     vince. Va bene se non è più lungo di [RegoleContromano.rapportoMassimo]
 *     volte il pezzo che sostituisce e di [RegoleContromano.deviazioneMassimaM]
 *     metri: è un ritocco a un incrocio, non un altro percorso. Se non c'è, il
 *     percorso resta com'è (e uscendo di strada si ricalcola, come sempre).
 *  3. **Le manovre.** Quelle del pezzo tolto se ne vanno; dove la strada
 *     nuova si stacca dalla vecchia nasce la manovra giusta, dalla geometria
 *     vera: un bivio dove anche l'altro ramo va quasi dritto è «Al bivio tieni
 *     la destra» (o la sinistra), altrimenti leggera, normale o stretta
 *     secondo l'angolo. Il nome della strada è quello della manovra tolta. Le
 *     manovre lontane non si toccano, la meta nemmeno.
 *
 * Telefono, auto (Android Auto e CarPlay) e scena 3D leggono tutti lo stesso
 * percorso e le stesse manovre: corretto qui, è corretto dappertutto. */

/// Le soglie di [correggiContromano].
class RegoleContromano {
  const RegoleContromano({
    this.raggioM = 14,
    this.passoM = 2,
    this.angoloGradi = 35,
    this.minimoM = 8,
    this.indietroM = const [30, 60, 100, 150, 200],
    this.avantiM = const [30, 60, 100],
    this.rapportoMassimo = 1.5,
    this.deviazioneMassimaM = 300,
  });

  /// Quanto lontano dalla linea si cercano le strade: la linea di TomTom sta
  /// anche otto, dieci metri di lato rispetto a quella di OpenStreetMap.
  final double raggioM;

  /// Ogni quanto si guarda lungo la linea.
  final double passoM;

  /// Quanto una strada può girare rispetto alla linea ed essere ancora
  /// «quella» (in un verso o nell'altro).
  final double angoloGradi;

  /// Quanti metri di fila solo contromano per correggere.
  final double minimoM;

  /// Da quanto prima del contromano si può far partire la strada nuova, dal
  /// più stretto al più largo.
  final List<double> indietroM;

  /// E dopo quanto si torna sulla linea.
  final List<double> avantiM;

  /// La strada nuova al più lunga così rispetto al pezzo che sostituisce.
  final double rapportoMassimo;

  /// E mai più lunga di così: oltre è un altro percorso, lo fa il motore.
  final double deviazioneMassimaM;
}

/// Un pezzo di percorso ridisegnato: da [daM] ad [aM] metri sul percorso di
/// prima, ora lungo [lunghezzaM]; i punti da [daIndice] (escluso) ad
/// [aIndice] (compreso) sono diventati [inseriti] punti nuovi.
class Deviazione {
  const Deviazione({
    required this.daM,
    required this.aM,
    required this.lunghezzaM,
    required this.daIndice,
    required this.aIndice,
    required this.inseriti,
    required this.contromanoDaM,
    required this.contromanoAM,
  });

  final double daM, aM, lunghezzaM;
  final int daIndice, aIndice, inseriti;

  /// Il pezzo che andava contromano, in metri sul percorso di prima.
  final double contromanoDaM, contromanoAM;

  /// Di quanto si allunga (negativo: si accorcia) il percorso.
  double get differenzaM => lunghezzaM - (aM - daM);

  @override
  String toString() => 'Deviazione(${daM.round()}–${aM.round()} m → ${lunghezzaM.round()} m, '
      'contromano ${contromanoDaM.round()}–${contromanoAM.round()} m)';
}

/// Il percorso corretto, e come ritrovarci le cose di quello di prima.
class PercorsoCorretto {
  PercorsoCorretto(this.percorso, List<Deviazione> deviazioni)
      : deviazioni = List.unmodifiable([...deviazioni]..sort((a, b) => a.daM.compareTo(b.daM)));

  final PercorsoCalcolato percorso;

  /// In ordine lungo il percorso.
  final List<Deviazione> deviazioni;

  /// Dove sta, nel percorso nuovo, il punto [vecchio] di quello di prima (i
  /// punti tolti finiscono all'inizio del pezzo nuovo).
  int indiceNuovo(int vecchio) {
    var piu = 0;
    for (final d in deviazioni) {
      if (vecchio > d.aIndice) {
        piu += d.inseriti - (d.aIndice - d.daIndice);
      } else if (vecchio > d.daIndice) {
        return d.daIndice + 1 + piu;
      } else {
        break;
      }
    }
    return vecchio + piu;
  }

  /// Se il punto [vecchio] di prima stava nel pezzo tolto.
  bool tolto(int vecchio) => deviazioni.any((d) => vecchio > d.daIndice && vecchio <= d.aIndice);

  /// I metri sul percorso nuovo di [m] metri su quello di prima.
  double metriNuovi(double m) {
    var piu = 0.0;
    for (final d in deviazioni) {
      if (m >= d.aM) {
        piu += d.differenzaM;
      } else if (m > d.daM) {
        final f = d.aM > d.daM ? (m - d.daM) / (d.aM - d.daM) : 0.0;
        return d.daM + piu + f * d.lunghezzaM;
      } else {
        break;
      }
    }
    return m + piu;
  }
}

/// Il percorso [p] senza i pezzi contromano fra [daM] e [aM] metri (tutto,
/// senza), rifatti sulle [strade] di OpenStreetMap; `null` se non ce n'è
/// nessuno, o se nessuno si può rifare con una deviazione corta.
///
/// [protettoM]: prima di qui il percorso non si tocca (dove è già l'auto).
PercorsoCorretto? correggiContromano(
  PercorsoCalcolato p,
  Iterable<TrattoStrada> strade, {
  double daM = 0,
  double? aM,
  double protettoM = 0,
  RegoleContromano regole = const RegoleContromano(),
}) {
  final punti = p.punti;
  if (punti.length < 2) return null;
  final linea = Linea(punti);
  final totale = linea.lunghezzaM;
  final fine = math.min(aM ?? totale, totale);
  final inizio = math.max(0.0, daM);
  if (fine - inizio < regole.minimoM) return null;

  final indietroMax = regole.indietroM.fold(0.0, math.max);
  final avantiMax = regole.avantiM.fold(0.0, math.max);
  final daLocale = math.max(0.0, inizio - indietroMax - 60);
  final aLocale = math.min(totale, fine + avantiMax + 60);
  final v = _Vecchio.da(linea, daLocale, aLocale);
  final rete = _Rete(v.piano, strade, v.riquadro(regole.deviazioneMassimaM / 2 + 100));
  if (rete.segmenti.isEmpty) return null;

  // 1. I passi contromano.
  final sospetti = <(double, double)>[];
  double? r0, r1;
  void chiudi() {
    if (r0 != null && r1! - r0! + regole.passoM >= regole.minimoM) sospetti.add((r0!, r1!));
    r0 = r1 = null;
  }

  for (var s = inizio; s <= fine; s += regole.passoM) {
    final g = rete.guarda(v.xy(s), v.rotta(s), regole);
    if (g.legale) {
      chiudi();
    } else if (g.contro) {
      if (r0 != null && s - r1! > regole.passoM * 3.5) chiudi();
      r0 ??= s;
      r1 = s;
    }
  }
  chiudi();
  if (sospetti.isEmpty) return null;

  // 2. La strada giusta per ognuno.
  final sostituzioni = <_Sostituzione>[];
  var liberoDa = math.max(protettoM, 0.0);
  for (final (c0, c1) in sospetti) {
    if (c0 < liberoDa) continue;
    final s = _sostituisci(p, linea, v, rete, regole, c0, c1, liberoDa, totale);
    if (s == null) continue;
    sostituzioni.add(s);
    liberoDa = s.deviazione.aM + 1;
  }
  if (sostituzioni.isEmpty) return null;

  // 3. Dal fondo, così gli indici dei pezzi prima restano buoni.
  var nuovo = p;
  for (final s in sostituzioni.reversed) {
    nuovo = s.applica(nuovo);
  }
  return PercorsoCorretto(nuovo, [for (final s in sostituzioni) s.deviazione]);
}

/* ─── Il piano locale ─────────────────────────────────────────────────────── */

class _Piano {
  _Piano(this.lat0, this.lon0) : kx = math.cos(lat0 * math.pi / 180) * _metriPerGrado;

  static const _metriPerGrado = 111195.08;
  final double lat0, lon0, kx;

  (double, double) xy(Punto p) => ((p.lon - lon0) * kx, (p.lat - lat0) * _metriPerGrado);
  Punto punto(double x, double y) => Punto(lat0 + y / _metriPerGrado, lon0 + x / kx);
}

/// La rotta (gradi da nord, in senso orario) da (ax, ay) a (bx, by).
double _rotta(double ax, double ay, double bx, double by) => (math.atan2(bx - ax, by - ay) * 180 / math.pi + 360) % 360;

/// Il percorso di prima nel piano locale, fra due metri.
class _Vecchio {
  _Vecchio(this.piano, this.x, this.y, this.s, this.indici);

  factory _Vecchio.da(Linea l, double daM, double aM) {
    final c = l.cumulate;
    var i0 = 0;
    while (i0 + 1 < c.length && c[i0 + 1] <= daM) {
      i0++;
    }
    var i1 = i0;
    while (i1 + 1 < c.length && c[i1] < aM) {
      i1++;
    }
    final piano = _Piano(l.punti[i0].lat, l.punti[i0].lon);
    final x = <double>[], y = <double>[], s = <double>[], indici = <int>[];
    for (var i = i0; i <= i1; i++) {
      final (px, py) = piano.xy(l.punti[i]);
      x.add(px);
      y.add(py);
      s.add(c[i]);
      indici.add(i);
    }
    return _Vecchio(piano, x, y, s, indici);
  }

  final _Piano piano;
  final List<double> x, y, s;
  final List<int> indici;

  int _seg(double m) {
    var lo = 0, hi = s.length - 1;
    if (m <= s.first) return 0;
    if (m >= s.last) return math.max(0, s.length - 2);
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (s[mid] <= m) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  (double, double) xy(double m) {
    if (s.length == 1) return (x.first, y.first);
    final i = _seg(m);
    final l = s[i + 1] - s[i];
    final f = l <= 0 ? 0.0 : ((m - s[i]) / l).clamp(0.0, 1.0);
    return (x[i] + f * (x[i + 1] - x[i]), y[i] + f * (y[i + 1] - y[i]));
  }

  /// La direzione della linea attorno a [m]: da quattro metri prima a quattro
  /// dopo, così un vertice non la fa saltare.
  double rotta(double m, [double campo = 4]) {
    final (ax, ay) = xy(m - campo);
    final (bx, by) = xy(m + campo);
    if ((ax - bx).abs() < 1e-6 && (ay - by).abs() < 1e-6) {
      final i = _seg(m);
      return _rotta(x[i], y[i], x[math.min(i + 1, x.length - 1)], y[math.min(i + 1, y.length - 1)]);
    }
    return _rotta(ax, ay, bx, by);
  }

  /// L'indice (del percorso intero) del segmento che contiene [m].
  int indiceDi(double m) => indici[_seg(m)];

  /// Il punto della linea più vicino a (qx, qy) fra [da] e [a] metri: i
  /// metri e quanto è lontano.
  (double, double) proietta(double qx, double qy, double da, double a) {
    var meglio = (da, double.infinity);
    for (var i = 0; i + 1 < s.length; i++) {
      if (s[i + 1] < da || s[i] > a) continue;
      final dx = x[i + 1] - x[i], dy = y[i + 1] - y[i];
      final l2 = dx * dx + dy * dy;
      final t = l2 == 0 ? 0.0 : (((qx - x[i]) * dx + (qy - y[i]) * dy) / l2).clamp(0.0, 1.0);
      final px = x[i] + t * dx, py = y[i] + t * dy;
      final d = math.sqrt((qx - px) * (qx - px) + (qy - py) * (qy - py));
      final m = (s[i] + t * (s[i + 1] - s[i])).clamp(da, a);
      if (d < meglio.$2) meglio = (m, d);
    }
    return meglio;
  }

  ({double x0, double y0, double x1, double y1}) riquadro(double margine) {
    var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    for (var i = 0; i < x.length; i++) {
      x0 = math.min(x0, x[i]);
      x1 = math.max(x1, x[i]);
      y0 = math.min(y0, y[i]);
      y1 = math.max(y1, y[i]);
    }
    return (x0: x0 - margine, y0: y0 - margine, x1: x1 + margine, y1: y1 + margine);
  }
}

/* ─── La rete delle strade ────────────────────────────────────────────────── */

class _Segmento {
  _Segmento(this.ax, this.ay, this.bx, this.by, this.na, this.nb, this.senso, this.servizio)
      : lunghezza = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)),
        rotta = _rotta(ax, ay, bx, by);

  final double ax, ay, bx, by;
  final int na, nb;

  /// 1 si va da a a b, -1 da b ad a, 0 tutti e due.
  final int senso;
  final bool servizio;
  final double lunghezza, rotta;

  bool get avanti => senso >= 0;
  bool get indietro => senso <= 0;
}

class _Arco {
  const _Arco(this.da, this.a, this.segmento, this.lunghezza, this.rotta, this.costo);
  final int da, a, segmento;
  final double lunghezza, rotta, costo;
}

/// Un punto su una strada, e in che verso la si percorre.
class _Su {
  const _Su(this.segmento, this.u, this.avanti, this.lontano);
  final int segmento;

  /// I metri dall'inizio (a) del segmento.
  final double u;
  final bool avanti;
  final double lontano;
}

class _Rete {
  _Rete(this.piano, Iterable<TrattoStrada> strade, ({double x0, double y0, double x1, double y1}) r) {
    for (final t in strade) {
      final pts = [for (final q in t.punti) piano.xy(q)];
      if (pts.every((q) => q.$1 < r.x0 || q.$1 > r.x1 || q.$2 < r.y0 || q.$2 > r.y1)) continue;
      final servizio = t.classe == 'service';
      var prima = _nodo(pts.first.$1, pts.first.$2);
      for (var i = 1; i < pts.length; i++) {
        final (ax, ay) = pts[i - 1];
        final (bx, by) = pts[i];
        final n = _nodo(bx, by);
        if (n == prima) continue;
        final seg = _Segmento(nodiX[prima], nodiY[prima], nodiX[n], nodiY[n], prima, n, t.senso, servizio);
        if (seg.lunghezza < 0.05) continue;
        final k = segmenti.length;
        segmenti.add(seg);
        _indicizza(k, ax, ay, bx, by);
        vicini[prima].add(n);
        vicini[n].add(prima);
        final costo = servizio ? 3.0 : 1.0;
        if (seg.avanti) _arco(_Arco(prima, n, k, seg.lunghezza, seg.rotta, seg.lunghezza * costo));
        if (seg.indietro) _arco(_Arco(n, prima, k, seg.lunghezza, (seg.rotta + 180) % 360, seg.lunghezza * costo));
        prima = n;
      }
    }
  }

  final _Piano piano;
  final nodiX = <double>[], nodiY = <double>[];
  final vicini = <Set<int>>[];
  final uscite = <List<int>>[];
  final archi = <_Arco>[];
  final segmenti = <_Segmento>[];
  final _celleNodi = <int, List<int>>{};
  final _celleSegmenti = <int, List<int>>{};
  static const _cella = 20.0;

  static int _chiave(int cx, int cy) => cx * 2000003 + cy;

  /// Lo stesso punto nella tessera accanto (o nella stessa strada spezzata)
  /// è lo stesso nodo: entro tre quarti di metro.
  int _nodo(double x, double y) {
    final cx = x.floor(), cy = y.floor();
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final n in _celleNodi[_chiave(cx + dx, cy + dy)] ?? const <int>[]) {
          if ((nodiX[n] - x).abs() <= 0.75 && (nodiY[n] - y).abs() <= 0.75) return n;
        }
      }
    }
    final n = nodiX.length;
    nodiX.add(x);
    nodiY.add(y);
    vicini.add(<int>{});
    uscite.add(<int>[]);
    (_celleNodi[_chiave(cx, cy)] ??= []).add(n);
    return n;
  }

  void _arco(_Arco a) {
    uscite[a.da].add(archi.length);
    archi.add(a);
  }

  void _indicizza(int k, double ax, double ay, double bx, double by) {
    final x0 = (math.min(ax, bx) / _cella).floor(), x1 = (math.max(ax, bx) / _cella).floor();
    final y0 = (math.min(ay, by) / _cella).floor(), y1 = (math.max(ay, by) / _cella).floor();
    for (var cx = x0; cx <= x1; cx++) {
      for (var cy = y0; cy <= y1; cy++) {
        (_celleSegmenti[_chiave(cx, cy)] ??= []).add(k);
      }
    }
  }

  Iterable<int> _segmentiVicini(double x, double y, double r) sync* {
    final visti = <int>{};
    for (var cx = ((x - r) / _cella).floor(); cx <= ((x + r) / _cella).floor(); cx++) {
      for (var cy = ((y - r) / _cella).floor(); cy <= ((y + r) / _cella).floor(); cy++) {
        for (final k in _celleSegmenti[_chiave(cx, cy)] ?? const <int>[]) {
          if (visti.add(k)) yield k;
        }
      }
    }
  }

  /// Le strade vicino a (x, y) che vanno come [rotta]: se ce n'è una
  /// percorribile in quel verso ([legale]), se ci sono solo sensi unici al
  /// contrario ([contro]), e la più vicina percorribile.
  ({bool legale, bool contro, _Su? su}) guarda((double, double) q, double rotta, RegoleContromano r) {
    final (x, y) = q;
    var legale = false, contro = false;
    _Su? su;
    for (final k in _segmentiVicini(x, y, r.raggioM)) {
      final s = segmenti[k];
      final dx = s.bx - s.ax, dy = s.by - s.ay;
      final u = ((x - s.ax) * dx + (y - s.ay) * dy) / s.lunghezza;
      // Il piede deve cadere sul segmento (con due metri di gioco): una
      // strada che finisce lì vicino non dice niente su questo punto.
      if (u < -2 || u > s.lunghezza + 2) continue;
      final uc = u.clamp(0.0, s.lunghezza);
      final px = s.ax + dx * uc / s.lunghezza, py = s.ay + dy * uc / s.lunghezza;
      final d = math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
      if (d > r.raggioM) continue;
      final giro = diQuantoSiGira(s.rotta, rotta).abs();
      final bool avanti;
      if (giro <= r.angoloGradi) {
        avanti = true;
      } else if (giro >= 180 - r.angoloGradi) {
        avanti = false;
      } else {
        continue;
      }
      final puo = avanti ? s.avanti : s.indietro;
      if (puo) {
        legale = true;
        if (su == null || d < su.lontano) su = _Su(k, uc, avanti, d);
      } else {
        contro = true;
      }
    }
    return (legale: legale, contro: contro && !legale, su: su);
  }

  /// I gradi di cui si gira passando da [rottaPrima] all'arco [a], o `null`
  /// se lì non si può: indietro sulla stessa strada, o un'inversione a un
  /// incrocio.
  double? _svolta(int nodo, double rottaPrima, int? daNodo, _Arco a) {
    if (a.a == daNodo) return null;
    final giro = diQuantoSiGira(rottaPrima, a.rotta);
    if (vicini[nodo].length >= 3 && giro.abs() > 150) return null;
    return giro;
  }

  static double _penale(double? giro, int gradoNodo) =>
      giro == null || gradoNodo < 3 ? 0 : (giro.abs() > 100 ? 30 : (giro.abs() > 60 ? 5 : 0));

  /// La strada più breve, rispettando i sensi unici, da [da] ad [a]: i nodi
  /// attraversati e la lunghezza vera; `null` se non c'è entro [massimoM].
  ({List<int> nodi, double lunghezza})? strada(_Su da, _Su a, double massimoM) {
    final s0 = segmenti[da.segmento], s1 = segmenti[a.segmento];
    // Sulla stessa strada, nello stesso verso, più avanti.
    if (da.segmento == a.segmento && da.avanti == a.avanti) {
      final l = da.avanti ? a.u - da.u : da.u - a.u;
      if (l >= 0) return (nodi: const <int>[], lunghezza: l);
    }
    final nodo0 = da.avanti ? s0.nb : s0.na;
    final prima0 = da.avanti ? s0.na : s0.nb;
    final rotta0 = da.avanti ? s0.rotta : (s0.rotta + 180) % 360;
    final l0 = da.avanti ? s0.lunghezza - da.u : da.u;
    // Dove si entra nel segmento d'arrivo, e quanto resta.
    final nodo1 = a.avanti ? s1.na : s1.nb;
    final rotta1 = a.avanti ? s1.rotta : (s1.rotta + 180) % 360;
    final l1 = a.avanti ? a.u : s1.lunghezza - a.u;
    final altro1 = a.avanti ? s1.nb : s1.na;

    final costi = <int, double>{}, veri = <int, double>{}, prima = <int, int>{};
    final coda = PriorityQueue<(double, int)>((x, y) => x.$1.compareTo(y.$1));
    double? migliore;
    int? ultimo;
    double? veroMigliore;

    void arrivo(int nodo, double rotta, int? daNodo, double costo, double vero, int? arco) {
      if (nodo != nodo1 || daNodo == altro1) return;
      final giro = diQuantoSiGira(rotta, rotta1);
      if (vicini[nodo].length >= 3 && giro.abs() > 150) return;
      final c = costo + l1 + _penale(giro, vicini[nodo].length);
      if (migliore == null || c < migliore!) {
        migliore = c;
        ultimo = arco;
        veroMigliore = vero + l1;
      }
    }

    arrivo(nodo0, rotta0, prima0, l0, l0, null);
    for (final k in uscite[nodo0]) {
      final ar = archi[k];
      final giro = _svolta(nodo0, rotta0, prima0, ar);
      if (giro == null && ar.a == prima0) continue;
      if (giro == null) continue;
      final c = l0 + ar.costo + _penale(giro, vicini[nodo0].length);
      if (c < (costi[k] ?? double.infinity)) {
        costi[k] = c;
        veri[k] = l0 + ar.lunghezza;
        prima[k] = -1;
        coda.add((c, k));
      }
    }
    while (coda.isNotEmpty) {
      final (c, k) = coda.removeFirst();
      if (c > (costi[k] ?? double.infinity)) continue;
      if (migliore != null && c >= migliore!) break;
      if (veri[k]! > massimoM) continue;
      final ar = archi[k];
      arrivo(ar.a, ar.rotta, ar.da, c, veri[k]!, k);
      for (final j in uscite[ar.a]) {
        final br = archi[j];
        final giro = _svolta(ar.a, ar.rotta, ar.da, br);
        if (giro == null) continue;
        final cc = c + br.costo + _penale(giro, vicini[ar.a].length);
        if (cc < (costi[j] ?? double.infinity)) {
          costi[j] = cc;
          veri[j] = veri[k]! + br.lunghezza;
          prima[j] = k;
          coda.add((cc, j));
        }
      }
    }
    if (migliore == null || veroMigliore! > massimoM) return null;
    final nodi = <int>[];
    var k = ultimo;
    while (k != null && k >= 0) {
      nodi.add(archi[k].a);
      k = prima[k];
    }
    nodi.add(nodo0);
    return (nodi: nodi.reversed.toList(), lunghezza: veroMigliore!);
  }

  /// La direzione da [nodo] verso [vicino], guardando una decina di metri
  /// avanti lungo quella strada (oltre i vertici senza incroci).
  double rottaVerso(int nodo, int vicino) {
    var da = nodo, a = vicino;
    while (math.sqrt(math.pow(nodiX[a] - nodiX[nodo], 2) + math.pow(nodiY[a] - nodiY[nodo], 2)) < 8 &&
        vicini[a].length == 2) {
      final dopo = vicini[a].firstWhere((n) => n != da);
      da = a;
      a = dopo;
    }
    return _rotta(nodiX[nodo], nodiY[nodo], nodiX[a], nodiY[a]);
  }
}

/* ─── Una sostituzione ────────────────────────────────────────────────────── */

/// Una manovra nuova nel pezzo rifatto: dove (indice fra gli inseriti) e cosa.
class _ManovraNuova {
  const _ManovraNuova(this.locale, this.manovra);
  final int locale;
  final Manovra manovra;
}

class _Sostituzione {
  _Sostituzione(this.deviazione, this.inseriti, this.manovre);

  final Deviazione deviazione;
  final List<Punto> inseriti;
  final List<_ManovraNuova> manovre;

  PercorsoCalcolato applica(PercorsoCalcolato p) {
    final d = deviazione;
    final iA = d.daIndice, iB = d.aIndice;
    if (iA < 0 || iB < iA || iB >= p.punti.length - 1) return p;
    final punti = [...p.punti.sublist(0, iA + 1), ...inseriti, ...p.punti.sublist(iB + 1)];
    final sposta = inseriti.length - (iB - iA);
    int nuovoIndice(int i) => i <= iA ? i : (i > iB ? i + sposta : iA + 1);
    final cum = Linea(punti).cumulate;

    // Le manovre: quelle del pezzo tolto se ne vanno, le nuove entrano.
    final prima = [
      for (final m in p.manovre)
        if (m.inizio <= iA) m
    ];
    final dopo = [
      for (final m in p.manovre)
        if (m.inizio > iB) m.spostata(m.inizio + sposta)
    ];
    final nuove = [for (final n in manovre) n.manovra.spostata(iA + 1 + n.locale)];
    final tutte = [...prima, ...nuove, ...dopo];
    // Le lunghezze fino alla prossima: quella prima del pezzo e le nuove.
    final velocita = prima.isNotEmpty && prima.last.secondi > 0 && prima.last.lunghezzaM > 0
        ? prima.last.lunghezzaM / prima.last.secondi
        : 13.9;
    for (var k = math.max(0, prima.length - 1); k < prima.length + nuove.length && k < tutte.length; k++) {
      final m = tutte[k];
      final fino = k + 1 < tutte.length ? tutte[k + 1].inizio : punti.length - 1;
      final l = math.max(0.0, cum[math.min(fino, cum.length - 1)] - cum[math.min(m.inizio, cum.length - 1)]);
      final v = m.secondi > 0 && m.lunghezzaM > 0 && k < prima.length ? m.lunghezzaM / m.secondi : velocita;
      tutte[k] = m.spostata(m.inizio, lunghezzaM: l, secondi: l / v);
    }

    // I limiti, segmento per segmento.
    final limiti = p.limiti.isEmpty
        ? const <int?>[]
        : [
            for (var i = 0; i < punti.length - 1; i++)
              if (i <= iA)
                p.limiteSul(i)
              else if (i <= iA + inseriti.length - 1)
                p.limiteSul(iA)
              else
                p.limiteSul(i - sposta),
          ];
    assert(nuovoIndice(iB + 1) == iA + inseriti.length + 1);

    double metri(double m) {
      if (m <= d.daM) return m;
      if (m >= d.aM) return m + d.differenzaM;
      final f = (m - d.daM) / (d.aM - d.daM);
      return d.daM + f * d.lunghezzaM;
    }

    return p.conGeometria(
      punti: punti,
      manovre: tutte,
      limiti: limiti,
      code: [
        for (final c in p.code)
          Coda(
            daM: metri(c.daM),
            aM: metri(c.aM),
            ritardo: c.ritardo,
            livello: c.livello,
            velocitaKmh: c.velocitaKmh,
            tipo: c.tipo,
          ),
      ],
      pedaggi: [
        for (final t in p.pedaggi)
          TrattoPedaggio(daM: metri(t.daM), aM: metri(t.aM), vignetta: t.vignetta, paese: t.paese),
      ],
      pagamentiPedaggio: p.pagamentiPedaggio == null
          ? null
          : [for (final x in p.pagamentiPedaggio!) PagamentoPedaggio(euro: x.euro, aM: metri(x.aM), nome: x.nome)],
      senzaTraffico: p.senzaTraffico == null || p.senzaTraffico!.punti.length != p.punti.length
          ? p.senzaTraffico
          : applica(p.senzaTraffico!),
    );
  }
}

/// Il pezzo di strada giusta attorno al contromano da [c0] a [c1] metri.
_Sostituzione? _sostituisci(
  PercorsoCalcolato p,
  Linea linea,
  _Vecchio v,
  _Rete rete,
  RegoleContromano r,
  double c0,
  double c1,
  double liberoDa,
  double totale,
) {
  // Il punto buono più vicino a [m], cercando verso [verso] per al più venti
  // metri: lì si sta su una strada percorribile nel verso del percorso.
  (double, _Su)? buono(double m, int verso) {
    for (var k = 0.0; k <= 20; k += r.passoM) {
      final s = m + verso * k;
      if (s < 0 || s > totale) return null;
      final g = rete.guarda(v.xy(s), v.rotta(s), r);
      if (g.su != null) return (s, g.su!);
    }
    return null;
  }

  for (final indietro in r.indietroM) {
    final sa = c0 - indietro;
    if (sa < liberoDa) break;
    final a = buono(sa, -1);
    if (a == null || a.$1 < liberoDa) continue;
    for (final avanti in r.avantiM) {
      final sb = c1 + avanti;
      if (sb >= totale - 5) break;
      final b = buono(sb, 1);
      if (b == null || b.$1 >= totale - 5) continue;
      final (sA, suA) = a;
      final (sB, suB) = b;
      final vecchioM = sB - sA;
      final massimo = math.min(r.deviazioneMassimaM, vecchioM * r.rapportoMassimo);
      final via = rete.strada(suA, suB, massimo);
      if (via == null) continue;
      return _costruisci(p, linea, v, rete, sA, sB, suA, suB, via.nodi, c0, c1, liberoDa);
    }
  }
  return null;
}

_Sostituzione _costruisci(
  PercorsoCalcolato p,
  Linea linea,
  _Vecchio v,
  _Rete rete,
  double sA0,
  double sB0,
  _Su suA,
  _Su suB,
  List<int> nodi,
  double c0,
  double c1,
  double liberoDa,
) {
  (double, double) piede(_Su su) {
    final s = rete.segmenti[su.segmento];
    final f = su.u / s.lunghezza;
    return (s.ax + f * (s.bx - s.ax), s.ay + f * (s.by - s.ay));
  }

  // La strada nuova: dal piede di partenza, per i nodi, al piede d'arrivo.
  final px = <double>[], py = <double>[];
  final nodoIn = <int, int>{}; // indice nella polilinea → nodo della rete
  void aggiungi(double x, double y, [int? nodo]) {
    if (px.isNotEmpty && (px.last - x).abs() < 0.05 && (py.last - y).abs() < 0.05) {
      if (nodo != null) nodoIn[px.length - 1] = nodo;
      return;
    }
    px.add(x);
    py.add(y);
    if (nodo != null) nodoIn[px.length - 1] = nodo;
  }

  final (ax, ay) = piede(suA);
  final (bx, by) = piede(suB);
  // Gli estremi sulla linea vecchia di fianco ai piedi, non un poco più
  // avanti o indietro: lo scarto di TomTom lungo la strada, raccordato,
  // faceva fare alla linea un passo all'indietro (un ricciolo).
  var (sA, _) = v.proietta(ax, ay, sA0 - 20, sA0 + 20);
  var (sB, _) = v.proietta(bx, by, sB0 - 20, sB0 + 20);
  if (sA < liberoDa || sA >= sB - 10) sA = sA0;
  if (sB <= sA + 10) sB = sB0;
  aggiungi(ax, ay);
  for (final n in nodi) {
    aggiungi(rete.nodiX[n], rete.nodiY[n], n);
  }
  aggiungi(bx, by);
  final cum = <double>[0];
  for (var i = 1; i < px.length; i++) {
    cum.add(cum.last + math.sqrt(math.pow(px[i] - px[i - 1], 2) + math.pow(py[i] - py[i - 1], 2)));
  }
  final lunghezza = cum.last;

  // La linea di TomTom sta di lato a quella di OpenStreetMap: la strada nuova
  // parte e arriva sulla sua, e ci si raccorda piano, in venticinque metri.
  final (rax, ray) = v.xy(sA);
  final (rbx, rby) = v.xy(sB);
  final oax = rax - ax, oay = ray - ay, obx = rbx - bx, oby = rby - by;
  final raccordo = math.min(25.0, lunghezza / 3);
  final qx = <double>[], qy = <double>[], qs = <double>[];
  final nodoA = <int, int>{}; // indice fra gli inseriti → nodo
  for (var i = 0; i < px.length; i++) {
    // Un punto ogni cinque metri al più, per un raccordo morbido.
    if (i > 0) {
      final l = cum[i] - cum[i - 1];
      final n = (l / 5).floor();
      for (var k = 1; k <= n; k++) {
        final f = k / (n + 1);
        qx.add(px[i - 1] + f * (px[i] - px[i - 1]));
        qy.add(py[i - 1] + f * (py[i] - py[i - 1]));
        qs.add(cum[i - 1] + f * l);
      }
    }
    if (nodoIn[i] case final n?) nodoA[qx.length] = n;
    qx.add(px[i]);
    qy.add(py[i]);
    qs.add(cum[i]);
  }
  final inseriti = <Punto>[];
  for (var i = 0; i < qx.length; i++) {
    final wa = raccordo <= 0 ? 0.0 : math.max(0.0, 1 - qs[i] / raccordo);
    final wb = raccordo <= 0 ? 0.0 : math.max(0.0, 1 - (lunghezza - qs[i]) / raccordo);
    inseriti.add(v.piano.punto(qx[i] + oax * wa + obx * wb, qy[i] + oay * wa + oby * wb));
  }
  final lungaDavvero = Linea(inseriti).lunghezzaM;

  final iA = v.indiceDi(sA);
  var iB = v.indiceDi(sB);
  if (iB < iA) iB = iA;
  final deviazione = Deviazione(
    daM: sA,
    aM: sB,
    lunghezzaM: lungaDavvero,
    daIndice: iA,
    aIndice: iB,
    inseriti: inseriti.length,
    contromanoDaM: c0,
    contromanoAM: c1,
  );

  // Le manovre.
  final tolte = [
    for (final m in p.manovre)
      if (m.inizio > iA && m.inizio <= iB) m
  ];
  // Prima e dopo, la linea vecchia riportata sulla strada (senza lo scarto di
  // TomTom): gli angoli si misurano tutti sulle strade vere.
  (double, double) sulNuovo(double d) {
    if (d <= 0) {
      final (x, y) = v.xy(sA + d);
      return (x - oax, y - oay);
    }
    if (d >= lunghezza) {
      final (x, y) = v.xy(sB + d - lunghezza);
      return (x - obx, y - oby);
    }
    var i = 1;
    while (i < cum.length - 1 && cum[i] < d) {
      i++;
    }
    final f = (d - cum[i - 1]) / math.max(1e-9, cum[i] - cum[i - 1]);
    return (px[i - 1] + f * (px[i] - px[i - 1]), py[i - 1] + f * (py[i] - py[i - 1]));
  }

  double rottaNuova(double d0, double d1) {
    final (x0, y0) = sulNuovo(d0);
    final (x1, y1) = sulNuovo(d1);
    return _rotta(x0, y0, x1, y1);
  }

  final nuove = <_ManovraNuova>[];
  final metriNodo = <int, double>{for (final e in nodoA.entries) e.key: qs[e.key]};
  var staccata = false;
  for (final e in nodoA.entries) {
    final locale = e.key, n = e.value, d = metriNodo[locale]!;
    if (d <= 0.5 || d >= lunghezza - 0.5 || rete.vicini[n].length < 3) continue;
    final entra = rottaNuova(d - 10, d), esce = rottaNuova(d, d + 10);
    final giro = diQuantoSiGira(entra, esce);
    // Dove si stacca dalla linea vecchia: lì la linea vecchia va altrove.
    final (m, _) = v.proietta(rete.nodiX[n], rete.nodiY[n], sA, sB);
    final vecchia = v.rotta(m, 5);
    final siStacca = !staccata && diQuantoSiGira(vecchia, esce).abs() >= 20;
    if (!siStacca && giro.abs() < 40) continue;
    staccata = staccata || siStacca;
    // Gli altri rami dell'incrocio: per dire «bivio».
    final indice = nodi.indexOf(n);
    final da = indice > 0 ? nodi[indice - 1] : -1, verso = indice + 1 < nodi.length ? nodi[indice + 1] : -1;
    double? altro;
    for (final w in rete.vicini[n]) {
      if (w == da || w == verso) continue;
      final rel = diQuantoSiGira(entra, rete.rottaVerso(n, w));
      if (rel.abs() <= 50 && (altro == null || rel.abs() < altro.abs())) altro = rel;
    }
    final tipo = altro != null && giro.abs() <= 50 ? (giro > altro ? 23 : 24) : _tipoDaAngolo(giro);
    nuove.add(_ManovraNuova(locale, _manovra(tipo, '', '')));
  }

  // Le manovre tolte che stanno ancora sulla strada nuova (una svolta più
  // avanti, sullo stesso incrocio): restano come le aveva date il motore.
  for (final m in tolte) {
    final (ox, oy) = v.piano.xy(p.punti[m.inizio]);
    var meglio = -1;
    var lontano = double.infinity;
    for (var i = 0; i < qx.length; i++) {
      final dd = math.sqrt(math.pow(qx[i] - ox, 2) + math.pow(qy[i] - oy, 2));
      if (dd < lontano) {
        lontano = dd;
        meglio = i;
      }
    }
    if (meglio < 0 || lontano > 15) continue;
    final mOld = linea.cumulate[m.inizio];
    final (vx0, vy0) = v.xy(mOld);
    final (vx1, vy1) = v.xy(mOld + 10);
    final dopoVecchia = _rotta(vx0, vy0, vx1, vy1);
    if (diQuantoSiGira(dopoVecchia, rottaNuova(qs[meglio], qs[meglio] + 10)).abs() > 30) continue;
    if (nuove.any((n) => (qs[n.locale] - qs[meglio]).abs() < 20)) continue;
    nuove.add(_ManovraNuova(meglio, m));
  }
  nuove.sort((a, b) => a.locale.compareTo(b.locale));

  // Il nome della strada: quello dell'ultima manovra tolta va all'ultima
  // nuova (è lì che si arriva), con le sue indicazioni.
  final ultimaTolta = tolte.lastOrNull;
  for (var k = 0; k < nuove.length; k++) {
    final n = nuove[k];
    if (tolte.contains(n.manovra)) continue;
    final ultima = k == nuove.length - 1 || nuove.sublist(k + 1).every((x) => tolte.contains(x.manovra));
    final strada = ultima ? ultimaTolta?.strada ?? '' : '';
    final verso = ultima ? ultimaTolta?.verso ?? '' : '';
    nuove[k] = _ManovraNuova(n.locale, _manovra(n.manovra.tipo, strada, verso));
  }
  // Niente da dire dove la strada nuova si stacca appena (una carreggiata
  // accanto) e non c'era nessuna manovra: si resta come prima.
  nuove.removeWhere((n) => n.manovra.tipo == 8 && tolte.isEmpty);
  return _Sostituzione(deviazione, inseriti, nuove);
}

int _tipoDaAngolo(double giro) {
  final a = giro.abs();
  if (a < 20) return 8;
  if (giro > 0) return a < 50 ? 9 : (a < 120 ? 10 : 11);
  return a < 50 ? 16 : (a < 120 ? 15 : 14);
}

/// La manovra di tipo [tipo] (i numeri di Valhalla, come le altre), con la
/// frase in italiano.
Manovra _manovra(int tipo, String strada, String verso) {
  final (frase, legame) = switch (tipo) {
    23 => ('Al bivio tieni la destra', 'verso'),
    24 => ('Al bivio tieni la sinistra', 'verso'),
    9 => ('Svolta leggermente a destra', 'in'),
    10 => ('Gira a destra', 'in'),
    11 => ('Svolta stretta a destra', 'in'),
    16 => ('Svolta leggermente a sinistra', 'in'),
    15 => ('Gira a sinistra', 'in'),
    14 => ('Svolta stretta a sinistra', 'in'),
    _ => ('Prosegui dritto', 'su'),
  };
  final dove = strada.isNotEmpty ? strada : verso;
  final istruzione = dove.isEmpty ? frase : '$frase $legame $dove';
  return Manovra(
    istruzione: istruzione,
    voce: istruzione,
    lunghezzaM: 0,
    secondi: 0,
    inizio: 0,
    tipo: tipo,
    strada: strada,
    verso: tipo == 23 || tipo == 24 ? verso : '',
  );
}
