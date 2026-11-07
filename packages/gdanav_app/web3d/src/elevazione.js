// L'altezza delle strade: i ponti al loro livello, le rampe in salita.
//
// Le tessere vettoriali non hanno quote: dicono solo che una strada è un
// ponte (`brunnel=bridge`) e a che livello sta (`layer`). Qui si fa il grafo
// delle strade, si fissano i ponti a [ALTEZZA_LIVELLO] metri per livello e
// la terra a zero, e le rampe in mezzo si trovano da sole: ogni nodo libero
// è la media dei vicini (rilassamento armonico), entro la distanza che una
// pendenza del [PENDENZA] serve per arrivare in quota. È il prototipo
// approvato (`build.mjs`), fatto una tessera alla volta.

export const ALTEZZA_LIVELLO = 7.0;
export const PENDENZA = 0.055;
const PASSO_FITTO = 6; // metri fra due nodi lungo le strade grandi
const PASSO_RADO = 12; // e lungo le piccole

export const CLASSI_STRADE = new Set(['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'service', 'rail']);

/** Quanto è larga una strada (in metri), dalla classe e da come è fatta. */
export function larghezzaStrada(p) {
  const larghe = { motorway: 11.5, trunk: 10.5, primary: 9, secondary: 8, tertiary: 7, minor: 5.5, service: 4, rail: 4.2 };
  const rampa = p.ramp === 1 || p.ramp === '1' || p.ramp === true;
  let w = larghe[p.class] ?? 5;
  if (rampa) w = p.class === 'motorway' || p.class === 'trunk' ? 6.5 : 6;
  else if ((p.class === 'primary' || p.class === 'secondary') && p.oneway) w *= 0.75;
  else if ((p.class === 'motorway' || p.class === 'trunk') && !p.oneway) w *= 1.8;
  if (p.class === 'service' && p.service === 'parking_aisle') w = 3.5;
  return w;
}

/** Il livello di una strada: almeno 1 per un ponte, 0 per una galleria. */
export function livelloStrada(p) {
  // Un ponte senza layer (o con un layer storto: 0, negativo, non un numero)
  // sta al primo livello; più di cinque livelli non ce ne sono.
  if (p.brunnel === 'bridge') return Math.min(5, Math.max(1, Math.round(+(p.layer ?? 1)) || 1));
  if (p.brunnel === 'tunnel') return 0;
  // Fuori dai ponti un layer positivo è quasi sempre un rilevato o un errore:
  // a terra (le rampe salgono da sole verso il ponte a cui si attaccano).
  return 0;
}

/** L'altezza di un ponte di quel livello. */
export const altezzaLivello = (livello) => (livello > 0 ? livello * ALTEZZA_LIVELLO : 0);

/**
 * Le estremità tagliate sui bordi delle tessere si uniscono: due strade che
 * escono da tessere vicine nello stesso punto (entro 4 pixel) diventano una.
 * [strade]: `{p, g}` con `g` in pixel globali (tx*4096+px).
 */
export function uniscIBordi(strade, estensione = 4096) {
  const pts = [];
  for (const r of strade) {
    for (const fine of [r.g[0], r.g[r.g.length - 1]]) {
      if (Math.abs(fine[0] / estensione - Math.round(fine[0] / estensione)) < 1e-9) {
        pts.push({ riga: 'x' + fine[0], lungo: fine[1], pt: fine });
      } else if (Math.abs(fine[1] / estensione - Math.round(fine[1] / estensione)) < 1e-9) {
        pts.push({ riga: 'y' + fine[1], lungo: fine[0], pt: fine });
      }
    }
  }
  pts.sort((a, b) => (a.riga < b.riga ? -1 : a.riga > b.riga ? 1 : a.lungo - b.lungo));
  let i = 0;
  let unite = 0;
  while (i < pts.length) {
    let j = i + 1;
    while (j < pts.length && pts[j].riga === pts[i].riga && pts[j].lungo - pts[j - 1].lungo < 4) j++;
    if (j - i > 1) {
      const m = pts.slice(i, j).reduce((s, q) => s + q.lungo, 0) / (j - i);
      for (let k = i; k < j; k++) {
        if (pts[k].riga[0] === 'x') pts[k].pt[1] = m;
        else pts[k].pt[0] = m;
      }
      unite++;
    }
    i = j;
  }
  return unite;
}

/** Un mucchio (max-heap o min-heap) per le visite del grafo. */
class Mucchio {
  constructor(massimo) {
    this.a = [];
    this.meglio = massimo ? (x, y) => x > y : (x, y) => x < y;
  }
  get length() {
    return this.a.length;
  }
  push(v, i) {
    const a = this.a;
    a.push([v, i]);
    let c = a.length - 1;
    while (c > 0) {
      const p = (c - 1) >> 1;
      if (!this.meglio(a[c][0], a[p][0])) break;
      [a[p], a[c]] = [a[c], a[p]];
      c = p;
    }
  }
  pop() {
    const a = this.a;
    const top = a[0];
    const last = a.pop();
    if (a.length) {
      a[0] = last;
      let c = 0;
      for (;;) {
        const l = 2 * c + 1;
        const r = l + 1;
        let m = c;
        if (l < a.length && this.meglio(a[l][0], a[m][0])) m = l;
        if (r < a.length && this.meglio(a[r][0], a[m][0])) m = r;
        if (m === c) break;
        [a[m], a[c]] = [a[c], a[m]];
        c = m;
      }
    }
    return top;
  }
}

/**
 * Il grafo delle strade con le altezze.
 *
 * [strade]: `{p, g}` (proprietà OpenMapTiles, punti in pixel globali);
 * [metri]: dai pixel globali ai metri locali. Restituisce i nodi (`x`, `y`,
 * `h`) e le strade (`nodi`, `cls`, `w`, `ponte`, `livello`, …).
 */
export function grafoStrade(strade, metri, { iterazioni = 1500 } = {}) {
  const nodi = [];
  const indice = new Map();
  const nodoPer = (gx, gy) => {
    const k = Math.round(gx * 4) + ',' + Math.round(gy * 4);
    let i = indice.get(k);
    if (i === undefined) {
      i = nodi.length;
      const [x, y] = metri(gx, gy);
      nodi.push({ x, y, adj: [], feats: [], fisso: null, h: 0 });
      indice.set(k, i);
    }
    return i;
  };
  const nuovo = (x, y) => {
    nodi.push({ x, y, adj: [], feats: [], fisso: null, h: 0 });
    return nodi.length - 1;
  };
  const collega = (a, b, f) => {
    if (a === b) return;
    const d = Math.hypot(nodi[a].x - nodi[b].x, nodi[a].y - nodi[b].y);
    nodi[a].adj.push({ to: b, d, f, avanti: true });
    nodi[b].adj.push({ to: a, d, f, avanti: false });
  };
  const aggiungiFeat = (i, fi) => {
    const fs = nodi[i].feats;
    if (fs[fs.length - 1] !== fi && !fs.includes(fi)) fs.push(fi);
  };
  const feats = [];
  for (const r of strade) {
    const p = r.p;
    const grandi = p.class !== 'minor' && p.class !== 'service';
    const passo = grandi ? PASSO_FITTO : PASSO_RADO;
    const idx = r.g.map(([x, y]) => nodoPer(x, y));
    const pieno = [idx[0]];
    for (let k = 1; k < idx.length; k++) {
      const a = nodi[idx[k - 1]];
      const b = nodi[idx[k]];
      const n = Math.floor(Math.hypot(b.x - a.x, b.y - a.y) / passo);
      for (let j = 1; j < n; j++) {
        const t = j / n;
        pieno.push(nuovo(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t));
      }
      pieno.push(idx[k]);
    }
    const fi = feats.length;
    feats.push({
      cls: p.class,
      sv: p.service,
      sub: p.subclass,
      galleria: p.brunnel === 'tunnel',
      rampa: p.ramp === 1 || p.ramp === '1' || p.ramp === true,
      ponte: p.brunnel === 'bridge',
      livello: livelloStrada(p),
      senso: +(p.oneway ?? 0) || 0,
      w: larghezzaStrada(p),
      nodi: pieno,
      nome: p.name,
      cucita: false,
    });
    for (let k = 0; k < pieno.length; k++) {
      aggiungiFeat(pieno[k], fi);
      if (k > 0) collega(pieno[k - 1], pieno[k], fi);
    }
  }

  // Le estremità penzolanti delle strade grandi (le tessere semplificate
  // perdono il vertice in comune): si cuciono alla strada che continuano.
  {
    const GRANDI = new Set(['motorway', 'trunk', 'primary', 'secondary']);
    const griglia = new Map();
    const gk = (x, y) => Math.floor(x / 25) + ',' + Math.floor(y / 25);
    feats.forEach((f, fi) => {
      if (!GRANDI.has(f.cls) || f.galleria) return;
      for (const i of f.nodi) {
        const k = gk(nodi[i].x, nodi[i].y);
        let l = griglia.get(k);
        if (!l) griglia.set(k, (l = []));
        l.push([i, fi]);
      }
    });
    const nf = feats.length;
    for (let fi = 0; fi < nf; fi++) {
      const f = feats[fi];
      if (!GRANDI.has(f.cls) || f.galleria || f.nodi.length < 2) continue;
      for (const allaFine of [false, true]) {
        const ni = allaFine ? f.nodi[f.nodi.length - 1] : f.nodi[0];
        const n = nodi[ni];
        if (n.adj.length !== 1) continue;
        const prima = nodi[allaFine ? f.nodi[f.nodi.length - 2] : f.nodi[1]];
        let dx = n.x - prima.x;
        let dy = n.y - prima.y;
        const dl = Math.hypot(dx, dy) || 1;
        dx /= dl;
        dy /= dl;
        let meglio = null;
        let punti = 1e9;
        let bd = 0;
        const cx = Math.floor(n.x / 25);
        const cy = Math.floor(n.y / 25);
        for (let ax = -3; ax <= 3; ax++) {
          for (let ay = -3; ay <= 3; ay++) {
            for (const [j, fj] of griglia.get(cx + ax + ',' + (cy + ay)) || []) {
              if (fj === fi) continue;
              const m = nodi[j];
              const d = Math.hypot(m.x - n.x, m.y - n.y);
              if (d < 0.5 || d > 70) continue;
              const lungo = ((m.x - n.x) * dx + (m.y - n.y) * dy) / d;
              if (d < 4) {
                if (lungo < 0.2) continue;
              } else {
                if (lungo < 0.8) continue;
                const tf = feats[fj];
                const k = tf.nodi.indexOf(j);
                const a = nodi[tf.nodi[Math.max(0, k - 1)]];
                const b = nodi[tf.nodi[Math.min(tf.nodi.length - 1, k + 1)]];
                const tl = Math.hypot(b.x - a.x, b.y - a.y) || 1;
                if (Math.abs(((b.x - a.x) * dx + (b.y - a.y) * dy) / tl) < 0.85) continue;
              }
              const s = d * (1 + 4 * (1 - lungo));
              if (s < punti) {
                punti = s;
                meglio = j;
                bd = d;
              }
            }
          }
        }
        if (meglio === null) continue;
        const catena = [ni];
        const m = nodi[meglio];
        const passi = Math.floor(bd / PASSO_FITTO);
        for (let q = 1; q < passi; q++) {
          const t = q / passi;
          catena.push(nuovo(n.x + (m.x - n.x) * t, n.y + (m.y - n.y) * t));
        }
        catena.push(meglio);
        const fn = { ...f, nodi: allaFine ? catena : catena.slice().reverse(), cucita: true };
        const id = feats.length;
        feats.push(fn);
        for (let q = 0; q < fn.nodi.length; q++) {
          aggiungiFeat(fn.nodi[q], id);
          if (q) collega(fn.nodi[q - 1], fn.nodi[q], id);
        }
      }
    }
  }

  altezze(nodi, feats, iterazioni);
  return { nodi, feats };
}

/** Le altezze dei nodi del grafo (vedi in cima). */
export function altezze(nodi, feats, iterazioni = 1500) {
  const hDi = (f) => altezzaLivello(f.livello);
  for (const n of nodi) {
    let hPonte = null;
    let diversi = false;
    for (const fi of n.feats) {
      const f = feats[fi];
      if (f.livello > 0) {
        if (hPonte !== null && hPonte !== hDi(f)) diversi = true;
        hPonte = hPonte === null ? hDi(f) : Math.max(hPonte, hDi(f));
      }
    }
    n.hPonte = hPonte;
    n.diversi = diversi;
  }
  // I nodi di un ponte vicini a un ponte di altro livello sono liberi: lì si
  // sale o si scende da un livello all'altro.
  for (const f of feats) {
    if (f.livello === 0) continue;
    const lungo = [0];
    let acc = 0;
    for (let k = 1; k < f.nodi.length; k++) {
      const a = nodi[f.nodi[k - 1]];
      const b = nodi[f.nodi[k]];
      acc += Math.hypot(a.x - b.x, a.y - b.y);
      lungo.push(acc);
    }
    const estremi = [0, f.nodi.length - 1].filter((k) => {
      const n = nodi[f.nodi[k]];
      return n.diversi || n.feats.some((o) => feats[o].livello > 0 && hDi(feats[o]) !== hDi(f));
    });
    for (let k = 0; k < f.nodi.length; k++) {
      const n = nodi[f.nodi[k]];
      let libero = n.diversi;
      for (const e of estremi) if (Math.abs(lungo[k] - lungo[e]) < 70) libero = true;
      if (n.fisso === null || n.fisso === 'libero') n.fisso = libero ? 'libero' : hDi(f);
      else if (!libero) n.fisso = Math.max(n.fisso, hDi(f));
    }
  }
  for (const n of nodi) if (n.fisso === null && n.feats.length && n.feats.every((fi) => feats[fi].galleria)) n.fisso = 0;
  const principale = (f) => (f.cls === 'motorway' || f.cls === 'trunk') && !f.rampa && f.livello === 0;
  for (const n of nodi) {
    if (n.fisso !== null) continue;
    const princ = n.feats.filter((fi) => principale(feats[fi])).length;
    // Dove una rampa si stacca da una carreggiata a terra, la carreggiata resta a terra.
    if (n.adj.length >= 3 && princ >= 1 && n.feats.some((fi) => feats[fi].rampa)) n.fisso = 0;
  }
  // Fin dove arriva la salita di un ponte: (h/pendenza − distanza) > 0.
  const arriva = new Float64Array(nodi.length).fill(-1);
  const mucchio = new Mucchio(true);
  nodi.forEach((n, i) => {
    if (n.hPonte) {
      arriva[i] = n.hPonte / PENDENZA;
      mucchio.push(arriva[i], i);
    }
  });
  while (mucchio.length) {
    const [v, i] = mucchio.pop();
    if (v < arriva[i]) continue;
    if (nodi[i].fisso === 0) continue;
    for (const e of nodi[i].adj) {
      const nv = v - e.d;
      if (nv > arriva[e.to]) {
        arriva[e.to] = nv;
        mucchio.push(nv, e.to);
      }
    }
  }
  nodi.forEach((n, i) => {
    if (typeof n.fisso === 'number') n.h = n.fisso;
    else if (n.fisso === 'libero' || arriva[i] > 0) {
      n.fisso = 'libero';
      n.h = n.hPonte ?? 0;
    } else {
      n.fisso = 0;
      n.h = 0;
    }
  });
  // Il rilassamento armonico dei nodi liberi.
  const liberi = [];
  nodi.forEach((n, i) => {
    if (n.fisso === 'libero') liberi.push(i);
  });
  for (let it = 0; it < iterazioni; it++) {
    let maxd = 0;
    for (const i of liberi) {
      const n = nodi[i];
      let s = 0;
      let w = 0;
      for (const e of n.adj) {
        const ww = 1 / Math.max(e.d, 0.5);
        s += nodi[e.to].h * ww;
        w += ww;
      }
      if (w) {
        const nh = s / w;
        maxd = Math.max(maxd, Math.abs(nh - n.h));
        n.h = nh;
      }
    }
    if (maxd < 1e-3) break;
  }
  // Un poco di levigatura per raccordi più morbidi (i ponti restano in quota).
  for (let it = 0; it < 6; it++) {
    const nh = nodi.map((n) => n.h);
    nodi.forEach((n, i) => {
      if (n.adj.length !== 2 || n.h < 0.05) return;
      if (typeof n.fisso === 'number' && n.fisso > 0) {
        const vicini = n.adj.map((e) => nodi[e.to].h);
        if (Math.max(...vicini.map((v) => Math.abs(v - n.h))) < 0.01) return;
      }
      nh[i] = (n.h * 2 + nodi[n.adj[0].to].h + nodi[n.adj[1].to].h) / 4;
    });
    nodi.forEach((n, i) => (n.h = nh[i]));
  }
  return liberi.length;
}
