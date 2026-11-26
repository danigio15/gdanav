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
import { ALTEZZA_LIVELLO, CLASSI_STRADE, PENDENZA, PENDENZA_MAX, SPESSORE_IMPALCATO, altezzaViadotto, grafoStrade, uniscIBordi } from './elevazione.js';
import { bordiCorsie } from './corsie.js';
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
import { costruisciSegnaletica } from './segnaletica.js';
import earcut from 'earcut';

/**
 * I tipi di nastro d'asfalto (ognuno con la sua trama di righe). `servizio`
 * solo nella vista «Corsie»: le strade di servizio (i piazzali, i
 * parcheggi, gli accessi), che lì non hanno corsie disegnate.
 */
export const TIPI_STRADA = ['motorway', 'trunk', 'ramp', 'primary1', 'primary2', 'tertiary', 'plain', 'servizio', 'rail'];

/**
 * Tutti i nastri: i tipi a terra, gli stessi sui ponti (`-ponte`, un asfalto
 * più chiaro, che l'impalcato si distingua dalle strade sotto) e le gallerie.
 */
export const NASTRI = [...TIPI_STRADA, ...TIPI_STRADA.map((t) => t + '-ponte'), 'galleria'];

/** Quanto sotto passa una galleria (sopra c'è la strada che la copre). */
const SOPRA_GALLERIA = 0.06;

/** Oltre questa quota (m) una strada non segnata come ponte si disegna come un viadotto. */
const ALTO_COME_PONTE = 6.5;
/** Quanto sotto l'asfalto delle corsie resta la cima di una spalla. */
const SOTTO_L_ASFALTO_M = 0.3;

/** Quanto si allarga la trincea dei binari per metro di profondità (le scarpate); e il rilevato per metro d'altezza. */
const SCARPATA = 1.5;
/** La ghiaia in cima al rilevato dei binari, oltre il binario, prima della scarpata (m). */
const BANCHINA_RILEVATO = 0.8;
/** Metri di strada per una ripetizione della trama. */
export const PERIODO_STRADA = 12;
export const PIANO = 3.2;
export const CAMPATA = 3.4;

/** Quanto resta libero sotto la pensilina di un casello, sopra la strada. */
const LUCE_PENSILINA = 5.4;
/** E quanto è spesso il suo tetto. */
const SPESSORE_PENSILINA = 0.7;
/** Se sotto le corsie salgono più di così, la pensilina non si fa. */
const DISLIVELLO_PENSILINA = 3;
/** I colori della pensilina, di giorno e di notte: il tetto, la fascia attorno, il ventre. */
const PENSILINA = {
  tetto: [rgb('#dad7d0'), rgb('#3d4554')],
  fascia: [rgb('#f4f3ef'), rgb('#7a8494')],
  ventre: [rgb('#96928b'), rgb('#272c37')],
};

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
 * le tessere più lontane.
 *
 * «La visuale dei palazzi non è completa.» Con gli edifici di Overture una
 * tessera di periferia ne ha più di tremila: ridotta ne teneva meno della
 * metà (1363 su 3141), e da lontano i quartieri erano a buchi. Un edificio
 * intero costa dieci triangoli per lato (il muro, il cornicione con la sua
 * ombra, l'ombra a terra) più il tetto e la sua ombra; uno «leggero» solo il
 * muro e il tetto, un terzo. Le tessere ridotte li fanno tutti leggeri (da
 * lontano il cornicione è un pixel), le piene solo oltre [leggeriOltre]
 * triangoli (il tetto di prima: dove ci stavano, restano come prima; i
 * piccoli, che vengono per ultimi, non restano più fuori). */
export const LIMITI = {
  pieno: { alberi: 1800, triangoliEdifici: 240000, leggeriOltre: 190000, lampioni: 400, margine: 450 },
  ridotto: { alberi: 0, triangoliEdifici: 100000, leggeriOltre: 0, lampioni: 0, margine: 250 },
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
export function costruisciTessera({ z, x, y, livelli, dettaglio = 'pieno', limiti, datiCorsie = null, vistaCorsie = false, grafo = false }) {
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
      const p = stradaVera(f.properties);
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
  // Le strade strette fra le case (vedi [strettaFraLeCase]): gli edifici delle
  // nove tessere, in metri.
  {
    const poligoni = [];
    for (const [chiaveOff, layers] of Object.entries(livelli)) {
      const Bd = layers?.building;
      if (!Bd) continue;
      const [dx, dy] = chiaveOff.split(',').map(Number);
      for (let i = 0; i < Bd.length; i++) {
        const f = Bd.feature(i);
        if (f.type !== 3) continue;
        // Solo i contorni esterni: un anello girato al contrario del primo è
        // un cortile (un buco nel palazzo), non un palazzo.
        let verso = 0;
        for (const anello of f.loadGeometry()) {
          let area = 0;
          for (let j = 0, m = anello.length - 1; j < anello.length; m = j++) area += (anello[m].x - anello[j].x) * (anello[j].y + anello[m].y);
          if (!area) continue;
          if (!verso) verso = Math.sign(area);
          if (Math.sign(area) !== verso) continue;
          const pts = anello.map((q) => sys.metri((x + dx) * ESTENSIONE + q.x, (y + dy) * ESTENSIONE + q.y));
          if (pts.some(([px, py]) => Math.abs(px) < meta + 80 && Math.abs(py) < meta + 80)) poligoni.push(pts);
        }
      }
    }
    strettaFraLeCase(feats, nodi, poligoni);
  }
  carreggiateAffiancate(feats, nodi);
  isolaDelleRotonde(feats, nodi);
  // Per il collaudo (la verifica delle strade su tessere vere): il grafo con le quote.
  const grafoPerIlCollaudo = grafo ? { nodi, feats } : undefined;
  const tGrafo = Date.now() - t0;

  // ── I nastri delle strade ─────────────────────────────────────────────
  // Anche le gallerie: un nastro scuro con gli imbocchi (non più niente, col
  // percorso che sembrava passare sopra la strada).
  const visibili = feats.filter(
    (f) => !(f.galleria && f.cls === 'rail') && !(f.cls === 'service' && ['parking_aisle', 'driveway', 'drive-through'].includes(f.sv)),
  );
  const ek = (p) => Math.round(p[0] * 10) + ',' + Math.round(p[1] * 10);
  const linee = visibili.map((f) => f.nodi.map((i) => [nodi[i].x, nodi[i].y, nodi[i].h]));
  const sottopassi = iSottopassi(nodi, feats);
  // La vista «Corsie»: le vie di OpenStreetMap con le corsie (vedi
  // `corsie.js`), alle quote delle strade della tessera; i nastri di sempre
  // che quelle vie coprono non si disegnano.
  const conCorsie = datiCorsie?.strade?.length ? corsieDellaTessera(datiCorsie, sys, linee, visibili, meta) : null;
  // Con le corsie vere (non stimate), le vie guidabili del relay: le strade
  // della mappa che non ci sono non si disegnano (vedi [senzaDati]).
  const vieVere =
    conCorsie && datiCorsie.strade.some((v) => !v.stimata)
      ? vieDelRelay([
          ...conCorsie.strade.map((v) => v.xyVia),
          ...(datiCorsie.altre ?? []).map((a) => {
            const out = [];
            for (let i = 0; i + 1 < a.ll.length; i += 2) out.push(sys.daLonLat(a.ll[i], a.ll[i + 1]));
            return out;
          }),
        ])
      : null;
  /* Le strade della mappa lungo una via con le corsie stanno alla sua quota
   * (`quotaCorsie`), e lungo le altre vie del relay non più in alto di loro
   * (`tettoQui`, vedi [corsieDellaTessera]): le opere, i piloni e il
   * percorso alla quota dell'asfalto. Anche i ponti della mappa: dove il
   * relay dà la stessa strada a terra, il ponte non c'è (un viadotto sopra
   * una strada che gli corre sotto ha la sua via, alta, e resta). Il resto
   * della strada le viene incontro senza scalini. Solo con le corsie vere:
   * quelle stimate vengono dalla mappa, e non sanno niente di più. */
  if (vieVere) {
    linee.forEach((pts, i) => {
      const f = visibili[i];
      if (f.galleria || f.cls === 'rail') return;
      let cambiata = false;
      pts.forEach((q, k) => {
        const a = pts[Math.max(0, k - 1)];
        const b = pts[Math.min(pts.length - 1, k + 1)];
        // Lungo la sua via con le corsie (della stessa classe), alla sua
        // quota (un ponte della mappa solo se è poco più su o più giù: molto
        // più in alto è un'altra strada, o la stessa due volte, vedi `doppia`).
        const c = conCorsie.quotaCorsie(q[0], q[1], b[0] - a[0], b[1] - a[1], q[2], Math.min(f.w / 2, 4) + 2, f.cls);
        if (c !== null && Math.abs(c - q[2]) > 0.05 && (!f.ponte || Math.abs(c - q[2]) <= 2)) {
          q[2] = c;
          cambiata = true;
          return;
        }
        const t = conCorsie.tettoQui(q[0], q[1], b[0] - a[0], b[1] - a[1], Math.min(f.w / 2, 4) + 3);
        if (t === null || q[2] <= t + 0.05) return;
        q[2] = t;
        cambiata = true;
      });
      if (!cambiata) return;
      const h = pts.map((q) => q[2]);
      limitaPendenza(h, pts);
      pts.forEach((q, k) => (q[2] = h[k]));
    });
  }
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
        aTerra.get(key).push([a, b, visibili[i].w / 2, visibili[i].cls === 'rail']);
      }
    }
  });
  /* E tutte le altre, a ogni quota: il pilone di un viadotto alto non passa
   * attraverso la rampa di sotto. Allo svincolo una rampa scendeva dal terzo
   * livello accanto a un'altra che saliva da terra, a due metri: i piloni di
   * quella alta stavano piantati sull'asfalto di quella bassa, davanti
   * all'auto. */
  const tutte = new Map();
  linee.forEach((pts, i) => {
    for (let k = 1; k < pts.length; k++) {
      const a = pts[k - 1];
      const b = pts[k];
      for (const q of [a, b]) {
        const key = Math.floor(q[0] / GRIGLIA) + ',' + Math.floor(q[1] / GRIGLIA);
        if (!tutte.has(key)) tutte.set(key, []);
        tutte.get(key).push([a, b, visibili[i].w / 2]);
      }
    }
  });
  const suStradaSotto = (px, py, margine, sopra) => {
    for (let ax = -1; ax <= 1; ax++) {
      for (let ay = -1; ay <= 1; ay++) {
        for (const [a, b, hw] of tutte.get(Math.floor(px / GRIGLIA) + ax + ',' + (Math.floor(py / GRIGLIA) + ay)) || []) {
          const ex = b[0] - a[0];
          const ey = b[1] - a[1];
          const l2 = ex * ex + ey * ey;
          const t = l2 ? Math.max(0, Math.min(1, ((px - a[0]) * ex + (py - a[1]) * ey) / l2)) : 0;
          if (Math.hypot(px - a[0] - ex * t, py - a[1] - ey * t) >= hw + margine) continue;
          if (a[2] + (b[2] - a[2]) * t < sopra - 3) return true;
        }
      }
    }
    return false;
  };
  // [senzaBinari]: solo le strade (per il rilevato dei binari, vedi sotto).
  const suStradaATerra = (px, py, margine, senzaBinari = false) => {
    for (let ax = -1; ax <= 1; ax++) {
      for (let ay = -1; ay <= 1; ay++) {
        for (const [a, b, hw, binari] of aTerra.get(Math.floor(px / GRIGLIA) + ax + ',' + (Math.floor(py / GRIGLIA) + ay)) || []) {
          if (senzaBinari && binari) continue;
          if (distanzaSegmento(px, py, a[0], a[1], b[0], b[1]) < hw + margine) return true;
        }
      }
    }
    return false;
  };
  /* «Tutto sballato, linee ovunque»: due parapetti bianchi che tagliavano in
   * diagonale la carreggiata, in viadotto. Era una rampa che si stacca dalla
   * carreggiata quasi parallela: per un centinaio di metri le due strade si
   * sovrappongono, e il parapetto della rampa correva sull'asfalto dell'altra
   * (i quaranta metri attorno allo svincolo non bastano, a un angolo così
   * stretto). Un parapetto sull'asfalto della strada da cui si stacca, alla
   * stessa quota, non c'è: lì le due strade sono ancora una. */
  const asfalti = new Map();
  linee.forEach((pts, i) => {
    const f = visibili[i];
    if (f.cls === 'rail' || f.galleria) return;
    for (let k = 1; k < pts.length; k++) {
      const a = pts[k - 1];
      const b = pts[k];
      const voce = [a, b, f.w / 2, i];
      const visti = new Set();
      // Ogni cella che il segmento attraversa (passo mezza cella).
      const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
      const passi = Math.max(1, Math.ceil(l / (GRIGLIA / 2)));
      for (let s = 0; s <= passi; s++) {
        const key = Math.floor((a[0] + ((b[0] - a[0]) * s) / passi) / GRIGLIA) + ',' + Math.floor((a[1] + ((b[1] - a[1]) * s) / passi) / GRIGLIA);
        if (visti.has(key)) continue;
        visti.add(key);
        if (!asfalti.has(key)) asfalti.set(key, []);
        asfalti.get(key).push(voce);
      }
    }
  });
  // Solo una strada che si stacca da questa (un punto in comune): due
  // carreggiate vicine, l'una accanto all'altra, tengono lo spartitraffico.
  const puntiDi = new Map();
  const giaLegate = new Map();
  const legate = (i, j) => {
    const chiaveCoppia = i < j ? i * 1e6 + j : j * 1e6 + i;
    const saputo = giaLegate.get(chiaveCoppia);
    if (saputo !== undefined) return saputo;
    for (const x of [i, j]) if (!puntiDi.has(x)) puntiDi.set(x, new Set(linee[x].map(ek)));
    const pj = puntiDi.get(j);
    let si = false;
    for (const q of puntiDi.get(i)) {
      if (pj.has(q)) {
        si = true;
        break;
      }
    }
    giaLegate.set(chiaveCoppia, si);
    return si;
  };
  const suAltraStrada = (px, py, pz, fi) => {
    for (let ax = -1; ax <= 1; ax++) {
      for (let ay = -1; ay <= 1; ay++) {
        for (const [a, b, hw, i] of asfalti.get(Math.floor(px / GRIGLIA) + ax + ',' + (Math.floor(py / GRIGLIA) + ay)) || []) {
          if (i === fi || !legate(fi, i)) continue;
          const dx = b[0] - a[0];
          const dy = b[1] - a[1];
          const l2 = dx * dx + dy * dy || 1;
          const t = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / l2));
          const qx = a[0] + dx * t;
          const qy = a[1] + dy * t;
          if (Math.hypot(px - qx, py - qy) > hw - 0.3) continue;
          if (Math.abs(a[2] + (b[2] - a[2]) * t - pz) < 2) return true;
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
  // Sotto i ponti un'ombra in più, un po' più larga dell'impalcato. Uno
  // strato solo: la scena scurisce ogni punto una volta (lo stencil), e due
  // strati quasi alla stessa quota litigavano a righe.
  const ombrePonti = new Costruttore();
  // I muri della trincea visti da fuori (sono sotto terra): non si
  // disegnano, ma nascondono quello che sta dietro (vedi la scena).
  const maschera = new Costruttore();
  // I binari in trincea, per non mettere un muro fra due binari affiancati.
  const binariSotto = [];
  for (const g of feats) {
    if (g.cls !== 'rail') continue;
    for (let k = 1; k < g.nodi.length; k++) {
      const a = nodi[g.nodi[k - 1]];
      const b = nodi[g.nodi[k]];
      if (a.h < -0.3 || b.h < -0.3) binariSotto.push([a.x, a.y, b.x, b.y, g]);
    }
  }
  // E quelli in alto (sul rilevato o su un ponte), per fare un rilevato solo
  // sotto due binari affiancati.
  const binariAlti = [];
  for (const g of feats) {
    if (g.cls !== 'rail' || g.galleria) continue;
    for (let k = 1; k < g.nodi.length; k++) {
      const a = nodi[g.nodi[k - 1]];
      const b = nodi[g.nodi[k]];
      if (a.h > 0.35 || b.h > 0.35) binariAlti.push([a.x, a.y, b.x, b.y, g]);
    }
  }
  const altriBinariAlti = (x, y, f, entro) => binariAlti.some(([ax, ay, bx, by, g]) => g !== f && distanzaSegmento(x, y, ax, ay, bx, by) < entro);
  const altriBinariInTrincea = (x, y, f, entro) =>
    binariSotto.some(([ax, ay, bx, by, g]) => {
      if (g === f) return false;
      const dx = bx - ax;
      const dy = by - ay;
      const l2 = dx * dx + dy * dy || 1;
      const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / l2));
      return Math.hypot(ax + dx * t - x, ay + dy * t - y) < entro;
    });
  const [sox, soy] = spostamentoOmbra();
  const piloni = [];
  const lampioni = [];
  const segmenti = [];
  // Per il collaudo: le mezze larghezze disegnate di ogni segmento, [sinistra, destra].
  const latiSegmenti = grafo ? [] : null;
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
  // La trincea dei binari: la ghiaia del fondo, l'erba delle scarpate.
  const GHIAIA = [rgb('#9a958c'), rgb('#3b3f47')];
  const SCARPA = [rgb('#a7b086'), rgb('#3a4234')];
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
    // (Con le mezze larghezze a sinistra e a destra, dove la strada si stringe fra le case.)
    // Nella vista «Corsie» le opere di una strada in quota (il ventre, il
    // cordolo, i parapetti, i muri) stanno sul bordo dell'asfalto delle vie
    // vere, non su quello della strada della mappa (vedi [bordiSullAsfalto]).
    //
    // E alla sua quota. La strada della mappa e la via vera non stanno
    // sempre alla stessa (fino a due metri l'una dall'altra, dove la mappa
    // dà un ponte e il relay una rampa che sale): i parapetti correvano
    // sospesi sopra l'asfalto, o ci affondavano, e la spalla del ponte
    // spuntava di traverso alla carreggiata. Lì le opere prendono la quota
    // dell'asfalto che hanno accanto, un bordo per volta (due vie affiancate
    // possono salire diversamente). I segmenti del percorso restano alla
    // quota della strada della mappa (l'ultimo numero).
    //
    // [x, y, h, tx, ty, s, sinistra, destra, sulle corsie, h a sinistra, h a destra, h della mappa,
    //  senza bordo a sinistra, senza bordo a destra].
    let larghezze = f.larghezze;
    // I varchi nell'asfalto di ogni punto (per i metri lungo la strada): vedi il piano dell'impalcato.
    const varchi = new Map();
    // (Non le strade di servizio: non hanno corsie loro, e accanto a una
    // carreggiata prenderebbero per suo l'asfalto di lei.)
    if (conCorsie && f.cls !== 'rail' && f.cls !== 'service' && !f.galleria && tutta.some((p) => p[2] > 0.35)) {
      larghezze = tutta.map((p, k) => {
        const suoi = f.larghezze?.[k] ?? [f.w / 2, f.w / 2];
        if (p[2] <= 0.35) return suoi;
        const [tx, ty] = tang[k];
        const veri = conCorsie.bordiQui(p[0], p[1], p[2], tx, ty, suoi[0], suoi[1]);
        if (veri?.[5].length) varchi.set(lungo[k], veri[5]);
        return veri ? [veri[0], veri[1], 1, veri[2], veri[3], veri[4], veri[6] ? 1 : 0, veri[7] ? 1 : 0] : suoi;
      });
    }
    const ricca = tutta.map((p, k) => {
      if (!larghezze) return [p[0], p[1], p[2], tang[k][0], tang[k][1], lungo[k]];
      const l = larghezze[k];
      return [p[0], p[1], l[5] ?? p[2], tang[k][0], tang[k][1], lungo[k], l[0], l[1], l[2] ?? 0, l[3] ?? p[2], l[4] ?? p[2], p[2], l[6] ?? 0, l[7] ?? 0];
    });
    const semePezzo = mescola(Math.round(tutta[0][0] * 7), Math.round(tutta[0][1] * 7));
    // I pezzi senza una via vera sotto (vedi [senzaDati]): niente nastro né opere.
    const senza = vieVere && f.cls !== 'rail' ? senzaDati(tutta, f.w, vieVere, f.cantiere) : null;
    /* E dove la stessa strada, con le corsie, passa a un'altra quota: la
     * mappa, coi suoi dati di prima, la dà a terra e il relay su un ponte (o
     * il contrario), e si vedevano tutte e due, una sotto l'altra. */
    if (senza && f.cls !== 'rail' && !f.galleria) {
      tutta.forEach((q, k) => {
        if (!senza[k] && conCorsie.doppia(q[0], q[1], tang[k][0], tang[k][1], q[2], f.cls)) senza[k] = true;
      });
    }
    const nascostoA = (sv) => {
      if (!senza) return false;
      let k = 1;
      while (k < n0 - 1 && lungo[k] < sv) k++;
      return senza[k - 1] && senza[k];
    };
    const zs = f.galleria ? SOPRA_GALLERIA : (SOPRA[f.cls] ?? 0.15) + (fi % 7) * 0.002;

    // I segmenti con le quote, un poco oltre il bordo (per il percorso). Non
    // dove la strada non si disegna: il percorso non ci sale.
    if (f.cls !== 'rail') {
      // Il senso unico (OpenMapTiles: 1 come la linea, -1 al contrario): 128 o
      // 256, perché il percorso non si agganci alla carreggiata opposta.
      const codice = (CODICI_CLASSE[f.cls] ?? 7) + (f.senso > 0 ? 128 : f.senso < 0 ? 256 : 0);
      for (const pezzo of ritagliaLinea(ricca, -meta - 40, -meta - 40, meta + 40, meta + 40)) {
        for (let k = 1; k < pezzo.length; k++) {
          const a = pezzo[k - 1];
          const b = pezzo[k];
          if (senza && nascostoA((a[5] + b[5]) / 2)) continue;
          segmenti.push(a[0], a[1], (a[11] ?? a[2]) + zs, b[0], b[1], (b[11] ?? b[2]) + zs, f.w, codice + (f.rampa ? 16 : 0) + (f.ponte ? 32 : 0) + (f.galleria ? 64 : 0));
          latiSegmenti?.push(((a[6] ?? f.w / 2) + (b[6] ?? f.w / 2)) / 2, ((a[7] ?? f.w / 2) + (b[7] ?? f.w / 2)) / 2);
        }
      }
    }

    // Gli imbocchi delle gallerie, dove la galleria incontra la strada aperta:
    // due spalle, l'architrave, il buio dentro e un pezzo di volta. Non per
    // un sottopasso ([iSottopassi]): lì la strada passa sotto e basta.
    if (f.galleria && !sottopassi.has(f)) {
      for (const e of [0, n0 - 1]) {
        const nodo = nodi[f.nodi[e]];
        if (!nodo.feats.some((j) => !feats[j].galleria) || !dentro(nodo.x, nodo.y) || senza?.[e]) continue;
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
      /* «Un grande ventaglio di spicchi bianchi su asfalto scuro»: sotto un
       * viadotto, le corsie di un parcheggio. Nella vista «Corsie» le strade
       * di servizio avevano lo stesso asfalto blu notte delle carreggiate, ma
       * senza righe: una macchia scura a spicchi che pareva un pezzo di
       * svincolo. Lì hanno un nastro loro, chiaro (vedi `asfaltoServizio`):
       * si vede dove sono, e non si confondono con le strade che contano. */
      const tipo = conCorsie && f.cls === 'service' ? 'servizio' : tipoDi(f);
      const gb = nastri[f.galleria ? 'galleria' : tipo + (f.ponte ? '-ponte' : '')];
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
          const sl = Math.hypot(sx, sy);
          // (Un tratto lungo zero non ha direzione: il bordo resta dov'è.)
          if (sl > 1e-6) m = 1 / Math.max(0.5, Math.abs((-sy / sl) * nx + (sx / sl) * ny));
        }
        const v = pezzo[k][5] / PERIODO_STRADA;
        const hs = pezzo[k][6] ?? hw;
        const hd = pezzo[k][7] ?? hw;
        L.push([pezzo[k][0] + nx * hs * m, pezzo[k][1] + ny * hs * m, (pezzo[k][9] ?? pezzo[k][2]) + zs, 0, v]);
        R.push([pezzo[k][0] - nx * hd * m, pezzo[k][1] - ny * hd * m, (pezzo[k][10] ?? pezzo[k][2]) + zs, 1, v]);
      }
      // Dove c'è la via con le corsie, il nastro di sempre non c'è.
      const coperto = conCorsie ? pezzo.map((q) => conCorsie.copre(q[0], q[1], q[3], q[4], q[2])) : null;
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
        if (coperto && coperto[k - 1] && coperto[k]) continue;
        if (senza && nascostoA(pezzo[k - 1][5] + 0.01) && nascostoA(pezzo[k][5] - 0.01)) continue;
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
      // I binari in trincea (sotto una strada a livello, vedi `altezze`): il
      // fondo di ghiaia e le due scarpate, larghe in cima come quelle vere (da
      // sbieco si vede dentro). Di fuori le scarpate non si vedono ma
      // nascondono (sono sotto terra): da fuori non si guarda dentro.
      if (f.cls === 'rail' && pezzo.some((q) => q[2] < -0.3)) {
        for (let k = 1; k < n; k++) {
          const za = Math.min(0, pezzo[k - 1][2]);
          const zb = Math.min(0, pezzo[k][2]);
          if (za > -0.3 && zb > -0.3) continue;
          for (const lato of [1, -1]) {
            const na = [-pezzo[k - 1][4] * lato, pezzo[k - 1][3] * lato];
            const nb = [-pezzo[k][4] * lato, pezzo[k][3] * lato];
            const piede = hw + 1.2;
            const su = (P, nn, z, piu = 0) => [P[0] + nn[0] * (piede + -z * SCARPATA + piu), P[1] + nn[1] * (piede + -z * SCARPATA + piu)];
            const a = [pezzo[k - 1][0] + na[0] * piede, pezzo[k - 1][1] + na[1] * piede];
            const b = [pezzo[k][0] + nb[0] * piede, pezzo[k][1] + nb[1] * piede];
            // Fra due binari in trincea uno accanto all'altro niente scarpata:
            // la trincea è una, larga per tutti e due.
            const mezza = (-(za + zb) / 2) * SCARPATA * 0.5;
            const mm = [(a[0] + b[0]) / 2 + ((na[0] + nb[0]) / 2) * mezza, (a[1] + b[1]) / 2 + ((na[1] + nb[1]) / 2) * mezza];
            if (altriBinariInTrincea(mm[0], mm[1], f, mezza + 2.6)) continue;
            const ta = su(pezzo[k - 1], na, za);
            const tb = su(pezzo[k], nb, zb);
            const dentroN = [-(na[0] + nb[0]) / 2, -(na[1] + nb[1]) / 2, 0.8];
            const fuoriN = [-dentroN[0], -dentroN[1], -0.8];
            opere.quad([a[0], a[1], za], [b[0], b[1], zb], [tb[0], tb[1], 0.02], [ta[0], ta[1], 0.02], dentroN, ...sfuma(SCARPA, 0.72, 1));
            // Sotto la scarpata, un poco più giù: da fuori vince sul suo retro.
            const af = [pezzo[k - 1][0] + na[0] * (piede + 0.1), pezzo[k - 1][1] + na[1] * (piede + 0.1)];
            const bf = [pezzo[k][0] + nb[0] * (piede + 0.1), pezzo[k][1] + nb[1] * (piede + 0.1)];
            const atf = su(pezzo[k - 1], na, za, 0.15);
            const btf = su(pezzo[k], nb, zb, 0.15);
            maschera.quad([bf[0], bf[1], zb - 0.15], [af[0], af[1], za - 0.15], [atf[0], atf[1], -0.02], [btf[0], btf[1], -0.02], fuoriN);
            // Il fondo, dal binario al piede della scarpata.
            const c0 = [pezzo[k - 1][0] + na[0] * hw, pezzo[k - 1][1] + na[1] * hw];
            const c1 = [pezzo[k][0] + nb[0] * hw, pezzo[k][1] + nb[1] * hw];
            opere.quad([c0[0], c0[1], za + 0.02], [c1[0], c1[1], zb + 0.02], [b[0], b[1], zb + 0.02], [a[0], a[1], za + 0.02], [0, 0, 1], ...sfuma(GHIAIA, 0.9, 1));
          }
        }
      }
      /* «I binari continuano oltre il ponte alla stessa altezza, sospesi nel
       * vuoto»: una ferrovia che scavalca una strada sale al suo ponte (o
       * resta in alto fra due ponti vicini, come spesso in città), e fuori dal
       * ponte non aveva niente sotto. OpenMapTiles non dice se c'è un
       * terrapieno, ma dove i binari stanno in alto senza un ponte nella
       * realtà c'è sempre: qui un rilevato, la ghiaia in cima e le scarpate
       * d'erba fino a terra. Dove una strada passa accanto, al posto della
       * scarpata un muro di sostegno; sotto due binari affiancati il rilevato
       * è uno; dove finisce in alto (contro il ponte) lo chiude un muro. */
      if (f.cls === 'rail' && !f.ponte && pezzo.some((q) => q[2] > 0.35)) {
        const cima = hw + BANCHINA_RILEVATO;
        for (let k = 1; k < n; k++) {
          const A = pezzo[k - 1];
          const B = pezzo[k];
          const za = Math.max(0, A[2]);
          const zb = Math.max(0, B[2]);
          if (za < 0.35 && zb < 0.35) continue;
          // Appena sotto il binario.
          const ta = za + zs - 0.03;
          const tb = zb + zs - 0.03;
          const mx = (A[0] + B[0]) / 2;
          const my = (A[1] + B[1]) / 2;
          // Una strada che passa sotto (i binari la scavalcano senza un ponte
          // nei dati): lì niente terra sopra l'asfalto.
          if (za + zb > 5 && suStradaATerra(mx, my, 1, true)) continue;
          for (const lato of [1, -1]) {
            const na = [-A[4] * lato, A[3] * lato];
            const nb = [-B[4] * lato, B[3] * lato];
            const nm = [(na[0] + nb[0]) / 2, (na[1] + nb[1]) / 2];
            const P = (Q, nn, d, z) => [Q[0] + nn[0] * d, Q[1] + nn[1] * d, z];
            // Un altro binario in alto accanto: la ghiaia fino a lui, niente scarpata in mezzo.
            if (altriBinariAlti(mx + nm[0] * (hw + 2.4), my + nm[1] * (hw + 2.4), f, 2.6)) {
              opere.quad(P(A, na, hw - 0.05, ta), P(B, nb, hw - 0.05, tb), P(B, nb, hw + 2.6, tb), P(A, na, hw + 2.6, ta), [0, 0, 1], ...sfuma(GHIAIA, 0.9, 1));
              continue;
            }
            opere.quad(P(A, na, hw - 0.05, ta), P(B, nb, hw - 0.05, tb), P(B, nb, cima, tb), P(A, na, cima, ta), [0, 0, 1], ...sfuma(GHIAIA, 0.9, 1));
            const largo = ((za + zb) / 2) * SCARPATA;
            const strada = [0.3, 0.65, 1].some((u) => suStradaATerra(mx + nm[0] * (cima + largo * u), my + nm[1] * (cima + largo * u), 0.3, true));
            if (strada) {
              opere.quad(P(A, na, cima, 0), P(B, nb, cima, 0), P(B, nb, cima, tb), P(A, na, cima, ta), [nm[0], nm[1], 0], ...sfuma(cCemento, 0.66, 0.98));
            } else {
              const l = Math.hypot(1, SCARPATA);
              opere.quad(P(A, na, cima + za * SCARPATA, 0.02), P(B, nb, cima + zb * SCARPATA, 0.02), P(B, nb, cima, tb), P(A, na, cima, ta), [nm[0] / l, nm[1] / l, SCARPATA / l], ...sfuma(SCARPA, 0.72, 1));
            }
          }
        }
        // Dove il rilevato finisce in alto (contro il ponte), il muro di testa.
        for (const e of [0, n - 1]) {
          const Q = pezzo[e];
          const capo = e === 0 ? Q[5] < 0.5 : Q[5] > lungo[n0 - 1] - 0.5;
          if (!capo || Q[2] < 0.35 || !dentro(Q[0], Q[1])) continue;
          const dir = e === 0 ? -1 : 1;
          const nn = [-Q[4], Q[3]];
          const base = cima + Q[2] * SCARPATA;
          const P = (d, z) => [Q[0] + nn[0] * d, Q[1] + nn[1] * d, z];
          opere.quad(P(-base, 0), P(base, 0), P(cima, Q[2] + zs - 0.03), P(-cima, Q[2] + zs - 0.03), [Q[3] * dir, Q[4] * dir, 0], ...sfuma(cCemento, 0.66, 0.98));
        }
      }
      if (f.galleria || (f.cls === 'rail' && !f.ponte)) continue;

      // In quota: parapetti, travi, muri; e l'ombra sul terreno.
      for (let k = 1; k < n; k++) {
        const ha = pezzo[k - 1][2];
        const hb = pezzo[k][2];
        if (ha < 0.35 && hb < 0.35) continue;
        if (senza && nascostoA((pezzo[k - 1][5] + pezzo[k][5]) / 2)) continue;
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
          }
        }
        // Coi bordi presi dall'asfalto delle corsie (vedi [bordiSullAsfalto]).
        const sulleCorsie = (pezzo[k - 1][8] ?? 0) > 0.5 && (pezzo[k][8] ?? 0) > 0.5;
        /* Il piano dell'impalcato nei varchi dell'asfalto: dove fra due vie
         * resta un varco stretto (lo spartitraffico fra le due carreggiate
         * dello stesso viadotto, il cuneo dove una rampa si stacca) si vede
         * il cemento del ponte, non il vuoto fino al ventre. Solo nel varco,
         * da un bordo all'altro, ognuno alla quota del suo asfalto (e un
         * palmo sotto: due carreggiate non stanno mai proprio alla stessa). */
        const lungoTratto = Math.hypot(pezzo[k][0] - pezzo[k - 1][0], pezzo[k][1] - pezzo[k - 1][1]);
        const salta = (col) => Math.abs((pezzo[k][col] ?? hw) - (pezzo[k - 1][col] ?? hw)) > Math.max(1.5, 0.5 * lungoTratto);
        const [va, vb] = [varchi.get(pezzo[k - 1][5]), varchi.get(pezzo[k][5])];
        if (sulleCorsie && va && vb && va.length === vb.length) {
          const P = (q, o, z) => [q[0] - q[4] * o, q[1] + q[3] * o, z + 0.04];
          va.forEach((a, j) => {
            const b = vb[j];
            // (Lo stesso varco nei due punti: non uno che comincia dove l'altro è già finito.)
            const stesso = Math.max(1, 0.4 * lungoTratto);
            if (Math.abs(a[0] - b[0]) > stesso || Math.abs(a[2] - b[2]) > stesso) return;
            opere.quad(P(pezzo[k - 1], a[2] + 0.3, a[3]), P(pezzo[k], b[2] + 0.3, b[3]), P(pezzo[k], b[0] - 0.3, b[1]), P(pezzo[k - 1], a[0] - 0.3, a[1]), [0, 0, 1], ...sfuma(cCemento, 0.74, 0.74));
          });
        }
        for (const lato of [1, -1]) {
          const A = lato > 0 ? L : R;
          const onA = [-pezzo[k - 1][4] * lato, pezzo[k - 1][3] * lato];
          const onB = [-pezzo[k][4] * lato, pezzo[k][3] * lato];
          const fuori = (P0, on, d) => [P0[0] + on[0] * d, P0[1] + on[1] * d];
          const mix = (p, q, u) => p.map((v, i) => v + (q[i] - v) * u);
          const AA = A[k - 1];
          const BB = A[k];
          /* Dove il bordo dell'asfalto fa un salto di lato (comincia o
           * finisce l'asfalto di un'altra via accanto) da un punto all'altro
           * non c'è un bordo da seguire: un parapetto tirato fra i due
           * sarebbe un pezzo di traverso sulla carreggiata. */
          if (salta(lato > 0 ? 6 : 7)) continue;
          // E dove da questa parte l'asfalto continua oltre (la carreggiata
          // accanto sullo stesso impalcato): il bordo è il suo, più in là.
          const senzaBordo = lato > 0 ? 12 : 13;
          if ((pezzo[k - 1][senzaBordo] ?? 0) > 0.5 || (pezzo[k][senzaBordo] ?? 0) > 0.5) continue;
          // Sull'asfalto di un'altra strada (vedi [suAltraStrada]): dove il
          // bordo ci passa sopra solo in parte, si taglia a pezzi di 8 m.
          const sopraAltra = (u) => {
            const q = mix(AA, BB, u);
            const on = mix(onA, onB, u);
            const px = q[0] + on[0] * 0.12;
            const py = q[1] + on[1] * 0.12;
            // Sul bordo dell'asfalto delle corsie conta solo quello: le
            // strade della mappa stanno un poco altrove, e a guardare loro
            // il parapetto del bordo vero spariva a tratti.
            if (sulleCorsie) return conCorsie.inMezzoAllAsfalto(px, py, q[2], 0.5);
            // Con le corsie anche il loro asfalto: le vie vere sono spesso più
            // larghe della strada della mappa, e un parapetto in mezzo a una
            // corsia (fra due rampe che si separano) non c'è.
            // Basta mezzo metro dentro: il ponte della mappa è spesso più
            // stretto delle corsie vere, e il suo parapetto correva
            // sull'asfalto a un metro dal bordo, entrando e uscendo a zig-zag.
            if (suAltraStrada(px, py, q[2], fi) || conCorsie?.inMezzoAllAsfalto(px, py, q[2], 0.5)) return true;
            // Fra due rampe che si separano, finché sono a meno di due metri
            // l'una dall'altra, c'è la zebratura sull'asfalto, non un muro.
            return suAltraStrada(q[0] + on[0] * 2, q[1] + on[1] * 2, q[2], fi);
          };
          const prove = [0.05, 0.25, 0.5, 0.75, 0.95].map(sopraAltra);
          const misto = prove.some((x) => x) && !prove.every((x) => x);
          const pezzi = misto ? Math.max(1, Math.ceil(Math.hypot(BB[0] - AA[0], BB[1] - AA[1]) / 8)) : 1;
          for (let j = 0; j < pezzi; j++) {
            const u0 = j / pezzi;
            const u1 = (j + 1) / pezzi;
            const a = pezzi === 1 ? AA : mix(AA, BB, u0);
            const b = pezzi === 1 ? BB : mix(AA, BB, u1);
            const on0 = pezzi === 1 ? onA : mix(onA, onB, u0);
            const on1 = pezzi === 1 ? onB : mix(onA, onB, u1);
            const nrm = [(on0[0] + on1[0]) / 2, (on0[1] + on1[1]) / 2, 0];
            const inr = [-nrm[0], -nrm[1], 0];
            const sopra = pezzi === 1 ? prove[2] && prove.every((x) => x) : sopraAltra((u0 + u1) / 2);
            if (sopra) continue;
            if (f.cls !== 'rail' && !f.cucita && (sulleCorsie || !vicinoASvincolo((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 40))) {
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
          if (!capo || P[2] < 2.5 || !dentro(P[0], P[1]) || nascostoA(P[5])) continue;
          const dir = e === 0 ? -1 : 1;
          // Larga quanto la strada com'è disegnata lì (nella vista «Corsie»
          // l'asfalto delle vie vere: larga quanto la strada della mappa,
          // spuntava di lato fra le due carreggiate).
          const mezzaSpalla = ((P[6] ?? hw) + (P[7] ?? hw)) / 2;
          const diLato = ((P[6] ?? hw) - (P[7] ?? hw)) / 2;
          // Un ponte spezzato in più pezzi può finire sopra una strada: lì niente spalla.
          const cx0 = P[0] + P[3] * 0.7 * dir - P[4] * diLato;
          const cy0 = P[1] + P[4] * 0.7 * dir + P[3] * diLato;
          let sullaStrada = false;
          for (let q = -1; q <= 1; q += 0.5) if (suStradaATerra(cx0 - P[4] * mezzaSpalla * q, cy0 + P[3] * mezzaSpalla * q, 1)) sullaStrada = true;
          if (sullaStrada) continue;
          // Nella vista «Corsie» l'asfalto che si vede è quello delle vie
          // vere, che qui può stare mezzo metro più giù del ponte della
          // mappa (la sua rampa scende prima): la spalla, larga quanto la
          // strada, spuntava dall'asfalto — una riga di cemento di traverso
          // su tutta la carreggiata. Resta sotto l'asfalto che ha sopra.
          let cima = P[2] + zs - 0.1;
          if (conCorsie) {
            for (let q = -1; q <= 1; q += 0.25) {
              for (const lungoVia of [0, 0.7, 1.4]) {
                const z = conCorsie.asfaltoQui(P[0] + P[3] * lungoVia * dir - P[4] * (diLato + (mezzaSpalla + 0.35) * q), P[1] + P[4] * lungoVia * dir + P[3] * (diLato + (mezzaSpalla + 0.35) * q), P[2]);
                if (z !== null) cima = Math.min(cima, z - SOTTO_L_ASFALTO_M);
              }
            }
          }
          if (cima < 1) continue;
          scatola(cx0, cy0, 0, cima, P[3], P[4], 0.7, mezzaSpalla + 0.35, cCemento);
        }
      }
      // I piloni: ai due lati di ogni strada che passa sotto (mai sopra), e
      // ogni trenta metri nel resto del ponte (e delle salite alte).
      if (f.ponte || pezzo.some((q) => q[2] > ALTO_COME_PONTE)) {
        const aS = (sv) => {
          let k = 1;
          while (k < n - 1 && pezzo[k][5] < sv) k++;
          const t = Math.max(0, Math.min(1, (sv - pezzo[k - 1][5]) / Math.max(1e-6, pezzo[k][5] - pezzo[k - 1][5])));
          return [0, 1, 2, 3, 4, 6, 7].map((j) => (pezzo[k - 1][j] ?? hw) + ((pezzo[k][j] ?? hw) - (pezzo[k - 1][j] ?? hw)) * t);
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
          if (sv < pezzo[0][5] || sv > pezzo[n - 1][5] || !libero(sv) || nascostoA(sv)) return false;
          const [x0, y0, h, tx, ty, sinistra, destra] = aS(sv);
          if (h < (f.ponte ? 2.5 : ALTO_COME_PONTE)) return false;
          const tl = Math.hypot(tx, ty) || 1;
          // Sotto l'impalcato com'è disegnato lì (nella vista «Corsie» largo
          // quanto l'asfalto delle vie vere, e non sempre sul mezzo della
          // strada della mappa: il capitello, largo quanto lei, spuntava di lato).
          const larga = Math.min(sinistra + destra, f.w + 2 * OLTRE_IL_BORDO_M);
          if (larga < 2) return false;
          const diLato = (sinistra - destra) / 2;
          const px = x0 - (ty / tl) * diLato;
          const py = y0 + (tx / tl) * diLato;
          const offs = larga > 9 ? [-larga * 0.27, larga * 0.27] : [0];
          for (const o of offs) if (suStradaATerra(px - (ty / tl) * o, py + (tx / tl) * o, 0.8) || suStradaSotto(px - (ty / tl) * o, py + (tx / tl) * o, 0.8, h)) return false;
          piloni.push({ x: px, y: py, h: h + zs - SPESSORE_IMPALCATO, ang: Math.atan2(ty, tx), w: larga, offs, alto: h > 14 });
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
            if (nascostoA(prossimo)) {
              prossimo += 48;
              continue;
            }
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
  /* Le pensiline dei caselli.
   *
   * «Verifica i caselli autostradali e tangenziale»: gli edifici veri
   * (Overture) hanno anche le pensiline dei caselli, ma senza dire che sono
   * tettoie: la scena le tirava su come palazzi con le finestre, di traverso
   * sulle corsie, e il percorso ci passava dentro. Un edificio attraversato
   * da un'autostrada, una tangenziale o una strada a pedaggio (che non sia in
   * galleria) non è un palazzo: è un tetto su pilastri, con la strada sotto.
   * Solo quelle strade: una stradina di servizio che entra in un capannone, o
   * un vicolo che l'impronta di una casa copre di un metro, restano com'erano.
   */
  const GP = 20;
  const corsie = new Map();
  linee.forEach((pts, i) => {
    const f = visibili[i];
    if (f.galleria || f.cls === 'rail' || !(f.cls === 'motorway' || f.cls === 'trunk' || f.pedaggio)) return;
    for (let k = 1; k < pts.length; k++) {
      const a = pts[k - 1];
      const c = pts[k];
      const n = Math.max(1, Math.ceil(Math.hypot(c[0] - a[0], c[1] - a[1]) / 3));
      for (let q = k === 1 ? 0 : 1; q <= n; q++) {
        const t = q / n;
        const px = a[0] + (c[0] - a[0]) * t;
        const py = a[1] + (c[1] - a[1]) * t;
        const key = Math.floor(px / GP) + ',' + Math.floor(py / GP);
        if (!corsie.has(key)) corsie.set(key, []);
        corsie.get(key).push([px, py, a[2] + (c[2] - a[2]) * t, f.w / 2]);
      }
    }
  });
  /**
   * La strada che passa sotto l'edificio (almeno sei metri di corsia), o
   * `null`: la sua [quota] più alta lì sotto, e se è [piana]. Dove le corsie
   * salgono o stanno a piani diversi (un casello su un viadotto con le sue
   * rampe: fra undici e ventiquattro metri) un tetto solo non le copre, e
   * finiva a trenta metri su pilastri sottili: lì non si disegna niente.
   */
  const corsiaSotto = (anelli) => {
    if (!corsie.size) return null;
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
    let dentro = 0;
    let quota = -Infinity;
    let bassa = Infinity;
    for (let cx = Math.floor(minx / GP); cx <= Math.floor(maxx / GP); cx++) {
      for (let cy = Math.floor(miny / GP); cy <= Math.floor(maxy / GP); cy++) {
        for (const [px, py, ph] of corsie.get(cx + ',' + cy) || []) {
          if (!puntoDentroPoligono(px, py, anelli)) continue;
          dentro++;
          if (ph > quota) quota = ph;
          if (ph < bassa) bassa = ph;
        }
      }
    }
    return dentro >= 3 ? { quota, piana: quota - bassa <= DISLIVELLO_PENSILINA } : null;
  };
  const sullaCorsia = (px, py) => {
    for (let ax = -1; ax <= 1; ax++) {
      for (let ay = -1; ay <= 1; ay++) {
        for (const [qx, qy, , hw] of corsie.get(Math.floor(px / GP) + ax + ',' + (Math.floor(py / GP) + ay)) || []) {
          if (Math.hypot(qx - px, qy - py) < hw + 1.2) return true;
        }
      }
    }
    return false;
  };
  const STILI = STILI_FACCIATA;
  const facciate = Object.fromEntries(STILI.map((s) => [s, new Costruttore({ uv: true, colori: true })]));
  const tetti = new Costruttore({ colori: true });
  /** Una pensilina: il tetto di [b] a [sotto] metri, spesso [SPESSORE_PENSILINA], sui suoi pilastri. */
  const pensilina = (b, sotto) => {
    const sopra = sotto + SPESSORE_PENSILINA;
    const piatti = [];
    const buchi = [];
    for (const [k, anello] of b.anelli.entries()) {
      if (k) buchi.push(piatti.length / 2);
      for (const [px, py] of anello.pts) piatti.push(px, py);
    }
    const facce = earcut(piatti, buchi.length ? buchi : null, 2);
    const P = (i, z) => [piatti[2 * i], piatti[2 * i + 1], z];
    for (let k = 0; k < facce.length; k += 3) {
      const [i0, i1, i2] = [facce[k], facce[k + 1], facce[k + 2]];
      tetti.triPunti(P(i0, sopra), P(i1, sopra), P(i2, sopra), [0, 0, 1], PENSILINA.tetto[0], PENSILINA.tetto[1]);
      tetti.triPunti(P(i0, sotto), P(i1, sotto), P(i2, sotto), [0, 0, -1], PENSILINA.ventre[0], PENSILINA.ventre[1]);
      // L'ombra: stesa col sole, e a piombo (sotto una pensilina è più scuro).
      ombre.triPunti(
        [piatti[2 * i0] + sox * sopra, piatti[2 * i0 + 1] + soy * sopra, 0],
        [piatti[2 * i1] + sox * sopra, piatti[2 * i1 + 1] + soy * sopra, 0],
        [piatti[2 * i2] + sox * sopra, piatti[2 * i2 + 1] + soy * sopra, 0],
        [0, 0, 1],
      );
      ombre.triPunti(P(i0, 0), P(i1, 0), P(i2, 0), [0, 0, 1]);
    }
    // La fascia attorno, e i pilastri lungo il bordo: mai su una corsia.
    let cx = 0;
    let cy = 0;
    for (const [px, py] of b.anelli[0].pts) {
      cx += px / b.anelli[0].pts.length;
      cy += py / b.anelli[0].pts.length;
    }
    let pilastri = 0;
    let ultimo = null;
    for (const [k, anello] of b.anelli.entries()) {
      const p = anello.pts;
      const ccw = area(p) < 0 !== k > 0;
      for (let i = 0; i < p.length; i++) {
        const a = p[i];
        const c = p[(i + 1) % p.length];
        const l = Math.hypot(c[0] - a[0], c[1] - a[1]);
        if (!anello.muro[i] || l < 0.01) continue;
        let nx = (c[1] - a[1]) / l;
        let ny = -(c[0] - a[0]) / l;
        if (!ccw) {
          nx = -nx;
          ny = -ny;
        }
        tetti.quad([a[0], a[1], sotto], [c[0], c[1], sotto], [c[0], c[1], sopra], [a[0], a[1], sopra], [nx, ny, 0], PENSILINA.fascia[0], PENSILINA.fascia[1]);
        if (k) continue;
        const passi = Math.max(1, Math.round(l / 12));
        for (let q = 0; q < passi && pilastri < 24; q++) {
          const t = q / passi;
          // Un poco dentro il bordo, verso il mezzo della pensilina.
          let px = a[0] + (c[0] - a[0]) * t;
          let py = a[1] + (c[1] - a[1]) * t;
          const d = Math.hypot(cx - px, cy - py) || 1;
          px += ((cx - px) / d) * 0.7;
          py += ((cy - py) / d) * 0.7;
          if (ultimo && Math.hypot(px - ultimo[0], py - ultimo[1]) < 4) continue;
          if (sullaCorsia(px, py)) continue;
          scatola(px, py, 0, sotto, 1, 0, 0.3, 0.3, cCemento);
          ultimo = [px, py];
          pilastri++;
        }
      }
    }
  };
  let triEdifici = 0;
  let edificiFatti = 0;
  let edificiLeggeri = 0;
  const seme = semeTessera(z, x, y);
  for (const [bi, b] of edificiOut.entries()) {
    if (triEdifici > lim.triangoliEdifici) break;
    // Leggero: solo il muro e il tetto (vedi [LIMITI]).
    const leggero = triEdifici >= (lim.leggeriOltre ?? Infinity);
    // Colore, facciata e tetto dall'id dell'edificio, non dalla tessera: un
    // palazzo a cavallo di due tessere si disegna a pezzi, e ogni pezzo
    // prendeva il suo colore e la sua facciata («a destra la facciata
    // giusta, al centro un'altra: non è così il palazzo»).
    const r = generatore(b.seme);
    // Una pensilina (un casello): la strada le passa sotto, a qualunque quota.
    const corsia = b.mh < 1 ? corsiaSotto(b.anelli.map((a) => a.pts)) : null;
    if (corsia !== null) {
      if (!corsia.piana) continue;
      const prima = tetti.triangoli + ombre.triangoli + opere.triangoli;
      pensilina(b, corsia.quota + LUCE_PENSILINA);
      triEdifici += tetti.triangoli + ombre.triangoli + opere.triangoli - prima;
      edificiFatti++;
      continue;
    }
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
    let cornice = cg.map((c) => Math.round(c + (255 - c) * 0.7));
    let sottoCornice = cg.map((c) => Math.round(c * 0.68));
    const corniceNotte = cn.map((c) => Math.round(c * 0.8));
    // Nella vista «Corsie» blocchi bianchi e grigio chiaro, col bordo del
    // tetto appena più scuro (come le mappe delle corsie): la forma resta,
    // i colori delle case no.
    if (vistaCorsie) {
      const t = 0.94 + r() * 0.06;
      const base = rgb(CORSIE_FACCIATE[Math.floor(r() * CORSIE_FACCIATE.length)]).map((c) => Math.round(c * t));
      for (let j = 0; j < 3; j++) cg[j] = base[j];
      cornice = cg.map((c) => Math.round(c * 0.86));
      sottoCornice = cg.map((c) => Math.round(c * 0.93));
    }
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
          if (leggero) {
            per += l;
            continue;
          }
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
    const rg = vistaCorsie ? rgb('#f7f8fa') : rgb(rp[0][ri]);
    const rn = rgb(rp[1][ri]);
    for (let k = 0; k < facce.length; k += 3) {
      const [i0, i1, i2] = [facce[k], facce[k + 1], facce[k + 2]];
      tetti.triPunti([piatti[2 * i0], piatti[2 * i0 + 1], h], [piatti[2 * i1], piatti[2 * i1 + 1], h], [piatti[2 * i2], piatti[2 * i2 + 1], h], [0, 0, 1], rg, rn);
      if (m0 < 1 && !leggero) {
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
    if (leggero) edificiLeggeri++;
  }

  // ── Gli alberi ────────────────────────────────────────────────────────
  const alberi = lim.alberi > 0 ? piantaAlberi({ centro, sys, x, y, linee, visibili, edifici: edificiOut, limite: lim.alberi, seme, verdi: vistaCorsie }) : [];
  // Nella vista «Corsie» anche gli alberi veri di OpenStreetMap, uno per uno
  // (`natural=tree`) e i filari (`natural=tree_row`): dove la mappa non ne ha,
  // niente alberi.
  if (conCorsie && lim.alberi > 0) {
    for (const [ax, ay, sc] of conCorsie.alberi) {
      if (alberi.length >= lim.alberi * 2) break;
      alberi.push([ax, ay, sc, 0, Math.floor(mescola(Math.round(ax * 10), Math.round(ay * 10)) * 100000)]);
    }
  }
  // Le ombre degli alberi: macchie tonde e sfumate (una trama), non esagoni.
  const ombreAlberi = new Costruttore({ uv: true });
  const istanzeAlberi = istanzeDiAlberi(alberi, ombreAlberi);

  // ── I lampioni ────────────────────────────────────────────────────────
  // Con le corsie la strada è larga quanto è davvero: un lampione messo al
  // bordo del nastro di sempre può finire in mezzo all'asfalto.
  const lamp = lampioni.filter((l) => dentro(l.x, l.y) && !conCorsie?.sullAsfalto(l.x, l.y)).slice(0, lim.lampioni);
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

  // La segnaletica delle corsie: asfalto, vernice, semafori.
  let segnaletica = null;
  let semafori = [];
  if (conCorsie) {
    // Le rotonde della tessera, dal grafo: centro e raggio dell'anello.
    const rotonde = [...new Set(nodi.map((n) => n.centroRotonda).filter(Boolean))];
    const sg = costruisciSegnaletica({ strade: conCorsie.strade, nodi: conCorsie.nodi, sopra: sopraCorsie, meta, rotonde });
    segnaletica = {
      asfalto: sg.asfalto.triangoli ? sg.asfalto.fatto() : null,
      vernice: sg.vernice.triangoli ? sg.vernice.fatto() : null,
      segnali: sg.segnali.triangoli ? sg.segnali.fatto() : null,
      marciapiedi: sg.marciapiedi.triangoli ? sg.marciapiedi.fatto() : null,
    };
    semafori = sg.semafori;
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
    maschera: maschera.triangoli ? maschera.fatto() : null,
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
    corsie: segnaletica,
    // Dove stanno i semafori (x, y, la cima, la quota della strada): il loro segno sulla pagina.
    semafori: new Float32Array(semafori),
  };
  const triStrade = Object.values(nastri).reduce((s, g) => s + g.triangoli, 0);
  out.conti = {
    strade: triStrade,
    opere: opere.triangoli,
    ombre: ombre.triangoli + ombrePonti.triangoli + ombreAlberi.triangoli,
    edifici: triEdifici,
    edificiFatti,
    edificiLeggeri,
    edificiTotali: edificiOut.length,
    piloni: piloni.length,
    alberi: alberi.length,
    lampioni: lamp.length,
    nodi: nodi.length,
    msGrafo: tGrafo,
    ms: Date.now() - t0,
  };
  out.conti.triangoli = stimaTriangoli(out);
  if (grafoPerIlCollaudo) out.grafo = { ...grafoPerIlCollaudo, corsie: conCorsie?.strade ?? null, latiSegmenti };
  return out;
}

/** Mai più stretta di così una strada fra le case (m). */
const STRETTA_MIN_M = 3;
/** Di quanto può cambiare la larghezza di una strada per metro, stringendosi fra le case. */
const STRETTA_PASSO = 0.15;

/**
 * Le strade strette fra le case. La larghezza viene dalla classe
 * ([larghezzaStrada]), e nei vicoli del centro, con le case a filo strada,
 * l'asfalto entrava nelle facciate («le case si sovrappongono alle
 * strade»). Qui, a ogni nodo di ogni strada a terra, si misura quanto c'è
 * fino alla facciata a sinistra e a destra; la strada lì arriva fin quasi
 * alla facciata (trenta centimetri prima), mai sotto [STRETTA_MIN_M] in
 * tutto, e la sua larghezza cambia piano ([STRETTA_PASSO] per metro).
 * [poligoni]: i contorni degli edifici, in metri. Mette in [feats] che si
 * stringono `larghezze`: per ogni nodo `[sinistra, destra]` (mezze
 * larghezze). Dove la strada passa sotto un palazzo (un androne) resta così.
 */
export function strettaFraLeCase(feats, nodi, poligoni) {
  if (!poligoni.length) return 0;
  const G = 20;
  const griglia = new Map();
  poligoni.forEach((poly, i) => {
    let x0 = Infinity;
    let y0 = Infinity;
    let x1 = -Infinity;
    let y1 = -Infinity;
    for (const [px, py] of poly) {
      x0 = Math.min(x0, px);
      y0 = Math.min(y0, py);
      x1 = Math.max(x1, px);
      y1 = Math.max(y1, py);
    }
    for (let gx = Math.floor(x0 / G); gx <= Math.floor(x1 / G); gx++) {
      for (let gy = Math.floor(y0 / G); gy <= Math.floor(y1 / G); gy++) {
        const k = gx + ',' + gy;
        if (!griglia.has(k)) griglia.set(k, []);
        griglia.get(k).push(i);
      }
    }
  });
  // La distanza dal punto alla facciata più vicina da un lato ([nx, ny] verso
  // quel lato), guardando fino a [fin] metri: Infinity se non ce n'è, e
  // null se il punto sta dentro un palazzo (un androne).
  const lato = (px, py, nx, ny, fin) => {
    let d = Infinity;
    const qx = px + nx * fin;
    const qy = py + ny * fin;
    const visti = new Set();
    for (let gx = Math.floor(Math.min(px, qx) / G); gx <= Math.floor(Math.max(px, qx) / G); gx++) {
      for (let gy = Math.floor(Math.min(py, qy) / G); gy <= Math.floor(Math.max(py, qy) / G); gy++) {
        for (const i of griglia.get(gx + ',' + gy) ?? []) {
          if (visti.has(i)) continue;
          visti.add(i);
          const poly = poligoni[i];
          let dentro = false;
          for (let j = 0, m = poly.length - 1; j < poly.length; m = j++) {
            const [ax, ay] = poly[m];
            const [bx, by] = poly[j];
            if (ay > py !== by > py && px < ((bx - ax) * (py - ay)) / (by - ay) + ax) dentro = !dentro;
            const ex = bx - ax;
            const ey = by - ay;
            const den = nx * ey - ny * ex;
            if (Math.abs(den) < 1e-9) continue;
            const t = ((ax - px) * ey - (ay - py) * ex) / den;
            const u = ((ax - px) * ny - (ay - py) * nx) / den;
            if (t >= 0 && t < d && u >= 0 && u <= 1) d = t;
          }
          if (dentro) return null;
        }
      }
    }
    return d;
  };
  let strette = 0;
  for (const f of feats) {
    if (f.ponte || f.galleria || f.cls === 'rail') continue;
    const n = f.nodi.length;
    if (n < 2) continue;
    const hw = f.w / 2;
    const sx = new Float64Array(n).fill(hw);
    const dx = new Float64Array(n).fill(hw);
    let stretta = false;
    // Lungo ogni tratto, un punto ogni due metri: lo spazio più stretto vale
    // per i due nodi del tratto (fra un nodo e l'altro lo spigolo di una casa
    // può sporgere).
    for (let k = 1; k < n; k++) {
      const a = nodi[f.nodi[k - 1]];
      const b = nodi[f.nodi[k]];
      const l = Math.hypot(b.x - a.x, b.y - a.y);
      if (!l) continue;
      const nx = -(b.y - a.y) / l;
      const ny = (b.x - a.x) / l;
      for (let t = 0; t <= l; t += 2) {
        const px = a.x + ((b.x - a.x) * Math.min(t, l)) / l;
        const py = a.y + ((b.y - a.y) * Math.min(t, l)) / l;
        const ls = lato(px, py, nx, ny, hw + 1);
        const ld = lato(px, py, -nx, -ny, hw + 1);
        if (ls === null || ld === null) continue;
        if (ls < hw + 0.3) {
          sx[k - 1] = Math.min(sx[k - 1], ls - 0.3);
          sx[k] = Math.min(sx[k], ls - 0.3);
          stretta = true;
        }
        if (ld < hw + 0.3) {
          dx[k - 1] = Math.min(dx[k - 1], ld - 0.3);
          dx[k] = Math.min(dx[k], ld - 0.3);
          stretta = true;
        }
      }
    }
    for (let k = 0; k < n; k++) {
      // Al minimo in tutto allargandosi dal lato libero, se c'è; con le case
      // da tutte e due le parti il vicolo è stretto davvero (non meno di 1,6 m).
      sx[k] = Math.max(sx[k], 0.3);
      dx[k] = Math.max(dx[k], 0.3);
      const manca = STRETTA_MIN_M - sx[k] - dx[k];
      if (manca > 0) {
        if (sx[k] >= hw - 0.01) sx[k] += manca;
        else if (dx[k] >= hw - 0.01) dx[k] += manca;
      }
    }
    if (!stretta) continue;
    // Piano: la larghezza cambia al più di STRETTA_PASSO per metro.
    const s = [0];
    for (let k = 1; k < n; k++) s.push(s[k - 1] + Math.hypot(nodi[f.nodi[k]].x - nodi[f.nodi[k - 1]].x, nodi[f.nodi[k]].y - nodi[f.nodi[k - 1]].y));
    for (const v of [sx, dx]) {
      for (let k = 1; k < n; k++) v[k] = Math.min(v[k], v[k - 1] + STRETTA_PASSO * (s[k] - s[k - 1]));
      for (let k = n - 2; k >= 0; k--) v[k] = Math.min(v[k], v[k + 1] + STRETTA_PASSO * (s[k + 1] - s[k]));
    }
    f.larghezze = [...sx].map((v, k) => [v, dx[k]]);
    strette++;
  }
  return strette;
}

/** L'isola in mezzo a una rotonda: almeno questo raggio (m). */
const ISOLA_MIN_M = 1.8;
/** E la carreggiata dell'anello, dalla parte dell'isola, almeno questa mezza larghezza (m). */
const ANELLO_MIN_M = 1.6;

/**
 * Le rotonde piccole: la carreggiata dell'anello non entra nell'isola.
 *
 * «Verifica le rotonde»: una rotonda di cinque metri di raggio con una
 * carreggiata larga sette, il bordo di dentro passava oltre il centro e si
 * incrociava con se stesso: l'isola usciva a punta, coi marciapiedi di
 * traverso e le righe una sopra l'altra. Dalla parte dell'isola la
 * carreggiata si stringe fino a lasciarle [ISOLA_MIN_M] metri (mai sotto
 * [ANELLO_MIN_M]); dalla parte di fuori resta com'e'. Mette `larghezze`.
 */
export function isolaDelleRotonde(feats, nodi) {
  let cambiate = 0;
  for (const f of feats) {
    if (f.galleria || f.cls === 'rail' || f.nodi.length < 2) continue;
    if (!f.nodi.every((i) => nodi[i].centroRotonda)) continue;
    const n = f.nodi.length;
    const hw = f.w / 2;
    const lati = f.larghezze ? f.larghezze.map((q) => [...q]) : Array.from({ length: n }, () => [hw, hw]);
    let toccata = false;
    for (let k = 0; k < n; k++) {
      const p = nodi[f.nodi[k]];
      const c = p.centroRotonda;
      const massimo = Math.max(ANELLO_MIN_M, c.r - ISOLA_MIN_M);
      const a = nodi[f.nodi[Math.max(0, k - 1)]];
      const b = nodi[f.nodi[Math.min(n - 1, k + 1)]];
      // Il centro a sinistra (prodotto positivo) o a destra della strada.
      const sinistra = (b.x - a.x) * (c.y - p.y) - (b.y - a.y) * (c.x - p.x) > 0;
      const q = sinistra ? 0 : 1;
      if (lati[k][q] > massimo) {
        lati[k][q] = massimo;
        toccata = true;
      }
    }
    if (!toccata) continue;
    f.larghezze = lati;
    cambiate++;
  }
  return cambiate;
}

/** Quanto si stringe per metro una carreggiata dalla parte dell'altra: alle
 * biforcazioni strette i rami si staccano in pochi metri, come la cuspide fra
 * le due (più svelto delle case, [STRETTA_PASSO]). */
const AFFIANCATE_PASSO = 0.6;
/** Ogni quanto un punto in più, sui tratti lunghi accanto a un'altra carreggiata. */
const AFFIANCATE_PUNTI_M = 1.5;

/**
 * Le carreggiate affiancate a quote diverse (due rampe una accanto
 * all'altra, una che sale e una che scende): le linee delle tessere stanno
 * più vicine della somma delle due mezze larghezze, e i due nastri si
 * sovrapponevano di lato, uno dentro l'altro. Ognuna si stringe dal lato
 * dell'altra fino a metà dello spazio fra le due linee (mai sotto 0,8 m), e
 * la larghezza cambia piano. Sui tratti lunghi lì accanto mette dei punti in
 * più (la larghezza fra due punti cambia dritta, e alla biforcazione il
 * cuneo è corto). Mette `larghezze` (vedi [strettaFraLeCase]).
 */
export function carreggiateAffiancate(feats, nodi) {
  const G = 15;
  const usabile = (f) => !f.galleria && f.cls !== 'rail' && f.nodi.length >= 2;
  let griglia;
  const indicizza = () => {
    griglia = new Map();
    feats.forEach((f, fi) => {
      if (!usabile(f)) return;
      for (let k = 1; k < f.nodi.length; k++) {
        const a = nodi[f.nodi[k - 1]];
        const b = nodi[f.nodi[k]];
        for (let gx = Math.floor(Math.min(a.x, b.x) / G); gx <= Math.floor(Math.max(a.x, b.x) / G); gx++) {
          for (let gy = Math.floor(Math.min(a.y, b.y) / G); gy <= Math.floor(Math.max(a.y, b.y) / G); gy++) {
            const key = gx + ',' + gy;
            if (!griglia.has(key)) griglia.set(key, []);
            griglia.get(key).push([fi, k]);
          }
        }
      }
    });
  };
  // Le altre carreggiate quasi parallele a quota diversa vicino al punto
  // (x, y, h) della strada fi, che va nella direzione (tx, ty): per ognuna
  // la distanza e se sta a sinistra.
  const accanto = (fi, x, y, h, tx, ty, salta) => {
    const out = [];
    const visti = new Set();
    for (let ox = -1; ox <= 1; ox++) {
      for (let oy = -1; oy <= 1; oy++) {
        for (const [gi, gk] of griglia.get(Math.floor(x / G) + ox + ',' + (Math.floor(y / G) + oy)) ?? []) {
          if (gi === fi || visti.has(gi * 100000 + gk)) continue;
          visti.add(gi * 100000 + gk);
          const g = feats[gi];
          if (salta !== undefined && (salta === g.nodi[gk - 1] || salta === g.nodi[gk])) continue;
          const c = nodi[g.nodi[gk - 1]];
          const d = nodi[g.nodi[gk]];
          const ex = d.x - c.x;
          const ey = d.y - c.y;
          const el = Math.hypot(ex, ey) || 1;
          if (Math.abs((ex * tx + ey * ty) / el) < 0.85) continue;
          const u = Math.max(0, Math.min(1, ((x - c.x) * ex + (y - c.y) * ey) / (el * el)));
          const qx = c.x + ex * u;
          const qy = c.y + ey * u;
          // Alla stessa quota sono una strada sola; sotto un viadotto (oltre
          // 4,5 m) passano una sotto l'altra e non si toccano.
          const dz = Math.abs(c.h + (d.h - c.h) * u - h);
          if (dz <= 0.6 || dz >= 4.5) continue;
          const dist = Math.hypot(qx - x, qy - y);
          if (dist >= (feats[fi].w + g.w) / 2) continue;
          out.push([dist, tx * (qy - y) - ty * (qx - x) > 0]);
        }
      }
    }
    return out;
  };
  indicizza();
  // I punti in più sui tratti lunghi che corrono accanto a un'altra: prima
  // si sceglie dove (la griglia guarda i tratti com'erano), poi si mettono.
  const daInfittire = feats.map((f, fi) => {
    const tratti = new Set();
    if (!usabile(f)) return tratti;
    for (let k = 1; k < f.nodi.length; k++) {
      const a = nodi[f.nodi[k - 1]];
      const b = nodi[f.nodi[k]];
      const l = Math.hypot(b.x - a.x, b.y - a.y);
      if (Math.floor(l / AFFIANCATE_PUNTI_M) < 2) continue;
      const tx = (b.x - a.x) / l;
      const ty = (b.y - a.y) / l;
      if ([0.25, 0.5, 0.75].some((t) => accanto(fi, a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.h + (b.h - a.h) * t, tx, ty).length)) tratti.add(k);
    }
    return tratti;
  });
  let aggiunti = 0;
  feats.forEach((f, fi) => {
    if (!daInfittire[fi].size) return;
    const nuovi = [f.nodi[0]];
    const larghe = f.larghezze ? [f.larghezze[0]] : null;
    for (let k = 1; k < f.nodi.length; k++) {
      if (daInfittire[fi].has(k)) {
        const a = nodi[f.nodi[k - 1]];
        const b = nodi[f.nodi[k]];
        const quanti = Math.floor(Math.hypot(b.x - a.x, b.y - a.y) / AFFIANCATE_PUNTI_M);
        for (let q = 1; q < quanti; q++) {
          const t = q / quanti;
          nuovi.push(nodi.length);
          nodi.push({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, h: a.h + (b.h - a.h) * t, adj: [], feats: [fi], fisso: null });
          if (larghe) {
            const [s0, d0] = f.larghezze[k - 1];
            const [s1, d1] = f.larghezze[k];
            larghe.push([s0 + (s1 - s0) * t, d0 + (d1 - d0) * t]);
          }
          aggiunti++;
        }
      }
      nuovi.push(f.nodi[k]);
      if (larghe) larghe.push(f.larghezze[k]);
    }
    f.nodi = nuovi;
    if (larghe) f.larghezze = larghe;
  });
  if (aggiunti) indicizza();
  let cambiate = 0;
  feats.forEach((f, fi) => {
    if (!usabile(f)) return;
    const n = f.nodi.length;
    const hw = f.w / 2;
    const sx = Float64Array.from(f.larghezze ? f.larghezze.map((q) => q[0]) : new Array(n).fill(hw));
    const dx = Float64Array.from(f.larghezze ? f.larghezze.map((q) => q[1]) : new Array(n).fill(hw));
    let toccata = false;
    for (let k = 0; k < n; k++) {
      const p = nodi[f.nodi[k]];
      const a = nodi[f.nodi[Math.max(0, k - 1)]];
      const b = nodi[f.nodi[Math.min(n - 1, k + 1)]];
      const l = Math.hypot(b.x - a.x, b.y - a.y) || 1;
      for (const [dist, sinistra] of accanto(fi, p.x, p.y, p.h, (b.x - a.x) / l, (b.y - a.y) / l, f.nodi[k])) {
        const meta = Math.max(0.8, dist / 2 - 0.05);
        if (sinistra && meta < sx[k]) {
          sx[k] = meta;
          toccata = true;
        } else if (!sinistra && meta < dx[k]) {
          dx[k] = meta;
          toccata = true;
        }
      }
    }
    if (!toccata) return;
    const s = [0];
    for (let k = 1; k < n; k++) s.push(s[k - 1] + Math.hypot(nodi[f.nodi[k]].x - nodi[f.nodi[k - 1]].x, nodi[f.nodi[k]].y - nodi[f.nodi[k - 1]].y));
    for (const v of [sx, dx]) {
      for (let k = 1; k < n; k++) v[k] = Math.min(v[k], v[k - 1] + AFFIANCATE_PASSO * (s[k] - s[k - 1]));
      for (let k = n - 2; k >= 0; k--) v[k] = Math.min(v[k], v[k + 1] + AFFIANCATE_PASSO * (s[k + 1] - s[k]));
    }
    f.larghezze = [...sx].map((v, k) => [v, dx[k]]);
    cambiate++;
  });
  return cambiate;
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
  if (t.corsie) for (const g of Object.values(t.corsie)) n += tri(g);
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
function piantaAlberi({ centro, sys, x, y, linee, visibili, edifici, limite, seme, verdi = false }) {
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
    // Nella vista «Corsie» ([verdi]) anche i giardini e le aree verdi di città.
    ['landcover', (c, p) => ['wood', 'forest'].includes(c) || (verdi && c === 'grass' && ['park', 'garden', 'recreation_ground', 'village_green'].includes(p.subclass))],
    ['park', () => true],
  ]) {
    const L = centro[nome];
    for (let i = 0; L && i < L.length; i++) {
      const f = L.feature(i);
      const p = f.properties;
      if (f.type !== 3 || !tieni(p.class, p)) continue;
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
 * Le proprietà di una strada, con la classe che la scena conosce.
 *
 * «La linea del traffico a un punto completamente sconnesso dalla strada»: su
 * via De Roberto, a Napoli, c'è uno svincolo nuovo — rampe e ponti da
 * duecento metri — che la mappa segna ancora «in costruzione»
 * (`trunk_construction`), e come lui decine di strade nella zona. Chi calcola
 * il percorso e il traffico le dà già aperte e ci passa; la scena non le
 * disegnava affatto, e la linea del percorso e quella del traffico correvano
 * nel vuoto, dove «mancano i cavalcavia». Una strada in costruzione si
 * disegna come la strada che sarà: se è ancora chiusa nessuno ci viene
 * mandato, e se è aperta la si trova dov'è.
 */
export function stradaVera(p) {
  const c = p.class;
  if (typeof c !== 'string' || !c.endsWith('_construction')) return p;
  return { ...p, class: c.slice(0, -'_construction'.length), cantiere: true };
}

/** Una galleria più corta di così, da un capo all'altro, è un sottopasso. */
const SOTTOPASSO_M = 70;

/**
 * Le gallerie che sono sottopassi: corte, con la strada aperta a tutti e due
 * i capi.
 *
 * «Mancano i cavalcavia»: dove una stradina passa sotto l'autostrada la mappa
 * la segna in galleria per quei venti, trenta metri, e la scena le metteva
 * gli imbocchi di una galleria vera — due scatole di cemento alte cinque
 * metri ai lati dell'autostrada, che sembravano le spalle di un cavalcavia a
 * cui manca l'impalcato. Un sottopasso non ha niente sopra il piano della
 * strada che lo copre: la stradina arriva al bordo, passa sotto (il nastro
 * scuro delle gallerie) e riesce dall'altra parte.
 *
 * Una galleria tagliata dal bordo dei dati (un capo senza niente attaccato)
 * non si sa quanto è lunga: resta una galleria, con i suoi imbocchi.
 */
export function iSottopassi(nodi, feats) {
  const out = new Set();
  const visti = new Set();
  for (let i = 0; i < feats.length; i++) {
    if (!feats[i].galleria || feats[i].cls === 'rail' || visti.has(i)) continue;
    // La catena di pezzi in galleria attaccati l'uno all'altro.
    const catena = [];
    const coda = [i];
    visti.add(i);
    let lunga = 0;
    let intera = true;
    while (coda.length) {
      const j = coda.pop();
      const f = feats[j];
      catena.push(f);
      for (let k = 1; k < f.nodi.length; k++) lunga += Math.hypot(nodi[f.nodi[k]].x - nodi[f.nodi[k - 1]].x, nodi[f.nodi[k]].y - nodi[f.nodi[k - 1]].y);
      for (const e of [f.nodi[0], f.nodi[f.nodi.length - 1]]) {
        const altri = nodi[e].feats.filter((q) => q !== j);
        if (!altri.length) intera = false;
        for (const q of altri) {
          if (!feats[q].galleria || feats[q].cls === 'rail' || visti.has(q)) continue;
          visti.add(q);
          coda.push(q);
        }
      }
    }
    if (intera && lunga < SOTTOPASSO_M) for (const f of catena) out.add(f);
  }
  return out;
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

/** I colori dei blocchi nella vista «Corsie»: bianchi, grigi chiari, appena caldi o freddi. */
const CORSIE_FACCIATE = ['#f6f7f8', '#f1f3f5', '#eceff2', '#f6f4f1', '#eff1f4', '#f3f3f1'];

/**
 * Nessun tratto di una via più ripido del [PENDENZA_MAX]: dove succede (una
 * quota presa dalla strada sbagliata), i due capi si vengono incontro e lo
 * scalino diventa una salita. Cambia [h] lungo i punti [xy].
 */
export function limitaPendenza(h, xy, fissi = null) {
  for (let giro = 0; giro < 60; giro++) {
    let troppo = 0;
    for (let k = 1; k < h.length; k++) {
      const d = Math.hypot(xy[k][0] - xy[k - 1][0], xy[k][1] - xy[k - 1][1]);
      const eccesso = Math.abs(h[k] - h[k - 1]) - PENDENZA_MAX * d;
      if (eccesso <= 0.01) continue;
      troppo++;
      const verso = Math.sign(h[k] - h[k - 1]);
      const fa = fissi?.[k - 1] ? 0 : fissi?.[k] ? 1 : 0.5;
      const fb = fissi?.[k] ? 0 : fissi?.[k - 1] ? 1 : 0.5;
      h[k - 1] += verso * eccesso * fa;
      h[k] -= verso * eccesso * fb;
    }
    if (!troppo) break;
  }
  return h;
}

/** Ogni quanti metri, al più, si guarda la quota di una via con le corsie (vedi [corsieDellaTessera]). */
export const PASSO_QUOTE_CORSIE = 8;

/**
 * I punti [xy] con un punto in più ogni [passo] metri, al più, sui tratti
 * più lunghi; `nuovi[k]` dice se il punto k è uno di quelli aggiunti.
 */
export function infittisci(xy, passo = PASSO_QUOTE_CORSIE) {
  const out = [];
  const nuovi = [];
  xy.forEach((q, k) => {
    if (k) {
      const a = xy[k - 1];
      const n = Math.ceil(Math.hypot(q[0] - a[0], q[1] - a[1]) / passo);
      for (let j = 1; j < n; j++) {
        out.push([a[0] + ((q[0] - a[0]) * j) / n, a[1] + ((q[1] - a[1]) * j) / n]);
        nuovi.push(true);
      }
    }
    out.push(q);
    nuovi.push(false);
  });
  return { xy: out, nuovi };
}

/**
 * Toglie i punti aggiunti da [infittisci] dove la quota va dritta: fra due
 * punti tenuti, un punto aggiunto resta solo se la quota si scosta di più di
 * [tolleranza] metri dalla retta (Douglas-Peucker sui metri lungo la via).
 * I punti della via restano tutti. Restituisce `{xy, h}`.
 */
export function sfoltisciQuote(xy, h, nuovi, tolleranza = 0.05) {
  const s = [0];
  for (let k = 1; k < xy.length; k++) s.push(s[k - 1] + Math.hypot(xy[k][0] - xy[k - 1][0], xy[k][1] - xy[k - 1][1]));
  const tieni = nuovi.map((n) => !n);
  const fra = (a, b) => {
    let peggio = -1;
    let quanto = tolleranza;
    for (let k = a + 1; k < b; k++) {
      const t = s[b] > s[a] ? (s[k] - s[a]) / (s[b] - s[a]) : 0;
      const d = Math.abs(h[k] - (h[a] + (h[b] - h[a]) * t));
      if (d > quanto) {
        quanto = d;
        peggio = k;
      }
    }
    if (peggio < 0) return;
    tieni[peggio] = true;
    fra(a, peggio);
    fra(peggio, b);
  };
  let a = 0;
  for (let k = 1; k < xy.length; k++) {
    if (nuovi[k]) continue;
    if (k - a > 1) fra(a, k);
    a = k;
  }
  return { xy: xy.filter((_, k) => tieni[k]), h: h.filter((_, k) => tieni[k]) };
}

/** Oltre la sua mezza larghezza, fin dove una via del relay fa «vera» una strada della mappa (m). */
const SENZA_DATI_M = 4;
/** E per una strada che la mappa dà in costruzione, quanto vicina deve essere la via (m). */
const CANTIERE_M = 3;
/** Da quanti metri di fila in su un pezzo senza una via vera non si disegna. */
const SENZA_DATI_LUNGO_M = 15;

/**
 * Le vie guidabili del relay ([linee]: `[[x, y], …]` nei metri della
 * tessera) in una griglia: `vicina(x, y, r, tx, ty)` dice se una passa a
 * meno di [r] metri, nel verso (tx, ty) o al contrario (non di traverso: una
 * via che passa sotto non fa vera la strada di sopra).
 */
export function vieDelRelay(linee, cella = 25) {
  const griglia = new Map();
  for (const p of linee) {
    for (let k = 1; k < p.length; k++) {
      const [a, b] = [p[k - 1], p[k]];
      for (let cx = Math.floor(Math.min(a[0], b[0]) / cella); cx <= Math.floor(Math.max(a[0], b[0]) / cella); cx++) {
        for (let cy = Math.floor(Math.min(a[1], b[1]) / cella); cy <= Math.floor(Math.max(a[1], b[1]) / cella); cy++) {
          const kk = cx + ',' + cy;
          if (!griglia.has(kk)) griglia.set(kk, []);
          griglia.get(kk).push([a, b]);
        }
      }
    }
  }
  return {
    vicina(x, y, r, tx = 0, ty = 0) {
      for (let cx = Math.floor((x - r) / cella); cx <= Math.floor((x + r) / cella); cx++) {
        for (let cy = Math.floor((y - r) / cella); cy <= Math.floor((y + r) / cella); cy++) {
          for (const [a, b] of griglia.get(cx + ',' + cy) ?? []) {
            if (distanzaSegmento(x, y, a[0], a[1], b[0], b[1]) >= r) continue;
            const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
            if ((tx || ty) && Math.abs(((b[0] - a[0]) * tx + (b[1] - a[1]) * ty) / l) < 0.6) continue;
            return true;
          }
        }
      }
      return false;
    },
  };
}

/**
 * Nella vista «Corsie», dove una strada della mappa ([punti]: `[x, y, …]`,
 * larga [w]) non ha una via guidabile del relay ([vie], da [vieDelRelay]):
 * per ogni punto, `true` se lì non si disegna.
 *
 * «Sopraelevate dove non ci sono strade, strade dove non ce ne sono»: la
 * mappa disegna anche le strade private (i viali chiusi di una fiera, i
 * piazzali di una fabbrica, coi loro cavalcavia) e quelle che per lei sono
 * ancora in costruzione; il relay, da OpenStreetMap, dà solo quelle dove si
 * può passare. Nella vista «Corsie», con le corsie vere, una strada della
 * mappa che per più di [SENZA_DATI_LUNGO_M] metri di fila non ha una via del
 * relay a meno di [SENZA_DATI_M] metri dal suo bordo (al più a otto dal suo
 * mezzo) non c'è: né il nastro né l'impalcato, i parapetti, i piloni, né il
 * percorso sopra; e così una strada tutta senza via, anche corta. I pezzi
 * più corti di una strada che per il resto ha la sua via (dove le due
 * geometrie si scostano a un incrocio) restano.
 */
export function senzaDati(punti, w, vie, cantiere = false) {
  const n = punti.length;
  // (Al più quattro metri di mezza larghezza: una strada larga della mappa
  // non prende per sua la via a dieci metri. Una strada in costruzione per
  // la mappa, solo la via che le sta proprio sopra: il viadotto nuovo
  // accanto a quello vecchio, per la mappa ancora un cantiere, non c'è.)
  const entro = cantiere ? CANTIERE_M : Math.min(w / 2, 4) + SENZA_DATI_M;
  const senza = punti.map((q, k) => {
    const a = punti[Math.max(0, k - 1)];
    const b = punti[Math.min(n - 1, k + 1)];
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
    return !vie.vicina(q[0], q[1], entro, (b[0] - a[0]) / l, (b[1] - a[1]) / l);
  });
  // Una strada tutta senza via (anche corta: i pezzi di un piazzale privato
  // sono tanti e brevi) non c'è.
  if (senza.every(Boolean)) return senza;
  for (let k = 0; k < n; ) {
    if (!senza[k]) {
      k++;
      continue;
    }
    let j = k;
    while (j < n && senza[j]) j++;
    // Il pezzo da k a j-1, con metà dei tratti fino ai punti con la via accanto.
    const tratto = (q) => (q >= 1 && q < n ? Math.hypot(punti[q][0] - punti[q - 1][0], punti[q][1] - punti[q - 1][1]) : 0);
    let lungo = (tratto(k) + tratto(j)) / 2;
    for (let q = k + 1; q < j; q++) lungo += tratto(q);
    if (lungo < SENZA_DATI_LUNGO_M) senza.fill(false, k, j);
    k = j;
  }
  return senza;
}

/**
 * Un varco nell'asfalto più stretto di così (m) non divide due carreggiate:
 * è la zebratura fra due rami che si separano (`ZEBRATURA_LARGA_M` in
 * segnaletica.js), o lo spartitraffico fra le due carreggiate di un viadotto.
 */
const VARCO_ASFALTO_M = 4.5;
/** Fra due punti a un palmo l'uno dall'altro, più di così (m) è uno scalino: l'asfalto di un'altra carreggiata, più su o più giù. */
const SCALINO_ASFALTO_M = 0.35;
/** Fin dove, oltre il bordo della strada della mappa, si cerca il bordo dell'asfalto delle corsie (m). */
const OLTRE_IL_BORDO_M = 8;

/**
 * Dove finisce davvero l'asfalto ai due lati di una strada della mappa, nel
 * punto (px, py) dove va verso (tx, ty) (un versore): `[sinistra, destra]`,
 * le due mezze larghezze dal suo mezzo, o `null` se lì l'asfalto delle corsie
 * non c'è (allora la strada resta larga com'è: [hs] a sinistra, [hd] a destra).
 * [su]`(x, y, z)` dice se un punto sta sull'asfalto delle corsie: la sua
 * quota lì (la più vicina a [z]), o `true`, o niente. Con le quote, dopo le
 * due larghezze vengono quella dell'asfalto ai due bordi e in mezzo; [h] è la
 * quota della strada. Poi i varchi passati: `[da, quota, a, quota]` (metri a
 * sinistra del mezzo, da destra a sinistra), e se a sinistra e a destra il
 * bordo non si è trovato: a [oltre] metri dal bordo della strada l'asfalto
 * continua ancora (un'altra carreggiata accanto: il bordo è il suo).
 *
 * «Larghe fasce grigie accanto alla corsia, tante strisce parallele sopra le
 * corsie»: nella vista «Corsie» l'asfalto è quello delle vie vere, ma il
 * ponte sotto (il ventre, il cordolo, i parapetti, i muri) era ancora largo
 * quanto la strada della mappa, che non ne sa niente: più larga, e accanto
 * alla corsia spuntava il ventre dell'impalcato con il parapetto un metro più
 * in là; più stretta o spostata, e il parapetto correva sull'asfalto. Le
 * opere stanno invece sul bordo dell'asfalto che c'è: dal mezzo della strada
 * verso fuori, fin dove l'asfalto continua (un varco più stretto di
 * [VARCO_ASFALTO_M] non lo interrompe) alla stessa quota: la carreggiata
 * accanto, più su o più giù di uno scalino, è un'altra strada col suo ponte.
 */
export function bordiSullAsfalto(su, px, py, tx, ty, hs, hd, h = 0, oltre = OLTRE_IL_BORDO_M) {
  const nx = -ty;
  const ny = tx;
  const PASSO = 0.25;
  // La quota dell'asfalto a [o] metri a sinistra del mezzo (la più vicina a [z]), o null.
  const a = (o, z) => {
    const r = su(px + nx * o, py + ny * o, z);
    return r === true ? z : typeof r === 'number' ? r : null;
  };
  // Da dove si parte: il mezzo, o l'asfalto più vicino dentro la strada.
  let o0 = null;
  let z0 = null;
  for (let d = 0; d <= Math.max(hs, hd) && o0 === null; d += PASSO) {
    for (const o of d ? [d, -d] : [0]) {
      if (o0 !== null || (o > 0 ? d > hs : d > hd)) continue;
      const z = a(o, h);
      if (z !== null) [o0, z0] = [o, z];
    }
  }
  if (o0 === null) return null;
  const varchi = [];
  const fin = (verso, limite) => {
    let ultimo = o0;
    let quota = z0;
    let vuoti = 0;
    // (Uno scalino non è lo stesso asfalto: oltre un varco la quota può cambiare un poco di più.)
    const continua = (z) => z !== null && Math.abs(z - quota) <= SCALINO_ASFALTO_M + 0.08 * vuoti * PASSO;
    for (let o = o0 + verso * PASSO; verso * o <= limite; o += verso * PASSO) {
      const z = a(o, quota);
      if (continua(z)) {
        // Un varco appena passato: da dove finiva l'asfalto a dove riprende.
        if (vuoti) varchi.push(verso > 0 ? [ultimo, quota, o, z] : [o, z, ultimo, quota]);
        ultimo = o;
        quota = z;
        vuoti = 0;
      } else if (++vuoti * PASSO >= VARCO_ASFALTO_M) break;
    }
    // Il bordo vero, fra l'ultimo punto sull'asfalto e il primo fuori.
    const inFondo = vuoti === 0;
    vuoti = 0;
    let dentro = ultimo;
    let fuori = ultimo + verso * PASSO;
    for (let giro = 0; giro < 4; giro++) {
      const m = (dentro + fuori) / 2;
      if (continua(a(m, quota))) dentro = m;
      else fuori = m;
    }
    // Arrivati in fondo ancora sull'asfalto: da questa parte il bordo non c'è (è più in là).
    return [dentro, quota, inFondo && verso * (ultimo + verso * PASSO) > limite];
  };
  const [sinistra, zs, apertaS] = fin(1, hs + oltre);
  const [destra, zd, apertaD] = fin(-1, hd + oltre);
  return [sinistra, -destra, zs, zd, z0, varchi, apertaS, apertaD];
}

/** Quanto sopra la quota sta l'asfalto delle corsie: come il nastro della sua classe, un poco sopra. */
function sopraCorsie(hw) {
  const b = String(hw ?? '').replace(/_link$/, '');
  const cls = b === 'motorway' || b === 'trunk' || b === 'primary' || b === 'secondary' || b === 'tertiary' ? b : 'minor';
  return (SOPRA[cls] ?? 0.16) + 0.012;
}

/**
 * Le vie con le corsie che toccano la tessera, nei suoi metri, con la quota
 * di ogni punto presa dalle strade della tessera ([linee], già con i ponti e
 * le rampe in salita): sotto un viadotto ci sono due quote, e una via
 * segnata come ponte prende la più alta, le altre quella più vicina alla
 * quota di prima (chi è a terra resta a terra). E [copre]: se un punto di un
 * nastro di sempre sta sotto una di queste vie (allora non si disegna).
 */
function corsieDellaTessera(corsie, sys, linee, visibili, meta) {
  const G = 20;
  const griglia = new Map();
  linee.forEach((pts, i) => {
    const f = visibili[i];
    if (f.cls === 'rail') return;
    for (let k = 1; k < pts.length; k++) {
      const a = pts[k - 1];
      const b = pts[k];
      for (let cx = Math.floor(Math.min(a[0], b[0]) / G); cx <= Math.floor(Math.max(a[0], b[0]) / G); cx++) {
        for (let cy = Math.floor(Math.min(a[1], b[1]) / G); cy <= Math.floor(Math.max(a[1], b[1]) / G); cy++) {
          const key = cx + ',' + cy;
          if (!griglia.has(key)) griglia.set(key, []);
          griglia.get(key).push([a, b, f]);
        }
      }
    }
  });
  /** Le quote possibili in [px, py] lungo (tx, ty): `[h, distanza, strada della mappa]`. */
  const quoteQui = (px, py, tx, ty) => {
    const out = [];
    const visti = new Set();
    const vicini = [];
    for (let ax = -1; ax <= 1; ax++) {
      for (let ay = -1; ay <= 1; ay++) {
        for (const t of griglia.get(Math.floor(px / G) + ax + ',' + (Math.floor(py / G) + ay)) ?? []) {
          if (visti.has(t)) continue;
          visti.add(t);
          vicini.push(t);
        }
      }
    }
    for (const [a, b, f] of vicini) {
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l2 = dx * dx + dy * dy || 1e-9;
      const u = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / l2));
      const d = Math.hypot(a[0] + dx * u - px, a[1] + dy * u - py);
      if (d > 8) continue;
      if (Math.abs((dx * tx + dy * ty) / Math.sqrt(l2)) < 0.55) continue;
      out.push([a[2] + (b[2] - a[2]) * u, d, f]);
    }
    return out;
  };
  const vicina = (q) => q[0] >= -meta - 60 && q[0] <= meta + 60 && q[1] >= -meta - 60 && q[1] <= meta + 60;
  const inMetri = (ll) => {
    const out = [];
    for (let i = 0; i < ll.length; i += 2) out.push(sys.daLonLat(ll[i], ll[i + 1]));
    return out;
  };
  const strade = [];
  // Le vie più in là (fin dove arrivano i dati): solo per il tetto delle rampe, qui sotto.
  const lontane = [];
  for (const v0 of corsie.strade) {
    const xyVia = inMetri(v0.ll);
    if (!xyVia.some(vicina)) {
      lontane.push({ xy: inMetri(v0.llVia ?? v0.ll), alto: v0.ponte || v0.livello > 0 });
      continue;
    }
    /* «Il percorso diventa tratteggiato e la freccia cambia colore», su un
     * rettilineo d'autostrada all'aperto: la via aveva due punti a quasi
     * quattrocento metri l'uno dall'altro, e il secondo all'inizio di un
     * ponte, a otto metri. La quota si prendeva solo nei punti della via, e
     * fra i due l'asfalto saliva dritto: a trecento metri dal ponte stava già
     * due metri e mezzo sopra la strada vera, coi suoi cinque metri e mezzo
     * per cento che cominciano centoquaranta metri prima. Il percorso e
     * l'auto, alla quota della strada vera, finivano sotto l'asfalto: il
     * percorso coperto (tenue e tratteggiato) e la sagoma rossa dell'auto.
     * Adesso la quota si guarda almeno ogni [PASSO_QUOTE_CORSIE] metri, e dei
     * punti aggiunti restano solo quelli dove la via non va dritta. */
    const fitta = infittisci(xyVia);
    const xy = fitta.xy;
    const h = new Array(xy.length).fill(NaN);
    /* La quota di ogni punto: quella di una strada della mappa lì vicino.
     *
     * «Una salita con strade in mezzo, non si capisce niente»: dove le rampe
     * di uno svincolo passano una sopra l'altra, vicino a ogni punto ci sono
     * strade della mappa a tre quote diverse. Si sceglieva punto per punto
     * la più vicina che non saltasse dalla quota di prima, e chi partiva sul
     * livello sbagliato ci restava: le corsie di una rampa a terra finivano
     * sopra l'auto, quelle del viadotto a terra. Adesso conta anche che cosa
     * è la strada — un ponte, a che livello (`layer`), una galleria — come la
     * via con le corsie dice di sé, e la quota si sceglie su tutta la via
     * insieme (Viterbi): il meno lontano, il più somigliante, senza salti. */
    // Il livello come lo conta la mappa (`livelloStrada`): un ponte almeno al primo, il resto a terra.
    const mio = v0.ponte ? Math.min(5, Math.max(1, v0.livello || 1)) : 0;
    const costo = (q) => {
      const f = q[2];
      let c = q[1];
      c += 3 * Math.abs((f.livello ?? 0) - mio);
      if (!!f.ponte !== !!v0.ponte) c += 4;
      if (!!f.galleria !== !!v0.galleria) c += 6;
      return c;
    };
    const cand = xy.map((_, k) => {
      const a = xy[Math.max(0, k - 1)];
      const b = xy[Math.min(xy.length - 1, k + 1)];
      const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
      return quoteQui(xy[k][0], xy[k][1], (b[0] - a[0]) / l, (b[1] - a[1]) / l);
    });
    for (let i = 0; i < xy.length; ) {
      if (!cand[i].length) {
        i++;
        continue;
      }
      let j = i;
      while (j < xy.length && cand[j].length) j++;
      const costi = [cand[i].map(costo)];
      const da = [cand[i].map(() => -1)];
      for (let k = i + 1; k < j; k++) {
        const cc = [];
        const dd = [];
        for (const q of cand[k]) {
          let meglio = Infinity;
          let chi = 0;
          // Un salto di quota oltre la pendenza di una strada vera costa
          // molto: è passare da una strada all'altra («la salita con
          // strade in mezzo», lo zig-zag del percorso sulle rampe).
          const passo = Math.hypot(xy[k][0] - xy[k - 1][0], xy[k][1] - xy[k - 1][1]);
          cand[k - 1].forEach((p, r) => {
            const salto = Math.abs(q[0] - p[0]);
            const v = costi[k - 1 - i][r] + 2 * salto + 12 * Math.max(0, salto - PENDENZA_MAX * passo - 0.2);
            if (v < meglio) {
              meglio = v;
              chi = r;
            }
          });
          cc.push(meglio + costo(q));
          dd.push(chi);
        }
        costi.push(cc);
        da.push(dd);
      }
      const ultimi = costi[j - 1 - i];
      let r = 0;
      for (let t = 1; t < ultimi.length; t++) if (ultimi[t] < ultimi[r]) r = t;
      for (let k = j - 1; k >= i; k--) {
        h[k] = cand[k][r][0];
        r = da[k - i][r];
      }
      i = j;
    }
    // Dove non c'è una strada sotto: fra le quote attorno, o a terra.
    let ultimo = -1;
    for (let k = 0; k <= h.length; k++) {
      if (k < h.length && Number.isNaN(h[k])) continue;
      for (let j = ultimo + 1; j < k; j++) h[j] = ultimo < 0 ? (k < h.length ? h[k] : 0) : k >= h.length ? h[ultimo] : h[ultimo] + ((h[k] - h[ultimo]) * (j - ultimo)) / (k - ultimo);
      ultimo = k;
    }
    limitaPendenza(h, xy);
    strade.push({ ...v0, xy, xyVia: inMetri(v0.llVia ?? v0.ll), h, nuovi: fitta.nuovi });
  }
  /* Niente in alto senza un ponte nei dati: una via che OpenStreetMap non
   * dà come ponte (né con un `layer` sopra zero) sale solo come una rampa,
   * attaccata a un ponte (vedi [tettoDelleRampe]). Le quote vengono dalle
   * strade della mappa, e la mappa a volte sbaglia: le sue tessere hanno
   * dati di qualche settimana prima, e una rotonda sotto un viadotto, che
   * per lei aveva un nodo in comune col viadotto, saliva a tre metri con
   * l'asfalto delle corsie sopra. Lo stesso tetto vale per le strade della
   * mappa lungo le vie (`tettoQui`). */
  // (Le corsie stimate vengono dalla mappa: non dicono niente di più.)
  const vere = strade.some((v) => !v.stimata);
  const altre = (corsie.altre ?? []).map((a) => ({ ...a, xy: inMetri(a.ll) })).filter((a) => a.xy.some(vicina));
  /* Anche con le vie più lontane di sessanta metri dalla tessera: un ponte
   * che finisce cento metri fuori ha la rampa che scende fin dentro, e
   * senza di lui la rampa qui stava a terra mentre la tessera accanto (che
   * il ponte lo vede) la teneva in alto: sul bordo uno scalino di due metri
   * nell'asfalto, e la fascia del percorso sospesa sopra. */
  const tetti = tettoDelleRampe([
    ...strade.map((v) => ({ xy: v.xyVia, alto: v.ponte || v.livello > 0, quote: quoteSullaVia(v) })),
    ...altre.map((a) => ({ xy: a.xy, alto: a.ponte || a.livello > 0 })),
    ...lontane,
  ]);
  strade.forEach((v, i) => {
    if (!vere || v.ponte || v.livello > 0 || v.galleria) return;
    const tetto = tetti[i];
    const sv = progressivi(v.xyVia);
    const sd = progressivi(v.xy);
    let cambiata = false;
    for (let k = 0; k < v.xy.length; k++) {
      const s = sd.at(-1) > 0 ? (sd[k] / sd.at(-1)) * sv.at(-1) : 0;
      const t = Math.max(0, tettoA(tetto, sv, s));
      if (v.h[k] > t + 0.05) {
        v.h[k] = t;
        cambiata = true;
      }
    }
    if (cambiata) limitaPendenza(v.h, v.xy);
  });
  // Il tetto lungo le vie, in una griglia: per le strade della mappa.
  const GT = new Map();
  [...strade.map((v, i) => [v.xyVia, tetti[i], v.ponte || v.livello > 0 || v.galleria]), ...altre.map((a, j) => [a.xy, tetti[strade.length + j], a.ponte || a.livello > 0 || a.galleria])].forEach(([xy, tetto, libera]) => {
    for (let k = 1; k < xy.length; k++) {
      const [a, b] = [xy[k - 1], xy[k]];
      const voce = [a, b, libera ? Infinity : tetto[k - 1], libera ? Infinity : tetto[k]];
      for (let cx = Math.floor((Math.min(a[0], b[0]) - 8) / G); cx <= Math.floor((Math.max(a[0], b[0]) + 8) / G); cx++) {
        for (let cy = Math.floor((Math.min(a[1], b[1]) - 8) / G); cy <= Math.floor((Math.max(a[1], b[1]) + 8) / G); cy++) {
          const key = cx + ',' + cy;
          if (!GT.has(key)) GT.set(key, []);
          GT.get(key).push(voce);
        }
      }
    }
  });
  /**
   * Fin dove può salire una strada della mappa in (px, py), verso (tx, ty):
   * il tetto della via lungo lei (la più vicina entro [entro] metri; con due
   * vie una sopra l'altra, la più alta), o null se non ce n'è.
   */
  const tettoQui = (px, py, tx, ty, entro) => {
    const vicine = [];
    for (const [a, b, ta, tb] of GT.get(Math.floor(px / G) + ',' + Math.floor(py / G)) ?? []) {
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l = Math.hypot(dx, dy) || 1e-9;
      const u = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / (l * l)));
      const d = Math.hypot(a[0] + dx * u - px, a[1] + dy * u - py);
      if (d > entro) continue;
      if (Math.abs((dx * tx + dy * ty) / l) < 0.7 * Math.hypot(tx, ty)) continue;
      vicine.push([d, Math.max(0, ta - PENDENZA * u * l, tb - PENDENZA * (1 - u) * l)]);
    }
    if (!vicine.length) return null;
    const d0 = Math.min(...vicine.map((v) => v[0]));
    // (Una rampa accanto, a qualche metro, non è la via di questa strada.)
    return Math.max(...vicine.filter((v) => v[0] < d0 + 1.5).map((v) => v[1]));
  };
  for (let i = 0; i < strade.length; i++) {
    const v = strade[i];
    const via = sfoltisciQuote(v.xy, v.h, v.nuovi);
    const { nuovi, ...resto } = v;
    strade[i] = { ...resto, xy: via.xy, h: via.h };
  }
  const nodi = (corsie.nodi ?? []).map((n) => ({ ...n, xy: sys.daLonLat(n.g[0], n.g[1]) })).filter((n) => vicina(n.xy));
  // Gli alberi veri di questa tessera (quelli sul bordo li fa una sola), e
  // lungo i filari uno ogni otto metri circa.
  const nellaTessera = (q) => q[0] >= -meta && q[0] <= meta && q[1] >= -meta && q[1] <= meta;
  const puntiAlberi = (corsie.alberi ?? []).map((a) => sys.daLonLat(a[0], a[1]));
  for (const f of corsie.filari ?? []) {
    const p = inMetri(f.g);
    for (let k = 1; k < p.length; k++) {
      const l = Math.hypot(p[k][0] - p[k - 1][0], p[k][1] - p[k - 1][1]);
      const n = Math.max(1, Math.round(l / 8));
      for (let j = k === 1 ? 0 : 1; j <= n; j++) puntiAlberi.push([p[k - 1][0] + ((p[k][0] - p[k - 1][0]) * j) / n, p[k - 1][1] + ((p[k][1] - p[k - 1][1]) * j) / n]);
    }
  }
  // Le vie con le corsie in una griglia: per sapere quali nastri coprono.
  const coperte = new Map();
  for (const v of strade) {
    const mezza = ((v.avanti + v.indietro) * v.lw + v.margini[0] + v.margini[1]) / 2;
    // I due bordi dell'asfalto, a sinistra della linea (come in segnaletica.js).
    const B = bordiCorsie(v);
    const bordoS = B.sinistra + v.margini[0];
    const bordoD = B.destra - v.margini[1];
    for (let k = 1; k < v.xy.length; k++) {
      const a = [...v.xy[k - 1], v.h[k - 1]];
      const b = [...v.xy[k], v.h[k]];
      for (let cx = Math.floor((Math.min(a[0], b[0]) - mezza) / G); cx <= Math.floor((Math.max(a[0], b[0]) + mezza) / G); cx++) {
        for (let cy = Math.floor((Math.min(a[1], b[1]) - mezza) / G); cy <= Math.floor((Math.max(a[1], b[1]) + mezza) / G); cy++) {
          const key = cx + ',' + cy;
          if (!coperte.has(key)) coperte.set(key, []);
          coperte.get(key).push([a, b, mezza + Math.abs(v.posa), classeMappa(v.hw), bordoS, bordoD]);
        }
      }
    }
  }
  const copre = (px, py, tx, ty, h) => {
    for (const [a, b, mezza] of coperte.get(Math.floor(px / G) + ',' + Math.floor(py / G)) ?? []) {
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l2 = dx * dx + dy * dy || 1e-9;
      const u = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / l2));
      if (Math.hypot(a[0] + dx * u - px, a[1] + dy * u - py) > mezza + 1.5) continue;
      if (Math.abs(a[2] + (b[2] - a[2]) * u - h) > 2) continue;
      const tl = Math.hypot(tx, ty) || 1;
      if (Math.abs((dx * tx + dy * ty) / (Math.sqrt(l2) * tl)) < 0.5) continue;
      return true;
    }
    return false;
  };
  const sullAsfalto = (px, py) => {
    for (const [a, b, mezza] of coperte.get(Math.floor(px / G) + ',' + Math.floor(py / G)) ?? []) {
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l2 = dx * dx + dy * dy || 1e-9;
      const u = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / l2));
      if (Math.hypot(a[0] + dx * u - px, a[1] + dy * u - py) < mezza + 0.6) return true;
    }
    return false;
  };
  /**
   * La quota della via con le corsie lungo una strada della mappa di classe
   * [cls] in (px, py), verso (tx, ty), alla quota [h]: fra le vie della
   * stessa classe (la stessa strada) nello stesso verso entro
   * [entro] metri (le più vicine; con due vie una sopra l'altra, quella alla
   * quota più simile). `null` se non ce n'è.
   */
  const quotaCorsie = (px, py, tx, ty, h, entro, cls) => {
    const vicine = [];
    for (const [a, b, , c] of coperte.get(Math.floor(px / G) + ',' + Math.floor(py / G)) ?? []) {
      if (c !== cls) continue;
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l = Math.hypot(dx, dy) || 1e-9;
      const u = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / (l * l)));
      const d = Math.hypot(a[0] + dx * u - px, a[1] + dy * u - py);
      if (d > entro || Math.abs((dx * tx + dy * ty) / l) < 0.7 * Math.hypot(tx, ty)) continue;
      vicine.push([d, a[2] + (b[2] - a[2]) * u]);
    }
    if (!vicine.length) return null;
    const d0 = Math.min(...vicine.map((v) => v[0]));
    return vicine.filter((v) => v[0] < d0 + 1.5).reduce((m, v) => (Math.abs(v[1] - h) < Math.abs(m - h) ? v[1] : m), Infinity);
  };
  /**
   * Lungo una via con le corsie della stessa classe, nello stesso verso, ma
   * a più di due metri di quota (e nessuna della stessa classe alla sua): la
   * stessa strada, una seconda volta.
   */
  const doppia = (px, py, tx, ty, h, cls) => {
    let altrove = false;
    for (const [a, b, mezza, c] of coperte.get(Math.floor(px / G) + ',' + Math.floor(py / G)) ?? []) {
      if (c !== cls) continue;
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l2 = dx * dx + dy * dy || 1e-9;
      const u = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / l2));
      if (Math.hypot(a[0] + dx * u - px, a[1] + dy * u - py) > mezza + 1.5) continue;
      const tl = Math.hypot(tx, ty) || 1;
      if (Math.abs((dx * tx + dy * ty) / (Math.sqrt(l2) * tl)) < 0.8) continue;
      if (Math.abs(a[2] + (b[2] - a[2]) * u - h) <= 2) return false;
      altrove = true;
    }
    return altrove;
  };
  /** Ben dentro l'asfalto di una via con le corsie (più di [dentro] metri dal bordo), alla quota [h]. */
  const inMezzoAllAsfalto = (px, py, h, dentro = 1.5) => {
    for (const [a, b, mezza] of coperte.get(Math.floor(px / G) + ',' + Math.floor(py / G)) ?? []) {
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l2 = dx * dx + dy * dy || 1e-9;
      const u = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / l2));
      if (Math.hypot(a[0] + dx * u - px, a[1] + dy * u - py) > mezza - dentro) continue;
      if (Math.abs(a[2] + (b[2] - a[2]) * u - h) < 2) return true;
    }
    return false;
  };
  /**
   * La quota dell'asfalto delle corsie in (px, py), la più bassa fra le vie
   * che lì passano a meno di [entro] metri da [h]; `null` fuori dall'asfalto.
   */
  const asfaltoQui = (px, py, h, entro = 3) => {
    let giu = null;
    for (const [a, b, mezza] of coperte.get(Math.floor(px / G) + ',' + Math.floor(py / G)) ?? []) {
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l2 = dx * dx + dy * dy || 1e-9;
      const u = Math.max(0, Math.min(1, ((px - a[0]) * dx + (py - a[1]) * dy) / l2));
      if (Math.hypot(a[0] + dx * u - px, a[1] + dy * u - py) > mezza + 0.6) continue;
      const z = a[2] + (b[2] - a[2]) * u;
      if (Math.abs(z - h) < entro && (giu === null || z < giu)) giu = z;
    }
    return giu;
  };
  /**
   * Sull'asfalto di una via con le corsie che va come (tx, ty) (o al
   * contrario), a meno di due metri dalla quota [h], proprio fra i suoi due
   * bordi: la sua quota lì (la più vicina a [h]), o null.
   */
  const sullAsfaltoLungo = (px, py, h, tx, ty) => {
    let meglio = null;
    for (const [a, b, , , bordoS, bordoD] of coperte.get(Math.floor(px / G) + ',' + Math.floor(py / G)) ?? []) {
      const dx = b[0] - a[0];
      const dy = b[1] - a[1];
      const l = Math.hypot(dx, dy) || 1e-9;
      // (Un metro oltre i capi del tratto: nelle curve fra un tratto e l'altro non resta un buco.)
      const lungo = ((px - a[0]) * dx + (py - a[1]) * dy) / l;
      if (lungo < -1 || lungo > l + 1) continue;
      const o = ((py - a[1]) * dx - (px - a[0]) * dy) / l;
      if (o > bordoS + 0.02 || o < bordoD - 0.02) continue;
      if (Math.abs((dx * tx + dy * ty) / l) < 0.7) continue;
      const u = Math.max(0, Math.min(1, lungo / l));
      const z = a[2] + (b[2] - a[2]) * u;
      if (Math.abs(z - h) < 2 && (meglio === null || Math.abs(z - h) < Math.abs(meglio - h))) meglio = z;
    }
    return meglio;
  };
  /** I bordi dell'asfalto delle corsie attorno a una strada della mappa (vedi [bordiSullAsfalto]). */
  const bordiQui = (px, py, h, tx, ty, hs, hd) => bordiSullAsfalto((x, y, z) => sullAsfaltoLungo(x, y, z, tx, ty), px, py, tx, ty, hs, hd, h);
  // Mai sull'asfalto (un nodo messo male, o la strada disegnata più larga).
  const alberi = puntiAlberi.filter((q) => nellaTessera(q) && !sullAsfalto(q[0], q[1])).map((q) => [q[0], q[1], 0.6 + mescola(Math.round(q[0] * 7), Math.round(q[1] * 7)) * 0.25]);
  return { strade, nodi, copre, doppia, sullAsfalto, inMezzoAllAsfalto, asfaltoQui, alberi, tettoQui, quotaCorsie, bordiQui };
}

/** La classe della mappa (OpenMapTiles) di una via di OpenStreetMap. */
function classeMappa(hw) {
  const b = String(hw ?? '').replace(/_link$/, '');
  return ['motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'service'].includes(b) ? b : 'minor';
}

/** I metri progressivi lungo i punti [p]. */
function progressivi(p) {
  const s = [0];
  for (let k = 1; k < p.length; k++) s.push(s[k - 1] + Math.hypot(p[k][0] - p[k - 1][0], p[k][1] - p[k - 1][1]));
  return s;
}

/** Le quote di una via con le corsie nei punti della sua geometria vera (`xyVia`), dai metri. */
function quoteSullaVia(v) {
  const sv = progressivi(v.xyVia);
  const sd = progressivi(v.xy);
  const L = sd.at(-1);
  return sv.map((s) => {
    const q = sv.at(-1) > 0 ? (s / sv.at(-1)) * L : 0;
    let k = 1;
    while (k < sd.length - 1 && sd[k] < q) k++;
    const t = sd[k] > sd[k - 1] ? Math.max(0, Math.min(1, (q - sd[k - 1]) / (sd[k] - sd[k - 1]))) : 0;
    return v.h[k - 1] + (v.h[k] - v.h[k - 1]) * t;
  });
}

/** Il tetto ([tettoDelleRampe]) a [s] metri lungo la via, coi metri [sv] dei suoi punti. */
function tettoA(tetto, sv, s) {
  let k = 1;
  while (k < sv.length - 1 && sv[k] < s) k++;
  return Math.max(tetto[k - 1] - PENDENZA * Math.max(0, s - sv[k - 1]), tetto[k] - PENDENZA * Math.max(0, sv[k] - s));
}

/** Per quanti metri dal capo di un ponte la via che continua può restare alla sua quota. */
export const RAMPA_PIANO_M = 40;

/**
 * Fin dove può salire ogni punto di ogni via di [vie] (`{xy, alto, quote}`:
 * i punti in metri, se è un ponte nei dati, e la quota dei suoi punti): sulle
 * vie alte quanto sono, sulle altre quanto una rampa che scende da un ponte
 * a cui si attacca, nodo per nodo (le vie si toccano dove hanno un punto in
 * comune): alla sua quota per [RAMPA_PIANO_M] metri (fra due ponti vicini la
 * strada resta in alto), poi giù del [PENDENZA]. Lontano dai ponti, zero.
 * Restituisce per ogni via il tetto in ognuno dei suoi punti.
 */
export function tettoDelleRampe(vie) {
  const chiave = (q) => Math.round(q[0] * 2) + ',' + Math.round(q[1] * 2);
  const indice = new Map();
  const valore = [];
  const lati = [];
  const nodo = (q) => {
    const k = chiave(q);
    let i = indice.get(k);
    if (i === undefined) {
      i = valore.length;
      indice.set(k, i);
      valore.push(-Infinity);
      lati.push([]);
    }
    return i;
  };
  const suoi = vie.map((v) => v.xy.map(nodo));
  vie.forEach((v, j) => {
    const n = suoi[j];
    for (let k = 1; k < n.length; k++) {
      const d = Math.hypot(v.xy[k][0] - v.xy[k - 1][0], v.xy[k][1] - v.xy[k - 1][1]);
      lati[n[k - 1]].push([n[k], d]);
      lati[n[k]].push([n[k - 1], d]);
    }
    if (!v.alto) return;
    n.forEach((i, k) => (valore[i] = Math.max(valore[i], (v.quote?.[k] ?? ALTEZZA_LIVELLO) + PENDENZA * RAMPA_PIANO_M)));
  });
  // Dal più alto in giù (Dijkstra, col massimo al posto del minimo).
  const mucchio = [];
  const spingi = (x) => {
    mucchio.push(x);
    let c = mucchio.length - 1;
    while (c > 0) {
      const p = (c - 1) >> 1;
      if (mucchio[p][0] >= mucchio[c][0]) break;
      [mucchio[p], mucchio[c]] = [mucchio[c], mucchio[p]];
      c = p;
    }
  };
  const togli = () => {
    const top = mucchio[0];
    const ultimo = mucchio.pop();
    if (mucchio.length) {
      mucchio[0] = ultimo;
      let c = 0;
      for (;;) {
        const l = 2 * c + 1;
        const r = l + 1;
        let m = c;
        if (l < mucchio.length && mucchio[l][0] > mucchio[m][0]) m = l;
        if (r < mucchio.length && mucchio[r][0] > mucchio[m][0]) m = r;
        if (m === c) break;
        [mucchio[m], mucchio[c]] = [mucchio[c], mucchio[m]];
        c = m;
      }
    }
    return top;
  };
  valore.forEach((v, i) => v > 0 && spingi([v, i]));
  while (mucchio.length) {
    const [v, i] = togli();
    if (v < valore[i]) continue;
    for (const [j, d] of lati[i]) {
      const w = v - PENDENZA * d;
      if (w > valore[j] && w > 0) {
        valore[j] = w;
        spingi([w, j]);
      }
    }
  }
  return suoi.map((n, j) => n.map((i) => (vie[j].alto ? Infinity : Math.max(0, valore[i]))));
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
  geo(t.maschera);
  geo(t.ombreAlberi);
  geo(t.tetti);
  for (const g of Object.values(t.facciate)) geo(g);
  if (t.corsie) for (const g of Object.values(t.corsie)) geo(g);
  if (t.semafori) lista.push(t.semafori.buffer);
  for (const a of [t.fusti, t.capitelli, t.pali, t.teste, t.luci, t.segmenti, ...Object.values(t.alberi)]) lista.push(a.buffer);
  return lista;
}
