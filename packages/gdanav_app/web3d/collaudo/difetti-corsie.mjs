// La verifica della vista «Corsie» su tessere vere: i difetti che si vedono
// guidando, trovati da soli e contati per tipo, per controllare una modifica
// su tante zone invece che a occhio su una.
//   NODE_USE_ENV_PROXY=1 node collaudo/difetti-corsie.mjs <zone.json> <cartella> [prima.json]
// [zone.json]: `[{nome, lon, lat, raggio?}, {nome, x, y}, {nome, percorso: <file {punti}>}, …]`
// (le zone vere restano fuori dal repo). Di ogni zona la tessera z14 del
// punto (e le vicine fino a [raggio]), o quelle che il percorso attraversa;
// le tessere della mappa da OpenFreeMap e le corsie dal relay, come le ha
// l'app. Scrive <cartella>/rapporto.json (i conti per tipo, i casi, i tempi
// di costruzione) e per i casi peggiori di ogni tipo la pianta dall'alto
// (<cartella>/casi/<tipo>-<n>.png); con un rapporto di [prima] stampa il
// confronto. CASI=n: quante piante per tipo (3); SOLO=<zona>: una zona.
//
// I tipi (un caso è un gruppo di punti dello stesso tipo entro 25 m):
// a) sollevato-corsie / sollevato-mappa: l'asfalto delle corsie, o una
//    strada della mappa con le sue opere (impalcato, parapetti, piloni), più
//    in alto di quanto concede il ponte più vicino nei dati (`bridge` o
//    `layer` > 0 di OpenStreetMap): un metro, più il 10% della distanza;
//    troppo-alto: un ponte oltre il suo livello (otto metri l'uno) di più
//    di un livello, fuori dai viadotti sulle valli;
// b) strada-senza-dati: un nastro della mappa disegnato dove il relay non
//    ha nessuna via (in costruzione, chiusa, tolta); nastro-fuori-quota: un
//    nastro della mappa sotto (o sopra) l'asfalto delle corsie, a un'altra
//    quota (una strada doppia); doppione: due vie con le corsie una sopra
//    l'altra per un tratto, senza essere un ramo dell'altra;
// c) incrocio-fuso: due vie che si incrociano senza un nodo in comune
//    disegnate alla stessa quota (-dati: anche OpenStreetMap le dà allo
//    stesso livello); giunzione-scalino: allo stesso nodo le vie a quote
//    diverse; nodo-fra-livelli-dati: un nodo in comune fra due vie a
//    livelli diversi, in mezzo a tutte e due; raccordo-fuori: asfalto delle
//    corsie (i capi tondi, gli angoli, i raccordi) fuori da ogni carreggiata;
//    rotonda-aperta (dati), rotonda-storta (l'anello non in piano),
//    rotonda-senza-isola (l'anello del relay che la mappa non riconosce);
// d) scalino-corsie / rampa-ripida: più del 12% (o del 10,5%) fra due punti
//    di una via; scalino-mappa, compenetrati, corsie-compenetrate, pilone:
//    quelli di `verifica-strade.mjs`;
// e) segnaletica-fuori: righe, frecce, strisce fuori dalla carreggiata;
//    segnaletica-sospesa: più in alto (o più in basso) dell'asfalto;
// f) opere-sulla-carreggiata: il cemento dei ponti (parapetti, muri,
//    spalle, il piano dell'impalcato) che spunta dall'asfalto delle corsie,
//    a più di 80 cm dal bordo: un parapetto di traverso, una spalla che
//    esce dalla strada; opere-a-spuntone: un triangolo in piano delle
//    opere (il ventre, il cordolo) che esce di più di tre metri da ogni
//    strada disegnata.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const W = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const { costruisci, controlla } = await import(`${W}/collaudo/verifica-strade.mjs`);
const { CLASSI_CORSIE, bordiCorsie } = await import(`${W}/src/corsie.js`);
const segnaletica = await import(`${W}/src/segnaletica.js`);
// Quanto sopra la sua quota sta l'asfalto di una via (la galleria, sotto le altre).
const sopraAsfalto = segnaletica.sopraAsfalto ?? ((v, sopra) => sopra(v.hw));
const { ALTEZZA_LIVELLO } = await import(`${W}/src/elevazione.js`);
const { mercX, mercY } = await import(`${W}/src/geo.js`);

const z = 14;
const tessX = (lon) => Math.floor(mercX(lon) * 2 ** z);
const tessY = (lat) => Math.floor(mercY(lat) * 2 ** z);

/** Una griglia di oggetti per riquadro, per cercare in fretta quelli vicini. */
class Griglia {
  constructor(cella = 12) {
    this.c = cella;
    this.m = new Map();
  }
  metti(x0, y0, x1, y1, o) {
    const c = this.c;
    for (let cx = Math.floor(Math.min(x0, x1) / c); cx <= Math.floor(Math.max(x0, x1) / c); cx++) {
      for (let cy = Math.floor(Math.min(y0, y1) / c); cy <= Math.floor(Math.max(y0, y1) / c); cy++) {
        const k = cx + ',' + cy;
        if (!this.m.has(k)) this.m.set(k, []);
        this.m.get(k).push(o);
      }
    }
  }
  vicini(x, y, r) {
    const c = this.c;
    const out = new Set();
    for (let cx = Math.floor((x - r) / c); cx <= Math.floor((x + r) / c); cx++) {
      for (let cy = Math.floor((y - r) / c); cy <= Math.floor((y + r) / c); cy++) for (const o of this.m.get(cx + ',' + cy) ?? []) out.add(o);
    }
    return out;
  }
}

/** Il punto [p] rispetto al tratto a→b: `{d, u, o, h}` (distanza, dove lungo il tratto, di lato a sinistra, quota). */
function sulTratto(p, a, b) {
  const ex = b[0] - a[0];
  const ey = b[1] - a[1];
  const l = Math.hypot(ex, ey) || 1e-9;
  const tx = ex / l;
  const ty = ey / l;
  const uu = ((p[0] - a[0]) * tx + (p[1] - a[1]) * ty) / l;
  const u = Math.max(0, Math.min(1, uu));
  const qx = a[0] + ex * u;
  const qy = a[1] + ey * u;
  return { d: Math.hypot(p[0] - qx, p[1] - qy), u: uu, o: -ty * (p[0] - a[0]) + tx * (p[1] - a[1]), h: a[2] !== undefined ? a[2] + (b[2] - a[2]) * u : 0, l };
}

/** Il punto in cui i tratti a-b e c-d si incrociano (fuori dai capi), o null. */
function incrocio(a, b, c, d) {
  const rx = b[0] - a[0];
  const ry = b[1] - a[1];
  const sx = d[0] - c[0];
  const sy = d[1] - c[1];
  const den = rx * sy - ry * sx;
  if (Math.abs(den) < 1e-9) return null;
  const t = ((c[0] - a[0]) * sy - (c[1] - a[1]) * sx) / den;
  const u = ((c[0] - a[0]) * ry - (c[1] - a[1]) * rx) / den;
  if (t <= 0 || t >= 1 || u <= 0 || u >= 1) return null;
  return { x: a[0] + rx * t, y: a[1] + ry * t, sen: Math.abs(den) / (Math.hypot(rx, ry) * Math.hypot(sx, sy)) };
}

const ponteDi = (w) => !!w.bridge && w.bridge !== 'no';
const galleriaDi = (w) => !!w.tunnel && w.tunnel !== 'no';
const layerDi = (w) => parseInt(w.layer, 10) || 0;
/** Il livello come lo dicono i tag: sotto, a terra, sopra. */
const livelloTag = (w) => (galleriaDi(w) ? Math.min(-1, layerDi(w)) : ponteDi(w) ? Math.max(1, layerDi(w)) : layerDi(w));

/** Le vie del relay delle nove tessere attorno, così come sono (coi tag). */
function relayAttorno(X, Y) {
  const vie = new Map();
  let centro = false;
  for (let dx = -1; dx <= 1; dx++) {
    for (let dy = -1; dy <= 1; dy++) {
      const f = path.join(os.tmpdir(), `relay-corsie-14-${X + dx}-${Y + dy}.json`);
      if (!fs.existsSync(f)) continue;
      let d = null;
      try {
        d = JSON.parse(fs.readFileSync(f, 'utf8'));
      } catch {
        continue;
      }
      if (!dx && !dy && d?.strade?.length) centro = true;
      for (const v of d?.strade ?? []) vie.set(v.id, v);
    }
  }
  return { vie: [...vie.values()], centro };
}

/** I triangoli di una geometria fatta: `[[x, y, z] ×3]`. */
function* triangoli(g) {
  if (!g) return;
  const P = g.posizioni;
  const I = g.indici;
  for (let k = 0; k < I.length; k += 3) yield [I[k], I[k + 1], I[k + 2]].map((i) => [P[3 * i], P[3 * i + 1], P[3 * i + 2]]);
}
const areaDi = (t) => Math.abs((t[1][0] - t[0][0]) * (t[2][1] - t[0][1]) - (t[1][1] - t[0][1]) * (t[2][0] - t[0][0])) / 2;
const baricentro = (t) => [(t[0][0] + t[1][0] + t[2][0]) / 3, (t[0][1] + t[1][1] + t[2][1]) / 3, (t[0][2] + t[1][2] + t[2][2]) / 3];

/** I punti di una linea `[[x, y, h?]]` uno ogni [passo] metri (con la quota interpolata). */
function fitti(p, passo) {
  const out = [p[0]];
  for (let k = 1; k < p.length; k++) {
    const a = p[k - 1];
    const b = p[k];
    const n = Math.max(1, Math.ceil(Math.hypot(b[0] - a[0], b[1] - a[1]) / passo));
    for (let j = 1; j <= n; j++) out.push(a.map((v, i) => v + ((b[i] - v) * j) / n));
  }
  return out;
}

/**
 * I difetti di una tessera costruita ([T] da `costruisci`), in metri della
 * tessera: `[{tipo, x, y, h, peso, info}]`. Solo dentro la tessera.
 */
export function difetti(T) {
  const out = [];
  const { t, sys } = T;
  const meta = sys.lato / 2;
  const dentro = (x, y) => Math.abs(x) < meta && Math.abs(y) < meta;
  const metti = (tipo, x, y, h, peso, info) => {
    if (dentro(x, y)) out.push({ tipo, x, y, h, peso, info });
  };
  const { vie: grezze, centro } = relayAttorno(T.X, T.Y);
  if (!centro || !t.grafo.corsie) return { difetti: out, conCorsie: false };
  const { nodi, feats } = t.grafo;
  const C = t.grafo.corsie;
  // Le vie del relay coi tag, nei metri della tessera.
  const perId = new Map();
  const relay = grezze.map((w) => {
    const xy = [];
    for (let i = 0; i + 1 < w.g.length; i += 2) xy.push(sys.daLonLat(w.g[i], w.g[i + 1]));
    const r = { w, xy, liv: livelloTag(w), alto: ponteDi(w) || layerDi(w) > 0 };
    perId.set(w.id, r);
    return r;
  });
  const gRelay = new Griglia(20);
  for (const r of relay) for (let k = 1; k < r.xy.length; k++) gRelay.metti(r.xy[k - 1][0], r.xy[k - 1][1], r.xy[k][0], r.xy[k][1], [r, k]);
  /** La via del relay più vicina a [x, y] (entro [r] metri): `[distanza, via]`. */
  const relayVicina = (x, y, r = 30) => {
    let meglio = [Infinity, null];
    for (const [v, k] of gRelay.vicini(x, y, r)) {
      const s = sulTratto([x, y], v.xy[k - 1], v.xy[k]);
      if (s.d < meglio[0]) meglio = [s.d, v];
    }
    return meglio;
  };
  const viadotti = new Griglia(25);
  for (const f of feats) {
    if (!f.altezza) continue;
    for (const i of f.nodi) viadotti.metti(nodi[i].x, nodi[i].y, nodi[i].x, nodi[i].y, f.altezza);
  }

  // Le vie disegnate con le corsie: i tratti con la quota e i bordi dell'asfalto.
  const gC = new Griglia(12);
  const vieC = C.map((v) => {
    const B = bordiCorsie(v);
    const p = v.xy.map((q, k) => [q[0], q[1], v.h[k]]);
    const r = { v, p, sx: B.sinistra + v.margini[0], dx: B.destra - v.margini[1], grezza: perId.get(v.id)?.w ?? null };
    r.largo = Math.max(Math.abs(r.sx), Math.abs(r.dx));
    for (let k = 1; k < p.length; k++) {
      const m = r.largo + 2;
      gC.metti(Math.min(p[k - 1][0], p[k][0]) - m, Math.min(p[k - 1][1], p[k][1]) - m, Math.max(p[k - 1][0], p[k][0]) + m, Math.max(p[k - 1][1], p[k][1]) + m, [r, k]);
    }
    return r;
  });
  /** La quota disegnata della via [r] nel punto più vicino a [x, y]. */
  const quotaSu = (r, x, y) => {
    let meglio = { d: Infinity, h: NaN };
    for (let k = 1; k < r.p.length; k++) {
      const s = sulTratto([x, y], r.p[k - 1], r.p[k]);
      if (s.d < meglio.d) meglio = s;
    }
    return meglio.h;
  };
  // Quanto in alto si può stare: sui ponti dei dati (`bridge`, o `layer` >
  // 0) quanto sono disegnati (almeno otto metri per livello), e sulle vie
  // attaccate a loro, nodo per nodo, come una rampa: alla stessa quota per
  // 40 m, poi giù del 5,5%; più un metro. Lontano dai ponti, un metro.
  const tetto = new Map();
  {
    const chiaveN = (q) => Math.round(q[0] * 2) + ',' + Math.round(q[1] * 2);
    const val = new Map();
    const adj = new Map();
    const perIdC = new Map(vieC.map((r) => [r.v.id, r]));
    for (const r of relay) {
      for (let k = 0; k < r.xy.length; k++) {
        const n = chiaveN(r.xy[k]);
        if (!adj.has(n)) adj.set(n, []);
        if (k) {
          const d = Math.hypot(r.xy[k][0] - r.xy[k - 1][0], r.xy[k][1] - r.xy[k - 1][1]);
          adj.get(n).push([chiaveN(r.xy[k - 1]), d]);
          adj.get(chiaveN(r.xy[k - 1])).push([n, d]);
        }
        if (!r.alto) continue;
        const c = perIdC.get(r.w.id);
        const disegnata = c ? quotaSu(c, r.xy[k][0], r.xy[k][1]) : 0;
        const H = Math.max(ALTEZZA_LIVELLO * Math.max(1, layerDi(r.w)), ...viadotti.vicini(r.xy[k][0], r.xy[k][1], 15), Number.isFinite(disegnata) ? disegnata : 0) + 0.055 * 40;
        val.set(n, Math.max(val.get(n) ?? 0, H));
      }
    }
    const coda = [...val].sort((x, y) => y[1] - x[1]);
    // Pochi nodi alti: una coda ordinata a mano basta.
    while (coda.length) {
      const [n, v] = coda.shift();
      if (v < (val.get(n) ?? 0)) continue;
      for (const [m, d] of adj.get(n) ?? []) {
        const w = v - 0.055 * d;
        if (w > (val.get(m) ?? 0)) {
          val.set(m, w);
          let i = 0;
          while (i < coda.length && coda[i][1] > w) i++;
          coda.splice(i, 0, [m, w]);
        }
      }
    }
    for (const r of relay) tetto.set(r, r.xy.map((q) => (r.alto ? Infinity : val.get(chiaveN(q)) ?? 0)));
  }
  /** Fin dove può salire il punto [x, y] della via del relay [r]. */
  const concessoSu = (r, x, y) => {
    const t = tetto.get(r);
    let meglio = null;
    for (let k = 1; k < r.xy.length; k++) {
      const s = sulTratto([x, y], r.xy[k - 1], r.xy[k]);
      if (!meglio || s.d < meglio.d) meglio = { ...s, k };
    }
    if (!meglio) return 1;
    const u = Math.max(0, Math.min(1, meglio.u));
    return 1 + Math.max(0, t[meglio.k - 1] - 0.055 * u * meglio.l, t[meglio.k] - 0.055 * (1 - u) * meglio.l);
  };
  /** Fin dove può salire una strada della mappa in [x, y] (verso tx, ty): quanto le vie del relay lungo lei (la più alta), o un metro. */
  const concesso = (x, y, tx, ty, w) => {
    let lim = 1;
    for (const [r, k] of gRelay.vicini(x, y, w / 2 + 4)) {
      const a = r.xy[k - 1];
      const b = r.xy[k];
      const s = sulTratto([x, y], a, b);
      if (s.d > w / 2 + 4 || Math.abs(((b[0] - a[0]) * tx + (b[1] - a[1]) * ty) / (s.l * (Math.hypot(tx, ty) || 1))) < 0.7) continue;
      lim = Math.max(lim, r.alto ? Infinity : concessoSu(r, x, y));
    }
    return lim;
  };

  /**
   * Sull'asfalto di una via con le corsie, a [tol] metri dal bordo e a meno
   * di [dz] metri di quota: la via e lo scarto di quota, o null.
   */
  const sullAsfalto = (x, y, h, tol, dz = 1.5) => {
    let meglio = null;
    for (const [r, k] of gC.vicini(x, y, 0)) {
      const a = r.p[k - 1];
      const b = r.p[k];
      const s = sulTratto([x, y], a, b);
      if (Math.abs(s.h - h) > dz) continue;
      let ok;
      if (s.u >= 0 && s.u <= 1) ok = s.o <= r.sx + tol && s.o >= r.dx - tol;
      // Oltre il capo del tratto: il capo tondo (o il tratto dopo).
      else ok = s.d <= r.largo + tol;
      if (ok && (!meglio || Math.abs(s.h - h) < Math.abs(meglio.dh))) meglio = { r, dh: h - s.h };
    }
    return meglio;
  };

  // ── a) Sollevati senza un ponte nei dati, o troppo alti ────────────────
  for (const r of vieC) {
    if (r.v.galleria) continue;
    const g = r.grezza;
    const suo = g && (ponteDi(g) || layerDi(g) > 0);
    for (const q of fitti(r.p, 4)) {
      if (!dentro(q[0], q[1]) || q[2] <= 1) continue;
      if (suo) {
        const lim = ALTEZZA_LIVELLO * Math.max(1, layerDi(g)) + ALTEZZA_LIVELLO + 0.5;
        if (q[2] > lim && ![...viadotti.vicini(q[0], q[1], 15)].length) metti('troppo-alto', q[0], q[1], q[2], q[2] - lim, `${q[2].toFixed(1)} m, layer ${g.layer ?? '-'} ${r.v.hw} ${r.v.id}`);
        continue;
      }
      const rr = perId.get(r.v.id);
      const lim = rr ? concessoSu(rr, q[0], q[1]) : 1;
      if (q[2] > lim) metti('sollevato-corsie', q[0], q[1], q[2], q[2] - lim, `${q[2].toFixed(1)} m (al più ${lim.toFixed(1)}) ${r.v.hw} ${r.v.id}`);
    }
  }

  // ── b) Strade senza dati, nastri a un'altra quota, doppioni ────────────
  const gFeat = new Griglia(20);
  for (const f of feats) {
    for (let k = 1; k < f.nodi.length; k++) {
      const a = nodi[f.nodi[k - 1]];
      const b = nodi[f.nodi[k]];
      gFeat.metti(a.x, a.y, b.x, b.y, [f, [a.x, a.y, a.h], [b.x, b.y, b.h]]);
    }
  }
  /** La strada della mappa più vicina a [x, y] (con [h], fra quelle a quella quota). */
  const featVicina = (x, y, h = null) => {
    let meglio = null;
    for (const [f, a, b] of gFeat.vicini(x, y, 15)) {
      const s = sulTratto([x, y], a, b);
      if (h !== null && Math.abs(s.h - h) > 2.5) continue;
      if (!meglio || s.d < meglio.s.d) meglio = { f, s, a, b };
    }
    return meglio;
  };
  // Le strade della mappa disegnate in alto (i nastri, gli impalcati, i
  // parapetti, i muri): più in alto di quanto concede la via del relay lungo
  // di loro (un ponte, una rampa attaccata a un ponte), o senza una via.
  {
    const visti = new Set();
    const prova = (g, togli) => {
      for (const tri of triangoli(g)) {
        const c = baricentro(tri);
        const z = Math.max(tri[0][2], tri[1][2], tri[2][2]) - togli;
        if (z <= 1.2 || !dentro(c[0], c[1])) continue;
        const kk = Math.round(c[0] / 3) + ',' + Math.round(c[1] / 3);
        if (visti.has(kk)) continue;
        visti.add(kk);
        const fv = featVicina(c[0], c[1], z);
        if (!fv || fv.f.cls === 'rail' || fv.s.d > fv.f.w / 2 + 3) continue;
        const lim = concesso(c[0], c[1], fv.b[0] - fv.a[0], fv.b[1] - fv.a[1], fv.f.w);
        if (z > lim) metti('sollevato-mappa', c[0], c[1], z, z - lim, `${z.toFixed(1)} m (al più ${lim.toFixed(1)}), ${fv.f.cls}${fv.f.ponte ? ' ponte' : ''}${fv.f.rampa ? ' rampa' : ''}${fv.f.cantiere ? ' cantiere' : ''}`);
      }
    };
    for (const [tipo, g] of Object.entries(t.strade)) if (!tipo.startsWith('rail') && tipo !== 'galleria') prova(g, 0.25);
    // (Il parapetto sta un metro sopra l'asfalto.)
    prova(t.opere, 1.1);
  }
  for (const [tipo, g] of Object.entries(t.strade)) {
    if (tipo.startsWith('rail') || tipo === 'galleria') continue;
    for (const tri of triangoli(g)) {
      const c = baricentro(tri);
      if (!dentro(c[0], c[1]) || areaDi(tri) < 0.05) continue;
      const fv = featVicina(c[0], c[1]);
      const hw = fv ? fv.f.w / 2 : 3;
      const [d] = relayVicina(c[0], c[1], hw + 30);
      if (d > hw + 4) {
        metti('strada-senza-dati', c[0], c[1], c[2], d, `${fv?.f.cls ?? tipo}${fv?.f.cantiere ? ' cantiere' : ''}${fv?.f.ponte ? ' ponte' : ''} a ${Number.isFinite(d) ? d.toFixed(0) : '∞'} m dal relay`);
        continue;
      }
      // Sotto (o sopra) l'asfalto delle corsie, a un'altra quota, nello stesso verso.
      const sotto = sullAsfalto(c[0], c[1], c[2], -0.5, 7);
      if (sotto && Math.abs(sotto.dh) > 0.6 && fv) {
        const ex = fv.b[0] - fv.a[0];
        const ey = fv.b[1] - fv.a[1];
        let cos = 0;
        for (let k = 1; k < sotto.r.p.length; k++) {
          const s = sulTratto(c, sotto.r.p[k - 1], sotto.r.p[k]);
          if (s.u >= 0 && s.u <= 1 && s.d < sotto.r.largo + 1) {
            const fx = sotto.r.p[k][0] - sotto.r.p[k - 1][0];
            const fy = sotto.r.p[k][1] - sotto.r.p[k - 1][1];
            cos = Math.abs(ex * fx + ey * fy) / ((Math.hypot(ex, ey) || 1) * (Math.hypot(fx, fy) || 1));
            break;
          }
        }
        if (cos > 0.8) metti('nastro-fuori-quota', c[0], c[1], c[2], Math.abs(sotto.dh), `nastro ${fv.f.cls} a ${c[2].toFixed(1)}, corsie a ${(c[2] - sotto.dh).toFixed(1)} (${sotto.r.v.hw} ${sotto.r.v.id})`);
      }
    }
  }
  // I nodi delle vie (la geometria vera), per sapere chi tocca chi.
  const chiave = (q) => Math.round(q[0] * 2) + ',' + Math.round(q[1] * 2);
  const nodiDi = vieC.map((r) => new Set((r.v.xyVia ?? r.v.xy).map(chiave)));
  const indiceC = new Map(vieC.map((r, i) => [r, i]));
  const comuni = (i, j) => {
    let n = 0;
    for (const k of nodiDi[i]) if (nodiDi[j].has(k)) n++;
    return n;
  };
  {
    const indice = new Map(vieC.map((r, i) => [r, i]));
    const visti = new Set();
    vieC.forEach((r, i) => {
      for (const q of fitti(r.p, 4)) {
        if (!dentro(q[0], q[1])) continue;
        for (const [o, k] of gC.vicini(q[0], q[1], 0)) {
          const j = indice.get(o);
          if (j <= i || visti.has(i + ':' + j)) continue;
          const s = sulTratto(q, o.p[k - 1], o.p[k]);
          if (s.u < 0 || s.u > 1 || s.d > 1.5 || Math.abs(s.h - q[2]) > 2) continue;
          // Nello stesso verso (o al contrario): un incrocio non è un doppione.
          const a = o.p[k - 1];
          const b = o.p[k];
          const kq = Math.min(r.p.length - 1, Math.max(1, r.p.findIndex((x) => Math.hypot(x[0] - q[0], x[1] - q[1]) < 4.01) + 1));
          const ux = r.p[kq][0] - r.p[kq - 1][0];
          const uy = r.p[kq][1] - r.p[kq - 1][1];
          if (Math.abs(ux * (b[0] - a[0]) + uy * (b[1] - a[1])) < 0.9 * (Math.hypot(ux, uy) * Math.hypot(b[0] - a[0], b[1] - a[1]) || 1)) continue;
          // Due rami dello stesso nodo corrono insieme per un poco: non sono un doppione.
          const n = comuni(i, j);
          if (n >= 1 && n < 3) continue;
          visti.add(i + ':' + j);
          metti('doppione', q[0], q[1], q[2], 1, `${r.v.hw} ${r.v.id} e ${o.v.hw} ${o.v.id} (${n} nodi in comune)`);
        }
      }
    });
  }

  // ── c) Incroci ─────────────────────────────────────────────────────────
  {
    const gV = new Griglia(20);
    vieC.forEach((r, i) => {
      const p = r.v.xyVia ?? r.v.xy;
      for (let k = 1; k < p.length; k++) gV.metti(p[k - 1][0], p[k - 1][1], p[k][0], p[k][1], [i, k]);
    });
    const visti = new Set();
    vieC.forEach((r, i) => {
      const p = r.v.xyVia ?? r.v.xy;
      for (let k = 1; k < p.length; k++) {
        const a = p[k - 1];
        const b = p[k];
        for (const [j, kk] of gV.vicini((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, Math.hypot(b[0] - a[0], b[1] - a[1]) / 2 + 1)) {
          if (j <= i) continue;
          const o = vieC[j];
          const q = o.v.xyVia ?? o.v.xy;
          const x = incrocio(a, b, q[kk - 1], q[kk]);
          if (!x || !dentro(x.x, x.y)) continue;
          const kx = Math.round(x.x) + ',' + Math.round(x.y);
          if (visti.has(i + ':' + j + ':' + kx)) continue;
          visti.add(i + ':' + j + ':' + kx);
          // Un nodo in comune lì vicino: è un incrocio vero (o quasi).
          let vicino = false;
          for (const kn of nodiDi[i]) {
            if (!nodiDi[j].has(kn)) continue;
            const [cx, cy] = kn.split(',').map((v) => v / 2);
            if (Math.hypot(cx - x.x, cy - x.y) < 3) vicino = true;
          }
          if (vicino) continue;
          const ha = quotaSu(r, x.x, x.y);
          const hb = quotaSu(o, x.x, x.y);
          if (Math.abs(ha - hb) >= 3) continue;
          // Una galleria disegnata sotto l'asfalto dell'altra: passa sotto.
          const za = ha + sopraAsfalto(r.v, () => 0.2);
          const zb = hb + sopraAsfalto(o.v, () => 0.2);
          if (r.v.galleria !== o.v.galleria && (r.v.galleria ? za < zb - 0.03 : zb < za - 0.03)) continue;
          const ga = r.grezza;
          const gb = o.grezza;
          const stessoLivello = ga && gb && livelloTag(ga) === livelloTag(gb);
          metti(stessoLivello ? 'incrocio-fuso-dati' : 'incrocio-fuso', x.x, x.y, Math.max(ha, hb), 3 - Math.abs(ha - hb), `${r.v.hw}${r.v.ponte ? ' ponte' : ''}${r.v.galleria ? ' galleria' : ''} L${ga ? livelloTag(ga) : '?'} a ${ha.toFixed(1)} × ${o.v.hw}${o.v.ponte ? ' ponte' : ''}${o.v.galleria ? ' galleria' : ''} L${gb ? livelloTag(gb) : '?'} a ${hb.toFixed(1)} (${r.v.id}/${o.v.id})`);
        }
      }
    });
  }
  {
    // Allo stesso nodo, le quote di tutte le vie.
    const perNodo = new Map();
    vieC.forEach((r, i) => {
      const p = r.v.xyVia ?? r.v.xy;
      p.forEach((q, k) => {
        const kk = chiave(q);
        if (!perNodo.has(kk)) perNodo.set(kk, []);
        perNodo.get(kk).push({ i, k, capo: k === 0 || k === p.length - 1, q });
      });
    });
    for (const elenco of perNodo.values()) {
      if (new Set(elenco.map((e) => e.i)).size < 2) continue;
      const q = elenco[0].q;
      if (!dentro(q[0], q[1])) continue;
      const hh = elenco.map((e) => quotaSu(vieC[e.i], q[0], q[1]));
      const salto = Math.max(...hh) - Math.min(...hh);
      if (salto > 0.8) metti('giunzione-scalino', q[0], q[1], Math.max(...hh), salto, elenco.map((e, n) => `${vieC[e.i].v.hw}@${hh[n].toFixed(1)}`).join(' '));
      // Un nodo in mezzo a due vie che i dati danno a livelli diversi.
      const mezzo = elenco.filter((e) => !e.capo && vieC[e.i].grezza);
      for (let a = 0; a < mezzo.length; a++) {
        for (let b = a + 1; b < mezzo.length; b++) {
          const la = livelloTag(vieC[mezzo[a].i].grezza);
          const lb = livelloTag(vieC[mezzo[b].i].grezza);
          if (la !== lb) metti('nodo-fra-livelli-dati', q[0], q[1], Math.max(...hh), Math.abs(la - lb), `L${la} ${vieC[mezzo[a].i].v.id} e L${lb} ${vieC[mezzo[b].i].v.id}`);
        }
      }
    }
  }
  // L'asfalto delle corsie per punto (una griglia dei suoi triangoli).
  const gA = new Griglia(10);
  for (const tri of triangoli(t.corsie?.asfalto)) {
    const xs = tri.map((q) => q[0]);
    const ys = tri.map((q) => q[1]);
    gA.metti(Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys), tri);
  }
  /** Se sotto [c] (fino a mezzo metro più giù) c'è l'asfalto delle corsie. */
  const asfaltoSotto = (c) =>
    [...gA.vicini(c[0], c[1], 0)].some(([a, b, d]) => {
      const s1 = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
      const s2 = (d[0] - b[0]) * (c[1] - b[1]) - (d[1] - b[1]) * (c[0] - b[0]);
      const s3 = (a[0] - d[0]) * (c[1] - d[1]) - (a[1] - d[1]) * (c[0] - d[0]);
      return ((s1 >= 0 && s2 >= 0 && s3 >= 0) || (s1 <= 0 && s2 <= 0 && s3 <= 0)) && c[2] - a[2] < 0.5 && c[2] - a[2] > -0.05;
    });
  /**
   * Nell'angolo fra due vie che si toccano lì vicino (a meno di 20 m), a
   * meno di [ANGOLO_M] dai bordi di tutte e due: l'asfalto dell'angolo
   * tondo, che sta proprio lì (fra i due cordoli e l'arco).
   */
  const ANGOLO_M = 3;
  const nellAngolo = (c) => {
    const vicine = new Map();
    for (const [r, k] of gC.vicini(c[0], c[1], 0)) {
      const d = sulTratto(c, r.p[k - 1], r.p[k]).d - r.largo;
      if (d < ANGOLO_M) vicine.set(indiceC.get(r), Math.min(vicine.get(indiceC.get(r)) ?? Infinity, d));
    }
    const ii = [...vicine.keys()];
    for (let a = 0; a < ii.length; a++) {
      for (let b = a + 1; b < ii.length; b++) {
        for (const kn of nodiDi[ii[a]]) {
          if (!nodiDi[ii[b]].has(kn)) continue;
          const [nx, ny] = kn.split(',').map((v) => v / 2);
          if (Math.hypot(nx - c[0], ny - c[1]) < 20) return true;
        }
      }
    }
    return false;
  };
  /** Fra due rami a senso unico che partono dallo stesso nodo (dove c'è la zebratura). */
  const fraDueRami = (c) => {
    const rami = [...new Set([...gC.vicini(c[0], c[1], 0)].filter(([r, k]) => sulTratto(c, r.p[k - 1], r.p[k]).d < r.largo + 7.5).map(([r]) => indiceC.get(r)))];
    const insieme = (i, j) => vieC[i].v.senso && vieC[j].v.senso && chiave((vieC[i].v.xyVia ?? vieC[i].v.xy)[0]) === chiave((vieC[j].v.xyVia ?? vieC[j].v.xy)[0]);
    return rami.some((i, a) => rami.some((j, b) => b > a && insieme(i, j)));
  };
  // L'asfalto delle corsie fuori da ogni carreggiata.
  if (t.corsie?.asfalto) {
    for (const tri of triangoli(t.corsie.asfalto)) {
      const c = baricentro(tri);
      if (!dentro(c[0], c[1])) continue;
      if (sullAsfalto(c[0], c[1], c[2] - 0.2, 1.2)) continue;
      // Fra due rami a senso unico che partono dallo stesso nodo (la
      // zebratura, dipinta sull'asfalto): va bene.
      if (fraDueRami(c) || nellAngolo(c)) continue;
      // Quanto fuori: dal bordo più vicino.
      let fuori = Infinity;
      for (const [r, k] of gC.vicini(c[0], c[1], 0)) {
        const s = sulTratto(c, r.p[k - 1], r.p[k]);
        fuori = Math.min(fuori, s.d - r.largo);
      }
      const area = areaDi(tri);
      if (area < 0.05) continue;
      metti('raccordo-fuori', c[0], c[1], c[2], Number.isFinite(fuori) ? fuori : 5, `${Number.isFinite(fuori) ? fuori.toFixed(1) : '?'} m fuori, ${area.toFixed(1)} m²`);
    }
  }
  // Le rotonde del relay: chiuse, in piano, riconosciute.
  {
    const anelli = relay.filter((r) => CLASSI_CORSIE.has(r.w.hw) && (r.w.junction === 'roundabout' || r.w.junction === 'circular') && r.xy.length >= 2);
    const padre = new Map(anelli.map((r) => [r, r]));
    const trova = (r) => (padre.get(r) === r ? r : trova(padre.get(r)));
    const capi = new Map();
    for (const r of anelli) {
      for (const q of [r.xy[0], r.xy.at(-1)]) {
        const k = chiave(q);
        if (capi.has(k)) padre.set(trova(r), trova(capi.get(k)));
        else capi.set(k, r);
      }
    }
    const gruppi = new Map();
    for (const r of anelli) {
      const g = trova(r);
      if (!gruppi.has(g)) gruppi.set(g, []);
      gruppi.get(g).push(r);
    }
    const centri = [...new Set(nodi.map((n) => n.centroRotonda).filter(Boolean))];
    for (const g of gruppi.values()) {
      const pts = g.flatMap((r) => r.xy);
      const cx = pts.reduce((s, q) => s + q[0], 0) / pts.length;
      const cy = pts.reduce((s, q) => s + q[1], 0) / pts.length;
      if (!dentro(cx, cy)) continue;
      const raggio = pts.reduce((s, q) => s + Math.hypot(q[0] - cx, q[1] - cy), 0) / pts.length;
      const conta = new Map();
      for (const r of g) for (const q of [r.xy[0], r.xy.at(-1)]) conta.set(chiave(q), (conta.get(chiave(q)) ?? 0) + 1);
      const chiuso = [...conta.values()].every((n) => n % 2 === 0);
      if (!chiuso && raggio < 60) {
        metti('rotonda-aperta', cx, cy, 0, raggio, `${g.length} vie, raggio ${raggio.toFixed(0)} m`);
        continue;
      }
      const disegnate = vieC.filter((r) => g.some((x) => x.w.id === r.v.id));
      const hh = disegnate.flatMap((r) => r.p.map((q) => q[2]));
      const inQuota = g.some((r) => r.alto);
      if (hh.length && !inQuota && Math.max(...hh) - Math.min(...hh) > 1) metti('rotonda-storta', cx, cy, Math.max(...hh), Math.max(...hh) - Math.min(...hh), `quote ${Math.min(...hh).toFixed(1)}…${Math.max(...hh).toFixed(1)}, raggio ${raggio.toFixed(0)} m`);
      // Come la segnaletica cerca l'isola: un centro della mappa e una via
      // dell'anello tutta sul suo cerchio.
      // (Le grandi, o non tonde, si disegnano bene anche senza isola.)
      const rr = pts.map((q) => Math.hypot(q[0] - cx, q[1] - cy));
      if (raggio > 25 || raggio < 5 || Math.min(...rr) < 0.7 * Math.max(...rr)) continue;
      const c = centri.find((c) => Math.hypot(c.x - cx, c.y - cy) < raggio);
      const sua = c && disegnate.some((r) => (r.v.xyVia ?? r.v.xy).length >= 3 && (r.v.xyVia ?? r.v.xy).every((q) => Math.abs(Math.hypot(q[0] - c.x, q[1] - c.y) - c.r) < 2.5));
      if (!sua) metti('rotonda-senza-isola', cx, cy, hh.length ? Math.max(...hh) : 0, raggio, c ? `centro della mappa a ${Math.hypot(c.x - cx, c.y - cy).toFixed(1)} m, raggio ${c.r.toFixed(1)}/${raggio.toFixed(1)}` : `la mappa non la riconosce, raggio ${raggio.toFixed(0)} m`);
    }
  }

  // ── d) Scalini e rampe ripide lungo le vie con le corsie ──────────────
  for (const r of vieC) {
    for (let k = 1; k < r.p.length; k++) {
      const a = r.p[k - 1];
      const b = r.p[k];
      const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (l < 2 || !dentro(a[0], a[1])) continue;
      const pend = Math.abs(b[2] - a[2]) / l;
      if (pend > 0.12) metti('scalino-corsie', (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, Math.max(a[2], b[2]), pend, `${(pend * 100).toFixed(0)}% ${a[2].toFixed(1)}→${b[2].toFixed(1)} ${r.v.hw} ${r.v.id}`);
      else if (pend > 0.105 && l >= 6) metti('rampa-ripida', (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, Math.max(a[2], b[2]), pend, `${(pend * 100).toFixed(1)}% ${r.v.hw} ${r.v.id}`);
    }
  }
  const nomi = { pendenza: 'scalino-mappa', compenetrati: 'compenetrati', pilone: 'pilone', 'corsie-compenetrate': 'corsie-compenetrate' };
  for (const e of controlla(T)) {
    if (!nomi[e.tipo]) continue;
    const [x, y] = sys.daLonLat(e.ll[0], e.ll[1]);
    metti(nomi[e.tipo], x, y, 0, 1, e.info);
  }

  // ── e) La segnaletica fuori dalla carreggiata, o sospesa ──────────────
  if (t.corsie?.vernice) {
    for (const tri of triangoli(t.corsie.vernice)) {
      const c = baricentro(tri);
      if (!dentro(c[0], c[1])) continue;
      const su = sullAsfalto(c[0], c[1], c[2], 0.3, 1.5);
      // Su una via qualunque lì sotto, poco sopra il suo asfalto: va bene.
      const bene = su && [...gC.vicini(c[0], c[1], 0)].some(([r, k]) => {
        const s = sulTratto(c, r.p[k - 1], r.p[k]);
        const dh = c[2] - s.h;
        return dh >= 0.05 && dh <= 0.45 && s.o <= r.sx + 0.3 && s.o >= r.dx - 0.3;
      });
      if (bene) continue;
      if (!su) {
        // La zebratura fra due rami: sull'asfalto suo, sotto di lei (vedi `segnaletica.js`).
        if (fraDueRami(c) && t.corsie.asfalto && asfaltoSotto(c)) continue;
        let fuori = Infinity;
        for (const [r, k] of gC.vicini(c[0], c[1], 0)) fuori = Math.min(fuori, sulTratto(c, r.p[k - 1], r.p[k]).d - r.largo);
        metti('segnaletica-fuori', c[0], c[1], c[2], Number.isFinite(fuori) ? fuori : 5, `${Number.isFinite(fuori) ? fuori.toFixed(1) : '?'} m fuori`);
      } else metti('segnaletica-sospesa', c[0], c[1], c[2], Math.abs(su.dh), `${su.dh.toFixed(2)} m dall'asfalto (${su.r.v.hw} ${su.r.v.id})`);
    }
  }

  // ── f) Le opere sull'asfalto delle corsie, o a spuntone ────────────────
  {
    const visti = new Set();
    for (const tri of triangoli(t.opere)) {
      const c = baricentro(tri);
      if (!dentro(c[0], c[1])) continue;
      const alto = Math.max(tri[0][2], tri[1][2], tri[2][2]);
      const kk = Math.round(c[0] / 2) + ',' + Math.round(c[1] / 2);
      // Ben dentro l'asfalto (80 cm dal bordo), e da un palmo a due metri e mezzo sopra.
      const su = sullAsfalto(c[0], c[1], alto, -0.8, 2.8);
      if (su && !visti.has(kk)) {
        const sopra = su.dh - sopraAsfalto(su.r.v, () => 0.2);
        if (sopra > 0.08 && sopra < 2.5) {
          visti.add(kk);
          metti('opere-sulla-carreggiata', c[0], c[1], alto, sopra, `${sopra.toFixed(2)} m sopra l'asfalto (${su.r.v.hw} ${su.r.v.id})`);
        }
      }
      // Un triangolo in piano lontano da ogni strada: uno spuntone.
      if (alto - Math.min(tri[0][2], tri[1][2], tri[2][2]) > 0.3 || areaDi(tri) < 2) continue;
      let fuori = 0;
      for (const q of tri) {
        let d = Infinity;
        for (const [r, k] of gC.vicini(q[0], q[1], 12)) d = Math.min(d, sulTratto(q, r.p[k - 1], r.p[k]).d - r.largo);
        for (const [f, a, b] of gFeat.vicini(q[0], q[1], 12)) d = Math.min(d, sulTratto(q, a, b).d - f.w / 2);
        fuori = Math.max(fuori, d);
      }
      if (fuori > 3 && Number.isFinite(fuori)) metti('opere-a-spuntone', c[0], c[1], alto, fuori, `${fuori.toFixed(1)} m fuori da ogni strada, ${areaDi(tri).toFixed(0)} m²`);
    }
  }
  return { difetti: out, conCorsie: true };
}

/** I punti dello stesso tipo entro [R] metri sono un caso solo (il peggiore li rappresenta). */
export function casi(punti, R = 25) {
  const out = [];
  const ordinati = [...punti].sort((a, b) => b.peso - a.peso);
  for (const p of ordinati) {
    const c = out.find((c) => c.tipo === p.tipo && Math.hypot(c.x - p.x, c.y - p.y) < R);
    if (c) c.punti++;
    else out.push({ ...p, punti: 1 });
  }
  return out;
}

const lonLat = (sys, x, y) => {
  const mx = sys.mx + x * sys.s;
  const my = sys.my - y * sys.s;
  return [+(mx * 360 - 180).toFixed(6), +((Math.atan(Math.sinh(Math.PI * (1 - 2 * my))) * 180) / Math.PI).toFixed(6)];
};

/** Le tessere di una zona: attorno al punto, o lungo il percorso. */
function tessereDi(zona, base) {
  if (zona.percorso) {
    const p = JSON.parse(fs.readFileSync(path.resolve(base, zona.percorso), 'utf8')).punti;
    const out = new Map();
    let s = 0;
    for (let i = 0; i + 1 < p.length; i += 2) {
      if (i) s += Math.hypot((p[i] - p[i - 2]) * 111320 * Math.cos((p[i + 1] * Math.PI) / 180), (p[i + 1] - p[i - 1]) * 110540);
      const k = tessX(p[i]) + ',' + tessY(p[i + 1]);
      if (!out.has(k)) out.set(k, Math.round(s));
    }
    return [...out].map(([k, m]) => [...k.split(',').map(Number), m]);
  }
  const r = zona.raggio ?? 0;
  const [cx, cy] = Number.isInteger(zona.x) ? [zona.x, zona.y] : [tessX(zona.lon), tessY(zona.lat)];
  const out = [];
  for (let dx = -r; dx <= r; dx++) for (let dy = -r; dy <= r; dy++) out.push([cx + dx, cy + dy, null]);
  return out;
}

/** La pianta dall'alto attorno a un caso: SVG (lato [L] metri). */
export function pianta(T, caso, L = 110) {
  const { t, sys } = T;
  const S = 7;
  const N = L * S;
  const X = (x) => ((x - caso.x) * S + N / 2).toFixed(1);
  const Y = (y) => ((caso.y - y) * S + N / 2).toFixed(1);
  const vicino = (q) => Math.abs(q[0] - caso.x) < L * 0.75 && Math.abs(q[1] - caso.y) < L * 0.75;
  const colore = (h) => {
    if (h < 0.6) return '#20304d';
    const u = Math.min(1, h / 18);
    return `hsl(${(30 - 30 * u).toFixed(0)}, 85%, ${(52 - 12 * u).toFixed(0)}%)`;
  };
  const tri = (g, fill, extra = '') => {
    let s = '';
    for (const q of triangoli(g)) {
      if (!q.some(vicino)) continue;
      const f = typeof fill === 'function' ? fill(q) : fill;
      s += `<path d="M${X(q[0][0])} ${Y(q[0][1])}L${X(q[1][0])} ${Y(q[1][1])}L${X(q[2][0])} ${Y(q[2][1])}Z" fill="${f}" ${extra}/>`;
    }
    return s;
  };
  let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${N}" height="${N + 70}" font-family="sans-serif"><rect width="${N}" height="${N + 70}" fill="#eef0e8"/>`;
  for (const [tipo, g] of Object.entries(t.strade)) svg += tri(g, tipo.startsWith('rail') ? '#9a958c' : tipo === 'galleria' ? '#7d8597' : (q) => (Math.max(q[0][2], q[1][2], q[2][2]) > 0.6 ? '#c79a7a' : '#a9afba'), 'opacity="0.85"');
  svg += tri(t.opere, '#bdb6aa', 'opacity="0.55"');
  if (t.corsie) {
    svg += tri(t.corsie.marciapiedi, '#d9d6cf');
    svg += tri(t.corsie.asfalto, (q) => colore(Math.max(q[0][2], q[1][2], q[2][2])));
    svg += tri(t.corsie.vernice, '#ffffff');
  }
  // Le vie del relay: la linea vera, rossa sui ponti, tratteggiata in galleria.
  const { vie } = relayAttorno(T.X, T.Y);
  for (const w of vie) {
    const xy = [];
    for (let i = 0; i + 1 < w.g.length; i += 2) xy.push(sys.daLonLat(w.g[i], w.g[i + 1]));
    if (!xy.some(vicino)) continue;
    const c = ponteDi(w) ? '#e0262b' : layerDi(w) > 0 ? '#ff8a00' : galleriaDi(w) ? '#5b6170' : w.hw === 'service' ? '#7aa36a' : '#111';
    svg += `<polyline points="${xy.map((q) => X(q[0]) + ',' + Y(q[1])).join(' ')}" fill="none" stroke="${c}" stroke-width="1.6" ${galleriaDi(w) ? 'stroke-dasharray="6 4"' : ''} opacity="0.9"/>`;
  }
  svg += `<circle cx="${X(caso.x)}" cy="${Y(caso.y)}" r="${5 * S}" fill="none" stroke="#e5007e" stroke-width="3"/>`;
  const testo = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  svg += `<rect y="${N}" width="${N}" height="70" fill="#fff"/><text x="10" y="${N + 24}" font-size="20" font-weight="bold">${testo(caso.tipo)} (${caso.punti} punti)</text><text x="10" y="${N + 50}" font-size="15">${testo(caso.info ?? '')}</text>`;
  svg += `<text x="${N - 10}" y="${N + 24}" font-size="13" text-anchor="end">nero: via a terra · rosso: ponte · arancio: layer>0 · tratteggio: galleria</text>`;
  svg += `<text x="${N - 10}" y="${N + 50}" font-size="13" text-anchor="end">asfalto blu: a terra · dal giallo al rosso: in quota · ${L} m di lato</text>`;
  return svg + '</svg>';
}

async function fotografa(pagine, cartella) {
  if (!pagine.length) return;
  const { playwright } = await import(`${W}/collaudo/pagina.mjs`);
  const { chromium } = await playwright();
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 800, height: 850 }, deviceScaleFactor: 2 });
  for (const [file, svg] of pagine) {
    await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
    await page.locator('svg').screenshot({ path: path.join(cartella, file) });
  }
  await browser.close();
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [fileZone, cartella, filePrima] = process.argv.slice(2);
  const zone = JSON.parse(fs.readFileSync(fileZone, 'utf8')).filter((z) => !process.env.SOLO || z.nome === process.env.SOLO);
  fs.mkdirSync(path.join(cartella, 'casi'), { recursive: true });
  const rapporto = { zone: [], conti: {}, ms: [] };
  const tutti = [];
  for (const zona of zone) {
    const conti = {};
    for (const [X, Y, metri] of tessereDi(zona, path.dirname(fileZone))) {
      const T = await costruisci(X, Y);
      const { difetti: punti, conCorsie } = difetti(T);
      if (!conCorsie) {
        console.log(zona.nome, X, Y, 'senza corsie del relay');
        continue;
      }
      const cc = casi(punti);
      const perTipo = {};
      for (const c of cc) {
        perTipo[c.tipo] = (perTipo[c.tipo] ?? 0) + 1;
        conti[c.tipo] = (conti[c.tipo] ?? 0) + 1;
        rapporto.conti[c.tipo] = (rapporto.conti[c.tipo] ?? 0) + 1;
        tutti.push({ ...c, zona: zona.nome, X, Y, metri, ll: lonLat(T.sys, c.x, c.y) });
      }
      rapporto.ms.push(T.t.conti.ms);
      console.log(zona.nome, X, Y, metri ?? '', `${T.t.conti.ms} ms`, JSON.stringify(perTipo));
    }
    rapporto.zone.push({ nome: zona.nome, conti });
  }
  rapporto.casi = tutti.map(({ zona, X, Y, metri, tipo, ll, h, peso, punti, info }) => ({ zona, X, Y, metri, tipo, ll, h: +h.toFixed(2), peso: Number.isFinite(peso) ? +peso.toFixed(2) : 999, punti, info }));
  fs.writeFileSync(path.join(cartella, 'rapporto.json'), JSON.stringify(rapporto, null, 1));
  const ms = [...rapporto.ms].sort((a, b) => a - b);
  console.log('\ncasi per tipo', JSON.stringify(rapporto.conti, null, 1));
  if (ms.length) console.log(`costruzione: mediana ${ms[Math.floor(ms.length / 2)]} ms, massimo ${ms.at(-1)} ms, ${ms.length} tessere`);
  if (filePrima) {
    const prima = JSON.parse(fs.readFileSync(filePrima, 'utf8'));
    const tipi = [...new Set([...Object.keys(prima.conti), ...Object.keys(rapporto.conti)])].sort();
    console.log('\ntipo'.padEnd(26), 'prima', 'dopo');
    for (const k of tipi) console.log(k.padEnd(25), String(prima.conti[k] ?? 0).padStart(5), String(rapporto.conti[k] ?? 0).padStart(5));
  }
  // Le piante dei casi peggiori di ogni tipo.
  const quanti = +(process.env.CASI ?? 3);
  const scelti = [];
  for (const tipo of Object.keys(rapporto.conti)) {
    tutti
      .filter((c) => c.tipo === tipo)
      .sort((a, b) => b.peso * Math.sqrt(b.punti) - a.peso * Math.sqrt(a.punti))
      .slice(0, quanti)
      .forEach((c, n) => scelti.push([c, `${tipo}-${n + 1}.png`]));
  }
  const pagine = [];
  const fatte = new Map();
  for (const [c, file] of scelti) {
    const k = c.X + ',' + c.Y;
    if (!fatte.has(k)) fatte.set(k, await costruisci(c.X, c.Y));
    pagine.push([file, pianta(fatte.get(k), c)]);
  }
  await fotografa(pagine, path.join(cartella, 'casi'));
}
