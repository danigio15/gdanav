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
   * Le quote delle strade vicine al punto che vanno come [dx, dy] (anche
   * contromano, ma non sui sensi unici); ognuna con la sua distanza dal punto.
   */
  candidati(x, y, dx, dy, raggio = 9, margine = 4) {
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
            if (d > w / 2 + margine || d > raggio) continue;
            const cod = s[o + 7];
            const prodotto = dx || dy ? (sx * dx + sy * dy) / Math.sqrt(l2) / (Math.hypot(dx, dy) || 1) : 1;
            // Contromano su un senso unico: la carreggiata opposta di una
            // strada a due carreggiate. «La linea è sull'altra carreggiata»
            // (SS7bis): TomTom passa nel mezzo e l'altra era più vicina.
            if (cod & 384 && (cod & 256 ? -prodotto : prodotto) < -0.2) continue;
            const coseno = Math.abs(prodotto);
            const h = s[o + 2] + (s[o + 5] - s[o + 2]) * u;
            // Una strada in quota vale solo se va quasi come il percorso
            // (entro 23°): «la linea non può salire sul ponte se la strada è
            // sotto». Un cavalcavia che taglia di sbieco passava il filtro
            // dei 45°, e dove il percorso cambia carreggiata (sotto, nessuna
            // strada abbastanza vicina) la linea saliva sull'impalcato.
            if (coseno < (h > 2.5 ? 0.92 : 0.7)) continue;
            out.push({ h, d, px, py, codice: s[o + 7], galleria: (cod & 64) !== 0 });
          }
        }
      }
    }
    return out;
  }
}

/** Quante strade candidate si tengono per punto, le più vicine. */
const CANDIDATI_MAX = 9;
/** E quante per piano (quote entro un metro e mezzo). */
const CANDIDATI_PER_PIANO = 3;

/**
 * Le candidate da tenere, le meno care ma di ogni piano: prendendo solo le
 * sei più vicine, sotto un viadotto con tante stradine a terra la
 * carreggiata vera (più lontana: il percorso di TomTom sta di lato) restava
 * fuori, e la linea era costretta a scendere sotto il ponte.
 */
function scegliCandidate(strade) {
  strade.sort((x, y) => x.costo - y.costo);
  const out = [];
  for (const c of strade) {
    if (out.length >= CANDIDATI_MAX) break;
    let delPiano = 0;
    for (const q of out) if (Math.abs(q.h - c.h) < 1.5) delPiano++;
    if (delPiano < CANDIDATI_PER_PIANO) out.push(c);
  }
  return out;
}

/** Quanto costa, per metro, saltare di lato da una strada all'altra. */
const SALTO_DI_LATO = 0.8;

/**
 * Quanto costa un salto di quota fra due punti vicini (4 m): poco finché è
 * la salita di una rampa, tanto quando è un altro piano. Era quattro al
 * metro; ma cercando le strade fino a tredici metri (il percorso di TomTom
 * sta di lato) sotto un viadotto la stradina a terra è spesso più vicina
 * della carreggiata vera, e dopo qualche centinaio di metri scendere costava
 * meno che restare su: linea e freccia finivano sotto il ponte.
 */
const SALTO_DI_QUOTA = 12;
const costoDelSalto = (d) => d * (d > 1.5 ? SALTO_DI_QUOTA : 1);

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
 *
 * [ancora] `{i, h}`: al punto [i] si sa già a che quota si è (l'auto, dal
 * profilo di prima): le strade a un'altra quota lì costano come un salto.
 * Chi è sul viadotto ci resta anche quando il tratto si rifà.
 */
export function quote(punti, indice, ancora = null) {
  const n = punti.length;
  const cand = new Array(n);
  for (let i = 0; i < n; i++) {
    const a = punti[Math.max(0, i - 1)];
    const b = punti[Math.min(n - 1, i + 1)];
    const lista = indice.candidati(punti[i][0], punti[i][1], b[0] - a[0], b[1] - a[1], AGGANCIO_RAGGIO_M, AGGANCIO_RAGGIO_M);
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
    if (ancora && ancora.i === i) for (const q of strade) q.costo += costoDelSalto(Math.abs(q.h - ancora.h));
    cand[i] = scegliCandidate(strade);
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
      // Il piano di prima continua qui? Se no (la strada finisce: il bordo
      // delle tessere costruite, un buco nei dati) il salto è obbligato e
      // costa poco; altrimenti un solo punto in fondo senza il viadotto
      // tirava giù la linea per tutto il tratto, fino a dove conveniva.
      const continua = prev.map((p) => cand[k].some((x) => Math.abs(x.h - p.h) < 1.5));
      for (const c of cand[k]) {
        let meglio = Infinity;
        let quale = 0;
        for (let q = 0; q < prev.length; q++) {
          // Un salto di quota fra due punti vicini (4 m) costa molto più
          // della salita di una rampa vera, che sale poco a ogni passo.
          const salto = continua[q] ? costoDelSalto(Math.abs(c.h - prev[q].h)) : Math.abs(c.h - prev[q].h);
          // E un salto di lato: lo spostamento verso la strada cambia piano
          // lungo la stessa strada, di colpo passando a un'altra.
          const lato = Math.hypot(
            c.px - punti[k][0] - (prev[q].px - punti[k - 1][0]),
            c.py - punti[k][1] - (prev[q].py - punti[k - 1][1]),
          );
          const v = costi[k - 1 - i][q] + salto + lato * SALTO_DI_LATO;
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
  /** La quota a [s] se lì sotto si è trovata una strada, altrimenti `null`. */
  quotaVera(s) {
    const i = Math.round((s - this.s0) / this.passo);
    return this.trovata && i >= 0 && i < this.trovata.length && this.trovata[i] ? this.quota(s) : null;
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

/**
 * Il profilo di [linea] fra [s0] e [s1], con le strade di [indice].
 * [ancora] `{s, h}`: la quota che si sa già a [s] metri (vedi [quote]).
 */
export function profiloDi(linea, s0, s1, indice, passo = 4, ancora = null) {
  const n = Math.max(2, Math.ceil((s1 - s0) / passo) + 1);
  const punti = [];
  for (let k = 0; k < n; k++) {
    const p = linea.a(s0 + k * passo);
    punti.push([p[0], p[1]]);
  }
  const ia = ancora ? Math.round((ancora.s - s0) / passo) : -1;
  const grezze = quote(punti, indice, ia >= 0 && ia < n ? { i: ia, h: ancora.h } : null);
  const [dx, dy] = spostamenti(grezze.dx, grezze.dy, punti, passo, grezze.galleria);
  const profilo = new Profilo(s0, passo, riempiQuote(grezze), grezze.galleria, dx, dy);
  profilo.trovata = Uint8Array.from(grezze, (v) => (Number.isNaN(v) ? 0 : 1));
  return profilo;
}

/** Più di così non si sposta: oltre, la strada giusta è un'altra.
 *
 * Il percorso arriva da TomTom (`ClienteTomTom`, per il traffico nei tempi),
 * e la sua geometria è quella delle strade di TomTom, non di OpenStreetMap che
 * la mappa disegna: in tante zone le due stanno a cinque, dieci metri l'una
 * dall'altra («ancora è fuori strada la linea», via Po: otto metri, mentre la
 * strada già fatta — il GPS — è sulla strada). Con sei metri non si
 * agganciava; per una notte, pensandolo di Valhalla, era sceso a due e mezzo.
 * Ora tredici: a non saltare sulla strada accanto ci pensa
 * la continuità di [quote], che sceglie la strada su cui si resta lungo tutto
 * il tratto, non la più vicina punto per punto. */
export const SPOSTAMENTO_MAX_M = 13;
/** Fin qui, attorno all'andamento, uno scarto di lato è ancora la stessa strada. */
const SCARTO_DELLA_STESSA_STRADA_M = 1.5;
/** Fin dove si cercano le strade intorno a un punto del percorso. */
const AGGANCIO_RAGGIO_M = SPOSTAMENTO_MAX_M;

/**
 * Lo spostamento di ogni punto sul mezzo della strada sotto, morbido.
 *
 * «In alcuni punti la linea del percorso non è sulla strada»: la geometria
 * del percorso arriva dal calcolatore dei percorsi, e in qualche tratto sta
 * qualche metro di lato rispetto alle strade della mappa. Le quote trovano
 * già la strada su cui si è ([quote]); qui la linea ci si appoggia sopra.
 *
 * «La linea sembra che vada a zig zag, non è diritta sul percorso.» Lo
 * spostamento si spegneva fra dieci e tredici metri, e lì un metro in più di
 * distanza ne toglieva tre di spostamento: dove il percorso sta a undici,
 * dodici metri dalla strada (le carreggiate larghe della tangenziale) la
 * linea ballava; e nei parcheggi saltava da una corsia all'altra. Adesso
 * conta solo quanto la strada sta **di lato** rispetto al percorso, un
 * numero col segno (a sinistra o a destra), e quel numero si leviga lungo
 * la linea: i buchi corti si riempiono, una mediana toglie i salti di un
 * punto o due, una media su una cinquantina di metri fa il resto. La linea
 * si sposta tutta insieme, come il percorso vero, e non fa più scalini.
 *
 * [punti] `[x, y]` della linea, uno per spostamento; [passo] i metri fra due.
 */
export function spostamenti(dxGrezzi, dyGrezzi, punti, passo = 4, galleria = null) {
  const n = dxGrezzi.length;
  const dx = new Float64Array(n);
  const dy = new Float64Array(n);
  if (!n) return [dx, dy];
  // La normale della linea in ogni punto (a sinistra del verso di marcia).
  const nx = new Float64Array(n);
  const ny = new Float64Array(n);
  for (let k = 0; k < n; k++) {
    const a = punti[Math.max(0, k - 1)];
    const b = punti[Math.min(n - 1, k + 1)];
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
    nx[k] = -(b[1] - a[1]) / l;
    ny[k] = (b[0] - a[0]) / l;
  }
  // Quanto sta di lato la strada, col segno; NaN dove non c'è.
  const lato = new Float64Array(n).fill(NaN);
  for (let k = 0; k < n; k++) {
    const x = dxGrezzi[k];
    const y = dyGrezzi[k];
    if (Number.isNaN(x) || Number.isNaN(y)) continue;
    lato[k] = x * nx[k] + y * ny[k];
  }
  const visto = Float64Array.from(lato);
  // I buchi corti (una trentina di metri) fra due tratti con la strada si
  // riempiono; dove la strada non c'è per davvero, zero.
  const buco = Math.max(1, Math.round(32 / passo));
  let k = 0;
  while (k < n) {
    if (!Number.isNaN(lato[k])) {
      k++;
      continue;
    }
    let j = k;
    while (j < n && Number.isNaN(lato[j])) j++;
    const prima = k > 0 ? lato[k - 1] : NaN;
    const dopo = j < n ? lato[j] : NaN;
    const ponte = !Number.isNaN(prima) && !Number.isNaN(dopo) && j - k <= buco;
    for (let q = k; q < j; q++) lato[q] = ponte ? prima + ((dopo - prima) * (q - k + 1)) / (j - k + 1) : 0;
    k = j;
  }
  // La mediana toglie i salti corti (un punto che si aggancia altrove).
  const m = Math.max(1, Math.round(18 / passo));
  const mediato = new Float64Array(n);
  const finestra = [];
  for (let q = 0; q < n; q++) {
    finestra.length = 0;
    for (let j = Math.max(0, q - m); j <= Math.min(n - 1, q + m); j++) finestra.push(lato[j]);
    finestra.sort((a, b) => a - b);
    mediato[q] = finestra[finestra.length >> 1];
  }
  // E la media, a triangolo, fa il raccordo: è l'andamento.
  const r = Math.max(1, Math.round(24 / passo));
  const andamento = new Float64Array(n);
  for (let q = 0; q < n; q++) {
    let somma = 0;
    let peso = 0;
    for (let j = Math.max(0, q - r); j <= Math.min(n - 1, q + r); j++) {
      const w = r + 1 - Math.abs(j - q);
      somma += mediato[j] * w;
      peso += w;
    }
    andamento[q] = somma / peso;
  }
  /* Attorno all'andamento, gli scarti piccoli sono la stessa strada vista
   * dal percorso, che la taglia a corde dove lei curva: quelli si seguono, e
   * la linea prende la curva della strada. Quelli grandi sono un'altra
   * strada (la corsia accanto, un punto agganciato altrove): si lasciano. */
  const fine = new Float64Array(n);
  for (let q = 0; q < n; q++) {
    // Solo dove tutti i punti intorno vedono la stessa strada: se lì attorno
    // gli scarti ballano (due corsie di un parcheggio, un punto altrove) o
    // la strada manca, resta l'andamento e basta.
    let minimo = Infinity;
    let massimo = -Infinity;
    for (let j = Math.max(0, q - m); j <= Math.min(n - 1, q + m); j++) {
      const v = visto[j];
      if (Number.isNaN(v)) {
        massimo = Infinity;
        break;
      }
      if (v < minimo) minimo = v;
      if (v > massimo) massimo = v;
    }
    const scarto = visto[q] - andamento[q];
    // In galleria la strada non si vede: seguirne le pieghe (le strade
    // interrate sono disegnate a mano, a spigoli) fa solo scalini sulla linea.
    const stessa = !galleria?.[q] && massimo - minimo < 2 * SCARTO_DELLA_STESSA_STRADA_M && Math.abs(scarto) < SCARTO_DELLA_STESSA_STRADA_M;
    fine[q] = andamento[q] + (stessa ? scarto : 0);
  }
  for (let q = 0; q < n; q++) {
    const a = fine[Math.max(0, q - 1)];
    const b = fine[Math.min(n - 1, q + 1)];
    const liscio = (a + 2 * fine[q] + b) / 4;
    dx[q] = liscio * nx[q];
    dy[q] = liscio * ny[q];
  }
  alleSvolte(dx, dy, visto, punti, passo);
  senzaPieghe(dx, dy, punti);
  return [dx, dy];
}

/** Fin dove (punti per parte) si cerca il raccordo attorno a una piega. */
const PIEGA_MAX_PUNTI = 6;

/**
 * La linea spostata non torna mai indietro.
 *
 * «Alla rotonda la freccia è errata»: arrivando a una rotonda il percorso di
 * TomTom stava sette, dieci metri dentro la curva (una carreggiata sola fino
 * all'anello, dove OpenStreetMap ne ha due), e girava di colpo verso
 * l'uscita. Spostando ogni punto di lato, di dieci metri, all'interno di uno
 * spigolo stretto la linea spostata faceva un cappio: andava avanti, poi
 * indietro e di traverso per qualche metro, poi di nuovo avanti — una V sul
 * nastro, e la punta della freccia lì in mezzo che guardava all'indietro.
 *
 * Dove un tratto della linea spostata va contro il verso del percorso, si
 * cerca il più corto raccordo attorno che vada avanti dappertutto e i punti
 * in mezzo si mettono in fila su quello: il cappio sparisce, lo spigolo resta.
 */
function senzaPieghe(dx, dy, punti) {
  const n = dx.length;
  if (n < 3) return;
  const qx = (k) => punti[k][0] + dx[k];
  const qy = (k) => punti[k][1] + dy[k];
  // Il verso del percorso fra k e k+1, e se la linea spostata lo segue.
  const tx = (k) => punti[Math.min(n - 1, k + 1)][0] - punti[Math.max(0, k)][0];
  const ty = (k) => punti[Math.min(n - 1, k + 1)][1] - punti[Math.max(0, k)][1];
  const indietro = (k) => k >= 0 && k < n - 1 && (qx(k + 1) - qx(k)) * tx(k) + (qy(k + 1) - qy(k)) * ty(k) < 0;
  for (let k = 0; k < n - 1; k++) {
    if (!indietro(k)) continue;
    let fine = k;
    while (fine + 1 < n - 1 && indietro(fine + 1)) fine++;
    let fatto = false;
    // Il raccordo da i a j: la corda va avanti rispetto a tutto il percorso fra i due.
    for (let g = 0; g <= 2 * PIEGA_MAX_PUNTI && !fatto; g++) {
      for (let a = Math.max(0, g - PIEGA_MAX_PUNTI); a <= Math.min(g, PIEGA_MAX_PUNTI) && !fatto; a++) {
        const i = k - a;
        const j = fine + 1 + (g - a);
        if (i < 0 || j > n - 1 || indietro(i - 1) || indietro(j)) continue;
        const cx = qx(j) - qx(i);
        const cy = qy(j) - qy(i);
        let avanti = true;
        for (let q = i; q < j && avanti; q++) if (cx * tx(q) + cy * ty(q) <= 0) avanti = false;
        if (!avanti) continue;
        const [x0, y0] = [qx(i), qy(i)];
        for (let q = i + 1; q < j; q++) {
          const t = (q - i) / (j - i);
          dx[q] = x0 + cx * t - punti[q][0];
          dy[q] = y0 + cy * t - punti[q][1];
        }
        fatto = true;
        k = j - 1;
      }
    }
    if (!fatto) k = fine;
  }
}

/**
 * Il verso della linea disegnata (il percorso spostato sulla strada) a [s]
 * metri, guardando gli ultimi [campo] metri: quello della punta della
 * freccia. Il verso del percorso di TomTom, sotto, può essere un altro
 * proprio dove la linea si sposta di più (agli spigoli, alle rotonde): la
 * punta guardava di traverso o all'indietro rispetto al nastro che chiude.
 */
export function direzioneDisegnata(linea, profilo, s, campo = 4) {
  const dove = (v) => {
    const [x, y] = linea.a(v);
    const [sx, sy] = profilo?.sposta ? profilo.sposta(v) : [0, 0];
    return [x + sx, y + sy];
  };
  const [bx, by] = dove(s);
  for (const c of [campo, 2 * campo, 4 * campo]) {
    const [ax, ay] = dove(Math.max(0, s - c));
    if (Math.hypot(bx - ax, by - ay) > 0.5) return Math.atan2(by - ay, bx - ax);
  }
  return linea.direzione(s, 3);
}

/** Da quanti gradi in su, in una ventina di metri, è una svolta. */
const SVOLTA_GRADI = 35;
/** E fin dove, prima e dopo, i due rami devono andare dritti perché lo sia. */
const RAMO_DRITTO_GRADI = 12;

/**
 * Alle svolte lo spostamento è un vettore intero, non solo di lato.
 *
 * «I punti per strada non sono corretti, soprattutto gli svincoli»: il
 * percorso del calcolatore sta di lato rispetto alle strade della mappa, e
 * di lato lo si rimette ([spostamenti]). Ma a una svolta «di lato» cambia
 * verso: quello che prima era lungo la strada dopo è di traverso. Spostando
 * solo di lato, lo spigolo del percorso restava dov'era: la linea superava
 * l'incrocio di qualche metro e poi girava (o girava prima), e intorno la
 * media mescolava i due lati e la portava fuori da tutte e due le strade.
 *
 * Qui, a ogni svolta, si prende quanto sta di lato la strada prima e quanto
 * dopo, e si cerca l'unico spostamento che va bene per tutte e due: quello
 * porta lo spigolo del percorso sull'incrocio vero. Attorno alla svolta
 * tutta la linea si sposta di quel vettore (lungo una strada dritta uno
 * spostamento in avanti non cambia niente), e più in là torna a quello di
 * lato, piano.
 */
function alleSvolte(dx, dy, visto, punti, passo) {
  const n = dx.length;
  const braccio = Math.max(2, Math.round(12 / passo));
  if (n < 4 * braccio + 3) return;
  // Di quanto gira la linea attorno a ogni punto, fra dodici metri prima e dodici dopo.
  const giro = new Float64Array(n);
  const verso = (a, b) => {
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
    return [(b[0] - a[0]) / l, (b[1] - a[1]) / l];
  };
  for (let k = braccio; k < n - braccio; k++) {
    const u = verso(punti[k - braccio], punti[k]);
    const w = verso(punti[k], punti[k + braccio]);
    giro[k] = Math.abs(Math.atan2(u[0] * w[1] - u[1] * w[0], u[0] * w[0] + u[1] * w[1])) * (180 / Math.PI);
  }
  const mediana = (da, a) => {
    const v = [];
    for (let j = Math.max(0, da); j <= Math.min(n - 1, a); j++) if (!Number.isNaN(visto[j])) v.push(visto[j]);
    if (v.length < 2) return NaN;
    v.sort((x, y) => x - y);
    return v[v.length >> 1];
  };
  /** Fra i punti [da] e [a] la linea va dritta (gira meno di [RAMO_DRITTO_GRADI])? */
  const dritto = (da, a) => {
    if (a - da < 2) return false;
    const m = (da + a) >> 1;
    const u = verso(punti[da], punti[m]);
    const w = verso(punti[m], punti[a]);
    return Math.abs(Math.atan2(u[0] * w[1] - u[1] * w[0], u[0] * w[0] + u[1] * w[1])) * (180 / Math.PI) < RAMO_DRITTO_GRADI;
  };
  const pieno = Math.round(20 / passo);
  const largo = Math.round(36 / passo);
  let ultima = -Infinity;
  for (let k = braccio; k < n - braccio; k++) {
    if (giro[k] < SVOLTA_GRADI || k - ultima < largo) continue;
    // La cima del giro: lo spigolo.
    let cima = k;
    for (let j = k + 1; j <= Math.min(n - braccio - 1, k + 2 * braccio); j++) if (giro[j] > giro[cima]) cima = j;
    ultima = cima;
    k = cima;
    // I due rami, lontano dallo spigolo quanto basta perché il lato sia il loro.
    const prima = [Math.max(0, cima - 3 * braccio), Math.max(0, cima - braccio)];
    const dopo = [Math.min(n - 1, cima + braccio), Math.min(n - 1, cima + 3 * braccio)];
    const l1 = mediana(prima[0], prima[1]);
    const l2 = mediana(dopo[0], dopo[1]);
    if (Number.isNaN(l1) || Number.isNaN(l2)) continue;
    const t1 = verso(punti[prima[0]], punti[prima[1]]);
    const t2 = verso(punti[dopo[0]], punti[dopo[1]]);
    // Una svolta è uno spigolo fra due strade dritte. In una rotonda, in un
    // tornante o in un'inversione i due rami girano anche loro: lì «di lato»
    // non ha un verso solo, il conto dava spostamenti di una decina di metri
    // e la linea faceva un giro largo fuori dalla rotonda.
    if (!dritto(prima[0], prima[1]) || !dritto(dopo[0], dopo[1])) continue;
    const n1 = [-t1[1], t1[0]];
    const n2 = [-t2[1], t2[0]];
    const det = n1[0] * n2[1] - n1[1] * n2[0];
    // Due rami quasi paralleli (una curva larga, un'inversione): niente da risolvere.
    if (Math.abs(det) < 0.5) continue;
    const vx = (l1 * n2[1] - l2 * n1[1]) / det;
    const vy = (n1[0] * l2 - n2[0] * l1) / det;
    if (Math.hypot(vx, vy) > SPOSTAMENTO_MAX_M) continue;
    for (let j = Math.max(0, cima - largo); j <= Math.min(n - 1, cima + largo); j++) {
      const d = Math.abs(j - cima);
      const peso = d <= pieno ? 1 : 1 - (d - pieno) / (largo - pieno);
      dx[j] += (vx - dx[j]) * peso;
      dy[j] += (vy - dy[j]) * peso;
    }
  }
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
    // Di traverso alla linea disegnata, non a quella di TomTom sotto: allo
    // spigolo dell'ingresso di una rotonda le due andavano diverse e il
    // nastro lì si strozzava.
    const dir = profilo.sposta ? direzioneDisegnata(linea, profilo, s + 1.5, 3) : linea.direzione(s, 3);
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

/**
 * Un nastro a pezzi corti, ognuno con le coordinate contate da un punto suo
 * ([ancora], in metri della scena): i dati di [nastro] (o di più nastri
 * uniti), tagliati dove ci si allontana più di [lato] metri dall'àncora.
 *
 * «I punti per strada non sono corretti, soprattutto gli svincoli.» I vertici
 * del nastro erano contati dall'origine della scena, che può stare a decine
 * di chilometri (si rinnova ogni quaranta); la scheda grafica fa i conti con
 * sette cifre, e a quelle distanze la profondità del nastro sbagliava di più
 * dei sessanta centimetri che lo tengono sopra l'asfalto: sulle rampe e sui
 * ponti la linea usciva a pezzi, un triangolo sì e uno no, e cambiava a ogni
 * movimento della mappa. Le strade non ne soffrono: ogni tessera ha già le
 * sue coordinate contate dal suo centro. Così anche il nastro.
 */
export function pezziDelNastro(dati, lato = 800) {
  const { posizioni: P, uv, livelli, indici } = dati;
  const pezzi = [];
  const nt = Math.floor(indici.length / 3);
  let t0 = 0;
  while (t0 < nt) {
    const primo = indici[3 * t0];
    const ax = Math.round(P[3 * primo]);
    const ay = Math.round(P[3 * primo + 1]);
    let vmin = Infinity;
    let vmax = -Infinity;
    let t1 = t0;
    for (; t1 < nt; t1++) {
      let dentro = true;
      let a = Infinity;
      let b = -Infinity;
      for (let k = 0; k < 3; k++) {
        const v = indici[3 * t1 + k];
        if (Math.abs(P[3 * v] - ax) > lato || Math.abs(P[3 * v + 1] - ay) > lato) dentro = false;
        if (v < a) a = v;
        if (v > b) b = v;
      }
      // Il primo triangolo c'è comunque: un pezzo non resta mai vuoto.
      if (!dentro && t1 > t0) break;
      if (a < vmin) vmin = a;
      if (b > vmax) vmax = b;
    }
    const nv = vmax - vmin + 1;
    const posizioni = new Float32Array(nv * 3);
    for (let v = 0; v < nv; v++) {
      posizioni[3 * v] = P[3 * (vmin + v)] - ax;
      posizioni[3 * v + 1] = P[3 * (vmin + v) + 1] - ay;
      posizioni[3 * v + 2] = P[3 * (vmin + v) + 2];
    }
    const n = 3 * (t1 - t0);
    const ind = nv > 65535 ? new Uint32Array(n) : new Uint16Array(n);
    for (let k = 0; k < n; k++) ind[k] = indici[3 * t0 + k] - vmin;
    pezzi.push({ ancora: [ax, ay], posizioni, uv: uv.slice(2 * vmin, 2 * (vmax + 1)), livelli: livelli.slice(vmin, vmax + 1), indici: ind });
    t0 = t1;
  }
  return pezzi;
}

/**
 * I due sensi di marcia del traffico, ognuno nella sua metà di strada.
 *
 * «Guarda le linee del traffico»: su una strada a doppio senso TomTom manda
 * una linea per senso, sulla stessa geometria. Appoggiate tutte e due sulla
 * strada finivano una sopra l'altra — si vedeva solo l'ultima, o una treccia
 * dove gli scarti di qualche metro le facevano incrociare.
 *
 * [linee]: per ognuna i punti `[x, y]` già appoggiati sulla strada, nel verso
 * di marcia. Una linea ha «l'altro senso» quando almeno [quota] dei suoi punti
 * ha, entro [raggio] metri, un punto di un'altra linea che va al contrario.
 * Ritorna, per ogni linea, di quanti metri spostarla a destra del suo verso:
 * [mezzaCorsia] se ha l'altro senso, zero se è sola (un senso unico resta in
 * mezzo alla strada).
 */
export function sensiDiMarcia(linee, { raggio = 6, quota = 0.3, mezzaCorsia = 1.3 } = {}) {
  const cella = raggio;
  const griglia = new Map();
  const versi = linee.map((punti) =>
    punti.map((_, k) => {
      const a = punti[Math.max(0, k - 1)];
      const b = punti[Math.min(punti.length - 1, k + 1)];
      const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
      return [(b[0] - a[0]) / l, (b[1] - a[1]) / l];
    }),
  );
  linee.forEach((punti, i) =>
    punti.forEach(([x, y], k) => {
      const c = `${Math.floor(x / cella)},${Math.floor(y / cella)}`;
      if (!griglia.has(c)) griglia.set(c, []);
      griglia.get(c).push([x, y, i, versi[i][k]]);
    }),
  );
  return linee.map((punti, i) => {
    if (punti.length < 2) return 0;
    let accoppiati = 0;
    punti.forEach(([x, y], k) => {
      const [vx, vy] = versi[i][k];
      const cx = Math.floor(x / cella);
      const cy = Math.floor(y / cella);
      for (let ox = -1; ox <= 1; ox++)
        for (let oy = -1; oy <= 1; oy++)
          for (const [px, py, j, [wx, wy]] of griglia.get(`${cx + ox},${cy + oy}`) ?? []) {
            if (j === i || Math.hypot(px - x, py - y) > raggio || vx * wx + vy * wy > -0.6) continue;
            accoppiati++;
            return;
          }
    });
    return accoppiati >= quota * punti.length ? mezzaCorsia : 0;
  });
}

/**
 * Di quanto alzare i nastri a questo [zoom], in metri.
 *
 * Il percorso sta sessanta centimetri sopra l'asfalto. Da vicino bastano; ma
 * la profondità che la scheda grafica distingue cresce allontanandosi, e
 * sotto lo zoom 17 quei centimetri sullo schermo sono meno di un punto: la
 * linea e la strada si contendevano i punti. Più lontano si guarda, più la
 * linea si alza, così che sullo schermo lo stacco resti quello dello zoom 17;
 * mai più di tre metri (sotto un cavalcavia ci deve passare).
 */
export function alzataDeiNastri(zoom) {
  if (!(zoom < 17)) return 0;
  return Math.min(3, 0.62 * (2 ** (17 - zoom) - 1));
}
