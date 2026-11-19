import 'dart:math' as math;
import 'dart:typed_data';

import '../geo/geo.dart';
import '../guida/aggancio_strada.dart';
import 'tessere_strade.dart' show classiStradeAuto;

/* ─── Il percorso sulle strade della mappa ──────────────────────────────────
 *
 * «Linee fuori strada.» Il percorso arriva da TomTom, e la sua geometria è
 * quella delle strade di TomTom; la mappa disegna quelle di OpenStreetMap, e
 * in tante zone le due stanno a cinque, dieci metri l'una dall'altra. La
 * scena 3D la appoggia sulle strade da sé (`spostamenti` in web3d); la mappa
 * di sempre, e soprattutto la vista immersiva (le strade larghe quanto sono,
 * da vicino), la disegnava com'era: in città sui marciapiedi e nelle case,
 * in autostrada sulla corsia d'emergenza, con le corsie della manovra di lato.
 *
 * Qui la linea che si DISEGNA, non quella della guida: la guida, i metri, le
 * manovre e la scena 3D restano sul percorso vero. [SullaMappa] tiene, per
 * ogni punto della linea da disegnare, i metri del punto del percorso da cui
 * viene: «a tanti metri» è lo stesso posto sulle due linee, e la freccia
 * dell'auto (che va a metri lungo il percorso) sta sulla linea disegnata.
 *
 * Come la scena 3D: si guarda di quanto sta DI LATO la strada sotto, ogni
 * [passoM] metri, e quel numero si leviga lungo la linea, così la linea si
 * sposta tutta insieme e non fa scalini. Solo strade che vanno nel verso del
 * percorso (un senso unico al contrario, la traversa di un incrocio, l'altra
 * carreggiata non rubano la linea), entro [spostamentoMaxM]. */

/// Più di così non si sposta: oltre, la strada giusta è un'altra (lo stesso
/// limite della scena 3D, `SPOSTAMENTO_MAX_M`).
const spostamentoMaxM = 13.0;

/// Ogni quanti metri si guarda la strada sotto.
const passoM = 4.0;

/// Una strada che va a più di tanti gradi dal percorso non è quella su cui si va.
const _direzioneGradi = 30.0;

/// Fin qui, attorno all'andamento, uno scarto di lato è ancora la stessa strada.
const _scartoStessaStradaM = 1.5;

/// Quanti metri in più conta una strada di un altro tipo di quella su cui si
/// era: una rampa (o la carreggiata, se si era su una rampa), un'altra classe.
///
/// «Linee fuori strada», all'uscita dell'autostrada: la linea del fornitore
/// sta di lato verso la rampa che si stacca, e la rampa le era più vicina
/// della carreggiata su cui si va ancora; la linea ci saltava sopra per
/// duecento metri e tornava, a zig zag. Su una rampa si passa quando la
/// carreggiata non c'è più (gira via, o è troppo lontana).
const _cambioRampaM = 9.0, _cambioClasseM = 2.0;

/// In quanti metri lo spostamento nuovo prende il posto di quello di prima.
const _raccordoM = 40.0;

/// La linea da disegnare per un percorso: i [punti] e, per ognuno, i [metri]
/// del percorso da cui viene (in salita).
class SullaMappa {
  SullaMappa._(this.percorso, this.punti, this.metri, [List<String?>? classi])
      : classi = classi ?? List.filled(punti.length, null);

  /// Com'è il percorso: nessuno spostamento.
  factory SullaMappa(List<Punto> percorso) {
    final l = Linea(percorso);
    return SullaMappa._(percorso, List.unmodifiable(percorso), List.unmodifiable(l.cumulate));
  }

  /// I punti del percorso vero.
  final List<Punto> percorso;
  final List<Punto> punti;
  final List<double> metri;

  /// La classe di OpenMapTiles della strada su cui sta ogni punto (`null`
  /// dove non si sa): le corsie disegnate prendono il suo colore.
  final List<String?> classi;

  /// La linea da disegnare, coi metri del percorso.
  late final Linea linea = Linea.conMetri(punti, metri);

  late final Linea _vera = Linea(percorso);

  /// Se qualcosa è stato spostato.
  late final bool spostata = () {
    if (punti.length != percorso.length) return true;
    for (var i = 0; i < punti.length; i++) {
      if (punti[i] != percorso[i]) return true;
    }
    return false;
  }();

  /// La stessa linea, fra [daM] e [aM] metri appoggiata sulle [strade]. Ai
  /// due capi in [_raccordoM] metri si passa da com'era a com'è adesso.
  SullaMappa allineata(Iterable<TrattoStrada> strade, {required double daM, required double aM}) {
    final vera = _vera;
    final totale = vera.lunghezzaM;
    final da = daM.clamp(0.0, totale), a = aM.clamp(0.0, totale);
    if (a - da < passoM * 3 || percorso.length < 2) return this;
    final nuovi = _spostamenti(vera, strade, da, a);
    if (nuovi == null) return this;
    final (ms, ps, cs) = nuovi;
    final out = <Punto>[], outM = <double>[], outC = <String?>[];
    for (var i = 0; i < punti.length && metri[i] < ms.first; i++) {
      out.add(punti[i]);
      outM.add(metri[i]);
      outC.add(classi[i]);
    }
    for (var k = 0; k < ms.length; k++) {
      final m = ms[k];
      if (outM.isNotEmpty && m <= outM.last) continue;
      // Ai capi: da com'era (anche già spostata da prima) a com'è adesso.
      final w = math.min(da > 0 ? (m - da) / _raccordoM : 1.0, a < totale ? (a - m) / _raccordoM : 1.0).clamp(0.0, 1.0);
      if (w >= 1) {
        out.add(ps[k]);
      } else {
        final prima = _puntoA(linea, m), vero = _puntoA(vera, m);
        out.add(
          Punto(
            vero.lat + (prima.lat - vero.lat) * (1 - w) + (ps[k].lat - vero.lat) * w,
            vero.lon + (prima.lon - vero.lon) * (1 - w) + (ps[k].lon - vero.lon) * w,
          ),
        );
      }
      outM.add(m);
      outC.add(cs[k]);
    }
    for (var i = 0; i < punti.length; i++) {
      if (metri[i] > outM.last) {
        out.add(punti[i]);
        outM.add(metri[i]);
        outC.add(classi[i]);
      }
    }
    return SullaMappa._(percorso, List.unmodifiable(out), List.unmodifiable(outM), List.unmodifiable(outC));
  }

  /// La classe della strada sotto la linea a [m] metri, se si sa (il punto
  /// più vicino, entro venti metri).
  String? classeA(double m) {
    var basso = 0, alto = metri.length - 1;
    while (basso < alto) {
      final mezzo = (basso + alto) >> 1;
      if (metri[mezzo] < m) {
        basso = mezzo + 1;
      } else {
        alto = mezzo;
      }
    }
    String? meglio;
    var d = 20.0;
    for (var i = math.max(0, basso - 8); i < math.min(metri.length, basso + 8); i++) {
      final c = classi[i];
      if (c != null && (metri[i] - m).abs() <= d) {
        d = (metri[i] - m).abs();
        meglio = c;
      }
    }
    return meglio;
  }

  /// Il punto della linea da disegnare a [m] metri lungo il percorso.
  Punto a(double m) => _puntoA(linea, m);
}

/// I punti spostati fra [da] e [a] (ogni [passoM] metri, più i vertici del
/// percorso), coi loro metri; `null` se lì sotto non c'è nessuna strada.
(List<double>, List<Punto>, List<String?>)? _spostamenti(
    Linea vera, Iterable<TrattoStrada> strade, double da, double a) {
  final totale = vera.lunghezzaM;
  // Un po' di strada in più ai lati: le medie hanno bisogno dei vicini.
  final w0 = math.max(0.0, da - 60), w1 = math.min(totale, a + 60);
  final metri = <double>[];
  for (var s = w0; s < w1; s += passoM) {
    metri.add(s);
  }
  metri.add(w1);
  // I vertici del percorso dentro: gli spigoli restano spigoli.
  for (var i = 0; i < vera.cumulate.length; i++) {
    final c = vera.cumulate[i];
    if (c > w0 && c < w1) metri.add(c);
  }
  metri.sort();
  final ms = <double>[];
  for (final m in metri) {
    if (ms.isEmpty || m - ms.last > 0.3) ms.add(m);
  }
  final n = ms.length;
  if (n < 4) return null;
  final centro = _puntoA(vera, (w0 + w1) / 2);
  final piano = _Piano(centro.lat, centro.lon);
  final px = Float64List(n), py = Float64List(n), nx = Float64List(n), ny = Float64List(n);
  final tx = Float64List(n), ty = Float64List(n);
  for (var k = 0; k < n; k++) {
    final (x, y) = piano.xy(_puntoA(vera, ms[k]));
    px[k] = x;
    py[k] = y;
    final (x0, y0) = piano.xy(_puntoA(vera, math.max(0, ms[k] - 6)));
    final (x1, y1) = piano.xy(_puntoA(vera, math.min(totale, ms[k] + 6)));
    final l = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    tx[k] = l > 0 ? (x1 - x0) / l : 1;
    ty[k] = l > 0 ? (y1 - y0) / l : 0;
    // A sinistra del verso di marcia.
    nx[k] = -ty[k];
    ny[k] = tx[k];
  }
  final rete = _Rete(piano, strade, px, py);
  if (rete.vuota) return null;

  // 1. Quanto sta di lato la strada, col segno; NaN dove non c'è.
  final lato = Float64List(n)..fillRange(0, n, double.nan);
  final classe = List<String?>.filled(n, null);
  final coseno = math.cos(_direzioneGradi * math.pi / 180);
  _Segmento? ultima;
  var trovati = 0;
  for (var k = 0; k < n; k++) {
    final c = rete.piuVicina(px[k], py[k], tx[k], ty[k], coseno, prima: ultima);
    if (c == null) continue;
    ultima = c.$3;
    classe[k] = c.$3.classe.isEmpty ? null : c.$3.classe;
    lato[k] = (c.$1 - px[k]) * nx[k] + (c.$2 - py[k]) * ny[k];
    trovati++;
  }
  if (trovati == 0) return null;
  final visto = Float64List.fromList(lato);

  // 2. I buchi corti (una trentina di metri) si riempiono; gli altri a zero.
  var k = 0;
  while (k < n) {
    if (!lato[k].isNaN) {
      k++;
      continue;
    }
    var j = k;
    while (j < n && lato[j].isNaN) {
      j++;
    }
    final prima = k > 0 ? lato[k - 1] : double.nan, dopo = j < n ? lato[j] : double.nan;
    final corto = !prima.isNaN && !dopo.isNaN && ms[math.min(j, n - 1)] - ms[math.max(k - 1, 0)] <= 36;
    for (var q = k; q < j; q++) {
      lato[q] = corto ? prima + (dopo - prima) * (ms[q] - ms[k - 1]) / (ms[j] - ms[k - 1]) : 0;
    }
    k = j;
  }

  // 3. La mediana toglie i salti corti, una media a triangolo fa il raccordo.
  final mediato = Float64List(n);
  final finestra = <double>[];
  for (var q = 0; q < n; q++) {
    finestra.clear();
    for (var j = q; j >= 0 && ms[q] - ms[j] <= 18; j--) {
      finestra.add(lato[j]);
    }
    for (var j = q + 1; j < n && ms[j] - ms[q] <= 18; j++) {
      finestra.add(lato[j]);
    }
    finestra.sort();
    mediato[q] = finestra[finestra.length >> 1];
  }
  final andamento = Float64List(n);
  for (var q = 0; q < n; q++) {
    var somma = 0.0, peso = 0.0;
    for (var j = q; j >= 0 && ms[q] - ms[j] <= 24; j--) {
      final w = 25 - (ms[q] - ms[j]);
      somma += mediato[j] * w;
      peso += w;
    }
    for (var j = q + 1; j < n && ms[j] - ms[q] <= 24; j++) {
      final w = 25 - (ms[j] - ms[q]);
      somma += mediato[j] * w;
      peso += w;
    }
    andamento[q] = somma / peso;
  }

  // 4. Attorno all'andamento, gli scarti piccoli sono la stessa strada che
  // curva: quelli si seguono, se lì attorno tutti vedono la stessa strada.
  final fine = Float64List(n);
  for (var q = 0; q < n; q++) {
    var minimo = double.infinity, massimo = double.negativeInfinity;
    var j0 = q;
    while (j0 > 0 && ms[q] - ms[j0 - 1] <= 18) {
      j0--;
    }
    for (var j = j0; j < n && ms[j] - ms[q] <= 18; j++) {
      final v = visto[j];
      if (v.isNaN) {
        massimo = double.infinity;
        break;
      }
      minimo = math.min(minimo, v);
      massimo = math.max(massimo, v);
    }
    final scarto = visto[q] - andamento[q];
    final stessa = massimo - minimo < 2 * _scartoStessaStradaM && scarto.abs() < _scartoStessaStradaM;
    fine[q] = (andamento[q] + (stessa ? scarto : 0)).clamp(-spostamentoMaxM, spostamentoMaxM);
  }

  // 5. Lo spostamento di ogni punto. A uno spigolo del percorso la linea
  // spostata di lato deve restare parallela ai due tratti: lì il punto va
  // lungo la bisettrice, di più quanto più stretto è lo spigolo.
  final dx = Float64List(n), dy = Float64List(n);
  for (var q = 0; q < n; q++) {
    var mx = nx[q], my = ny[q], scala = 1.0;
    if (q > 0 && q < n - 1) {
      final ax = px[q] - px[q - 1], ay = py[q] - py[q - 1];
      final bx = px[q + 1] - px[q], by = py[q + 1] - py[q];
      final la = math.sqrt(ax * ax + ay * ay), lb = math.sqrt(bx * bx + by * by);
      if (la > 0.05 && lb > 0.05) {
        final n1x = -ay / la, n1y = ax / la, n2x = -by / lb, n2y = bx / lb;
        final sx = n1x + n2x, sy = n1y + n2y, ls = math.sqrt(sx * sx + sy * sy);
        if (ls > 0.2) {
          mx = sx / ls;
          my = sy / ls;
          // cos(metà angolo) = ls / 2: al più il doppio.
          scala = math.min(2.0, 2 / ls);
        }
      }
    }
    dx[q] = fine[q] * mx * scala;
    dy[q] = fine[q] * my * scala;
  }

  // 6. La linea spostata non torna mai indietro: dove un pezzo va contro il
  // verso del percorso (dentro uno spigolo stretto), i suoi due capi si
  // spostano allo stesso modo, e il pezzo resta parallelo al suo.
  for (var giro = 0; giro < 8; giro++) {
    var rotti = 0;
    for (var q = 0; q < n - 1; q++) {
      final ox = px[q + 1] - px[q], oy = py[q + 1] - py[q];
      final sx = ox + dx[q + 1] - dx[q], sy = oy + dy[q + 1] - dy[q];
      if (sx * ox + sy * oy >= 0) continue;
      final mx = (dx[q] + dx[q + 1]) / 2, my = (dy[q] + dy[q + 1]) / 2;
      dx[q] = dx[q + 1] = mx;
      dy[q] = dy[q + 1] = my;
      rotti++;
    }
    if (rotti == 0) break;
  }

  final outM = <double>[], outP = <Punto>[], outC = <String?>[];
  for (var q = 0; q < n; q++) {
    if (ms[q] < da - 0.01 || ms[q] > a + 0.01) continue;
    outM.add(ms[q]);
    outP.add(piano.punto(px[q] + dx[q], py[q] + dy[q]));
    outC.add(classe[q]);
  }
  if (outM.length < 2) return null;
  return (outM, outP, outC);
}

/// Il punto di [linea] a [metri] dalla partenza (coi suoi metri).
Punto _puntoA(Linea linea, double metri) {
  final c = linea.cumulate, p = linea.punti;
  if (p.length < 2) return p.isEmpty ? const Punto(0, 0) : p.first;
  final m = metri.clamp(0.0, linea.lunghezzaM);
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

class _Piano {
  _Piano(this.lat0, this.lon0) : kx = math.cos(lat0 * math.pi / 180) * _metriPerGrado;

  static const _metriPerGrado = 111195.08;
  final double lat0, lon0, kx;

  (double, double) xy(Punto p) => ((p.lon - lon0) * kx, (p.lat - lat0) * _metriPerGrado);
  Punto punto(double x, double y) => Punto(lat0 + y / _metriPerGrado, lon0 + x / kx);
}

/// I pezzi delle strade attorno al percorso, in una griglia.
class _Rete {
  _Rete(_Piano piano, Iterable<TrattoStrada> strade, Float64List px, Float64List py) {
    var x0 = double.infinity, y0 = double.infinity, x1 = double.negativeInfinity, y1 = double.negativeInfinity;
    for (var k = 0; k < px.length; k++) {
      x0 = math.min(x0, px[k]);
      x1 = math.max(x1, px[k]);
      y0 = math.min(y0, py[k]);
      y1 = math.max(y1, py[k]);
    }
    const m = spostamentoMaxM + _cella;
    var id = 0;
    for (final s in strade) {
      id++;
      if (s.classe.isNotEmpty && !classiStradeAuto.contains(s.classe)) continue;
      // In galleria la mappa la strada non la disegna (o tratteggiata).
      if (s.ponte == 'tunnel') continue;
      final pts = [for (final p in s.punti) piano.xy(p)];
      for (var i = 1; i < pts.length; i++) {
        final (ax, ay) = pts[i - 1];
        final (bx, by) = pts[i];
        if (math.max(ax, bx) < x0 - m || math.min(ax, bx) > x1 + m) continue;
        if (math.max(ay, by) < y0 - m || math.min(ay, by) > y1 + m) continue;
        final l = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
        if (l < 0.05) continue;
        final seg = _Segmento(ax, ay, bx, by, l, s.senso, id, s.rampa, s.classe);
        final c0 = (math.min(ax, bx) / _cella).floor(), c1 = (math.max(ax, bx) / _cella).floor();
        final r0 = (math.min(ay, by) / _cella).floor(), r1 = (math.max(ay, by) / _cella).floor();
        for (var cx = c0; cx <= c1; cx++) {
          for (var cy = r0; cy <= r1; cy++) {
            (_celle[(cx, cy)] ??= []).add(seg);
          }
        }
        vuota = false;
      }
    }
  }

  static const _cella = 20.0;
  final _celle = <(int, int), List<_Segmento>>{};
  var vuota = true;

  /// Il punto della strada più vicina a [x], [y] entro [spostamentoMaxM] che
  /// va come ([tx], [ty]) — entro [coseno] — e il suo pezzo; a pari
  /// distanza (un metro e mezzo) la strada su cui si era ([prima]), e una
  /// dello stesso tipo ([_cambioRampaM], [_cambioClasseM]).
  (double, double, _Segmento)? piuVicina(double x, double y, double tx, double ty, double coseno, {_Segmento? prima}) {
    (double, double, _Segmento)? meglio;
    var punti = double.infinity;
    final cx = (x / _cella).floor(), cy = (y / _cella).floor();
    final visti = <_Segmento>{};
    for (var ax = cx - 1; ax <= cx + 1; ax++) {
      for (var ay = cy - 1; ay <= cy + 1; ay++) {
        for (final s in _celle[(ax, ay)] ?? const <_Segmento>[]) {
          if (!visti.add(s)) continue;
          final ux = (s.bx - s.ax) / s.l, uy = (s.by - s.ay) / s.l;
          final d = ux * tx + uy * ty;
          final va = switch (s.senso) {
            1 => d >= coseno,
            -1 => d <= -coseno,
            _ => d.abs() >= coseno,
          };
          if (!va) continue;
          final t = (((x - s.ax) * ux + (y - s.ay) * uy) / s.l).clamp(0.0, 1.0);
          final fx = s.ax + (s.bx - s.ax) * t, fy = s.ay + (s.by - s.ay) * t;
          final dist = math.sqrt((fx - x) * (fx - x) + (fy - y) * (fy - y));
          if (dist > spostamentoMaxM) continue;
          var p = dist;
          if (prima != null) {
            if (s.id == prima.id) p -= _scartoStessaStradaM;
            if (s.rampa != prima.rampa) p += _cambioRampaM;
            if (s.classe != prima.classe) p += _cambioClasseM;
          }
          if (p < punti) {
            punti = p;
            meglio = (fx, fy, s);
          }
        }
      }
    }
    return meglio;
  }
}

class _Segmento {
  _Segmento(this.ax, this.ay, this.bx, this.by, this.l, this.senso, this.id, this.rampa, this.classe);
  final double ax, ay, bx, by, l;
  final int senso, id;
  final bool rampa;
  final String classe;
}
