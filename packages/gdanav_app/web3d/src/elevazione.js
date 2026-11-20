// L'altezza delle strade: i ponti al loro livello, le rampe in salita.
//
// Le tessere vettoriali non hanno quote: dicono solo che una strada è un
// ponte (`brunnel=bridge`) e a che livello sta (`layer`). Qui si fa il grafo
// delle strade, si fissano i ponti a [ALTEZZA_LIVELLO] metri per livello e
// la terra a zero, e le rampe in mezzo si trovano da sole: ogni nodo libero
// è la media dei vicini (rilassamento armonico), entro la distanza che una
// pendenza del [PENDENZA] serve per arrivare in quota. È il prototipo
// approvato (`build.mjs`), fatto una tessera alla volta.

// Otto metri per livello: con l'impalcato spesso [SPESSORE_IMPALCATO] restano
// quasi sei metri di luce, e da dietro l'auto il vuoto sotto il ponte si vede.
export const ALTEZZA_LIVELLO = 8.0;
export const PENDENZA = 0.055;
/** Al più così ripida, la salita che arriva a un punto che sta a terra (una rotonda). */
export const PENDENZA_MAX = 0.1;
/** Fin dove una carreggiata che diventa un ponte non resta a terra allo svincolo. */
const PONTE_VICINO_M = 150;
/** Due strade attaccate entro tanti metri, se si incrociano in pianta, si stanno unendo. */
const ATTACCATE_M = 50;
/** Lo spessore dell'impalcato di un ponte, dall'asfalto al ventre. */
export const SPESSORE_IMPALCATO = 1.9;
/** Dove un ponte scavalca una strada, quanto sta sopra di lei: cinque metri di luce e l'impalcato. */
export const SCAVALCO_M = 5.1 + SPESSORE_IMPALCATO;
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

/**
 * Quanto è alto sulla valle un viadotto lungo [metri] (da un capo all'altro):
 * 4,5 m ogni cento, fra 10 e 60; 0 sotto i 200 m (lì vale il livello).
 */
export function altezzaViadotto(metri) {
  if (!(metri >= 200)) return 0;
  return Math.max(10, Math.min(60, metri * 0.045));
}

/** L'altezza di un ponte di quel livello. */
export const altezzaLivello = (livello) => (livello > 0 ? livello * ALTEZZA_LIVELLO : 0);

/**
 * Le estremità tagliate sui bordi delle tessere si uniscono: due strade che
 * escono da tessere vicine nello stesso punto (entro 4 pixel) diventano una.
 * [strade]: `{p, g}` con `g` in pixel globali (tx*4096+px).
 *
 * Solo strade dello stesso genere (livello, ponte, galleria): sono i due
 * pezzi della stessa via. Allo svincolo di una tangenziale il bordo passava
 * dove un viadotto al terzo livello corre proprio sopra una rampa a terra, a
 * un metro in pianta: i quattro capi diventavano un nodo solo, e la rampa
 * saliva a ventiquattro metri («una salita con strade in mezzo»).
 */
export function uniscIBordi(strade, estensione = 4096) {
  const pts = [];
  for (const r of strade) {
    const genere = `${livelloStrada(r.p)}${r.p.brunnel === 'tunnel' ? 'g' : ''}${r.p.class === 'rail' ? 'f' : ''}|`;
    for (const fine of [r.g[0], r.g[r.g.length - 1]]) {
      if (Math.abs(fine[0] / estensione - Math.round(fine[0] / estensione)) < 1e-9) {
        pts.push({ riga: genere + 'x' + fine[0], lungo: fine[1], pt: fine });
      } else if (Math.abs(fine[1] / estensione - Math.round(fine[1] / estensione)) < 1e-9) {
        pts.push({ riga: genere + 'y' + fine[1], lungo: fine[0], pt: fine });
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
        if (pts[k].riga.split('|')[1][0] === 'x') pts[k].pt[1] = m;
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
/** Il raggio delle curve di una strada (m): quanto si arrotondano gli angoli delle tessere. */
const RAGGIO_CURVE = { motorway: 150, trunk: 100, primary: 50, secondary: 35, tertiary: 25, minor: 12, service: 8, rail: 150 };

/**
 * Le curve arrotondate. Le tessere danno le strade semplificate, pochi
 * tratti dritti: ogni vertice era uno spigolo («le strade sulle curve a
 * volte sono spigolose»). Qui ogni vertice in mezzo a una strada (non un
 * incrocio, non un capo: [fermi]) diventa un arco col raggio della sua
 * classe ([RAGGIO_CURVE], in metri; [pxm]: pixel per metro), al più fino a
 * metà dei due tratti accanto; un punto ogni dieci gradi. [g]: i punti in
 * pixel. Restituisce i punti nuovi.
 */
export function arrotonda(g, raggio, pxm, fermi = () => false) {
  // Prima le linee che tornano indietro su sé stesse (vertici sbagliati nei
  // dati, a volte più d'uno di fila): via, finché ce ne sono.
  for (let pulita = false; !pulita && g.length >= 3; ) {
    pulita = true;
    for (let k = 1; k < g.length - 1; k++) {
      const [A, B, C] = [g[k - 1], g[k], g[k + 1]];
      const t1 = Math.atan2(B[1] - A[1], B[0] - A[0]);
      const t2 = Math.atan2(C[1] - B[1], C[0] - B[0]);
      const giro = Math.abs(Math.atan2(Math.sin(t2 - t1), Math.cos(t2 - t1)));
      const corto = Math.hypot(B[0] - A[0], B[1] - A[1]) < 1e-9 || Math.hypot(C[0] - B[0], C[1] - B[1]) < 1e-9;
      if ((giro > (140 * Math.PI) / 180 || corto) && !fermi(B)) {
        g = [...g.slice(0, k), ...g.slice(k + 1)];
        pulita = false;
        break;
      }
    }
  }
  if (g.length < 3) return g;
  const out = [g[0]];
  // Quanto di ogni tratto è già usato dall'arco del vertice prima.
  let usato = 0;
  for (let k = 1; k < g.length - 1; k++) {
    const [A, B, C] = [g[k - 1], g[k], g[k + 1]];
    const ab = Math.hypot(B[0] - A[0], B[1] - A[1]);
    const bc = Math.hypot(C[0] - B[0], C[1] - B[1]);
    const u1 = ab ? [(A[0] - B[0]) / ab, (A[1] - B[1]) / ab] : [0, 0];
    const u2 = bc ? [(C[0] - B[0]) / bc, (C[1] - B[1]) / bc] : [0, 0];
    const cos = -(u1[0] * u2[0] + u1[1] * u2[1]);
    const giro = Math.acos(Math.max(-1, Math.min(1, cos)));
    if (fermi(B) || !ab || !bc || giro < (3 * Math.PI) / 180 || giro > (150 * Math.PI) / 180) {
      out.push(B);
      usato = 0;
      continue;
    }
    const tMax = Math.min(ab - usato, bc / 2);
    let t = raggio * pxm * Math.tan(giro / 2);
    if (t > tMax) t = Math.max(0, tMax);
    if (t < 0.3 * pxm) {
      out.push(B);
      usato = 0;
      continue;
    }
    const r = t / Math.tan(giro / 2);
    const P1 = [B[0] + u1[0] * t, B[1] + u1[1] * t];
    const P2 = [B[0] + u2[0] * t, B[1] + u2[1] * t];
    // Il centro, sulla bisettrice dentro la curva.
    const bx = u1[0] + u2[0];
    const by = u1[1] + u2[1];
    const bl = Math.hypot(bx, by) || 1;
    const dc = Math.hypot(t, r);
    const O = [B[0] + (bx / bl) * dc, B[1] + (by / bl) * dc];
    const a1 = Math.atan2(P1[1] - O[1], P1[0] - O[0]);
    let a2 = Math.atan2(P2[1] - O[1], P2[0] - O[0]);
    let da = a2 - a1;
    while (da > Math.PI) da -= 2 * Math.PI;
    while (da < -Math.PI) da += 2 * Math.PI;
    const n = Math.max(2, Math.ceil(Math.abs(da) / ((10 * Math.PI) / 180)));
    for (let j = 0; j <= n; j++) {
      const a = a1 + (da * j) / n;
      out.push([O[0] + Math.cos(a) * r, O[1] + Math.sin(a) * r]);
    }
    usato = t;
  }
  out.push(g[g.length - 1]);
  return out;
}

export function grafoStrade(strade, metri) {
  // Le curve arrotondate (vedi [arrotonda]), ma non dove le strade si
  // toccano: un vertice che sta su due strade (o al capo di una) resta.
  {
    const conta = new Map();
    const k = (q) => Math.round(q[0] * 4) + ',' + Math.round(q[1] * 4);
    for (const r of strade) for (const q of r.g) conta.set(k(q), (conta.get(k(q)) ?? 0) + 1);
    const [x0, y0] = metri(0, 0);
    const [x1, y1] = metri(1000, 0);
    const pxm = 1000 / (Math.hypot(x1 - x0, y1 - y0) || 1);
    for (const r of strade) {
      const raggio = RAGGIO_CURVE[r.p.class] ?? 12;
      r.g = arrotonda(r.g, raggio, pxm, (q) => (conta.get(k(q)) ?? 0) > 1);
    }
  }
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
      // Un viadotto alto (vedi `segnaViadotti` in tessera.js): più del livello.
      altezza: p.brunnel === 'bridge' && +p.altezza > 0 ? +p.altezza : null,
      senso: +(p.oneway ?? 0) || 0,
      // A pagamento: sopra, ai caselli, c'è una pensilina (vedi `tessera.js`).
      pedaggio: p.toll === 1 || p.toll === '1' || p.toll === true,
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

  segnaRotonde(nodi, feats);
  altezze(nodi, feats);
  return { nodi, feats };
}

/** Quanto può essere grande (raggio, in metri) una rotonda. */
const ROTONDA_RAGGIO_MAX = 45;
/** Di quanto può girare l'anello a ogni nodo (gradi): agli spigoli di un isolato sono 90. */
const ROTONDA_SVOLTA_MAX = 75;

/**
 * Le rotonde a terra.
 *
 * «Mi è capitato in due rotonde che erano a livello strada ma le faceva
 * vedere sopraelevate.» Le tessere non dicono che una strada è una rotonda,
 * e una rotonda a qualche decina di metri dal capo di un cavalcavia stava
 * tutta dentro la salita: ogni nodo libero è la media dei vicini, e in un
 * anello con quattro, cinque bracci la terra (a 145 m dal ponte) è lontana
 * da tutti; l'anello finiva a sei, sette metri. Un anello piccolo e tondo di
 * strade che non sono ponti (girando sempre dalla stessa parte, niente
 * spigoli da isolato) è una rotonda, e senza un ponte suo sta a terra: la
 * salita è nei bracci, fra la rotonda e il ponte. Una rotonda sopraelevata
 * vera passa sopra le strade coi suoi pezzi di ponte, e resta com'è.
 * Segna `rotonda` sui nodi; restituisce quante ne ha trovate.
 */
export function segnaRotonde(nodi, feats) {
  // Anche coi pezzi di ponte: una rotonda in quota si riconosce, e resta in piano.
  const buona = (f) => !f.galleria && !f.rampa && f.cls !== 'rail';
  const sMax = (ROTONDA_SVOLTA_MAX * Math.PI) / 180;
  const sMin = (-8 * Math.PI) / 180;
  const lunghezzaMax = 2 * Math.PI * ROTONDA_RAGGIO_MAX * 1.15;
  const svolta = (a, b, c) => {
    const t = Math.atan2(c.y - b.y, c.x - b.x) - Math.atan2(b.y - a.y, b.x - a.x);
    return Math.atan2(Math.sin(t), Math.cos(t));
  };
  const tonda = (giro) => {
    let cx = 0;
    let cy = 0;
    for (const i of giro) {
      cx += nodi[i].x / giro.length;
      cy += nodi[i].y / giro.length;
    }
    let rMin = Infinity;
    let rMax = 0;
    for (const i of giro) {
      const r = Math.hypot(nodi[i].x - cx, nodi[i].y - cy);
      rMin = Math.min(rMin, r);
      rMax = Math.max(rMax, r);
    }
    return rMax <= ROTONDA_RAGGIO_MAX && rMax > 3 && rMin >= 0.55 * rMax;
  };
  let trovate = 0;
  // Si parte dai nodi dove la strada gira (in mezzo a un rettilineo no):
  // il giro, dalla parte dove gira.
  const cerca = (a, b, verso) => {
    const pila = [[a, b, Math.hypot(nodi[b].x - nodi[a].x, nodi[b].y - nodi[a].y), 0, [a, b]]];
    let passi = 0;
    while (pila.length && passi++ < 2000) {
      const [p, c, l, giro, cam] = pila.pop();
      for (const e of nodi[c].adj) {
        if (e.to === p || !buona(feats[e.f])) continue;
        const t = verso * svolta(nodi[p], nodi[c], nodi[e.to]);
        if (t < sMin || t > sMax) continue;
        const nl = l + e.d;
        const ng = giro + t;
        if (e.to === a) {
          const chiusa = verso * svolta(nodi[c], nodi[a], nodi[b]);
          const tutto = ((ng + chiusa) * 180) / Math.PI;
          if (chiusa >= sMin && chiusa <= sMax && Math.abs(tutto - 360) < 45 && nl > 20 && cam.length >= 4 && tonda(cam)) return cam;
          continue;
        }
        // Un anello di [ROTONDA_RAGGIO_MAX] metri gira almeno di un radiante ogni tanti metri.
        if (nl > lunghezzaMax || ng > 2.3 * Math.PI || ng < (nl - 25) / (1.3 * ROTONDA_RAGGIO_MAX) || cam.includes(e.to)) continue;
        pila.push([c, e.to, nl, ng, [...cam, e.to]]);
      }
    }
    return null;
  };
  for (const f of feats) {
    if (!buona(f) || f.nodi.length < 3) continue;
    for (let k = 1; k < f.nodi.length - 1; k++) {
      const a = f.nodi[k];
      if (nodi[a].rotonda) continue;
      const t = svolta(nodi[f.nodi[k - 1]], nodi[a], nodi[f.nodi[k + 1]]);
      if (Math.abs(t) < 0.05 || Math.abs(t) > sMax) continue;
      const anello = cerca(a, f.nodi[k + 1], Math.sign(t));
      if (!anello) continue;
      // Con un pezzo di ponte suo (un nodo in comune con un ponte) la rotonda è in quota.
      if (anello.some((i) => nodi[i].feats.some((fi) => feats[fi].livello > 0))) {
        // Ed è tutta in piano, alla quota del suo ponte (vedi `altezze`).
        for (const i of anello) nodi[i].anelloInQuota = anello;
        continue;
      }
      for (const i of anello) nodi[i].rotonda = true;
      trovate++;
    }
  }
  return trovate;
}

/**
 * Le altezze dei nodi del grafo.
 *
 * Il `layer` delle tessere dice solo chi passa sopra chi, non quanto in
 * alto: un ponte al terzo livello sta otto metri sopra quello che scavalca,
 * non a ventiquattro. Prima ogni ponte stava a otto metri per livello e
 * certi incroci erano inchiodati a terra: dove un viadotto «di terzo
 * livello» finiva su una carreggiata a terra scendeva di ventiquattro metri
 * in venticinque («una salita con strade in mezzo»), e le rampe fra due
 * ponti facevano scalini.
 *
 * Adesso, un livello alla volta dal basso, due specie di quote:
 * - quelle che servono: dove un ponte scavalca un'altra strada (o un ponte
 *   più basso), [ALTEZZA_LIVELLO] metri sopra di lei;
 * - quelle che si vorrebbero: un ponte almeno a [ALTEZZA_LIVELLO] metri, un
 *   viadotto sulle valli più in alto (vedi `segnaViadotti` in tessera.js)
 *   man mano che si allontana dai capi, un ponte in piano fra due punti alti,
 *   una rotonda con un pezzo di ponte tutta in piano.
 * Da quei punti la strada scende al più del [PENDENZA], per tutte le strade
 * attaccate, ponti o no. Le seconde però cedono ai punti che stanno a terra
 * (le rotonde, la carreggiata dove si stacca una rampa, i sottopassi): lì la
 * salita arriva al più del [PENDENZA_MAX]. Le gallerie lunghe (in montagna)
 * vanno alla quota della strada che ci entra: senza il terreno, una galleria
 * a terra accanto a un viadotto era un muro.
 */
export function altezze(nodi, feats) {
  const N = nodi.length;
  const tuttaGalleria = (n) => n.feats.length > 0 && n.feats.every((fi) => feats[fi].galleria);
  // I tratti di ogni strada, e dove un ponte ne scavalca un altro più basso.
  const tratti = [];
  feats.forEach((f, fi) => {
    for (let k = 1; k < f.nodi.length; k++) tratti.push([f.nodi[k - 1], f.nodi[k], fi]);
  });
  const G = 30;
  const griglia = new Map();
  const celle = (A, B, fn) => {
    for (let gx = Math.floor(Math.min(A.x, B.x) / G); gx <= Math.floor(Math.max(A.x, B.x) / G); gx++) {
      for (let gy = Math.floor(Math.min(A.y, B.y) / G); gy <= Math.floor(Math.max(A.y, B.y) / G); gy++) fn(gx + ',' + gy);
    }
  };
  tratti.forEach(([a, b], ti) =>
    celle(nodi[a], nodi[b], (k) => {
      if (!griglia.has(k)) griglia.set(k, []);
      griglia.get(k).push(ti);
    }),
  );
  // I sottopassi: le gallerie dove passano sotto un'altra strada restano a
  // terra; le altre (in collina, in montagna) vanno con la strada.
  const sottopasso = new Uint8Array(N);
  const incrocia = (A, B, C, D) => {
    const rx = B.x - A.x;
    const ry = B.y - A.y;
    const sx = D.x - C.x;
    const sy = D.y - C.y;
    const den = rx * sy - ry * sx;
    if (Math.abs(den) < 1e-9) return null;
    const t = ((C.x - A.x) * sy - (C.y - A.y) * sx) / den;
    const u = ((C.x - A.x) * ry - (C.y - A.y) * rx) / den;
    return t < 0 || t > 1 || u < 0 || u > 1 ? null : u;
  };
  {
    const vista = new Uint8Array(feats.length);
    for (let i = 0; i < feats.length; i++) {
      if (!feats[i].galleria || vista[i]) continue;
      const catena = [];
      const coda = [i];
      vista[i] = 1;
      while (coda.length) {
        const j = coda.pop();
        const f = feats[j];
        catena.push(j);
        for (const e of [f.nodi[0], f.nodi[f.nodi.length - 1]]) {
          for (const q of nodi[e].feats) {
            if (vista[q] || !feats[q].galleria) continue;
            vista[q] = 1;
            coda.push(q);
          }
        }
      }
      // A terra solo dove passa sotto: il resto scende dentro, dall'imbocco.
      for (const j of catena) {
        const f = feats[j];
        for (let k = 1; k < f.nodi.length; k++) {
          const [a, b] = [f.nodi[k - 1], f.nodi[k]];
          celle(nodi[a], nodi[b], (cella) => {
            for (const tj of griglia.get(cella) || []) {
              const [c, d, fj] = tratti[tj];
              if (feats[fj].galleria || c === a || c === b || d === a || d === b) continue;
              if (incrocia(nodi[a], nodi[b], nodi[c], nodi[d]) !== null) {
                if (tuttaGalleria(nodi[a])) sottopasso[a] = 1;
                if (tuttaGalleria(nodi[b])) sottopasso[b] = 1;
              }
            }
          });
        }
      }
    }
  }
  // Due strade attaccate a pochi metri si incrociano in pianta dove si
  // uniscono (le rampe di uno svincolo): non è uno scavalco.
  const vicine = (da, a, b) => {
    const visti = new Map([[da, 0]]);
    const coda = [da];
    while (coda.length) {
      const i = coda.shift();
      if (i === a || i === b) return true;
      for (const e of nodi[i].adj) {
        const d = visti.get(i) + e.d;
        if (d > ATTACCATE_M || (visti.has(e.to) && visti.get(e.to) <= d)) continue;
        visti.set(e.to, d);
        coda.push(e.to);
      }
    }
    return false;
  };
  // Il punto di CD (0..1) sotto AB, se le due carreggiate si sovrappongono (più vicine di [entro]).
  const sovrapposte = (A, B, C, D, entro) => {
    const sul = (P, Q, R) => {
      const ex = R.x - Q.x;
      const ey = R.y - Q.y;
      const l2 = ex * ex + ey * ey;
      const t = l2 ? Math.max(0, Math.min(1, ((P.x - Q.x) * ex + (P.y - Q.y) * ey) / l2)) : 0;
      return [Math.hypot(P.x - Q.x - ex * t, P.y - Q.y - ey * t), t];
    };
    // Tutto un tratto sopra l'altro, non solo un capo che sfiora.
    const [da, ta] = sul(A, C, D);
    const [db, tb] = sul(B, C, D);
    if (da < entro && db < entro) return (ta + tb) / 2;
    const [dc] = sul(C, A, B);
    const [dd] = sul(D, A, B);
    if (dc < entro && dd < entro) return 0.5;
    return null;
  };
  const scavalchi = [];
  for (const [a, b, fi] of tratti) {
    const f = feats[fi];
    if (!f.ponte) continue;
    const A = nodi[a];
    const B = nodi[b];
    const visti = new Set();
    celle(A, B, (k) => {
      for (const tj of griglia.get(k) || []) {
        if (visti.has(tj)) continue;
        visti.add(tj);
        const [c, d, fj] = tratti[tj];
        const g = feats[fj];
        // (Una galleria sta sotto terra: passarci sopra non chiede quota.)
        if (fj === fi || g.livello >= f.livello || g.galleria || c === a || c === b || d === a || d === b) continue;
        // Anche senza incrociarsi: le due carreggiate una sopra l'altra
        // (allo svincolo il viadotto correva sopra la rampa, quasi parallelo,
        // e restava tre metri sopra di lei).
        let u = incrocia(A, B, nodi[c], nodi[d]);
        if (u === null) {
          const sopraVicine = sovrapposte(A, B, nodi[c], nodi[d], ((f.w + g.w) / 2) * 0.5);
          if (sopraVicine === null) continue;
          u = sopraVicine;
        }
        if (vicine(a, c, d)) continue;
        scavalchi.push({ a, b, c, d, u, livello: f.livello });
      }
    });
  }
  /* Le strade affiancate che si uniscono (o si dividono): le due linee
   * corrono sovrapposte per qualche decina di metri prima del nodo, e una
   * rampa che sale stava lì quattro metri sotto la carreggiata in cui
   * entrava, una dentro l'altra. Dove si sovrappongono stanno alla stessa
   * quota (vedi `affianca`). */
  const affiancate = [];
  for (const [a, b, fi] of tratti) {
    const f = feats[fi];
    if (f.galleria) continue;
    const visti = new Set();
    celle(nodi[a], nodi[b], (k) => {
      for (const tj of griglia.get(k) || []) {
        if (visti.has(tj)) continue;
        visti.add(tj);
        const [c, d, fj] = tratti[tj];
        const g = feats[fj];
        if (fj === fi || g.galleria || (g.cls === 'rail') !== (f.cls === 'rail') || c === a || c === b || d === a || d === b) continue;
        // Collegate lì vicino (si uniscono): affiancate quasi parallele. Tutte e
        // due a terra (le due carreggiate di un viale, o un incrocio dove le
        // tessere hanno perso il nodo in comune): anche se si incrociano.
        const [A, B, C, D] = [nodi[a], nodi[b], nodi[c], nodi[d]];
        const aTerraTutte = !f.ponte && !g.ponte;
        const coseno = ((B.x - A.x) * (D.x - C.x) + (B.y - A.y) * (D.y - C.y)) / (Math.hypot(B.x - A.x, B.y - A.y) * Math.hypot(D.x - C.x, D.y - C.y) || 1);
        let u = Math.abs(coseno) < 0.75 ? null : sovrapposte(A, B, C, D, ((f.w + g.w) / 2) * 0.6);
        if (u === null && aTerraTutte) u = incrocia(A, B, C, D);
        if (u === null) continue;
        if (!aTerraTutte && !vicine(a, c, d)) continue;
        affiancate.push({ a, b, c, d, u, aTerraTutte });
      }
    });
  }
  /* I punti a terra: le rotonde (vedi `segnaRotonde`), i sottopassi e la
   * carreggiata principale dove se ne stacca una rampa (ma non se, poco più
   * in là, diventa lei un ponte: lì è la salita del viadotto). */
  const principale = (f) => (f.cls === 'motorway' || f.cls === 'trunk') && !f.rampa;
  const ponteVicino = (da) => {
    const visti = new Map([[da, 0]]);
    const coda = [da];
    while (coda.length) {
      const i = coda.shift();
      for (const e of nodi[i].adj) {
        const f = feats[e.f];
        if (!principale(f)) continue;
        if (f.ponte) return true;
        const d = visti.get(i) + e.d;
        if (d > PONTE_VICINO_M || (visti.has(e.to) && visti.get(e.to) <= d)) continue;
        visti.set(e.to, d);
        coda.push(e.to);
      }
    }
    return false;
  };
  const aTerra = nodi.map((n, i) => {
    if (sottopasso[i]) return true;
    // Un nodo di un ponte non sta a terra (dove nei dati un ponte comincia
    // proprio dove si stacca una rampa, il ponte partiva da zero).
    if (n.feats.some((fi) => feats[fi].ponte)) return false;
    if (n.rotonda) return true;
    if (n.adj.length < 3 || !n.feats.some((fi) => feats[fi].rampa)) return false;
    if (!n.feats.some((fi) => principale(feats[fi]) && !feats[fi].ponte)) return false;
    return !ponteVicino(i);
  });
  // Il tetto che i punti a terra mettono alle quote che si vorrebbero.
  const tetto = new Float64Array(N).fill(Infinity);
  {
    const mucchio = new Mucchio(false);
    for (let i = 0; i < N; i++) {
      if (aTerra[i]) {
        tetto[i] = 0;
        mucchio.push(0, i);
      }
    }
    while (mucchio.length) {
      const [x, i] = mucchio.pop();
      if (x > tetto[i]) continue;
      for (const e of nodi[i].adj) {
        const nx = x + PENDENZA_MAX * e.d;
        if (nx < tetto[e.to]) {
          tetto[e.to] = nx;
          mucchio.push(nx, e.to);
        }
      }
    }
  }
  // Quanto è lontano ogni nodo di un ponte dal capo del ponte (per i viadotti alti).
  const dalCapo = new Float64Array(N).fill(Infinity);
  {
    const mucchio = new Mucchio(false);
    for (let i = 0; i < N; i++) {
      const n = nodi[i];
      if (!n.feats.some((fi) => feats[fi].ponte)) continue;
      if (n.adj.length < 2 || n.adj.some((e) => !feats[e.f].ponte)) {
        dalCapo[i] = 0;
        mucchio.push(0, i);
      }
    }
    while (mucchio.length) {
      const [x, i] = mucchio.pop();
      if (x > dalCapo[i]) continue;
      for (const e of nodi[i].adj) {
        if (!feats[e.f].ponte) continue;
        const nx = x + e.d;
        if (nx < dalCapo[e.to]) {
          dalCapo[e.to] = nx;
          mucchio.push(nx, e.to);
        }
      }
    }
  }
  // Dove una strada è scavalcata, il ponte di sopra non la tira su (la sua
  // salita la scavalca, non ci passa): la quota che aveva prima di lui.
  const sottoAl = new Float64Array(N).fill(Infinity);
  const serve = new Float64Array(N).fill(-Infinity);
  const vorrei = new Float64Array(N).fill(-Infinity);
  const h = new Float64Array(N);
  // Le ferrovie salgono per conto loro: la salita di un ponte della ferrovia
  // non passa alle strade dal passaggio a livello (e viceversa).
  const binari = nodi.map((n) => n.feats.length > 0 && n.feats.every((fi) => feats[fi].cls === 'rail'));
  const spandi = (sorgente, pendenza, fermaATerra, rotaie) => {
    const v = new Float64Array(N).fill(-Infinity);
    const mucchio = new Mucchio(true);
    for (let i = 0; i < N; i++) {
      if (sorgente[i] > 0 && nodi[i].feats.some((fi) => (feats[fi].cls === 'rail') === rotaie)) {
        v[i] = sorgente[i];
        mucchio.push(v[i], i);
      }
    }
    while (mucchio.length) {
      const [x, i] = mucchio.pop();
      if (x < v[i]) continue;
      if (fermaATerra && aTerra[i] && !(serve[i] > 0)) continue;
      for (const e of nodi[i].adj) {
        if (sottopasso[e.to] || (feats[e.f].cls === 'rail') !== rotaie) continue;
        const nx = Math.min(x - pendenza * e.d, sottoAl[e.to]);
        if (nx > v[e.to] && nx > 0) {
          v[e.to] = nx;
          mucchio.push(nx, e.to);
        }
      }
    }
    return v;
  };
  // Il tetto in più delle strade affiancate (vedi sotto), e le sue sorgenti.
  const tettoAffiancate = new Float64Array(N).fill(Infinity);
  // La parte della quota che serve (la salita verso uno scavalco): non scende.
  const obbligata = new Float64Array(N);
  const calcola = () => {
    // Quelle che servono scendono anche più ripide (come le rampe vere),
    // quando un punto a terra non lascia spazio per la salita dolce.
    const tutte = new Float64Array(N);
    for (let i = 0; i < N; i++) tutte[i] = Math.max(serve[i], vorrei[i]);
    for (const rotaie of [false, true]) {
      const vs = spandi(serve, PENDENZA_MAX, false, rotaie);
      const vv = spandi(tutte, PENDENZA, true, rotaie);
      // Un nodo con una strada sta alla quota della strada (il passaggio a livello).
      for (let i = 0; i < N; i++) {
        if (binari[i] !== rotaie) continue;
        h[i] = sottopasso[i] ? 0 : Math.max(0, vs[i], Math.min(vv[i], tetto[i], tettoAffiancate[i]));
        obbligata[i] = sottopasso[i] ? 0 : Math.max(0, vs[i]);
      }
    }
  };
  /* Le affiancate alla stessa quota: prima si alza quella più bassa (se
   * niente la tiene a terra); se non si può, quella più alta scende verso
   * di lei (al più del PENDENZA_MAX), se la sua quota non serve. */
  const affianca = () => {
    let cambiate = 0;
    const altra = (p, i) => (i === p.a || i === p.b ? h[p.c] + (h[p.d] - h[p.c]) * p.u : h[p.a] + (h[p.b] - h[p.a]) * 0.5);
    for (const p of affiancate) {
      // Due strade a terra: non si alza quella bassa (il viale salirebbe
      // tutto); scende quella che la salita di un ponte ha tirato su. Ma se
      // quella in alto ci deve stare (sale verso un ponte che scavalca),
      // sale l'altra: la rampa si stacca alla quota della carreggiata.
      if (p.aTerraTutte) {
        const ha = (h[p.a] + h[p.b]) / 2;
        const hb = h[p.c] + (h[p.d] - h[p.c]) * p.u;
        const [alti, bassi] = ha > hb ? [[p.a, p.b], [p.c, p.d]] : [[p.c, p.d], [p.a, p.b]];
        if (!alti.every((i) => obbligata[i] > h[i] - 0.3)) continue;
        for (const i of bassi) {
          const q = Math.max(ha, hb);
          if (q > h[i] + 0.3 && q <= tetto[i] && q > vorrei[i] + 0.01) {
            vorrei[i] = q;
            cambiate++;
          }
        }
        continue;
      }
      const qui = altra(p, p.a);
      for (const i of [p.a, p.b]) {
        if (qui > h[i] + 0.3 && qui <= tetto[i] && qui > vorrei[i] + 0.01) {
          vorrei[i] = qui;
          cambiate++;
        }
      }
      const la = altra(p, p.c);
      for (const i of [p.c, p.d]) {
        if (la > h[i] + 0.3 && la <= tetto[i] && la > vorrei[i] + 0.01) {
          vorrei[i] = la;
          cambiate++;
        }
      }
    }
    if (cambiate) calcola();
    // Dove la più bassa non è potuta salire, scende la più alta.
    const sorgenti = new Float64Array(N).fill(Infinity);
    let scese = 0;
    for (const p of affiancate) {
      const hb = h[p.c] + (h[p.d] - h[p.c]) * p.u;
      const ha = (h[p.a] + h[p.b]) / 2;
      const [alti, basso] = ha > hb ? [[p.a, p.b], hb] : [[p.c, p.d], ha];
      if (Math.abs(ha - hb) < 0.5) continue;
      for (const i of alti) {
        if (nodi[i].anelloInQuota) continue;
        if (serve[i] < basso + 0.5 && basso < sorgenti[i]) {
          sorgenti[i] = basso;
          scese++;
        }
      }
    }
    if (!scese) return cambiate;
    const mucchio = new Mucchio(false);
    for (let i = 0; i < N; i++) {
      if (sorgenti[i] < tettoAffiancate[i]) {
        tettoAffiancate[i] = sorgenti[i];
        mucchio.push(sorgenti[i], i);
      }
    }
    while (mucchio.length) {
      const [x, i] = mucchio.pop();
      if (x > tettoAffiancate[i]) continue;
      for (const e of nodi[i].adj) {
        const nx = x + PENDENZA_MAX * e.d;
        if (nx < tettoAffiancate[e.to]) {
          tettoAffiancate[e.to] = nx;
          mucchio.push(nx, e.to);
        }
      }
    }
    calcola();
    return cambiate + scese;
  };
  // Fra due punti alti un ponte non scende; una rotonda con un pezzo di ponte resta in piano.
  const inPiano = () => {
    let alzati = 0;
    const alza = (i, p) => {
      if (p > vorrei[i] + 0.01 && p > h[i] + 0.01) {
        vorrei[i] = p;
        alzati++;
      }
    };
    for (const f of feats) {
      if (!f.ponte) continue;
      const n = f.nodi.length;
      const prima = new Float64Array(n);
      const dopo = new Float64Array(n);
      for (let k = 0; k < n; k++) prima[k] = Math.max(k ? prima[k - 1] : 0, h[f.nodi[k]]);
      for (let k = n - 1; k >= 0; k--) dopo[k] = Math.max(k < n - 1 ? dopo[k + 1] : 0, h[f.nodi[k]]);
      for (let k = 0; k < n; k++) alza(f.nodi[k], Math.min(prima[k], dopo[k]));
    }
    for (let i = 0; i < N; i++) {
      const anello = nodi[i].anelloInQuota;
      if (!anello || i !== anello[0]) continue;
      const p = Math.max(...anello.map((j) => h[j]));
      for (const j of anello) alza(j, p);
    }
    return alzati;
  };
  const livelloMax = feats.reduce((m, f) => Math.max(m, f.livello), 0);
  for (let giro = 0; giro < 3; giro++) {
    let cambiati = 0;
    for (let L = 1; L <= livelloMax; L++) {
      for (const f of feats) {
        if (f.livello !== L) continue;
        for (const i of f.nodi) {
          if (tuttaGalleria(nodi[i])) continue;
          const alta = f.altezza ? Math.min(f.altezza, ALTEZZA_LIVELLO + PENDENZA * dalCapo[i]) : 0;
          vorrei[i] = Math.max(vorrei[i], ALTEZZA_LIVELLO, alta);
        }
      }
      if (giro === 0) {
        // (Con le quote che il livello vuole già messe: la rampa che parte dal
        // ponte accanto sale con lui; quello che si ferma è la rincorsa.)
        calcola();
        for (const s of scavalchi) {
          if (s.livello !== L) continue;
          sottoAl[s.c] = Math.min(sottoAl[s.c], Math.max(h[s.c], serve[s.c]));
          sottoAl[s.d] = Math.min(sottoAl[s.d], Math.max(h[s.d], serve[s.d]));
        }
      }
      for (const s of scavalchi) {
        if (s.livello !== L) continue;
        const sopra = h[s.c] + (h[s.d] - h[s.c]) * s.u + SCAVALCO_M;
        for (const i of [s.a, s.b]) {
          if (sopra > serve[i] + 0.05) {
            serve[i] = sopra;
            cambiati++;
          }
        }
      }
      calcola();
      if (inPiano()) calcola();
    }
    if (!cambiati) break;
  }
  for (let k = 0; k < 2; k++) if (!affianca()) break;
  // Un poco di levigatura per raccordi più morbidi (non dove la quota serve).
  for (let it = 0; it < 6; it++) {
    const nh = Float64Array.from(h);
    for (let i = 0; i < N; i++) {
      const n = nodi[i];
      if (n.adj.length !== 2 || h[i] < 0.05 || sottopasso[i] || h[i] <= Math.max(serve[i], Math.min(vorrei[i], tetto[i])) + 0.01) continue;
      nh[i] = (h[i] * 2 + h[n.adj[0].to] + h[n.adj[1].to]) / 4;
    }
    h.set(nh);
  }
  /* Ultima rifinitura: nessun tratto più ripido del PENDENZA_MAX. Dove
   * resta uno scalino (due quote che si vogliono vicine), i due capi si
   * vengono incontro; senza scendere sotto la quota che serve, né salire
   * sopra quella di una strada scavalcata, né muovere i sottopassi. */
  const limita = (forte = false) => {
    for (let giro = 0; giro < 400; giro++) {
      let troppo = 0;
      for (let i = 0; i < N; i++) {
        for (const e of nodi[i].adj) {
          const j = e.to;
          if (j < i) continue;
          const eccesso = Math.abs(h[i] - h[j]) - PENDENZA_MAX * e.d;
          if (eccesso <= 0.01) continue;
          const [alto, basso] = h[i] > h[j] ? [i, j] : [j, i];
          // Quanto può scendere quello alto e salire quello basso.
          // (Forte: l'ultima volta, se lo scalino resta, cedono anche le quote che servono.)
          const giu = sottopasso[alto] ? 0 : Math.max(0, h[alto] - (forte ? 0 : Math.max(0, serve[alto])));
          const su = sottopasso[basso] ? 0 : forte ? Infinity : Math.max(0, sottoAl[basso] - h[basso]);
          if (giu + su < 0.01) continue;
          troppo++;
          const quanto = Math.min(eccesso, giu + su);
          const g = su === Infinity ? quanto / 2 : (quanto * giu) / (giu + su || 1);
          h[alto] -= Math.min(giu, g);
          h[basso] += Math.min(su, quanto - Math.min(giu, g));
        }
      }
      if (!troppo) break;
    }
  };

  /* Il risolutore: le carreggiate ancora una dentro l'altra (un tratto a
   * meno di metà carreggiata da un altro, a una quota fra 0,6 e 4,6 m di
   * differenza: né la stessa strada né una che passa sopra), cercate come le
   * cerca la verifica (collaudo/verifica-strade.mjs). Un ponte troppo basso
   * sopra un'altra strada sale; due strade affiancate o che si incrociano a
   * terra vanno alla stessa quota. Poi di nuovo tutto, al più quattro volte. */
  const contrasti = () => {
    const out = [];
    for (const [a, b, fi] of tratti) {
      const f = feats[fi];
      if (f.galleria || f.cls === 'rail') continue;
      const A = nodi[a];
      const B = nodi[b];
      const mx = (A.x + B.x) / 2;
      const my = (A.y + B.y) / 2;
      const hm = (h[a] + h[b]) / 2;
      const visti = new Set();
      celle({ x: mx - 6, y: my - 6 }, { x: mx + 6, y: my + 6 }, (k) => {
        for (const tj of griglia.get(k) || []) {
          if (visti.has(tj)) continue;
          visti.add(tj);
          const [c, d, fj] = tratti[tj];
          const g = feats[fj];
          if (fj === fi || g.galleria || g.cls === 'rail' || c === a || c === b || d === a || d === b) continue;
          const C = nodi[c];
          const D = nodi[d];
          const ex = D.x - C.x;
          const ey = D.y - C.y;
          const l2 = ex * ex + ey * ey;
          const u = l2 ? Math.max(0, Math.min(1, ((mx - C.x) * ex + (my - C.y) * ey) / l2)) : 0;
          if (Math.hypot(mx - C.x - ex * u, my - C.y - ey * u) >= Math.min(f.w, g.w) / 2) continue;
          const hc = h[c] + (h[d] - h[c]) * u;
          const dz = Math.abs(hm - hc);
          if (dz <= 0.6 || dz >= 4.6) continue;
          out.push({ a, b, c, d, u, fi, fj, sopra: hm > hc });
        }
      });
    }
    return out;
  };
  const abbassate = new Float64Array(N).fill(Infinity);
  const risolvi = () => {
  for (let giro = 0; giro < 4; giro++) {
    const cc = contrasti();
    if (!cc.length) break;
    for (const p of cc) {
      const [su, giu] = p.sopra ? [feats[p.fi], feats[p.fj]] : [feats[p.fj], feats[p.fi]];
      const [sa, sb] = p.sopra ? [p.a, p.b] : [p.c, p.d];
      // (Due strade attaccate lì vicino si stanno unendo: alla stessa quota.)
      if (su.ponte && (su.livello > giu.livello || !giu.ponte) && !vicine(sa, p.sopra ? p.c : p.a, p.sopra ? p.d : p.b)) {
        // Il ponte sopra: almeno la luce sopra quella di sotto. Prima scende
        // quella di sotto, se la sua quota non serve; se no sale il ponte.
        const [lc, ld, lu] = p.sopra ? [p.c, p.d, p.u] : [p.a, p.b, 0.5];
        const hSu = (h[sa] + h[sb]) / 2;
        const voluta = hSu - SCAVALCO_M;
        if (voluta >= 0 && [lc, ld].every((i) => obbligata[i] <= voluta + 0.05 && !sottopasso[i])) {
          for (const i of [lc, ld]) if (voluta < abbassate[i]) abbassate[i] = voluta;
        } else {
          const sopra = h[lc] + (h[ld] - h[lc]) * lu + SCAVALCO_M;
          for (const i of [sa, sb]) if (sopra > serve[i]) serve[i] = sopra;
          sottoAl[lc] = Math.min(sottoAl[lc], h[lc]);
          sottoAl[ld] = Math.min(sottoAl[ld], h[ld]);
        }
      } else {
        affiancate.push({ a: p.a, b: p.b, c: p.c, d: p.d, u: p.u, aTerraTutte: !feats[p.fi].ponte && !feats[p.fj].ponte });
      }
    }
    // Le strade da abbassare: un tetto in più, che sale del PENDENZA_MAX.
    {
      const mucchio = new Mucchio(false);
      for (let i = 0; i < N; i++) {
        if (abbassate[i] < tettoAffiancate[i]) {
          tettoAffiancate[i] = abbassate[i];
          mucchio.push(abbassate[i], i);
        }
      }
      while (mucchio.length) {
        const [x, i] = mucchio.pop();
        if (x > tettoAffiancate[i]) continue;
        for (const e of nodi[i].adj) {
          const nx = x + PENDENZA_MAX * e.d;
          if (nx < tettoAffiancate[e.to]) {
            tettoAffiancate[e.to] = nx;
            mucchio.push(nx, e.to);
          }
        }
      }
    }
    calcola();
    if (inPiano()) calcola();
    for (let k = 0; k < 2; k++) if (!affianca()) break;
    limita();
  }
  };
  // Il risolutore e lo scalino a turno: quello che uno sistema l'altro può
  // guastarlo, finché non resta niente (o quasi: tre volte).
  for (let volta = 0; volta < 3; volta++) {
    risolvi();
    limita();
    limita(true);
    if (!contrasti().length) break;
  }
  for (let i = 0; i < N; i++) nodi[i].h = h[i];
  return scavalchi.length;
}
