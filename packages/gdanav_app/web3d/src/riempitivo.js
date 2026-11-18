// La città piena, nella vista «Corsie»: le case che OpenStreetMap non ha.
//
// «Però devi comunque mettere case ecc., così sembra morto.» In tanti paesi
// del Sud gli edifici veri nella mappa sono pochi:
// lungo una strada di città restava un piano bianco, come una campagna
// innevata. Dove la mappa dice che è abitato (o in una tessera di città,
// fuori dai campi, dai parchi e dall'acqua), lungo le strade nascono dei
// blocchi plausibili: arretrati dal marciapiede, staccati fra loro, da due a
// sei piani le case, larghi e bassi i capannoni. Sono sempre gli stessi
// (il seme è la strada), mai su una strada, su un edificio vero o su un
// altro blocco. E gli alberi lungo i viali, ogni dieci metri circa.
//
// Solo numeri, niente three.js: lo usa il lavoratore (`tessera.js`).

import { generatore } from './caso.js';
import { distanzaSegmento, puntoDentroPoligono } from './ritaglio.js';

/** Come sono fatti i blocchi, per tipo di zona (metri). */
export const TIPI_ISOLATO = {
  residenziale: { largo: [9, 20], fondo: [9, 15], distacco: [1.0, 3.5], spazio: [1.5, 6], piani: [2, 6], piano: 3.1 },
  industriale: { largo: [22, 45], fondo: [18, 32], distacco: [5, 9], spazio: [6, 14], piani: [1, 1], piano: 7.5 },
};

/** Un numero da [a, b] con [r] fra 0 e 1. */
const fra = ([a, b], r) => a + (b - a) * r;

/** Un hash di due interi (il seme di un lato di una strada). */
export function semeDi(a, b, c = 0) {
  let h = Math.imul(a | 0, 0x9e3779b1) ^ Math.imul(b | 0, 0x85ebca77) ^ Math.imul(c | 0, 0xc2b2ae3d);
  h = Math.imul(h ^ (h >>> 15), 0x2c1b3c6d);
  return (h ^ (h >>> 13)) >>> 0;
}

/** Un indice di segmenti in una griglia: `[ax, ay, bx, by, mezza, cosa]`. */
class GrigliaSegmenti {
  constructor(cella = 25) {
    this.c = cella;
    this.g = new Map();
  }
  aggiungi(a, b, mezza, cosa = null) {
    const c = this.c;
    const s = [a[0], a[1], b[0], b[1], mezza, cosa];
    for (let x = Math.floor((Math.min(a[0], b[0]) - mezza) / c); x <= Math.floor((Math.max(a[0], b[0]) + mezza) / c); x++) {
      for (let y = Math.floor((Math.min(a[1], b[1]) - mezza) / c); y <= Math.floor((Math.max(a[1], b[1]) + mezza) / c); y++) {
        const k = x + ',' + y;
        if (!this.g.has(k)) this.g.set(k, []);
        this.g.get(k).push(s);
      }
    }
  }
  /** I segmenti che possono stare entro [r] dal riquadro [x0, y0, x1, y1]. */
  vicini(x0, y0, x1, y1, r = 0) {
    const c = this.c;
    const out = new Set();
    for (let x = Math.floor((x0 - r) / c); x <= Math.floor((x1 + r) / c); x++) {
      for (let y = Math.floor((y0 - r) / c); y <= Math.floor((y1 + r) / c); y++) for (const s of this.g.get(x + ',' + y) ?? []) out.add(s);
    }
    return out;
  }
}

/** Il riquadro di un poligono `[[x, y], …]`. */
const riquadro = (p) => {
  let x0 = Infinity;
  let y0 = Infinity;
  let x1 = -Infinity;
  let y1 = -Infinity;
  for (const [x, y] of p) {
    x0 = Math.min(x0, x);
    y0 = Math.min(y0, y);
    x1 = Math.max(x1, x);
    y1 = Math.max(y1, y);
  }
  return [x0, y0, x1, y1];
};

/** Se il segmento [a, b] incrocia il segmento [c, d]. */
function siTagliano(a, b, c, d) {
  const o = (p, q, r) => Math.sign((q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]));
  return o(a, b, c) !== o(a, b, d) && o(c, d, a) !== o(c, d, b);
}

/**
 * Se il poligono convesso [p] (un blocco) arriva entro [m] metri dal
 * segmento [a, b]: un capo dentro, un lato che lo taglia, o vicini.
 */
export function bloccoTocca(p, a, b, m) {
  if (puntoDentroPoligono(a[0], a[1], [p]) || puntoDentroPoligono(b[0], b[1], [p])) return true;
  for (let k = 0; k < p.length; k++) {
    const c = p[k];
    const d = p[(k + 1) % p.length];
    if (siTagliano(a, b, c, d)) return true;
    if (distanzaSegmento(c[0], c[1], a[0], a[1], b[0], b[1]) < m) return true;
  }
  return distanzaSegmento(a[0], a[1], p[0][0], p[0][1], p[1][0], p[1][1]) < m || distanzaSegmento(b[0], b[1], p[0][0], p[0][1], p[1][0], p[1][1]) < m;
}

/** Se due poligoni convessi si toccano (assi separatori), con [m] metri di margine. */
export function siToccano(p, q, m = 0) {
  for (const poli of [p, q]) {
    for (let k = 0; k < poli.length; k++) {
      const a = poli[k];
      const b = poli[(k + 1) % poli.length];
      const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
      const nx = (a[1] - b[1]) / l;
      const ny = (b[0] - a[0]) / l;
      let p0 = Infinity;
      let p1 = -Infinity;
      let q0 = Infinity;
      let q1 = -Infinity;
      for (const v of p) {
        const t = v[0] * nx + v[1] * ny;
        p0 = Math.min(p0, t);
        p1 = Math.max(p1, t);
      }
      for (const v of q) {
        const t = v[0] * nx + v[1] * ny;
        q0 = Math.min(q0, t);
        q1 = Math.max(q1, t);
      }
      if (p1 + m <= q0 || q1 + m <= p0) return false;
    }
  }
  return true;
}

/** Il punto a [s] metri lungo [pts] e la direzione lì: `[x, y, tx, ty]`, o null oltre la fine. */
function lungo(pts, cum, s) {
  if (s < 0 || s > cum[cum.length - 1]) return null;
  let k = 1;
  while (k < pts.length - 1 && cum[k] < s) k++;
  const a = pts[k - 1];
  const b = pts[k];
  const l = cum[k] - cum[k - 1] || 1e-9;
  const t = (s - cum[k - 1]) / l;
  return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, (b[0] - a[0]) / l, (b[1] - a[1]) / l];
}

const progressiva = (pts) => {
  const c = [0];
  for (let k = 1; k < pts.length; k++) c.push(c[k - 1] + Math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]));
  return c;
};

/**
 * I blocchi da aggiungere lungo le strade.
 *
 * [strade]: `{pts, mezza, seme}` le strade che hanno case ai lati (metri
 * della tessera, mezza larghezza dell'asfalto, un seme che non dipende dalla
 * tessera); [ostacoli]: `{pts, mezza}` tutte le strade e le ferrovie, dove
 * non si costruisce; [edifici]: gli anelli esterni degli edifici veri;
 * [zona(x, y)]: `'residenziale'`, `'industriale'` o null (lì niente);
 * [mezzaQui(x, y)]: se la strada lì è più larga di [mezza] (le corsie vere),
 * quanto; [dentro(x, y)]: se il blocco tocca a questa tessera; [limite]: al
 * più quanti. Restituisce `{pts, h, tipo}`: quattro angoli, l'altezza.
 */
export function blocchiLungoLeStrade({ strade, ostacoli = strade, edifici = [], zona, mezzaQui = null, dentro = () => true, limite = 1500, marciapiede = 2.5 }) {
  const strada = new GrigliaSegmenti();
  for (const o of ostacoli) for (let k = 1; k < o.pts.length; k++) strada.aggiungi(o.pts[k - 1], o.pts[k], o.mezza);
  // Gli edifici veri, per il loro riquadro (la diagonale come segmento: basta per trovarli).
  const veri = new GrigliaSegmenti(30);
  for (const p of edifici) {
    if (p.length < 3) continue;
    const [x0, y0, x1, y1] = riquadro(p);
    veri.aggiungi([x0, y0], [x1, y1], 0, p);
  }
  const messi = new GrigliaSegmenti(30);
  const out = [];
  const libero = (blocco) => {
    const [x0, y0, x1, y1] = riquadro(blocco);
    for (const [ax, ay, bx, by, m] of strada.vicini(x0, y0, x1, y1, 12)) if (bloccoTocca(blocco, [ax, ay], [bx, by], m + 0.8)) return false;
    for (const [ax, ay, bx, by, , p] of veri.vicini(x0, y0, x1, y1, 2)) {
      // Il riquadro dell'edificio vero: se tocca quello del blocco, si guarda meglio.
      if (bx < x0 - 1 || ax > x1 + 1 || by < y0 - 1 || ay > y1 + 1) continue;
      if (blocco.some(([x, y]) => puntoDentroPoligono(x, y, [p]))) return false;
      if (p.some(([x, y]) => puntoDentroPoligono(x, y, [blocco]))) return false;
      for (let k = 0; k < p.length; k++) if (bloccoTocca(blocco, p[k], p[(k + 1) % p.length], 1.0)) return false;
    }
    for (const s of messi.vicini(x0, y0, x1, y1, 2)) if (siToccano(blocco, s[5], 1.2)) return false;
    return true;
  };
  for (const st of strade) {
    if (out.length >= limite) break;
    const cum = progressiva(st.pts);
    const L = cum[cum.length - 1];
    for (const lato of [1, -1]) {
      const r = generatore(semeDi(st.seme, lato));
      let s = r() * 6;
      while (s < L - 6 && out.length < limite) {
        const p0 = lungo(st.pts, cum, s);
        // Che zona è, una dozzina di metri dentro dal bordo della strada.
        const prova = [p0[0] - p0[3] * lato * (st.mezza + 12), p0[1] + p0[2] * lato * (st.mezza + 12)];
        const tipo = zona(prova[0], prova[1]);
        if (!tipo) {
          s += 10;
          continue;
        }
        const T = TIPI_ISOLATO[tipo];
        const largo = fra(T.largo, r());
        const fondo = fra(T.fondo, r());
        const distacco = fra(T.distacco, r());
        const piani = Math.round(fra(T.piani, r() * 0.6 + r() * 0.4));
        const spazio = fra(T.spazio, r());
        const p1 = lungo(st.pts, cum, s + largo);
        if (!p1) break;
        // La facciata dritta fra i due punti (la corda), a destra o a sinistra.
        const dx = p1[0] - p0[0];
        const dy = p1[1] - p0[1];
        const l = Math.hypot(dx, dy) || 1;
        const nx = (-dy / l) * lato;
        const ny = (dx / l) * lato;
        const mezza = Math.max(st.mezza, mezzaQui ? mezzaQui(p0[0], p0[1]) : 0, mezzaQui ? mezzaQui(p1[0], p1[1]) : 0);
        const o = mezza + marciapiede + distacco;
        const a = [p0[0] + nx * o, p0[1] + ny * o];
        const b = [p1[0] + nx * o, p1[1] + ny * o];
        const blocco = [a, b, [b[0] + nx * fondo, b[1] + ny * fondo], [a[0] + nx * fondo, a[1] + ny * fondo]];
        const cx = (a[0] + b[0]) / 2 + (nx * fondo) / 2;
        const cy = (a[1] + b[1]) / 2 + (ny * fondo) / 2;
        // Una strada che curva troppo sotto la facciata: niente blocco qui.
        const piega = l < largo * 0.9;
        if (!piega && dentro(cx, cy) && blocco.every(([x, y]) => zona(x, y) === tipo) && libero(blocco)) {
          // Girato in senso antiorario (come gli anelli degli edifici).
          const giro = (b[0] - a[0]) * (blocco[2][1] - a[1]) - (b[1] - a[1]) * (blocco[2][0] - a[0]) > 0 ? blocco : [...blocco].reverse();
          out.push({ pts: giro, h: piani * T.piano + (tipo === 'residenziale' ? 0.6 : 0), tipo });
          const [x0, y0, x1, y1] = riquadro(blocco);
          messi.aggiungi([x0, y0], [x1, y1], 0, blocco);
          s += largo + spazio;
        } else s += 4;
      }
    }
  }
  return out;
}

/**
 * Gli alberi lungo le strade di città: sul bordo esterno del marciapiede,
 * ogni [passo] metri (con un poco di disordine), dai due lati; mai vicino
 * agli incroci ([incroci]: punti `[x, y]`), su una strada ([ostacoli]),
 * dentro un edificio ([occupato(x, y)]). Restituisce `[x, y, scala]`.
 */
export function alberiLungoLeStrade({ strade, ostacoli = strade, incroci = [], occupato = () => false, mezzaQui = null, dentro = () => true, passo = 10, marciapiede = 2.5, limite = 1200 }) {
  const strada = new GrigliaSegmenti();
  for (const o of ostacoli) for (let k = 1; k < o.pts.length; k++) strada.aggiungi(o.pts[k - 1], o.pts[k], o.mezza);
  const out = [];
  // Lontano dagli incroci: lì si devono vedere le strisce, la linea d'arresto e il semaforo.
  const vicinoIncrocio = (x, y) => incroci.some((q) => Math.hypot(q[0] - x, q[1] - y) < 22);
  for (const st of strade) {
    const cum = progressiva(st.pts);
    const L = cum[cum.length - 1];
    for (const lato of [1, -1]) {
      const r = generatore(semeDi(st.seme, lato, 7));
      for (let s = r() * passo; s < L && out.length < limite; s += passo * (0.85 + r() * 0.3)) {
        const p = lungo(st.pts, cum, s);
        const mezza = Math.max(st.mezza, mezzaQui ? mezzaQui(p[0], p[1]) : 0);
        const o = mezza + marciapiede - 0.6;
        const x = p[0] - p[3] * lato * o;
        const y = p[1] + p[2] * lato * o;
        if (!dentro(x, y) || vicinoIncrocio(x, y) || occupato(x, y)) continue;
        let suStrada = false;
        for (const [ax, ay, bx, by, m] of strada.vicini(x, y, x, y, 2)) {
          if (distanzaSegmento(x, y, ax, ay, bx, by) < m + 1.2) {
            suStrada = true;
            break;
          }
        }
        // Alberi di città, più piccoli di quelli dei parchi: la strada resta in vista.
        if (!suStrada) out.push([x, y, 0.5 + r() * 0.15]);
      }
    }
  }
  return out;
}
