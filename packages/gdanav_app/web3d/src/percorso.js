// Il percorso in 3D: all'altezza delle strade su cui passa.
//
// Le tessere dicono a che quota sta ogni pezzo di strada (i segmenti di
// `tessera.js`); il percorso che arriva dall'app è solo una linea in pianta.
// Ogni pochi metri si cercano le strade sotto la linea che vanno nello
// stesso verso, e fra le quote possibili (sotto un viadotto ce ne sono due o
// tre) si sceglie la sequenza più continua: chi è sul viadotto ci resta,
// chi passa sotto resta sotto (Viterbi sulle quote candidate).

import { latDaMerc, lonDaMerc, mercPerMetro, mercX, mercY } from './geo.js';

/** Il sistema in metri di tutta la scena: un'origine e la sua scala. */
export class Origine {
  constructor(lon, lat) {
    this.mx = mercX(lon);
    this.my = mercY(lat);
    this.s = mercPerMetro(lat);
  }
  daLonLat(lon, lat) {
    return [(mercX(lon) - this.mx) / this.s, -(mercY(lat) - this.my) / this.s];
  }
  daMerc(mx, my) {
    return [(mx - this.mx) / this.s, -(my - this.my) / this.s];
  }
  lonLat(x, y) {
    return [lonDaMerc(this.mx + x * this.s), latDaMerc(this.my - y * this.s)];
  }
}

/**
 * I segmenti delle strade con le quote, di tutte le tessere costruite,
 * cercabili per posizione. Ogni tessera ha la sua griglia; la ricerca guarda
 * solo le tessere che contengono il punto.
 */
export class IndiceSegmenti {
  constructor(cella = 20) {
    this.cella = cella;
    this.tessere = new Map();
  }

  /** I segmenti di una tessera (metri suoi), messi nei metri della scena. */
  aggiungi(chiave, segmenti, ox, oy, k) {
    const n = segmenti.length / 8;
    const s = new Float32Array(segmenti.length);
    let minx = Infinity;
    let miny = Infinity;
    let maxx = -Infinity;
    let maxy = -Infinity;
    const griglia = new Map();
    const c = this.cella;
    for (let i = 0; i < n; i++) {
      const o = 8 * i;
      const x0 = ox + segmenti[o] * k;
      const y0 = oy + segmenti[o + 1] * k;
      const x1 = ox + segmenti[o + 3] * k;
      const y1 = oy + segmenti[o + 4] * k;
      s[o] = x0;
      s[o + 1] = y0;
      s[o + 2] = segmenti[o + 2];
      s[o + 3] = x1;
      s[o + 4] = y1;
      s[o + 5] = segmenti[o + 5];
      s[o + 6] = segmenti[o + 6];
      s[o + 7] = segmenti[o + 7];
      minx = Math.min(minx, x0, x1);
      maxx = Math.max(maxx, x0, x1);
      miny = Math.min(miny, y0, y1);
      maxy = Math.max(maxy, y0, y1);
      for (let cx = Math.floor(Math.min(x0, x1) / c); cx <= Math.floor(Math.max(x0, x1) / c); cx++) {
        for (let cy = Math.floor(Math.min(y0, y1) / c); cy <= Math.floor(Math.max(y0, y1) / c); cy++) {
          const key = cx * 100003 + cy;
          let l = griglia.get(key);
          if (!l) griglia.set(key, (l = []));
          l.push(i);
        }
      }
    }
    this.tessere.set(chiave, { s, griglia, minx, miny, maxx, maxy });
  }

  togli(chiave) {
    this.tessere.delete(chiave);
  }

  get vuoto() {
    return this.tessere.size === 0;
  }

  /** C'è una tessera costruita sotto il punto? */
  copre(x, y) {
    for (const t of this.tessere.values()) if (x >= t.minx && x <= t.maxx && y >= t.miny && y <= t.maxy) return true;
    return false;
  }

  /**
   * Le quote delle strade vicine al punto che vanno come [dx, dy] (senza
   * verso: anche contromano); ognuna con la sua distanza dal punto.
   */
  candidati(x, y, dx, dy, raggio = 9) {
    const out = [];
    const c = this.cella;
    const visti = new Set();
    for (const [chiave, t] of this.tessere) {
      if (x < t.minx - raggio || x > t.maxx + raggio || y < t.miny - raggio || y > t.maxy + raggio) continue;
      for (let cx = Math.floor((x - raggio) / c); cx <= Math.floor((x + raggio) / c); cx++) {
        for (let cy = Math.floor((y - raggio) / c); cy <= Math.floor((y + raggio) / c); cy++) {
          for (const i of t.griglia.get(cx * 100003 + cy) || []) {
            const id = chiave + i;
            if (visti.has(id)) continue;
            visti.add(id);
            const o = 8 * i;
            const s = t.s;
            const sx = s[o + 3] - s[o];
            const sy = s[o + 4] - s[o + 1];
            const l2 = sx * sx + sy * sy;
            if (l2 < 1e-6) continue;
            let u = ((x - s[o]) * sx + (y - s[o + 1]) * sy) / l2;
            u = Math.max(0, Math.min(1, u));
            const px = s[o] + sx * u;
            const py = s[o + 1] + sy * u;
            const d = Math.hypot(x - px, y - py);
            const w = s[o + 6];
            if (d > w / 2 + 4 || d > raggio) continue;
            const coseno = dx || dy ? Math.abs((sx * dx + sy * dy) / Math.sqrt(l2) / (Math.hypot(dx, dy) || 1)) : 1;
            const h = s[o + 2] + (s[o + 5] - s[o + 2]) * u;
            // Una strada in quota vale solo se va quasi come il percorso
            // (entro 23°): «la linea non può salire sul ponte se la strada è
            // sotto». Un cavalcavia che taglia di sbieco passava il filtro
            // dei 45°, e dove il percorso cambia carreggiata (sotto, nessuna
            // strada abbastanza vicina) la linea saliva sull'impalcato.
            if (coseno < (h > 2.5 ? 0.92 : 0.7)) continue;
            out.push({ h, d, px, py, codice: s[o + 7], galleria: (s[o + 7] & 64) !== 0 });
          }
        }
      }
    }
    return out;
  }
}

/** Quante strade candidate si tengono per punto, le più vicine. */
const CANDIDATI_MAX = 6;

/** Quanto costa, per metro, saltare di lato da una strada all'altra. */
const SALTO_DI_LATO = 0.8;

/**
 * Le quote di una linea campionata: [punti] `[x, y]` ogni pochi metri. Per
 * ogni punto le strade candidate, ognuna per sé (stessa quota e stesso posto
 * entro un metro e mezzo: la stessa strada); poi la sequenza che costa meno:
 * lontananza dalla strada, salti di quota e salti di lato. Dove non c'è
 * nessuna strada costruita la quota resta `NaN` (si decide dopo).
 *
 * Il salto di lato è la continuità: «agli svincoli, se non devo uscire, la
 * linea del percorso non è diritta: va allo svincolo e poi ritorna al
 * centro». Prima ogni punto prendeva la strada più vicina alla sua quota, e
 * dove la rampa si stacca dalla carreggiata (o sull'altro lato di una
 * rotonda) un metro più vicino bastava a spostarlo di là; la levigatura
 * faceva il resto, una curva verso lo svincolo e ritorno. Adesso cambiare
 * strada costa quanto il salto: si resta su quella su cui si era.
 */
export function quote(punti, indice) {
  const n = punti.length;
  const cand = new Array(n);
  for (let i = 0; i < n; i++) {
    const a = punti[Math.max(0, i - 1)];
    const b = punti[Math.min(n - 1, i + 1)];
    const lista = indice.candidati(punti[i][0], punti[i][1], b[0] - a[0], b[1] - a[1]);
    const strade = [];
    for (const c of lista) {
      // Le strade piccole contano un po' meno, se ci sono anche quelle grandi.
      const piccola = (c.codice & 15) >= 6 ? 0.6 : 0;
      const costo = c.d * 0.15 + piccola;
      const g = strade.find((q) => Math.abs(q.h - c.h) < 0.8 && Math.hypot(q.px - c.px, q.py - c.py) < 1.5);
      if (g) {
        if (costo < g.costo) Object.assign(g, { h: c.h, costo, galleria: c.galleria, px: c.px, py: c.py });
      } else strade.push({ h: c.h, costo, galleria: c.galleria, px: c.px, py: c.py });
    }
    strade.sort((x, y) => x.costo - y.costo);
    cand[i] = strade.slice(0, CANDIDATI_MAX);
  }
  const h = new Float64Array(n).fill(NaN);
  // Quali punti passano in galleria (sotto qualcosa): il nastro lì è «dentro».
  h.galleria = new Uint8Array(n);
  // Di quanto spostare ogni punto per stare sul mezzo della strada scelta.
  h.dx = new Float64Array(n).fill(NaN);
  h.dy = new Float64Array(n).fill(NaN);
  // Viterbi su ogni tratto di punti che hanno candidati.
  let i = 0;
  while (i < n) {
    if (!cand[i].length) {
      i++;
      continue;
    }
    let j = i;
    while (j < n && cand[j].length) j++;
    const costi = [cand[i].map((c) => c.costo)];
    const da = [cand[i].map(() => -1)];
    for (let k = i + 1; k < j; k++) {
      const prev = cand[k - 1];
      const cc = [];
      const dd = [];
      for (const c of cand[k]) {
        let meglio = Infinity;
        let quale = 0;
        for (let q = 0; q < prev.length; q++) {
          // Un salto di quota fra due punti vicini (4 m) costa molto più
          // della salita di una rampa vera, che sale poco a ogni passo.
          const salto = Math.abs(c.h - prev[q].h);
          // E un salto di lato: lo spostamento verso la strada cambia piano
          // lungo la stessa strada, di colpo passando a un'altra.
          const lato = Math.hypot(
            c.px - punti[k][0] - (prev[q].px - punti[k - 1][0]),
            c.py - punti[k][1] - (prev[q].py - punti[k - 1][1]),
          );
          const v = costi[k - 1 - i][q] + salto * (salto > 1.5 ? 4 : 1) + lato * SALTO_DI_LATO;
          if (v < meglio) {
            meglio = v;
            quale = q;
          }
        }
        cc.push(meglio + c.costo);
        dd.push(quale);
      }
      costi.push(cc);
      da.push(dd);
    }
    let q = 0;
    const ultimi = costi[j - 1 - i];
    for (let k = 1; k < ultimi.length; k++) if (ultimi[k] < ultimi[q]) q = k;
    for (let k = j - 1; k >= i; k--) {
      h[k] = cand[k][q].h;
      h.galleria[k] = cand[k][q].galleria ? 1 : 0;
      if (cand[k][q].px !== undefined) {
        h.dx[k] = cand[k][q].px - punti[k][0];
        h.dy[k] = cand[k][q].py - punti[k][1];
      }
      q = da[k - i][q];
    }
    i = j;
  }
  return h;
}

/**
 * Le quote finite: i buchi corti (fino a [buco] campioni) si riempiono fra i
 * due capi, quelli lunghi tornano a terra piano; poi una levigatura.
 */
export function riempiQuote(h, buco = 50) {
  const n = h.length;
  const out = Float64Array.from(h);
  let i = 0;
  while (i < n) {
    if (!Number.isNaN(out[i])) {
      i++;
      continue;
    }
    let j = i;
    while (j < n && Number.isNaN(out[j])) j++;
    const a = i > 0 ? out[i - 1] : NaN;
    const b = j < n ? out[j] : NaN;
    for (let k = i; k < j; k++) {
      if (!Number.isNaN(a) && !Number.isNaN(b) && j - i <= buco) out[k] = a + ((b - a) * (k - i + 1)) / (j - i + 1);
      else {
        // Lontano dalle strade conosciute: a terra, scendendo dolcemente.
        const da = Number.isNaN(a) ? 0 : a * Math.max(0, 1 - (k - i + 1) / 20);
        const db = Number.isNaN(b) ? 0 : b * Math.max(0, 1 - (j - k) / 20);
        out[k] = Math.max(da, db);
      }
    }
    i = j;
  }
  for (let it = 0; it < 2; it++) {
    const c = Float64Array.from(out);
    for (let k = 1; k < n - 1; k++) out[k] = (c[k - 1] + 2 * c[k] + c[k + 1]) / 4;
  }
  return out;
}

/** Una linea in metri con le distanze cumulate. */
export class Linea {
  /**
   * [xy]: `[x, y, …]` in metri. [metri]: i metri di ogni punto dalla
   * partenza, se li sa chi manda il percorso (l'app li conta sulla Terra,
   * non in pianta); altrimenti si contano qui.
   */
  constructor(xy, metri = null) {
    this.x = new Float64Array(xy.length / 2);
    this.y = new Float64Array(xy.length / 2);
    this.s = new Float64Array(xy.length / 2);
    for (let i = 0; i < this.x.length; i++) {
      this.x[i] = xy[2 * i];
      this.y[i] = xy[2 * i + 1];
      if (metri) this.s[i] = Math.max(i ? this.s[i - 1] : 0, metri[i]);
      else if (i) this.s[i] = this.s[i - 1] + Math.hypot(this.x[i] - this.x[i - 1], this.y[i] - this.y[i - 1]);
    }
  }
  get lunghezza() {
    return this.s.length ? this.s[this.s.length - 1] : 0;
  }
  /** Il punto a [s] metri: `[x, y]` e l'indice del segmento. */
  a(s) {
    const n = this.s.length;
    if (n === 0) return [0, 0, 0];
    if (n === 1 || s <= 0) return [this.x[0], this.y[0], 1];
    if (s >= this.lunghezza) return [this.x[n - 1], this.y[n - 1], n - 1];
    let lo = 1;
    let hi = n - 1;
    while (lo < hi) {
      const m = (lo + hi) >> 1;
      if (this.s[m] < s) lo = m + 1;
      else hi = m;
    }
    const t = (s - this.s[lo - 1]) / Math.max(1e-9, this.s[lo] - this.s[lo - 1]);
    return [this.x[lo - 1] + (this.x[lo] - this.x[lo - 1]) * t, this.y[lo - 1] + (this.y[lo] - this.y[lo - 1]) * t, lo];
  }
  /** La direzione (radianti, da est verso nord) attorno a [s]. */
  direzione(s, campo = 14) {
    const a = this.a(s - campo);
    const b = this.a(s + campo);
    return Math.atan2(b[1] - a[1], b[0] - a[0]);
  }
  /** Il punto della linea più vicino a [x, y]: i suoi metri e la distanza. */
  proietta(x, y, da = 0, a = Infinity) {
    let meglio = { s: 0, d: Infinity };
    for (let i = 1; i < this.x.length; i++) {
      if (this.s[i] < da || this.s[i - 1] > a) continue;
      const sx = this.x[i] - this.x[i - 1];
      const sy = this.y[i] - this.y[i - 1];
      const l2 = sx * sx + sy * sy;
      let u = l2 ? ((x - this.x[i - 1]) * sx + (y - this.y[i - 1]) * sy) / l2 : 0;
      u = Math.max(0, Math.min(1, u));
      const d = Math.hypot(x - this.x[i - 1] - sx * u, y - this.y[i - 1] - sy * u);
      if (d < meglio.d) meglio = { s: this.s[i - 1] + (this.s[i] - this.s[i - 1]) * u, d };
    }
    return meglio;
  }
}

/**
 * Se una linea di [punti] `[x, y]` corre lungo [linea] fra [da] e [a]: se
 * almeno [quota] dei suoi punti (al più dodici, presi a intervalli) sta entro
 * [entro] metri. Il traffico lungo il percorso lo dice già il percorso coi
 * suoi colori: disegnato una seconda volta, con la geometria di chi lo
 * fornisce, correva accanto alla linea («la linea del traffico non segue la
 * linea del percorso ma è decentrata»).
 */
export function lungoLaLinea(linea, punti, da, a, entro = 12, quota = 0.6) {
  if (!linea || !punti.length) return false;
  const passo = Math.max(1, Math.floor(punti.length / 12));
  let vicini = 0;
  let visti = 0;
  for (let k = 0; k < punti.length; k += passo) {
    visti++;
    if (linea.proietta(punti[k][0], punti[k][1], da, a).d < entro) vicini++;
  }
  return vicini >= visti * quota;
}

/** Il profilo delle quote di un tratto della linea: un campione ogni [passo] metri. */
export class Profilo {
  constructor(s0, passo, h, galleria = null, dx = null, dy = null) {
    this.s0 = s0;
    this.passo = passo;
    this.h = h;
    this.galleria = galleria;
    this.dx = dx;
    this.dy = dy;
  }

  /** Di quanto spostare il punto a [s] metri per stare sulla strada (vedi [spostamenti]). */
  sposta(s) {
    if (!this.dx) return [0, 0];
    const n = this.dx.length;
    const f = (s - this.s0) / this.passo;
    if (!(f >= 0) || f > n - 1) return [0, 0];
    const i = Math.min(n - 2, Math.floor(f));
    const t = f - i;
    return [this.dx[i] + (this.dx[i + 1] - this.dx[i]) * t, this.dy[i] + (this.dy[i + 1] - this.dy[i]) * t];
  }
  /** I tratti in galleria, in metri: `[da, a]`. */
  get gallerie() {
    const out = [];
    const g = this.galleria;
    if (!g) return out;
    let i = 0;
    while (i < g.length) {
      if (!g[i]) {
        i++;
        continue;
      }
      let j = i;
      while (j < g.length && g[j]) j++;
      out.push([this.s0 + Math.max(0, i - 0.5) * this.passo, this.s0 + Math.min(g.length - 1, j - 0.5) * this.passo]);
      i = j;
    }
    return out;
  }
  get s1() {
    return this.s0 + (this.h.length - 1) * this.passo;
  }
  quota(s) {
    const n = this.h.length;
    if (!n) return 0;
    const f = (s - this.s0) / this.passo;
    if (f <= 0) return this.h[0];
    if (f >= n - 1) return this.h[n - 1];
    const i = Math.floor(f);
    return this.h[i] + (this.h[i + 1] - this.h[i]) * (f - i);
  }
}

/** Il profilo di [linea] fra [s0] e [s1], con le strade di [indice]. */
export function profiloDi(linea, s0, s1, indice, passo = 4) {
  const n = Math.max(2, Math.ceil((s1 - s0) / passo) + 1);
  const punti = [];
  for (let k = 0; k < n; k++) {
    const p = linea.a(s0 + k * passo);
    punti.push([p[0], p[1]]);
  }
  const grezze = quote(punti, indice);
  const [dx, dy] = spostamenti(grezze.dx, grezze.dy);
  return new Profilo(s0, passo, riempiQuote(grezze), grezze.galleria, dx, dy);
}

/** Più di così non si sposta: oltre, la strada giusta è un'altra. La
 * geometria del percorso (Valhalla) è quella delle stesse strade della mappa:
 * le differenze sono di un paio di metri, e sei bastavano a finire sulla
 * strada accanto. */
export const SPOSTAMENTO_MAX_M = 4.5;

/**
 * Lo spostamento di ogni punto sul mezzo della strada sotto, morbido.
 *
 * «In alcuni punti la linea del percorso non è sulla strada»: la geometria
 * del percorso arriva dal calcolatore dei percorsi, e in qualche tratto sta
 * qualche metro di lato rispetto alle strade della mappa. Le quote trovano
 * già la strada su cui si è ([quote]); qui la linea ci si appoggia sopra.
 * Dove non c'è una strada lo spostamento è zero; si leviga su una trentina
 * di metri, così agli incroci e ai cambi di strada non fa scalini.
 */
export function spostamenti(dxGrezzi, dyGrezzi) {
  const n = dxGrezzi.length;
  const dx = new Float64Array(n);
  const dy = new Float64Array(n);
  for (let k = 0; k < n; k++) {
    let x = dxGrezzi[k];
    let y = dyGrezzi[k];
    if (Number.isNaN(x) || Number.isNaN(y)) continue;
    const l = Math.hypot(x, y);
    if (l > SPOSTAMENTO_MAX_M) {
      x = 0;
      y = 0;
    }
    dx[k] = x;
    dy[k] = y;
  }
  const r = 4;
  const lisci = (a) => {
    const out = new Float64Array(n);
    for (let k = 0; k < n; k++) {
      let somma = 0;
      let peso = 0;
      for (let j = Math.max(0, k - r); j <= Math.min(n - 1, k + r); j++) {
        const w = r + 1 - Math.abs(j - k);
        somma += a[j] * w;
        peso += w;
      }
      out[k] = somma / peso;
    }
    return out;
  };
  return [lisci(dx), lisci(dy)];
}

/**
 * Il nastro del percorso fra [s0] e [s1]: due vertici ogni [passo] metri
 * (più uno a ogni cambio di coda), larghi [largo], sollevati di [sopra]. Le
 * uv: u attraverso (0..1), v i metri; e per ogni vertice il livello della
 * coda (0 niente, 1 rallenta … 4 chiusa).
 */
export function nastro(linea, profilo, s0, s1, largo, sopra, { passo = 2, code = [], gallerie = profilo?.gallerie ?? [] } = {}) {
  const tagli = new Set();
  for (let s = s0; s < s1; s += passo) tagli.add(+s.toFixed(3));
  tagli.add(s1);
  for (const [da, a] of [...code, ...gallerie]) {
    for (const v of [da, a]) if (v > s0 && v < s1) tagli.add(v);
  }
  const ss = [...tagli].filter((s) => s >= s0 && s <= s1).sort((a, b) => a - b);
  // Il livello della coda, più 10 nei tratti in galleria (lo shader li fa «dentro»).
  const livelloA = (s) => {
    let l = 0;
    for (const [da, a, lv] of code) if (s >= da && s < a) l = lv;
    for (const [da, a] of gallerie) if (s >= da && s < a) l += 10;
    return l;
  };
  // Le stazioni: a ogni cambio di coda due (stesso punto, livello di prima e
  // di dopo), così il colore cambia netto e non sfuma lungo il nastro.
  const stazioni = [];
  for (let k = 0; k < ss.length; k++) {
    const s = ss[k];
    const prima = k ? livelloA((ss[k - 1] + s) / 2) : null;
    const dopo = k + 1 < ss.length ? livelloA((s + ss[k + 1]) / 2) : prima;
    if (prima !== null && prima !== dopo) stazioni.push([s, prima, false]);
    stazioni.push([s, dopo ?? 0, prima !== null && prima !== dopo]);
  }
  const p = [];
  const uv = [];
  const liv = [];
  const ind = [];
  for (let k = 0; k < stazioni.length; k++) {
    const [s, l, staccata] = stazioni[k];
    const [x0, y0] = linea.a(s);
    const [sx, sy] = profilo.sposta ? profilo.sposta(s) : [0, 0];
    const x = x0 + sx;
    const y = y0 + sy;
    const dir = linea.direzione(s, 3);
    const nx = -Math.sin(dir);
    const ny = Math.cos(dir);
    const z = profilo.quota(s) + sopra;
    p.push(x + (nx * largo) / 2, y + (ny * largo) / 2, z, x - (nx * largo) / 2, y - (ny * largo) / 2, z);
    uv.push(0, s, 1, s);
    liv.push(l, l);
    if (k && !staccata) {
      const b = 2 * (k - 1);
      ind.push(b, b + 1, b + 3, b, b + 3, b + 2);
    }
  }
  return {
    posizioni: new Float32Array(p),
    uv: new Float32Array(uv),
    livelli: new Float32Array(liv),
    indici: p.length / 3 > 65535 ? new Uint32Array(ind) : new Uint16Array(ind),
  };
}
