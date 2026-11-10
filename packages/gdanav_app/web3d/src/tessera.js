// Una tessera della scena 3D: dalle tessere vettoriali (quella di mezzo e le
// otto intorno, per le rampe che passano il bordo) alle geometrie pronte da
// disegnare. Gira nel lavoratore, senza three.js: dentro solo numeri.
//
// Cosa esce: le strade (nastri d'asfalto per tipo, con le righe nella
// trama), i ponti (parapetti, travi, muri delle rampe), i piloni, gli
// edifici con le facciate, gli alberi, i lampioni, le ombre stese a terra e
// i segmenti delle strade con la loro quota (per mettere il percorso, il
// traffico e l'auto all'altezza giusta).

import { generatore, mescola, semeTessera } from './caso.js';
import { Costruttore, matrice } from './costruttore.js';
import { CLASSI_STRADE, SPESSORE_IMPALCATO, altezzaViadotto, grafoStrade, uniscIBordi } from './elevazione.js';
import { ESTENSIONE, sistemaTessera } from './geo.js';
import {
  anelliPoligoni,
  area,
  distanzaSegmento,
  puntoDentroPoligono,
  ritagliaAnello,
  ritagliaLinea,
} from './ritaglio.js';
import { CHIOME, FACCIATE, TETTI, rgb, spostamentoOmbra } from './tavolozza.js';
import earcut from 'earcut';

/** I tipi di nastro d'asfalto (ognuno con la sua trama di righe). */
export const TIPI_STRADA = ['motorway', 'trunk', 'ramp', 'primary1', 'primary2', 'tertiary', 'plain', 'rail'];

/**
 * Tutti i nastri: i tipi a terra, gli stessi sui ponti (`-ponte`, un asfalto
 * più chiaro, che l'impalcato si distingua dalle strade sotto) e le gallerie.
 */
export const NASTRI = [...TIPI_STRADA, ...TIPI_STRADA.map((t) => t + '-ponte'), 'galleria'];

/** Quanto sotto passa una galleria (sopra c'è la strada che la copre). */
const SOPRA_GALLERIA = 0.06;

/** Oltre questa quota (m) una strada non segnata come ponte si disegna come un viadotto. */
const ALTO_COME_PONTE = 6.5;

/** Metri di strada per una ripetizione della trama. */
export const PERIODO_STRADA = 12;
export const PIANO = 3.2;
export const CAMPATA = 3.4;

/** Quanti modelli di facciata ha ogni tipo di edificio (vedi `trameFacciata`). */
export const VARIANTI_FACCIATA = { residenziale: 4, uffici: 2, industria: 1 };
/** Le facciate, una geometria e un materiale l'una: «residenziale-0» … */
export const STILI_FACCIATA = Object.entries(VARIANTI_FACCIATA).flatMap(([s, n]) => Array.from({ length: n }, (_, i) => `${s}-${i}`));

/** Quanto sopra il terreno sta ogni classe di strada (per non litigare col suolo). */
const SOPRA = { motorway: 0.24, trunk: 0.23, primary: 0.21, secondary: 0.2, tertiary: 0.18, minor: 0.16, service: 0.14, rail: 0.12 };

/** I limiti di una tessera, per non chiedere troppo al telefono.
 *
 * «Qui è pieno di case.» Una tessera di paese (Carinaro, 1631 edifici)
 * ridotta ne teneva 736: le case piccole restavano fuori appena la tessera non
 * era quella dell'auto. Con 100 000 ne entrano quasi tutte; il tetto di tutta
 * la scena (`BUDGET.triangoli`) resta quello, e se non ci si sta si lasciano
 * le tessere più lontane. */
export const LIMITI = {
  pieno: { alberi: 1800, triangoliEdifici: 200000, lampioni: 400, margine: 450 },
  ridotto: { alberi: 0, triangoliEdifici: 100000, lampioni: 0, margine: 250 },
};

const tipoDi = (f) =>
  f.cls === 'rail'
    ? 'rail'
    : f.rampa && (f.cls === 'motorway' || f.cls === 'trunk')
      ? 'ramp'
      : f.cls === 'motorway'
        ? f.senso
          ? 'motorway'
          : 'primary2'
        : f.cls === 'trunk'
          ? f.senso
            ? 'trunk'
            : 'primary2'
          : f.cls === 'primary' || f.cls === 'secondary'
            ? f.senso
              ? 'primary1'
              : 'primary2'
            : f.cls === 'tertiary'
              ? 'tertiary'
              : 'plain';

/** Le classi delle strade nei segmenti: per sapere quali reggono il percorso. */
export const CODICI_CLASSE = { motorway: 1, trunk: 2, primary: 3, secondary: 4, tertiary: 5, minor: 6, service: 7, rail: 8 };

/**
 * Fa la tessera z/x/y. [livelli]: le tessere decodificate, per spostamento
 * `"dx,dy"` (da -1 a 1; quella di mezzo è "0,0"); [dettaglio]: «pieno» o
 * «ridotto» (lontano: niente alberi né lampioni, meno edifici).
 */
export function costruisciTessera({ z, x, y, livelli, dettaglio = 'pieno', limiti }) {
  const lim = { ...LIMITI[dettaglio], ...limiti };
  const sys = sistemaTessera(z, x, y);
  const meta = sys.lato / 2;
  const t0 = Date.now();
  const centro = livelli['0,0'];
  if (!centro) throw new Error('manca la tessera di mezzo');
  const pxPerMetro = ESTENSIONE / sys.lato;
  const marginePx = lim.margine * pxPerMetro;

  // ── Le strade, da questa tessera e dalle vicine (vicino al bordo) ──────
  const strade = [];
  for (const [chiaveOff, layers] of Object.entries(livelli)) {
    const [dx, dy] = chiaveOff.split(',').map(Number);
    const T = layers?.transportation;
    if (!T) continue;
    const ox = (x + dx) * ESTENSIONE;
    const oy = (y + dy) * ESTENSIONE;
    // Il riquadro della tessera di mezzo, allargato, nei pixel di questa.
    const minx = -dx * ESTENSIONE - marginePx;
    const maxx = (1 - dx) * ESTENSIONE + marginePx;
    const miny = -dy * ESTENSIONE - marginePx;
    const maxy = (1 - dy) * ESTENSIONE + marginePx;
    for (let i = 0; i < T.length; i++) {
      const f = T.feature(i);
      const p = f.properties;
      if (f.type !== 2 || !CLASSI_STRADE.has(p.class)) continue;
      for (const linea of f.loadGeometry()) {
        const pts = linea.map((q) => [q.x, q.y]);
        if (dx || dy) {
          let vicino = false;
          for (const [qx, qy] of pts) {
            if (qx >= minx && qx <= maxx && qy >= miny && qy <= maxy) {
              vicino = true;
              break;
            }
          }
          if (!vicino) continue;
        }
        for (const pezzo of ritagliaLinea(pts, 0, 0, ESTENSIONE, ESTENSIONE)) {
          strade.push({ p, g: pezzo.map(([px, py]) => [ox + px, oy + py]) });
        }
      }
    }
  }
  uniscIBordi(strade);
  segnaViadotti(livelli, x, y, strade, sys);
  const { nodi, feats } = grafoStrade(strade, sys.metri);
  const tGrafo = Date.now() - t0;

  // ── I nastri delle strade ─────────────────────────────────────────────
  // Anche le gallerie: un nastro scuro con gli imbocchi (non più niente, col
  // percorso che sembrava passare sopra la strada).
  const visibili = feats.filter(
    (f) => !(f.galleria && f.cls === 'rail') && !(f.cls === 'service' && ['parking_aisle', 'driveway', 'drive-through'].includes(f.sv)),
  );
  const ek = (p) => Math.round(p[0] * 10) + ',' + Math.round(p[1] * 10);
  const linee = visibili.map((f) => f.nodi.map((i) => [nodi[i].x, nodi[i].y, nodi[i].h]));
  const estremi = new Map();
  linee.forEach((pts, i) => {
    if (pts.length < 2) return;
    for (const e of [0, 1]) {
      const k = ek(e ? pts[pts.length - 1] : pts[0]);
      if (!estremi.has(k)) estremi.set(k, []);
      estremi.get(k).push([i, e]);
    }
  });
  const versoFuori = (pts, e) => {
    const a = e ? pts[pts.length - 2] : pts[1];
    const b = e ? pts[pts.length - 1] : pts[0];
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const l = Math.hypot(dx, dy) || 1;
    return [dx / l, dy / l];
  };
  // Le strade a terra, per non piantare piloni in mezzo.
  const GRIGLIA = 25;
  const aTerra = new Map();
  linee.forEach((pts, i) => {
    for (let k = 1; k < pts.length; k++) {
      const a = pts[k - 1];
      const b = pts[k];
      if (a[2] > 0.6 && b[2] > 0.6) continue;
      for (const q of [a, b]) {
        const key = Math.floor(q[0] / GRIGLIA) + ',' + Math.floor(q[1] / GRIGLIA);
        if (!aTerra.has(key)) aTerra.set(key, []);
        aTerra.get(key).push([a, b, visibili[i].w / 2]);
      }
    }
  });
  const suStradaATerra = (px, py, margine) => {
    for (let ax = -1; ax <= 1; ax++) {
      for (let ay = -1; ay <= 1; ay++) {
        for (const [a, b, hw] of aTerra.get(Math.floor(px / GRIGLIA) + ax + ',' + (Math.floor(py / GRIGLIA) + ay)) || []) {
          if (distanzaSegmento(px, py, a[0], a[1], b[0], b[1]) < hw + margine) return true;
        }
      }
    }
    return false;
  };
  // Gli svincoli in quota: lì niente parapetti in mezzo alla biforcazione.
  const grado = new Map();
  linee.forEach((pts, i) => {
    const f = visibili[i];
    if (['service', 'minor', 'rail'].includes(f.cls)) return;
    pts.forEach((p, k) => {
      const key = ek(p);
      grado.set(key, (grado.get(key) || 0) + (k === 0 || k === pts.length - 1 ? (f.cucita ? 3 : 1) : 2));
    });
  });
  const GS = 50;
  const svincoli = new Map();
  linee.forEach((pts) => {
    for (const p of pts) {
      if ((grado.get(ek(p)) ?? 0) >= 3 && p[2] > 0.3) {
        const key = Math.floor(p[0] / GS) + ',' + Math.floor(p[1] / GS);
        if (!svincoli.has(key)) svincoli.set(key, []);
        svincoli.get(key).push(p);
      }
    }
  });
  const vicinoASvincolo = (px, py, r) => {
    for (let ax = -1; ax <= 1; ax++) {
      for (let ay = -1; ay <= 1; ay++) {
        for (const p of svincoli.get(Math.floor(px / GS) + ax + ',' + (Math.floor(py / GS) + ay)) || []) {
          if (Math.hypot(p[0] - px, p[1] - py) < r) return true;
        }
      }
    }
    return false;
  };
  const dentro = (px, py, m = 0) => px >= -meta - m && px <= meta + m && py >= -meta - m && py <= meta + m;

  const nastri = Object.fromEntries(NASTRI.map((t) => [t, new Costruttore({ uv: true })]));
  const opere = new Costruttore({ colori: true });
  const ombre = new Costruttore();
  // Sotto i ponti un'ombra in più, morbida: un alone largo e il nucleo
  // (più in alto di un soffio, così dove si sovrappongono scurisce due volte).
  const ombrePonti = new Costruttore();
  const [sox, soy] = spostamentoOmbra();
  const piloni = [];
  const lampioni = [];
  const segmenti = [];
  // Il cemento: un colore di giorno e uno di notte, più scuro in basso (gli
  // angoli in ombra), più chiaro sul cordolo in cima all'impalcato.
  const tinta = (c, k) => c.map((v) => Math.min(255, Math.round(v * k)));
  const CEM = [rgb('#d6d3cc'), rgb('#59606c')];
  // Il fianco dell'impalcato: il cordolo in cima chiaro, la trave sotto più
  // scura, il ventre scurissimo; così il ponte ha uno spessore che si legge.
  const CORDOLO = [rgb('#f6f5f1'), rgb('#86909f')];
  const TRAVE = [rgb('#7f7b74'), rgb('#323742')];
  const SOTTO = [rgb('#5f5c57'), rgb('#1f2229')];
  // Il corrimano scuro sopra il parapetto: una riga netta lungo il bordo.
  const CORRIMANO = [rgb('#5d636d'), rgb('#232832')];
  /** Quattro colori per un quadrilatero a-b (in basso), c-d (in alto). */
  const sfuma = (c, basso, alto) => [
    [tinta(c[0], basso), tinta(c[0], basso), tinta(c[0], alto), tinta(c[0], alto)],
    [tinta(c[1], basso), tinta(c[1], basso), tinta(c[1], alto), tinta(c[1], alto)],
  ];
  const cCemento = CEM;
  const cSotto = SOTTO;
  const cBuio = [rgb('#15181e'), rgb('#07080b')];
  /** Una scatola (cinque facce, senza il fondo) in [opere]. */
  const scatola = (cx, cy, z0, z1, ux, uy, lu, lv, colore) => {
    const vx = -uy;
    const vy = ux;
    const P = (a, b, z) => [cx + ux * a * lu + vx * b * lv, cy + uy * a * lu + vy * b * lv, z];
    // Ogni faccia con la sua normale verso fuori.
    const facce = [
      [[-1, -1], [1, -1], [uy, -ux]],
      [[1, -1], [1, 1], [ux, uy]],
      [[1, 1], [-1, 1], [-uy, ux]],
      [[-1, 1], [-1, -1], [-ux, -uy]],
    ];
    for (const [[a0, b0], [a1, b1], nn] of facce) {
      opere.quad(P(a0, b0, z0), P(a1, b1, z0), P(a1, b1, z1), P(a0, b0, z1), [nn[0], nn[1], 0], ...sfuma(colore, 0.7, 1));
    }
    opere.quad(P(-1, -1, z1), P(1, -1, z1), P(1, 1, z1), P(-1, 1, z1), [0, 0, 1], ...colore);
  };

  linee.forEach((tutta, fi) => {
    const f = visibili[fi];
    const n0 = tutta.length;
    if (n0 < 2) return;
    // Le tangenti sulla strada intera, agli estremi guardando quella che continua.
    const tang = tutta.map((p, k) => {
      let dx;
      let dy;
      if (k === 0 || k === n0 - 1) {
        const e = k === n0 - 1 ? 1 : 0;
        let [ox, oy] = versoFuori(tutta, e);
        let meglio = null;
        let bd = 0.5;
        for (const [j, e2] of estremi.get(ek(p)) || []) {
          if (j === fi) continue;
          if (Math.abs(visibili[j].w - f.w) > 4) continue;
          const [qx, qy] = versoFuori(linee[j], e2);
          const d = -(ox * qx + oy * qy);
          if (d > bd) {
            bd = d;
            meglio = [-qx, -qy];
          }
        }
        if (meglio) {
          ox = (ox + meglio[0]) / 2;
          oy = (oy + meglio[1]) / 2;
        }
        dx = e ? ox : -ox;
        dy = e ? oy : -oy;
      } else {
        dx = tutta[k + 1][0] - tutta[k - 1][0];
        dy = tutta[k + 1][1] - tutta[k - 1][1];
      }
      const l = Math.hypot(dx, dy) || 1;
      return [dx / l, dy / l];
    });
    let acc = 0;
    const lungo = [0];
    for (let k = 1; k < n0; k++) {
      acc += Math.hypot(tutta[k][0] - tutta[k - 1][0], tutta[k][1] - tutta[k - 1][1]);
      lungo.push(acc);
    }
    // [x, y, h, tx, ty, s]: si taglia sulla tessera e tutto si interpola.
    const ricca = tutta.map((p, k) => [p[0], p[1], p[2], tang[k][0], tang[k][1], lungo[k]]);
    const semePezzo = mescola(Math.round(tutta[0][0] * 7), Math.round(tutta[0][1] * 7));
    const zs = f.galleria ? SOPRA_GALLERIA : (SOPRA[f.cls] ?? 0.15) + (fi % 7) * 0.002;

    // I segmenti con le quote, un poco oltre il bordo (per il percorso).
    if (f.cls !== 'rail') {
      const codice = CODICI_CLASSE[f.cls] ?? 7;
      for (const pezzo of ritagliaLinea(ricca, -meta - 40, -meta - 40, meta + 40, meta + 40)) {
        for (let k = 1; k < pezzo.length; k++) {
          const a = pezzo[k - 1];
          const b = pezzo[k];
          segmenti.push(a[0], a[1], a[2] + zs, b[0], b[1], b[2] + zs, f.w, codice + (f.rampa ? 16 : 0) + (f.ponte ? 32 : 0) + (f.galleria ? 64 : 0));
        }
      }
    }

    // Gli imbocchi delle gallerie, dove la galleria incontra la strada aperta:
    // due spalle, l'architrave, il buio dentro e un pezzo di volta.
    if (f.galleria) {
      for (const e of [0, n0 - 1]) {
        const nodo = nodi[f.nodi[e]];
        if (!nodo.feats.some((j) => !feats[j].galleria) || !dentro(nodo.x, nodo.y)) continue;
        const [ux, uy] = versoFuori(tutta, e);
        const vx = -uy;
        const vy = ux;
        const hw = f.w / 2;
        const h0 = nodo.h;
        for (const lato of [1, -1]) scatola(nodo.x + vx * (hw + 0.45) * lato, nodo.y + vy * (hw + 0.45) * lato, h0, h0 + 5.2, ux, uy, 0.5, 0.45, cCemento);
        scatola(nodo.x, nodo.y, h0 + 4.4, h0 + 5.4, ux, uy, 0.5, hw + 0.9, cCemento);
        scatola(nodo.x - ux * 4.6, nodo.y - uy * 4.6, h0 + 4.6, h0 + 5.4, ux, uy, 4.1, hw + 0.9, cCemento);
        const mx = nodo.x - ux * 0.7;
        const my = nodo.y - uy * 0.7;
        opere.quad(
          [mx + vx * hw, my + vy * hw, h0],
          [mx - vx * hw, my - vy * hw, h0],
          [mx - vx * hw, my - vy * hw, h0 + 4.4],
          [mx + vx * hw, my + vy * hw, h0 + 4.4],
          [ux, uy, 0],
          ...cBuio,
        );
      }
    }

    for (const pezzo of ritagliaLinea(ricca, -meta, -meta, meta, meta)) {
      const n = pezzo.length;
      const hw = f.w / 2;
      const gb = nastri[f.galleria ? 'galleria' : tipoDi(f) + (f.ponte ? '-ponte' : '')];
      const L = [];
      const R = [];
      for (let k = 0; k < n; k++) {
        let tx = pezzo[k][3];
        let ty = pezzo[k][4];
        const tl = Math.hypot(tx, ty) || 1;
        tx /= tl;
        ty /= tl;
        pezzo[k][3] = tx;
        pezzo[k][4] = ty;
        const nx = -ty;
        const ny = tx;
        let m = 1;
        if (k > 0 && k < n - 1) {
          const sx = pezzo[k + 1][0] - pezzo[k][0];
          const sy = pezzo[k + 1][1] - pezzo[k][1];
          const sl = Math.hypot(sx, sy) || 1;
          m = 1 / Math.max(0.5, Math.abs((-sy / sl) * nx + (sx / sl) * ny));
        }
        const zz = pezzo[k][2] + zs;
        const v = pezzo[k][5] / PERIODO_STRADA;
        L.push([pezzo[k][0] + nx * hw * m, pezzo[k][1] + ny * hw * m, zz, 0, v]);
        R.push([pezzo[k][0] - nx * hw * m, pezzo[k][1] - ny * hw * m, zz, 1, v]);
      }
      // Il nastro: due vertici per punto, a indici.
      const base = gb.vertici;
      for (let k = 0; k < n; k++) {
        gb.v(L[k][0], L[k][1], L[k][2], 0, 0, 1, 0, L[k][4]);
        gb.v(R[k][0], R[k][1], R[k][2], 0, 0, 1, 1, R[k][4]);
      }
      // Il verso dei triangoli: come `quad` del prototipo (normale in su).
      for (let k = 1; k < n; k++) {
        const l0 = base + 2 * (k - 1);
        const r0 = l0 + 1;
        const l1 = base + 2 * k;
        const r1 = l1 + 1;
        const ux = R[k - 1][0] - L[k - 1][0];
        const uy = R[k - 1][1] - L[k - 1][1];
        const vx = R[k][0] - L[k - 1][0];
        const vy = R[k][1] - L[k - 1][1];
        if (ux * vy - uy * vx >= 0) {
          gb.tri(l0, r0, r1);
          gb.tri(l0, r1, l1);
        } else {
          gb.tri(l0, r1, r0);
          gb.tri(l0, l1, r1);
        }
      }
      if (f.galleria || (f.cls === 'rail' && !f.ponte)) continue;

      // In quota: parapetti, travi, muri; e l'ombra sul terreno.
      for (let k = 1; k < n; k++) {
        const ha = pezzo[k - 1][2];
        const hb = pezzo[k][2];
        if (ha < 0.35 && hb < 0.35) continue;
        // Una strada non segnata come ponte ma alta (la salita di un viadotto
        // alto): da qui in su è un viadotto anche lei, non un muro.
        const comePonte = f.ponte || (ha > ALTO_COME_PONTE && hb > ALTO_COME_PONTE);
        // L'ombra dell'impalcato.
        {
          const a = L[k - 1];
          const b = L[k];
          const c = R[k];
          const d = R[k - 1];
          const ha2 = a[2];
          const hb2 = b[2];
          ombre.quad(
            [a[0] + sox * ha2, a[1] + soy * ha2, 0],
            [b[0] + sox * hb2, b[1] + soy * hb2, 0],
            [c[0] + sox * hb2, c[1] + soy * hb2, 0],
            [d[0] + sox * ha2, d[1] + soy * ha2, 0],
            [0, 0, 1],
          );
          // E sotto, a piombo: sotto un ponte è sempre più scuro.
          if (comePonte && ha > 2.5 && hb > 2.5) {
            ombre.quad([a[0], a[1], 0], [b[0], b[1], 0], [c[0], c[1], 0], [d[0], d[1], 0], [0, 0, 1]);
            const nl0 = [-pezzo[k - 1][4], pezzo[k - 1][3]];
            const nl1 = [-pezzo[k][4], pezzo[k][3]];
            const largo = (P0, nn, d2, z) => [P0[0] + nn[0] * d2, P0[1] + nn[1] * d2, z];
            ombrePonti.quad(largo(a, nl0, 2.6, 0), largo(b, nl1, 2.6, 0), largo(c, nl1, -2.6, 0), largo(d, nl0, -2.6, 0), [0, 0, 1]);
            ombrePonti.quad(largo(a, nl0, 0.6, 0.04), largo(b, nl1, 0.6, 0.04), largo(c, nl1, -0.6, 0.04), largo(d, nl0, -0.6, 0.04), [0, 0, 1]);
          }
        }
        for (const lato of [1, -1]) {
          const A = lato > 0 ? L : R;
          const on0 = [-pezzo[k - 1][4] * lato, pezzo[k - 1][3] * lato];
          const on1 = [-pezzo[k][4] * lato, pezzo[k][3] * lato];
          const fuori = (P0, on, d) => [P0[0] + on[0] * d, P0[1] + on[1] * d];
          const a = A[k - 1];
          const b = A[k];
          const nrm = [(on0[0] + on1[0]) / 2, (on0[1] + on1[1]) / 2, 0];
          const inr = [-nrm[0], -nrm[1], 0];
          if (f.cls !== 'rail' && !f.cucita && !vicinoASvincolo((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 40)) {
            // Il parapetto: cemento chiaro, e sopra il corrimano scuro.
            const ph = f.ponte ? 1.05 : 0.9;
            const pr = 0.16;
            const a0 = fuori(a, on0, 0.12);
            const b0 = fuori(b, on1, 0.12);
            const a1 = fuori(a, on0, -0.23);
            const b1 = fuori(b, on1, -0.23);
            opere.quad([a0[0], a0[1], a[2] - 0.1], [b0[0], b0[1], b[2] - 0.1], [b0[0], b0[1], b[2] + ph - pr], [a0[0], a0[1], a[2] + ph - pr], nrm, ...sfuma(cCemento, 0.86, 1.06));
            opere.quad([a0[0], a0[1], a[2] + ph - pr], [b0[0], b0[1], b[2] + ph - pr], [b0[0], b0[1], b[2] + ph], [a0[0], a0[1], a[2] + ph], nrm, ...sfuma(CORRIMANO, 1, 1.1));
            opere.quad([a0[0], a0[1], a[2] + ph], [b0[0], b0[1], b[2] + ph], [b1[0], b1[1], b[2] + ph], [a1[0], a1[1], a[2] + ph], [0, 0, 1], ...sfuma(CORRIMANO, 1.15, 1.15));
            opere.quad([a1[0], a1[1], a[2]], [b1[0], b1[1], b[2]], [b1[0], b1[1], b[2] + ph], [a1[0], a1[1], a[2] + ph], inr, ...sfuma(cCemento, 0.7, 0.95));
          }
          if (comePonte) {
            // Il fianco dell'impalcato: il cordolo chiaro che sporge un poco
            // (col suo sottile ventre in ombra), poi la trave più scura, rientrata.
            const CO = 0.55;
            const c0 = fuori(a, on0, 0.38);
            const c1 = fuori(b, on1, 0.38);
            const t0 = fuori(a, on0, 0.0);
            const t1 = fuori(b, on1, 0.0);
            const p0 = fuori(a, on0, 0.12);
            const p1 = fuori(b, on1, 0.12);
            opere.quad([c0[0], c0[1], a[2] - CO], [c1[0], c1[1], b[2] - CO], [c1[0], c1[1], b[2] + 0.02], [c0[0], c0[1], a[2] + 0.02], nrm, ...sfuma(CORDOLO, 1, 1.08));
            opere.quad([p0[0], p0[1], a[2] + 0.02], [p1[0], p1[1], b[2] + 0.02], [c1[0], c1[1], b[2] + 0.02], [c0[0], c0[1], a[2] + 0.02], [0, 0, 1], ...sfuma(CORDOLO, 1.04, 1.04));
            opere.quad([t0[0], t0[1], a[2] - CO], [t1[0], t1[1], b[2] - CO], [c1[0], c1[1], b[2] - CO], [c0[0], c0[1], a[2] - CO], [0, 0, -1], ...sfuma(SOTTO, 1, 1));
            opere.quad(
              [t0[0], t0[1], a[2] - SPESSORE_IMPALCATO],
              [t1[0], t1[1], b[2] - SPESSORE_IMPALCATO],
              [t1[0], t1[1], b[2] - CO],
              [t0[0], t0[1], a[2] - CO],
              nrm,
              ...sfuma(TRAVE, 0.6, 0.86),
            );
          } else {
            const a0 = fuori(a, on0, 0.1);
            const b0 = fuori(b, on1, 0.1);
            opere.quad([a0[0], a0[1], 0], [b0[0], b0[1], 0], [b0[0], b0[1], b[2]], [a0[0], a0[1], a[2]], nrm, ...sfuma(cCemento, 0.66, 0.98));
          }
        }
        if (comePonte) {
          const a = L[k - 1];
          const b = L[k];
          const c = R[k];
          const d = R[k - 1];
          // Il ventre dell'impalcato, scuro: da sotto si capisce che è un ponte.
          const sp = SPESSORE_IMPALCATO;
          opere.quad([a[0], a[1], a[2] - sp], [b[0], b[1], b[2] - sp], [c[0], c[1], c[2] - sp], [d[0], d[1], d[2] - sp], [0, 0, -1], ...cSotto);
        }
      }
      // Le spalle: dove il ponte finisce ancora in alto (poi c'è il
      // terrapieno), un muro di cemento pieno fino a terra.
      if (f.ponte) {
        for (const e of [0, n - 1]) {
          const P = pezzo[e];
          const capo = e === 0 ? P[5] < 0.5 : P[5] > lungo[n0 - 1] - 0.5;
          if (!capo || P[2] < 2.5 || !dentro(P[0], P[1])) continue;
          const dir = e === 0 ? -1 : 1;
          // Un ponte spezzato in più pezzi può finire sopra una strada: lì niente spalla.
          const cx0 = P[0] + P[3] * 0.7 * dir;
          const cy0 = P[1] + P[4] * 0.7 * dir;
          let sullaStrada = false;
          for (let q = -1; q <= 1; q += 0.5) if (suStradaATerra(cx0 - P[4] * hw * q, cy0 + P[3] * hw * q, 1)) sullaStrada = true;
          if (sullaStrada) continue;
          scatola(P[0] + P[3] * 0.7 * dir, P[1] + P[4] * 0.7 * dir, 0, P[2] + zs - 0.1, P[3], P[4], 0.7, hw + 0.35, cCemento);
        }
      }
      // I piloni: ai due lati di ogni strada che passa sotto (mai sopra), e
      // ogni trenta metri nel resto del ponte (e delle salite alte).
      if (f.ponte || pezzo.some((q) => q[2] > ALTO_COME_PONTE)) {
        const aS = (sv) => {
          let k = 1;
          while (k < n - 1 && pezzo[k][5] < sv) k++;
          const t = Math.max(0, Math.min(1, (sv - pezzo[k - 1][5]) / Math.max(1e-6, pezzo[k][5] - pezzo[k - 1][5])));
          return [0, 1, 2, 3, 4].map((j) => pezzo[k - 1][j] + (pezzo[k][j] - pezzo[k - 1][j]) * t);
        };
        const vietati = [];
        const appoggi = [];
        for (let k = 1; k < n; k++) {
          const P0 = pezzo[k - 1];
          const P1 = pezzo[k];
          const dx = P1[0] - P0[0];
          const dy = P1[1] - P0[1];
          const visti = new Set();
          for (let cx = Math.floor(Math.min(P0[0], P1[0]) / GRIGLIA) - 1; cx <= Math.floor(Math.max(P0[0], P1[0]) / GRIGLIA) + 1; cx++) {
            for (let cy = Math.floor(Math.min(P0[1], P1[1]) / GRIGLIA) - 1; cy <= Math.floor(Math.max(P0[1], P1[1]) / GRIGLIA) + 1; cy++) {
              for (const g of aTerra.get(cx + ',' + cy) || []) {
                if (visti.has(g)) continue;
                visti.add(g);
                const [a, b, ghw] = g;
                const ex = b[0] - a[0];
                const ey = b[1] - a[1];
                const den = dx * ey - dy * ex;
                if (Math.abs(den) < 1e-9) continue;
                const t = ((a[0] - P0[0]) * ey - (a[1] - P0[1]) * ex) / den;
                const u = ((a[0] - P0[0]) * dy - (a[1] - P0[1]) * dx) / den;
                if (t < 0 || t > 1 || u < -0.05 || u > 1.05) continue;
                const seno = Math.abs(den) / (Math.hypot(dx, dy) * Math.hypot(ex, ey));
                if (seno < 0.25) continue;
                const sv = P0[5] + (P1[5] - P0[5]) * t;
                const meta2 = ghw / seno;
                vietati.push([sv - meta2 - 1.2, sv + meta2 + 1.2]);
                appoggi.push(sv - meta2 - 2.4, sv + meta2 + 2.4);
              }
            }
          }
        }
        const libero = (sv) => !vietati.some(([a, b]) => sv > a && sv < b);
        const metti = (sv) => {
          if (sv < pezzo[0][5] || sv > pezzo[n - 1][5] || !libero(sv)) return false;
          const [px, py, h, tx, ty] = aS(sv);
          if (h < (f.ponte ? 2.5 : ALTO_COME_PONTE)) return false;
          const tl = Math.hypot(tx, ty) || 1;
          const offs = f.w > 9 ? [-f.w * 0.27, f.w * 0.27] : [0];
          for (const o of offs) if (suStradaATerra(px - (ty / tl) * o, py + (tx / tl) * o, 0.8)) return false;
          piloni.push({ x: px, y: py, h: h + zs - SPESSORE_IMPALCATO, ang: Math.atan2(ty, tx), w: f.w, offs, alto: h > 14 });
          return true;
        };
        // Nello spartitraffico fra due carreggiate di sotto: un pilone a metà.
        const mezzi = [];
        const occupati = [...vietati].sort((p, q) => p[0] - q[0]);
        for (let k = 1; k < occupati.length; k++) {
          const fine = Math.max(...occupati.slice(0, k).map((v) => v[1]));
          const gap = occupati[k][0] - fine;
          if (gap > 0.2 && gap < 14) mezzi.push((fine + occupati[k][0]) / 2);
        }
        const fatti = [];
        for (const sv of mezzi) if (metti(sv)) fatti.push(sv);
        for (const sv of appoggi.sort((a, b) => a - b)) {
          if (fatti.some((q) => Math.abs(q - sv) < 6)) continue;
          if (metti(sv)) fatti.push(sv);
        }
        let prossimo = 12 + Math.floor(semePezzo * 5) * 3;
        // Si conta dall'inizio della strada intera: le due tessere ai lati
        // del bordo mettono i piloni negli stessi punti.
        while (prossimo < pezzo[0][5]) prossimo += pezzo.some((q) => q[2] > 20) ? 45 : 30;
        // Sui viadotti alti le campate sono più lunghe.
        const campata = pezzo.some((q) => q[2] > 20) ? 45 : 30;
        for (; prossimo <= pezzo[n - 1][5]; prossimo += campata) {
          if (fatti.some((q) => Math.abs(q - prossimo) < 10)) continue;
          metti(prossimo);
        }
      }
      // I lampioni delle strade grandi.
      if (lim.lampioni > 0 && ['motorway', 'trunk', 'primary'].includes(f.cls) && !f.rampa && !f.cucita) {
        let prossimo = 20 + Math.floor(semePezzo * 4) * 9;
        while (prossimo < pezzo[0][5]) prossimo += 48;
        for (let k = 1; k < n; k++) {
          const a = pezzo[k - 1];
          const b = pezzo[k];
          const d = Math.hypot(b[0] - a[0], b[1] - a[1]);
          if (!d) continue;
          while (b[5] >= prossimo) {
            const t = (prossimo - a[5]) / Math.max(1e-6, b[5] - a[5]);
            const px = a[0] + (b[0] - a[0]) * t;
            const py = a[1] + (b[1] - a[1]) * t;
            const h = a[2] + (b[2] - a[2]) * t;
            const nx = -(b[1] - a[1]) / d;
            const ny = (b[0] - a[0]) / d;
            const lato = f.senso ? -1 : Math.floor(prossimo / 48) % 2 ? 1 : -1;
            const off = f.w / 2 + 0.6;
            lampioni.push({
              x: px + nx * off * lato,
              y: py + ny * off * lato,
              z: h + zs,
              hx: px + nx * (off - 2.2) * lato,
              hy: py + ny * (off - 2.2) * lato,
            });
            prossimo += 48;
          }
        }
      }
    }
  });

  // I piloni (istanze): fusto e capitello; e la loro ombra.
  let nFusti = 0;
  for (const p of piloni) nFusti += p.offs.length;
  const fusti = new Float32Array(nFusti * 16);
  const capitelli = new Float32Array(piloni.length * 16);
  {
    let i = 0;
    piloni.forEach((p, j) => {
      for (const o of p.offs) {
        const px = p.x - Math.sin(p.ang) * o;
        const py = p.y + Math.cos(p.ang) * o;
        // Più alto, più grosso: un pilone di quaranta metri non è un palo.
        const g = 1 + Math.min(1.4, Math.max(0, p.h - 12) / 22);
        matrice(fusti, 16 * i++, px, py, 0, p.ang, 1.25 * g, 1.6 * g, Math.max(0.5, p.h - 0.8));
        const h = p.h;
        // L'ombra del fusto: una striscia stretta verso l'ombra.
        const ex = px + sox * h;
        const ey = py + soy * h;
        const l = Math.hypot(ex - px, ey - py) || 1;
        const qx = (-(ey - py) / l) * 0.8;
        const qy = ((ex - px) / l) * 0.8;
        ombre.quad([px + qx, py + qy, 0], [ex + qx, ey + qy, 0], [ex - qx, ey - qy, 0], [px - qx, py - qy, 0], [0, 0, 1]);
      }
      matrice(capitelli, 16 * j, p.x, p.y, Math.max(0, p.h - 1.0), p.ang, 2.2, p.w * 0.86, 1.0);
    });
  }

  // ── Gli edifici ───────────────────────────────────────────────────────
  const edificiOut = [];
  const B = centro.building;
  if (B) {
    for (let i = 0; i < B.length; i++) {
      const f = B.feature(i);
      const p = f.properties;
      if (p.hide_3d) continue;
      for (const poli of anelliPoligoni(f.loadGeometry())) {
        const anelli = [];
        for (const r of poli) {
          const c = ritagliaAnello(r, 0, 0, ESTENSIONE, ESTENSIONE);
          if (c) anelli.push(c);
        }
        if (!anelli.length) continue;
        const out = anelli.map((r) => {
          const pts = r.map(([px, py]) => sys.metri(x * ESTENSIONE + px, y * ESTENSIONE + py));
          const sulBordo = (u, v) => Math.abs(u - v) < 1e-6;
          const muro = r.map((a, k) => {
            const b = r[(k + 1) % r.length];
            return !(
              (sulBordo(a[0], 0) && sulBordo(b[0], 0)) ||
              (sulBordo(a[0], ESTENSIONE) && sulBordo(b[0], ESTENSIONE)) ||
              (sulBordo(a[1], 0) && sulBordo(b[1], 0)) ||
              (sulBordo(a[1], ESTENSIONE) && sulBordo(b[1], ESTENSIONE))
            );
          });
          return { pts, muro };
        });
        edificiOut.push({
          seme: semeEdificio(f.id, poli[0], x, y, z),
          h: Math.max(+(p.render_height ?? 8) || 8, 3),
          mh: +(p.render_min_height ?? 0) || 0,
          // L'area dell'edificio intero (non del pezzo dentro la tessera):
          // decide lo stile, che deve essere lo stesso in ogni pezzo.
          area: Math.max(Math.abs(area(out[0].pts)), Math.abs(area(poli[0].map(([px, py]) => sys.metri(x * ESTENSIONE + px, y * ESTENSIONE + py))))),
          anelli: out,
        });
      }
    }
  }
  // I più grandi per primi: se non ci stanno tutti, restano fuori i piccoli.
  edificiOut.sort((a, b) => b.area - a.area);
  // Un edificio sotto un viadotto (le mappe a volte li sovrappongono) non
  // buca l'impalcato: si ferma un poco sotto il ventre, o non si fa.
  const GQ = 20;
  const inQuota = new Map();
  linee.forEach((pts, i) => {
    if (visibili[i].galleria) return;
    for (const p of pts) {
      if (p[2] < 2.5) continue;
      const key = Math.floor(p[0] / GQ) + ',' + Math.floor(p[1] / GQ);
      if (!inQuota.has(key)) inQuota.set(key, []);
      inQuota.get(key).push([p[0], p[1], p[2] - SPESSORE_IMPALCATO]);
    }
  });
  const sottoIlPonte = (anelli) => {
    let minx = 1e9;
    let miny = 1e9;
    let maxx = -1e9;
    let maxy = -1e9;
    for (const [px, py] of anelli[0]) {
      minx = Math.min(minx, px);
      maxx = Math.max(maxx, px);
      miny = Math.min(miny, py);
      maxy = Math.max(maxy, py);
    }
    let basso = Infinity;
    for (let cx = Math.floor(minx / GQ); cx <= Math.floor(maxx / GQ); cx++) {
      for (let cy = Math.floor(miny / GQ); cy <= Math.floor(maxy / GQ); cy++) {
        for (const [px, py, hb] of inQuota.get(cx + ',' + cy) || []) {
          if (hb < basso && puntoDentroPoligono(px, py, anelli)) basso = hb;
        }
      }
    }
    return basso;
  };
  const STILI = STILI_FACCIATA;
  const facciate = Object.fromEntries(STILI.map((s) => [s, new Costruttore({ uv: true, colori: true })]));
  const tetti = new Costruttore({ colori: true });
  let triEdifici = 0;
  let edificiFatti = 0;
  const seme = semeTessera(z, x, y);
  for (const [bi, b] of edificiOut.entries()) {
    if (triEdifici > lim.triangoliEdifici) break;
    // Colore, facciata e tetto dall'id dell'edificio, non dalla tessera: un
    // palazzo a cavallo di due tessere si disegna a pezzi, e ogni pezzo
    // prendeva il suo colore e la sua facciata («a destra la facciata
    // giusta, al centro un'altra: non è così il palazzo»).
    const r = generatore(b.seme);
    const ventre = sottoIlPonte(b.anelli.map((a) => a.pts));
    const h = Math.min(b.h, ventre - 0.6);
    const m0 = b.mh;
    if (h < 2.5 || h <= m0 + 0.5) continue;
    const stile = b.area > 2500 && h <= 22 ? 'industria' : h >= 34 ? 'uffici' : b.area > 1400 && h < 14 ? 'industria' : 'residenziale';
    const pal = FACCIATE[stile];
    const scelta = Math.floor(r() * pal.giorno.length);
    const v = 0.92 + r() * 0.12;
    const cg = rgb(pal.giorno[scelta]).map((c) => Math.min(255, Math.round(c * v)));
    const cn = rgb(pal.notte[scelta]).map((c) => Math.min(255, Math.round(c * v)));
    const gb = facciate[`${stile}-${Math.floor(r() * VARIANTI_FACCIATA[stile])}`];
    // L'ombra a terra al massimo quella di un palazzo di 40 m: le torri
    // stendevano lastre grigie su interi isolati, come una mappa non caricata.
    const hOmbra = Math.min(h, 40);
    const cornice = cg.map((c) => Math.round(c + (255 - c) * 0.7));
    const sottoCornice = cg.map((c) => Math.round(c * 0.68));
    const corniceNotte = cn.map((c) => Math.round(c * 0.8));
    const bw = stile === 'industria' ? 6 : CAMPATA;
    const uoff = Math.floor(r() * 4) * 0.25;
    const voff = Math.floor(r() * 4) * 0.25;
    const prima = gb.triangoli + tetti.triangoli + ombre.triangoli;
    for (const [k, anello] of b.anelli.entries()) {
      const p = anello.pts;
      // I muri guardano fuori dall'anello; quelli di un cortile (gli anelli
      // dopo il primo) guardano dentro, verso il cortile: prima guardavano
      // dentro il muro e sparivano.
      const ccw = area(p) < 0 !== k > 0;
      let per = 0;
      for (let i = 0; i < p.length; i++) {
        const a = p[i];
        const c = p[(i + 1) % p.length];
        const dx = c[0] - a[0];
        const dy = c[1] - a[1];
        const l = Math.hypot(dx, dy);
        if (anello.muro[i] && l > 0.01) {
          let nx = dy / l;
          let ny = -dx / l;
          if (!ccw) {
            nx = -nx;
            ny = -ny;
          }
          const u0 = per / (bw * 4) + uoff;
          const u1 = (per + l) / (bw * 4) + uoff;
          const v0 = m0 / (PIANO * 4) + voff;
          const v1 = h / (PIANO * 4) + voff;
          gb.quad([a[0], a[1], m0, u0, v0], [c[0], c[1], m0, u1, v0], [c[0], c[1], h, u1, v1], [a[0], a[1], h, u0, v1], [nx, ny, 0], cg, cn);
          // Il cornicione: una fascia chiara in cima, il bordo del palazzo si legge.
          const fx = nx * 0.25;
          const fy = ny * 0.25;
          tetti.quad([a[0] + fx, a[1] + fy, h - 0.6], [c[0] + fx, c[1] + fy, h - 0.6], [c[0] + fx, c[1] + fy, h + 0.3], [a[0] + fx, a[1] + fy, h + 0.3], [nx, ny, 0], cornice, corniceNotte);
          // E sotto, la sua ombra: una riga scura che stacca il tetto dalla facciata.
          tetti.quad([a[0] + fx * 0.6, a[1] + fy * 0.6, h - 1.2], [c[0] + fx * 0.6, c[1] + fy * 0.6, h - 1.2], [c[0] + fx * 0.6, c[1] + fy * 0.6, h - 0.6], [a[0] + fx * 0.6, a[1] + fy * 0.6, h - 0.6], [nx, ny, 0], sottoCornice, corniceNotte);
          // L'ombra del muro, stesa a terra.
          if (m0 < 1) {
            ombre.quad([a[0], a[1], 0], [c[0], c[1], 0], [c[0] + sox * hOmbra, c[1] + soy * hOmbra, 0], [a[0] + sox * hOmbra, a[1] + soy * hOmbra, 0], [0, 0, 1]);
          }
        }
        per += l;
      }
    }
    // Il tetto, e la sua ombra spostata.
    const piatti = [];
    const buchi = [];
    for (const [k, anello] of b.anelli.entries()) {
      if (k) buchi.push(piatti.length / 2);
      for (const [px, py] of anello.pts) piatti.push(px, py);
    }
    const facce = earcut(piatti, buchi.length ? buchi : null, 2);
    const rp =
      stile === 'industria'
        ? [TETTI.industriaGiorno, TETTI.industriaNotte]
        : stile === 'uffici'
          ? [TETTI.ufficiGiorno, TETTI.ufficiNotte]
          : [TETTI.giorno, TETTI.notte];
    const ri = Math.floor(r() * rp[0].length);
    const rg = rgb(rp[0][ri]);
    const rn = rgb(rp[1][ri]);
    for (let k = 0; k < facce.length; k += 3) {
      const [i0, i1, i2] = [facce[k], facce[k + 1], facce[k + 2]];
      tetti.triPunti([piatti[2 * i0], piatti[2 * i0 + 1], h], [piatti[2 * i1], piatti[2 * i1 + 1], h], [piatti[2 * i2], piatti[2 * i2 + 1], h], [0, 0, 1], rg, rn);
      if (m0 < 1) {
        ombre.triPunti(
          [piatti[2 * i0] + sox * hOmbra, piatti[2 * i0 + 1] + soy * hOmbra, 0],
          [piatti[2 * i1] + sox * hOmbra, piatti[2 * i1 + 1] + soy * hOmbra, 0],
          [piatti[2 * i2] + sox * hOmbra, piatti[2 * i2 + 1] + soy * hOmbra, 0],
          [0, 0, 1],
        );
      }
    }
    triEdifici += gb.triangoli + tetti.triangoli + ombre.triangoli - prima;
    edificiFatti++;
  }

  // ── Gli alberi ────────────────────────────────────────────────────────
  const alberi = lim.alberi > 0 ? piantaAlberi({ centro, sys, x, y, linee, visibili, edifici: edificiOut, limite: lim.alberi, seme }) : [];
  // Le ombre degli alberi: macchie tonde e sfumate (una trama), non esagoni.
  const ombreAlberi = new Costruttore({ uv: true });
  const istanzeAlberi = istanzeDiAlberi(alberi, ombreAlberi);

  // ── I lampioni ────────────────────────────────────────────────────────
  const lamp = lampioni.filter((l) => dentro(l.x, l.y)).slice(0, lim.lampioni);
  const pali = new Float32Array(lamp.length * 16);
  const teste = new Float32Array(lamp.length * 16);
  const luci = new Float32Array(lamp.length * 3);
  lamp.forEach((l, i) => {
    matrice(pali, 16 * i, l.x, l.y, l.z, 0, 1, 1, 10);
    matrice(teste, 16 * i, (l.x + l.hx) / 2, (l.y + l.hy) / 2, l.z + 10, Math.atan2(l.hy - l.y, l.hx - l.x), 2.6, 0.35, 0.22);
    luci.set([l.hx, l.hy, l.z + 9.85], 3 * i);
  });

  // I nomi dei ponti (e i numeri delle strade sui ponti), con la quota
  // dell'impalcato: la mappa li scrive lassù, non a terra sotto il viadotto.
  // I nomi delle strade che MapLibre scriverebbe nel posto sbagliato: sui
  // ponti e sulle rampe in quota (a terra, sotto), e sulle gallerie (sopra
  // quello che le copre; le tessere uniscono i pezzi in galleria a quelli
  // aperti). Li scrive il 3D: al centro del pezzo più lungo fuori dalla
  // galleria, alla quota della strada lì; MapLibre li tace ([nascosti]).
  const etichette = [];
  const nascosti = new Set();
  const TN = centro.transportation_name;
  if (TN) {
    const gp = new Map();
    for (const f of visibili) {
      if (f.cls === 'rail') continue;
      for (const i of f.nodi) {
        const nn = nodi[i];
        const key = Math.floor(nn.x / GQ) + ',' + Math.floor(nn.y / GQ);
        if (!gp.has(key)) gp.set(key, []);
        gp.get(key).push({ x: nn.x, y: nn.y, h: f.galleria ? 0 : nn.h, galleria: !!f.galleria });
      }
    }
    // Il nodo aperto più vicino e quello in galleria più vicino: in galleria
    // solo se è chiaramente più vicino (una strada che passa sopra una
    // galleria le sta proprio sopra).
    const vicino = (px, py, raggio) => {
      let aperto = null;
      let da = raggio;
      let dg = raggio;
      for (let ax = -1; ax <= 1; ax++) {
        for (let ay = -1; ay <= 1; ay++) {
          for (const nn of gp.get(Math.floor(px / GQ) + ax + ',' + (Math.floor(py / GQ) + ay)) || []) {
            const d = Math.hypot(nn.x - px, nn.y - py);
            if (nn.galleria) dg = Math.min(dg, d);
            else if (d < da) {
              da = d;
              aperto = nn;
            }
          }
        }
      }
      if (dg < raggio && dg < da - 2) return { galleria: true, h: 0 };
      return aperto;
    };
    /** Ci sono almeno [n] campioni di fila che fanno [prova]? (Un incrocio sotto un ponte non basta.) */
    const diFila = (campioni, prova, n = 3) => {
      let fila = 0;
      for (const c of campioni) {
        fila = c.salto ? 0 : fila;
        fila = prova(c) ? fila + 1 : 0;
        if (fila >= n) return true;
      }
      return false;
    };
    for (let i = 0; i < TN.length && etichette.length < 60; i++) {
      const f = TN.feature(i);
      const p = f.properties;
      if (f.type !== 2 || !(p.name || p.ref) || p.class === 'rail' || p.class === 'transit') continue;
      // I campioni ogni 8 m lungo i pezzi nella tessera: in galleria, in quota, a terra.
      const campioni = [];
      for (const linea of f.loadGeometry()) {
        for (const pezzo of ritagliaLinea(
          linea.map((q) => sys.metri(x * ESTENSIONE + q.x, y * ESTENSIONE + q.y)),
          -meta,
          -meta,
          meta,
          meta,
        )) {
          let prossimo = 0;
          let fatto = 0;
          let primo = true;
          for (let k = 1; k < pezzo.length; k++) {
            const [ax, ay] = pezzo[k - 1];
            const [bx, by] = pezzo[k];
            const d = Math.hypot(bx - ax, by - ay);
            while (d > 0 && prossimo <= fatto + d) {
              const t = prossimo - fatto;
              const cx = ax + ((bx - ax) * t) / d;
              const cy = ay + ((by - ay) * t) / d;
              campioni.push({ x: cx, y: cy, dir: Math.atan2(by - ay, bx - ax), nn: vicino(cx, cy, 14), salto: primo });
              primo = false;
              prossimo += 8;
            }
            fatto += d;
          }
        }
      }
      if (!campioni.length) continue;
      const galleria = p.brunnel === 'tunnel' || diFila(campioni, (c) => c.nn?.galleria);
      const inAlto = p.brunnel === 'bridge' || diFila(campioni, (c) => c.nn && !c.nn.galleria && c.nn.h > 2.5);
      if (!galleria && !inAlto) continue;
      if (p.name) nascosti.add(p.name);
      // Il pezzo più lungo fuori dalla galleria.
      let meglio = null;
      let corrente = [];
      const chiudi = () => {
        if (corrente.length && (!meglio || corrente.length > meglio.length)) meglio = corrente;
        corrente = [];
      };
      // Con una galleria: fuori dalla galleria. In quota: sul pezzo in quota.
      const buono = galleria ? (c) => !c.nn?.galleria && p.brunnel !== 'tunnel' : (c) => c.nn && c.nn.h > 2.5;
      for (const c of campioni) {
        if (c.salto) chiudi();
        if (buono(c)) corrente.push(c);
        else chiudi();
      }
      chiudi();
      if (!meglio || meglio.length * 8 < 32) continue;
      const c = meglio[Math.floor(meglio.length / 2)];
      const h = c.nn?.h ?? 0;
      // Un ponte senza un nodo vicino in quota: niente (prima si saltava uguale).
      if (p.brunnel === 'bridge' && h < 2) continue;
      etichette.push({ x: c.x, y: c.y, h: h + 0.25, dir: c.dir, nome: p.name ?? '', ref: p.ref ?? '', cls: p.class, galleria });
    }
  }

  const fatti = Object.fromEntries(NASTRI.filter((t) => nastri[t].triangoli).map((t) => [t, nastri[t].fatto()]));
  const out = {
    chiave: `${z}/${x}/${y}`,
    dettaglio,
    centro: { mx: sys.mx, my: sys.my, s: sys.s, lato: sys.lato },
    strade: fatti,
    opere: opere.triangoli ? opere.fatto() : null,
    ombre: ombre.triangoli ? ombre.fatto() : null,
    ombrePonti: ombrePonti.triangoli ? ombrePonti.fatto() : null,
    ombreAlberi: ombreAlberi.triangoli ? ombreAlberi.fatto() : null,
    facciate: Object.fromEntries(STILI.filter((s) => facciate[s].triangoli).map((s) => [s, facciate[s].fatto()])),
    tetti: tetti.triangoli ? tetti.fatto() : null,
    fusti,
    capitelli,
    alberi: istanzeAlberi,
    pali,
    teste,
    luci,
    segmenti: new Float32Array(segmenti),
    etichette,
    nascosti: [...nascosti],
  };
  const triStrade = Object.values(nastri).reduce((s, g) => s + g.triangoli, 0);
  out.conti = {
    strade: triStrade,
    opere: opere.triangoli,
    ombre: ombre.triangoli + ombrePonti.triangoli + ombreAlberi.triangoli,
    edifici: triEdifici,
    edificiFatti,
    edificiTotali: edificiOut.length,
    piloni: piloni.length,
    alberi: alberi.length,
    lampioni: lamp.length,
    nodi: nodi.length,
    msGrafo: tGrafo,
    ms: Date.now() - t0,
  };
  out.conti.triangoli = stimaTriangoli(out);
  return out;
}

/** Triangoli di una geometria istanziata, per le stime. */
export const TRIANGOLI_ISTANZA = { fusto: 24, capitello: 12, albero: 2, palo: 12, testa: 12 };

/** Quanti triangoli disegna la tessera (le istanze contano per ognuna). */
export function stimaTriangoli(t) {
  const tri = (g) => (g ? g.indici.length / 3 : 0);
  let n = 0;
  for (const g of Object.values(t.strade)) n += tri(g);
  n += tri(t.opere) + tri(t.ombre) + tri(t.ombrePonti) + tri(t.ombreAlberi) + tri(t.tetti);
  for (const g of Object.values(t.facciate)) n += tri(g);
  n += (t.fusti.length / 16) * TRIANGOLI_ISTANZA.fusto + (t.capitelli.length / 16) * TRIANGOLI_ISTANZA.capitello;
  // Gli alberi sono immagini: due triangoli l'uno.
  const a = t.alberi;
  n += ((a.foglie.length + a.abeti.length) / 16) * TRIANGOLI_ISTANZA.albero;
  n += (t.pali.length / 16) * (TRIANGOLI_ISTANZA.palo + TRIANGOLI_ISTANZA.testa);
  return n;
}

/**
 * Dove nascono gli alberi: dentro i boschi e i parchi veri della tessera, e
 * da nessun'altra parte; mai su una strada, in un edificio o nell'acqua. Il seme è la tessera: tornandoci sono gli stessi.
 */
function piantaAlberi({ centro, sys, x, y, linee, visibili, edifici, limite, seme }) {
  const rnd = generatore(seme ^ 0x9e3779b9);
  const meta = sys.lato / 2;
  const metriDi = (px, py) => sys.metri(x * ESTENSIONE + px, y * ESTENSIONE + py);
  const verde = [];
  const acqua = [];
  /* «Lungo il percorso voglio vedere le cose reali, non alberi dove non ci
   * sono.» Le tessere non hanno i singoli alberi: si sa solo dove c'è un
   * bosco o un parco. Gli alberi nascono lì e basta. Prima nascevano anche nei
   * prati, nei quartieri, nelle scuole, negli ospedali, nei campi sportivi,
   * nei cimiteri, in filare lungo ogni strada principale e ai bordi delle
   * autostrade: tutti inventati. */
  for (const [nome, tieni] of [
    ['landcover', (c) => ['wood', 'forest'].includes(c)],
    ['park', () => true],
  ]) {
    const L = centro[nome];
    for (let i = 0; L && i < L.length; i++) {
      const f = L.feature(i);
      const p = f.properties;
      if (f.type !== 3 || !tieni(p.class)) continue;
      for (const poli of anelliPoligoni(f.loadGeometry())) {
        const anelli = [];
        for (const r of poli) {
          const c = ritagliaAnello(r, 0, 0, ESTENSIONE, ESTENSIONE);
          if (c) anelli.push(c.map(([px, py]) => metriDi(px, py)));
        }
        if (anelli.length) verde.push({ strato: nome, cls: p.class, anelli });
      }
    }
  }
  const W = centro.water;
  for (let i = 0; W && i < W.length; i++) {
    const f = W.feature(i);
    for (const poli of anelliPoligoni(f.loadGeometry())) {
      const anelli = [];
      for (const r of poli) {
        const c = ritagliaAnello(r, 0, 0, ESTENSIONE, ESTENSIONE);
        if (c) anelli.push(c.map(([px, py]) => metriDi(px, py)));
      }
      if (anelli.length) acqua.push(anelli);
    }
  }
  // Gli ostacoli: strade, muri.
  const CELLA = 20;
  const griglia = new Map();
  const gk = (px, py) => Math.floor(px / CELLA) + ',' + Math.floor(py / CELLA);
  const aggiungi = (ax, ay, bx, by, rad) => {
    const minx = Math.min(ax, bx) - rad;
    const maxx = Math.max(ax, bx) + rad;
    const miny = Math.min(ay, by) - rad;
    const maxy = Math.max(ay, by) + rad;
    if (maxx < -meta - 30 || minx > meta + 30 || maxy < -meta - 30 || miny > meta + 30) return;
    for (let cx = Math.floor(minx / CELLA); cx <= Math.floor(maxx / CELLA); cx++) {
      for (let cy = Math.floor(miny / CELLA); cy <= Math.floor(maxy / CELLA); cy++) {
        const k = cx + ',' + cy;
        if (!griglia.has(k)) griglia.set(k, []);
        griglia.get(k).push([ax, ay, bx, by, rad]);
      }
    }
  };
  linee.forEach((pts, i) => {
    const w = visibili[i].w;
    for (let k = 1; k < pts.length; k++) {
      aggiungi(pts[k - 1][0], pts[k - 1][1], pts[k][0], pts[k][1], w / 2 + (pts[k][2] > 1 ? 3.5 : 2.2));
    }
  });
  const gEdifici = new Map();
  edifici.forEach((b, bi) => {
    const r = b.anelli[0].pts;
    let minx = 1e9;
    let miny = 1e9;
    let maxx = -1e9;
    let maxy = -1e9;
    for (const [px, py] of r) {
      minx = Math.min(minx, px);
      maxx = Math.max(maxx, px);
      miny = Math.min(miny, py);
      maxy = Math.max(maxy, py);
    }
    for (let cx = Math.floor(minx / 50); cx <= Math.floor(maxx / 50); cx++) {
      for (let cy = Math.floor(miny / 50); cy <= Math.floor(maxy / 50); cy++) {
        const k = cx + ',' + cy;
        if (!gEdifici.has(k)) gEdifici.set(k, []);
        gEdifici.get(k).push(bi);
      }
    }
    for (const a of b.anelli) {
      for (let k = 0; k < a.pts.length; k++) {
        const p = a.pts[k];
        const q = a.pts[(k + 1) % a.pts.length];
        aggiungi(p[0], p[1], q[0], q[1], 1.8);
      }
    }
  });
  const inEdificio = (px, py) =>
    (gEdifici.get(Math.floor(px / 50) + ',' + Math.floor(py / 50)) || []).some((bi) =>
      puntoDentroPoligono(
        px,
        py,
        edifici[bi].anelli.map((r) => r.pts),
      ),
    );
  const inAcqua = (px, py) => acqua.some((w) => puntoDentroPoligono(px, py, w));
  const celle = new Map();
  const bloccato = (px, py, spazio) => {
    for (const s of griglia.get(gk(px, py)) || []) if (distanzaSegmento(px, py, s[0], s[1], s[2], s[3]) < s[4]) return true;
    if (inEdificio(px, py)) return true;
    for (let dx = -1; dx <= 1; dx++) {
      for (let dy = -1; dy <= 1; dy++) {
        for (const t of celle.get(Math.floor(px / 4) + dx + ',' + (Math.floor(py / 4) + dy)) || []) {
          if (Math.hypot(t[0] - px, t[1] - py) < spazio) return true;
        }
      }
    }
    return false;
  };
  const alberi = [];
  const pianta = (px, py, conifera, scala) => {
    if (alberi.length >= limite) return;
    const ck = Math.floor(px / 4) + ',' + Math.floor(py / 4);
    if (!celle.has(ck)) celle.set(ck, []);
    celle.get(ck).push([px, py]);
    alberi.push([px, py, scala, conifera ? 1 : 0, Math.floor(rnd() * 100000)]);
  };
  for (const g of verde) {
    if (alberi.length >= limite) break;
    const r0 = g.anelli[0];
    let minx = 1e9;
    let miny = 1e9;
    let maxx = -1e9;
    let maxy = -1e9;
    for (const [px, py] of r0) {
      minx = Math.min(minx, px);
      maxx = Math.max(maxx, px);
      miny = Math.min(miny, py);
      maxy = Math.max(maxy, py);
    }
    const a = Math.abs(area(r0));
    // Un bosco è fitto; un parco ha prati, viali e alberi, più radi.
    const densita = g.cls === 'wood' || g.cls === 'forest' ? 1 / 45 : 1 / 110;
    const n = Math.min(4000, Math.round(a * densita));
    const spazio = g.cls === 'wood' ? 4.2 : 5.5;
    for (let k = 0; k < n * 2 && k < 8000 && alberi.length < limite; k++) {
      const px = minx + rnd() * (maxx - minx);
      const py = miny + rnd() * (maxy - miny);
      if (!puntoDentroPoligono(px, py, g.anelli)) continue;
      if (bloccato(px, py, spazio) || inAcqua(px, py)) continue;
      pianta(px, py, rnd() < (g.cls === 'wood' ? 0.22 : 0.12), 0.8 + rnd() * 0.6);
    }
  }
  return alberi;
}

/**
 * Il seme di un edificio: lo stesso in ogni tessera in cui compare a pezzi,
 * diverso per ogni edificio. Le tessere mettono insieme in un solo oggetto
 * (un solo id) tutti gli edifici della stessa altezza: l'id da solo dava lo
 * stesso colore e la stessa facciata a decine di case («sempre uguali»).
 * Allora l'id più dove sta l'edificio: i lati del suo rettangolo, in una
 * griglia di circa due metri, tranne quelli tagliati dal bordo della
 * tessera (che cambiano da una tessera all'altra).
 */
function semeEdificio(id, anello, x, y, z) {
  let minx = Infinity;
  let maxx = -Infinity;
  let miny = Infinity;
  let maxy = -Infinity;
  for (const p of anello) {
    minx = Math.min(minx, p[0]);
    maxx = Math.max(maxx, p[0]);
    miny = Math.min(miny, p[1]);
    maxy = Math.max(maxy, p[1]);
  }
  const taglioX = minx <= -60 || maxx >= ESTENSIONE + 60;
  const taglioY = miny <= -60 || maxy >= ESTENSIONE + 60;
  const g = (v, t) => Math.round(((t * ESTENSIONE + v) / ESTENSIONE) * 2 ** (24 - z));
  let h = Math.imul(Number(id ?? 0) % 2147483647, 2654435761) ^ 0x5bd1e995;
  const parti = taglioX ? [0, 0] : [g(minx, x), g(maxx, x)];
  parti.push(...(taglioY ? [0, 0] : [g(miny, y), g(maxy, y)]));
  for (const v of parti) h = Math.imul(h ^ (v | 0), 0x01000193) ^ (h >>> 13);
  return h >>> 0;
}

/**
 * Le istanze degli alberi: tronchi, chiome (due), coni; e le loro ombre: un
 * quadrato con la trama di una macchia tonda e sfumata (vedi `Scena`), poco
 * spostato verso l'ombra, così sta sotto la chioma come quella vera.
 */
function istanzeDiAlberi(alberi, ombre) {
  const latifoglie = alberi.filter((t) => t[3] === 0).length;
  const conifere = alberi.length - latifoglie;
  const tronchi = new Float32Array(alberi.length * 16);
  const chiome = new Float32Array(latifoglie * 16);
  const chiome2 = new Float32Array(latifoglie * 16);
  const coni = new Float32Array(conifere * 16);
  const coloriChiome = new Uint8Array(latifoglie * 3);
  const coloriChiome2 = new Uint8Array(latifoglie * 3);
  const coloriConi = new Uint8Array(conifere * 3);
  // Gli alberi dipinti (vedi `Scena.alberiDipinti`): un'immagine per albero,
  // da terra alla cima, larga quanto la chioma; il colore è solo la luce.
  const foglie = new Float32Array(latifoglie * 16);
  const coloriFoglie = new Uint8Array(latifoglie * 3);
  const abeti = new Float32Array(conifere * 16);
  const coloriAbeti = new Uint8Array(conifere * 3);
  const totale = CHIOME.reduce((s, a) => s + a[1], 0);
  const scegli = (u) => {
    let a = u * totale;
    for (const [c, w] of CHIOME) {
      a -= w;
      if (a <= 0) return rgb(c);
    }
    return rgb(CHIOME[0][0]);
  };
  const [sox, soy] = spostamentoOmbra();
  let it = 0;
  let id = 0;
  let ic = 0;
  for (const [px, py, s, tipo, rr] of alberi) {
    const r = generatore(rr * 7919 + 13);
    const th = tipo ? 1.4 * s : (2.0 + r() * 0.8) * s;
    matrice(tronchi, 16 * it++, px, py, 0, 0, s, s, th + 0.6);
    let alto;
    let raggio;
    if (tipo === 0) {
      const cr = (2.3 + r() * 1.0) * s;
      const ch = cr * (1.05 + r() * 0.3);
      const ang = r() * 6.28;
      matrice(chiome, 16 * id, px, py, th + ch * 0.85, ang, cr, cr * (0.9 + r() * 0.2), ch);
      const ox = (r() - 0.5) * cr * 0.9;
      const oy = (r() - 0.5) * cr * 0.9;
      matrice(chiome2, 16 * id, px + ox, py + oy, th + ch * (0.9 + r() * 0.5), ang, cr * 0.62, cr * 0.62, ch * 0.62);
      const c = scegli(r());
      const luce = 1 + (r() - 0.5) * 0.12;
      coloriChiome.set(c.map((v) => Math.min(255, Math.round(v * luce))), 3 * id);
      coloriChiome2.set(c.map((v) => Math.min(255, Math.round(v * luce * 1.08))), 3 * id);
      matrice(foglie, 16 * id, px, py, 0, ang, cr * 2.25, cr * 2.25, th + ch * 1.85);
      const l = Math.round(232 + (r() - 0.5) * 40);
      coloriFoglie.set([l, Math.min(255, l + 6), l - 6], 3 * id);
      id++;
      alto = th + ch * 0.85;
      raggio = cr;
    } else {
      const hh = (7 + r() * 4) * s;
      const rad = (1.9 + r() * 0.5) * s;
      matrice(coni, 16 * ic, px, py, th * 0.6, 0, rad, rad, hh);
      coloriConi.set(rgb(r() < 0.8 ? '#3f6b3c' : '#4e7a3e'), 3 * ic);
      matrice(abeti, 16 * ic, px, py, 0, 0, rad * 2.3, rad * 2.3, th * 0.6 + hh * 1.02);
      const l = Math.round(228 + (r() - 0.5) * 36);
      coloriAbeti.set([l, l, l], 3 * ic);
      ic++;
      alto = th * 0.6 + hh * 0.4;
      raggio = rad;
    }
    // L'ombra: una macchia sfumata a terra, un po' spostata col sole.
    const cx = px + sox * alto * 0.5;
    const cy = py + soy * alto * 0.5;
    const rr2 = raggio * 1.25;
    ombre.quad([cx - rr2, cy - rr2, 0, 0, 0], [cx + rr2, cy - rr2, 0, 1, 0], [cx + rr2, cy + rr2, 0, 1, 1], [cx - rr2, cy + rr2, 0, 0, 1], [0, 0, 1]);
  }
  return { tronchi, chiome, chiome2, coni, coloriChiome, coloriChiome2, coloriConi, foglie, coloriFoglie, abeti, coloriAbeti };
}

/**
 * I viadotti alti. Le tessere non dicono quanto è alto un ponte: solo il suo
 * livello (8 m l'uno). In Italia però i ponti sulle valli si chiamano
 * «Viadotto …», e più sono lunghi più sono alti: il viadotto di Genova (un
 * chilometro) sta a 45 m sulla valle. Dai nomi delle nove tessere si prende
 * quanto è lungo ogni viadotto (da un capo all'altro), e i suoi pezzi di
 * ponte stanno a [altezzaViadotto] metri, se è più del loro livello. I ponti
 * sui fiumi («Ponte sul Po») e le tangenziali sopraelevate restano al loro
 * livello: lunghi, ma bassi.
 */
function segnaViadotti(livelli, x, y, strade, sys) {
  // I nomi: «Viadotto …», o un'autostrada che si chiama «Ponte …» (il ponte
  // di Genova è «(Ponte San Giorgio) A10 …»). Le tessere uniscono i pezzi
  // della strada in una linea sola, ponte o no: il nome dice dove cercare.
  const linee = new Map();
  for (const [chiaveOff, layers] of Object.entries(livelli)) {
    const TN = layers?.transportation_name;
    if (!TN) continue;
    const [dx, dy] = chiaveOff.split(',').map(Number);
    const ox = (x + dx) * ESTENSIONE;
    const oy = (y + dy) * ESTENSIONE;
    for (let i = 0; i < TN.length; i++) {
      const f = TN.feature(i);
      const p = f.properties;
      const nome = p.name ?? '';
      if (f.type !== 2 || !(/viadott/i.test(nome) || (/\bponte\b/i.test(nome) && (p.class === 'motorway' || p.class === 'trunk')))) continue;
      if (!linee.has(nome)) linee.set(nome, []);
      for (const l of f.loadGeometry()) linee.get(nome).push(l.map((q) => [ox + q.x, oy + q.y]));
    }
  }
  if (!linee.size) return;
  const pxPerMetro = ESTENSIONE / sys.lato;
  const vicino = 25 * pxPerMetro;
  // I pezzi di ponte (non rampe) lungo quei nomi, e quanto è lungo il ponte
  // da un capo all'altro.
  const perNome = new Map();
  for (const r of strade) {
    if (r.p.brunnel !== 'bridge' || r.p.ramp) continue;
    const m = r.g[Math.floor(r.g.length / 2)];
    for (const [nome, ls] of linee) {
      if (ls.some((l) => distanzaLinea(m[0], m[1], l) < vicino)) {
        if (!perNome.has(nome)) perNome.set(nome, []);
        perNome.get(nome).push(r);
        break;
      }
    }
  }
  for (const pezzi of perNome.values()) {
    const pts = pezzi.flatMap((r) => r.g);
    let L = 0;
    for (let a = 0; a < pts.length; a += Math.max(1, pts.length >> 6)) {
      for (const b of pts) L = Math.max(L, Math.hypot(b[0] - pts[a][0], b[1] - pts[a][1]));
    }
    const h = altezzaViadotto(L / pxPerMetro);
    if (h > 0) for (const r of pezzi) r.p = { ...r.p, altezza: Math.max(h, r.p.altezza ?? 0) };
  }
}

function distanzaLinea(px, py, l) {
  let d = Infinity;
  for (let k = 1; k < l.length; k++) {
    const [ax, ay] = l[k - 1];
    const [bx, by] = l[k];
    const L2 = (bx - ax) ** 2 + (by - ay) ** 2 || 1;
    const u = Math.max(0, Math.min(1, ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / L2));
    d = Math.min(d, Math.hypot(ax + (bx - ax) * u - px, ay + (by - ay) * u - py));
  }
  return d;
}

/** Tutti i buffer di una tessera fatta, da trasferire. */
export function bufferDellaTessera(t) {
  const lista = [];
  const geo = (g) => {
    if (!g) return;
    for (const k of ['posizioni', 'normali', 'indici', 'uv', 'colori', 'coloriNotte']) if (g[k]) lista.push(g[k].buffer);
  };
  for (const g of Object.values(t.strade)) geo(g);
  geo(t.opere);
  geo(t.ombre);
  geo(t.ombrePonti);
  geo(t.ombreAlberi);
  geo(t.tetti);
  for (const g of Object.values(t.facciate)) geo(g);
  for (const a of [t.fusti, t.capitelli, t.pali, t.teste, t.luci, t.segmenti, ...Object.values(t.alberi)]) lista.push(a.buffer);
  return lista;
}
