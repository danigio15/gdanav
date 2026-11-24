// La segnaletica della vista «Corsie»: l'asfalto largo quanto le corsie
// vere, le righe bianche, le frecce dipinte, le strisce pedonali, le linee
// d'arresto e i semafori, dalle vie di OpenStreetMap (`corsie.js`). Gira nel
// lavoratore, una tessera alla volta, senza three.js.
//
// Tutto in tre geometrie per tessera, comunque sia fatta: l'asfalto, la
// vernice (righe, frecce, strisce: un solo colore, un solo disegno) e i
// pali dei semafori. Nessuna geometria per riga o per freccia: sui telefoni
// e sulle autoradio conta quante volte si disegna, non quanti triangoli.

import { Costruttore } from './costruttore.js';
import { bordiCorsie, centroCorsia, larghezzaCorsie, normali, progressive } from './corsie.js';
import { ritagliaLinea } from './ritaglio.js';


/** Quanto le strisce (asfalto, righe) vanno oltre il bordo della tessera (m): vedi [striscia]. */
export const SORMONTO_M = 0.25;
/** Più lunga di così una zebratura non è (m): oltre è una carreggiata a parte. */
const ZEBRATURA_AL_PIU_M = 150;
/** E fin dove i due rami sono così lontani (m). */
const ZEBRATURA_LARGA_M = 4.5;
/** E solo fra due rami che partono così vicini di direzione (a venti metri dal nodo, radianti). */
const ZEBRATURA_APERTA = (30 * Math.PI) / 180;
/**
 * I marciapiedi delle strade di città (m): larghi secondo la strada, alti
 * [ALTO_MARCIAPIEDE] sopra l'asfalto, col cordolo. Non in autostrada, sulle
 * superstrade e sulle rampe.
 */
export const MARCIAPIEDI = { primary: 2.5, secondary: 2.5, tertiary: 2.2, unclassified: 1.8, residential: 1.8, living_street: 1.5 };
export const ALTO_MARCIAPIEDE = 0.14;

/*
 * Come si vede il marciapiede.
 *
 * «Non si capisce che sono marciapiedi»: erano una banda grigia piatta,
 * come una banchina. Adesso, come nelle mappe delle corsie dei navigatori:
 *  - il cordolo: la fascia chiara di pietra verso la strada ([CORDOLO_M]),
 *    lo spigolo scuro, la faccia verticale in ombra;
 *  - le lastre: le fughe sottili e il tono che cambia appena da una lastra
 *    all'altra, disegnati dalla scheda grafica con le uv (`u` i metri dal
 *    cordolo, `v` quelli lungo la via: vedi `corsie-marciapiedi` in
 *    scena.js), nessun triangolo in più;
 *  - gli angoli tondi agli incroci: il cordolo gira da una via all'altra,
 *    e l'asfalto riempie l'angolo (vedi [angoloMarciapiede]);
 *  - lo scivolo alle strisce pedonali: il marciapiede scende quasi
 *    all'asfalto, il cordolo sparisce, il piano cambia tono (le piastrelle
 *    per i ciechi).
 * Il colore delle facce e degli scivoli sta nei vertici (moltiplica quello
 * del materiale, che è della tavolozza: giorno o notte).
 */
/** La fascia chiara del cordolo, dal bordo della strada (m). */
export const CORDOLO_M = 0.35;
/** Lo scivolo: il piano basso lungo quanto le strisce (dal mezzo, m), la rampa, e quanto resta sopra l'asfalto. */
export const SCIVOLO = { mezzo: 1.6, rampa: 1.0, alto: 0.02 };
/** Il raggio voluto degli angoli tondi oltre la larghezza del marciapiede, e quanto lunga al più la curva su ogni via (m). */
export const ANGOLO = { raggio: 2.5, lungo: 14, minimo: (25 * Math.PI) / 180, massimo: (155 * Math.PI) / 180 };
// I colori nei vertici (moltiplicano il colore del materiale): la faccia
// del cordolo in ombra, il piano dello scivolo. Giorno e notte.
const FACCIA = [
  [104, 104, 110],
  [118, 118, 126],
];
const TATTILE = [
  [246, 230, 190],
  [226, 216, 188],
];
const PIENO = [255, 255, 255];
/** Quanto e' alta l'isola di una rotonda sopra l'asfalto (m): come un cordolo. */
const ISOLA_ALTA = 0.16;
/** Quanto si può semplificare la linea dei marciapiedi (m): il cordolo resta sul bordo dell'asfalto. */
const SEMPLIFICA_M = 0.04;

/** Larghezze delle righe (m): un poco più larghe del codice, che da lontano non spariscano. */
export const RIGHE = { corsia: 0.18, corsiaGrande: 0.2, bordo: 0.2, bordoGrande: 0.25, mezzeria: 0.2, doppia: 0.16, decelerazione: 0.5, arresto: 0.5 };

/**
 * Quanto sopra la sua quota sta l'asfalto di una via: quello che dice
 * [sopra] per la sua classe, e le gallerie appena sopra il suolo.
 *
 * «Incroci sbagliati»: una galleria sotto una strada, a terra, aveva il suo
 * asfalto alla quota di quella di sopra (una galleria non scende: la quota è
 * quella degli imbocchi), e le due strade parevano incrociarsi. Più in basso
 * delle altre, la strada di sopra la copre: passa sotto.
 */
export const SOPRA_GALLERIA_CORSIE = 0.07;
export const sopraAsfalto = (v, sopra) => (v.galleria ? SOPRA_GALLERIA_CORSIE : sopra(v.hw));

const base = (hw) => String(hw ?? '').replace(/_link$/, '');
const grande = (hw) => base(hw) === 'motorway' || base(hw) === 'trunk';
const rampa = (hw) => String(hw ?? '').endsWith('_link');

/**
 * Il tratteggio: dei pezzi `[da, a]` pieni di [pieno] metri ogni [pieno +
 * vuoto], da 0 a [L], contati dall'inizio della via (le tessere vicine li
 * mettono negli stessi punti), senza i [buchi] (`[da, a]`).
 */
export function trattini(L, pieno, vuoto, buchi = [], fase = 0) {
  const out = [];
  const periodo = pieno + vuoto;
  for (let s = fase; s < L; s += periodo) {
    const a = Math.max(0, s);
    const b = Math.min(L, s + pieno);
    if (b - a > 0.05) out.push([a, b]);
  }
  return togli(out, buchi);
}

/**
 * Il tratteggio di una via stimata (`stimata`, vedi stima.js): un numero
 * intero di trattini, appena allungati o accorciati, con mezzo vuoto ai due
 * capi. I pezzi stimati nascono e finiscono sul bordo della tessera, e
 * contati dall'inizio di ognuno (come [trattini]) lì due trattini
 * finirebbero attaccati: così sul bordo c'è un vuoto intero.
 */
export function trattiniAdattati(L, pieno, vuoto, buchi = []) {
  const periodo = pieno + vuoto;
  const n = Math.max(1, Math.round(L / periodo));
  const k = L / (n * periodo);
  return trattini(L, pieno * k, vuoto * k, buchi, (vuoto * k) / 2);
}

/** Gli intervalli [pezzi] senza le parti dentro [buchi] (tutti `[da, a]`). */
export function togli(pezzi, buchi) {
  let out = pezzi;
  for (const [h0, h1] of buchi) {
    const nuovi = [];
    for (const [a, b] of out) {
      if (h1 <= a || h0 >= b) nuovi.push([a, b]);
      else {
        if (h0 > a + 0.05) nuovi.push([a, h0]);
        if (h1 < b - 0.05) nuovi.push([h1, b]);
      }
    }
    out = nuovi;
  }
  return out;
}

/**
 * Le frecce dipinte: triangoli in un piano tutto suo, `[u, v]` con u a
 * destra e v avanti (in metri), lunga [L] e larga [W] (la punta). Una
 * freccia per ogni direzione di [dirs] (`left`, `through;right`, …), tutte
 * dallo stesso gambo, come in Italia.
 */
export function formaFreccia(dirs, L = 6, W = 1.5) {
  const tri = [];
  const g = W * 0.16; // mezzo gambo
  const quad = (a, b, c, d) => tri.push([a, b, c], [a, c, d]);
  // Un tratto dritto da [p] a [q], largo 2g.
  const tratto = (p, q) => {
    const dx = q[0] - p[0];
    const dy = q[1] - p[1];
    const l = Math.hypot(dx, dy) || 1;
    const nx = (-dy / l) * g;
    const ny = (dx / l) * g;
    quad([p[0] + nx, p[1] + ny], [q[0] + nx, q[1] + ny], [q[0] - nx, q[1] - ny], [p[0] - nx, p[1] - ny]);
  };
  // La punta in [p], verso [ang] (radianti, 0 = avanti, positivo a destra).
  const punta = (p, ang, lung = L * 0.3, larga = W / 2) => {
    const fx = Math.sin(ang);
    const fy = Math.cos(ang);
    tri.push([
      [p[0] + fy * larga, p[1] - fx * larga],
      [p[0] + fx * lung, p[1] + fy * lung],
      [p[0] - fy * larga, p[1] + fx * larga],
    ]);
  };
  const gambo = L * 0.55;
  for (const d of dirs) {
    const lato = d.includes('right') ? 1 : d.includes('left') ? -1 : 0;
    if (d === 'through' || (!lato && d !== 'reverse')) {
      tratto([0, 0], [0, L * 0.7]);
      punta([0, L * 0.7], 0);
    } else if (d.startsWith('slight_') || d.startsWith('merge_to_')) {
      // Il gambo, poi di sbieco a trenta gradi.
      const a = (lato * Math.PI) / 6;
      const q = [Math.sin(a) * L * 0.22, gambo + Math.cos(a) * L * 0.22];
      tratto([0, 0], [0, gambo]);
      tratto([0, gambo - g], q);
      punta(q, a, L * 0.26);
    } else if (d === 'reverse') {
      tratto([0, 0], [0, gambo]);
      tratto([0, gambo], [-W * 0.7, gambo]);
      tratto([-W * 0.7, gambo + g], [-W * 0.7, gambo - L * 0.2]);
      punta([-W * 0.7, gambo - L * 0.2], Math.PI, L * 0.25);
    } else {
      // A destra o a sinistra: il gambo fino a metà, poi di lato.
      const ang = d.startsWith('sharp_') ? (lato * Math.PI * 3) / 4 : (lato * Math.PI) / 2;
      const y = gambo * 0.85;
      const q = [lato * W * 0.55, y + (d.startsWith('sharp_') ? -W * 0.4 : 0)];
      tratto([0, 0], [0, y + g]);
      tratto([0, y], q);
      punta(q, ang, L * 0.22, W * 0.42);
    }
  }
  return tri;
}

/**
 * Una via pronta da disegnare: i punti `[x, y, h, nx, ny, s]` (metri della
 * tessera, la quota, la normale a sinistra, i metri dall'inizio).
 */
export function lineaRicca(xy, quote) {
  const nn = normali(xy);
  const s = progressive(xy);
  return xy.map((p, k) => [p[0], p[1], quote[k], nn[k][0], nn[k][1], s[k]]);
}

/** Il pezzo di linea ricca fra [s0] e [s1] metri. */
export function pezzoFra(r, s0, s1) {
  const at = (sv) => {
    let k = 1;
    while (k < r.length - 1 && r[k][5] < sv) k++;
    const a = r[k - 1];
    const b = r[k];
    const t = Math.max(0, Math.min(1, (sv - a[5]) / Math.max(1e-9, b[5] - a[5])));
    return a.map((v, i) => v + (b[i] - v) * t);
  };
  const out = [at(s0)];
  for (const p of r) if (p[5] > s0 && p[5] < s1) out.push(p);
  out.push(at(s1));
  return out;
}

/**
 * Una striscia lungo la linea ricca [r], fra lo spostamento [oa] e [ob] (a
 * sinistra positivo, numeri o funzioni dei metri), alta [dz] sopra la
 * quota, tagliata sul quadrato [-meta, meta]. In [c].
 */
export function striscia(c, r, oa, ob, dz, meta) {
  const fa = typeof oa === 'function' ? oa : () => oa;
  const fb = typeof ob === 'function' ? ob : () => ob;
  /* Un palmo oltre il bordo della tessera. «Righe sottili di traverso sulla
   * carreggiata»: la striscia finisce di traverso alla via nel punto dove la
   * sua linea esce dalla tessera, e la tessera accanto riparte da lì; ma in
   * curva le due non hanno gli stessi punti (ognuna tiene quelli che servono
   * alle sue quote), i due tagli non sono proprio paralleli, e dalla parte
   * di fuori restava una fessura a cuneo da cui si vedeva quello che c'è
   * sotto. Così le due strisce si sormontano. */
  const m = meta + SORMONTO_M;
  for (const pezzo of ritagliaLinea(r, -m, -m, m, m)) {
    if (pezzo.length < 2) continue;
    const base = c.vertici;
    for (const p of pezzo) {
      const nl = Math.hypot(p[3], p[4]) || 1;
      const nx = p[3] / nl;
      const ny = p[4] / nl;
      const a = fa(p[5]);
      const b = fb(p[5]);
      c.v(p[0] + nx * a, p[1] + ny * a, p[2] + dz, 0, 0, 1);
      c.v(p[0] + nx * b, p[1] + ny * b, p[2] + dz, 0, 0, 1);
    }
    for (let k = 1; k < pezzo.length; k++) {
      const l0 = base + 2 * (k - 1);
      // In su: a sinistra (a) prima, a destra (b) dopo, girati come serve.
      if (fa(pezzo[k][5]) >= fb(pezzo[k][5])) {
        c.tri(l0, l0 + 1, l0 + 3);
        c.tri(l0, l0 + 3, l0 + 2);
      } else {
        c.tri(l0, l0 + 3, l0 + 1);
        c.tri(l0, l0 + 2, l0 + 3);
      }
    }
  }
}

/** Il punto della linea ricca a [s] metri, spostato di [o] a sinistra: `[x, y, h, tx, ty]`. */
export function puntoA(r, s, o = 0) {
  const p = pezzoFra(r, s, s)[0];
  const nl = Math.hypot(p[3], p[4]) || 1;
  const nx = p[3] / nl;
  const ny = p[4] / nl;
  return [p[0] + nx * o, p[1] + ny * o, p[2], ny, -nx];
}

/** Dei triangoli piani in [c], dal piano `[u, v]` (u a destra, v avanti) al posto [x, y, z] verso [tx, ty]. */
function triangoliPiani(c, tri, x, y, z, tx, ty) {
  // A destra di chi va verso (tx, ty): (ty, -tx).
  for (const [a, b, d] of tri) {
    const P = (q) => [x + ty * q[0] + tx * q[1], y - tx * q[0] + ty * q[1], z];
    c.triPunti(P(a), P(b), P(d), [0, 0, 1]);
  }
}

/** Una scatola dritta (pali, lanterne) in [c], coi colori di giorno e di notte. */
function scatola(c, x, y, z0, z1, tx, ty, lu, lv, cg, cn) {
  const vx = -ty;
  const vy = tx;
  const P = (a, b, z) => [x + tx * a * lu + vx * b * lv, y + ty * a * lu + vy * b * lv, z];
  const facce = [
    [[-1, -1], [1, -1], [ty, -tx]],
    [[1, -1], [1, 1], [tx, ty]],
    [[1, 1], [-1, 1], [-ty, tx]],
    [[-1, 1], [-1, -1], [-tx, -ty]],
  ];
  for (const [[a0, b0], [a1, b1], nn] of facce) c.quad(P(a0, b0, z0), P(a1, b1, z0), P(a1, b1, z1), P(a0, b0, z1), [nn[0], nn[1], 0], cg, cn);
  c.quad(P(-1, -1, z1), P(1, -1, z1), P(1, 1, z1), P(-1, 1, z1), [0, 0, 1], cg, cn);
}

/*
 * I semafori, come in Italia: il palo tondo d'acciaio grigio, alto tre
 * metri, con la lanterna in cima; la lanterna verde scurissimo con tre
 * lenti tonde, ognuna con la sua visiera, e dietro il pannello nero col
 * bordino bianco. Agli incroci larghi (due corsie per chi arriva, o più di
 * quindici metri da attraversare) il palo a sbraccio: alto, col braccio che
 * passa sopra le corsie e la lanterna appesa sopra di loro, e una seconda
 * lanterna sul palo, all'altezza di sempre.
 *
 * Spenti: in Italia non si sa di che colore è un semaforo né quando cambia
 * (nessuno lo pubblica), e una luce rossa o verde disegnata direbbe una
 * cosa falsa. Le lenti sono vetro scuro, tutte uguali. Un poco più grandi del
 * vero, che sul telefono a sessanta metri si leggano.
 */
const PALO = [[132, 138, 146], [66, 70, 78]];
// Più scuri del vero: la luce chiara della vista «Corsie» li schiarisce.
const LANTERNA = [[14, 22, 18], [10, 14, 12]];
const PANNELLO = [[6, 6, 8], [4, 4, 6]];
const BORDINO = [[238, 240, 243], [150, 156, 166]];
const LENTE = [[70, 76, 86], [50, 54, 62]];
/** Le misure (m): il palo, la lanterna (alta, larga, profonda), le lenti, lo sbraccio. */
export const SEMAFORO = { palo: 2.6, raggioPalo: 0.09, alta: 1.3, larga: 0.44, fonda: 0.3, lente: 0.15, sbraccio: 6.2, sopraCorsie: 5.4 };

/** Un cilindro a [lati] facce fra i punti [a] e [b] (`[x, y, z]`), di raggio [r]. */
export function cilindro(c, a, b, r, lati, cg, cn) {
  const ax = b[0] - a[0];
  const ay = b[1] - a[1];
  const az = b[2] - a[2];
  const l = Math.hypot(ax, ay, az) || 1;
  const u = [ax / l, ay / l, az / l];
  // Due direzioni di traverso all'asse.
  const q = Math.abs(u[2]) < 0.9 ? [0, 0, 1] : [1, 0, 0];
  let p1 = [u[1] * q[2] - u[2] * q[1], u[2] * q[0] - u[0] * q[2], u[0] * q[1] - u[1] * q[0]];
  const l1 = Math.hypot(...p1);
  p1 = p1.map((v) => v / l1);
  const p2 = [u[1] * p1[2] - u[2] * p1[1], u[2] * p1[0] - u[0] * p1[2], u[0] * p1[1] - u[1] * p1[0]];
  const giro = (k) => {
    const t = (2 * Math.PI * k) / lati;
    return [Math.cos(t) * p1[0] + Math.sin(t) * p2[0], Math.cos(t) * p1[1] + Math.sin(t) * p2[1], Math.cos(t) * p1[2] + Math.sin(t) * p2[2]];
  };
  for (let k = 0; k < lati; k++) {
    const d0 = giro(k);
    const d1 = giro(k + 1);
    const n = giro(k + 0.5);
    const P = (o, d) => [o[0] + d[0] * r, o[1] + d[1] * r, o[2] + d[2] * r];
    c.quad(P(a, d0), P(a, d1), P(b, d1), P(b, d0), n, cg, cn);
  }
}

/**
 * Una lanterna in [c]: il centro [x, y, z] (z il mezzo della lanterna), che
 * guarda verso [fx, fy]; il pannello nero col bordino, la scatola, le tre
 * lenti con le visiere.
 */
export function lanterna(c, x, y, z, fx, fy) {
  const { alta, larga, fonda, lente } = SEMAFORO;
  // A destra di chi guarda la lanterna da davanti: (fy, -fx).
  const P = (dx, dz, avanti) => [x + fy * dx + fx * avanti, y - fx * dx + fy * avanti, z + dz];
  const piano = (w, h, avanti, cg, cn) => c.quad(P(-w, -h, avanti), P(w, -h, avanti), P(w, h, avanti), P(-w, h, avanti), [fx, fy, 0], cg, cn);
  // Il pannello: prima il bordino bianco, un poco più grande e dietro; poi il nero.
  piano(larga / 2 + 0.2, alta / 2 + 0.16, -0.02, ...BORDINO);
  piano(larga / 2 + 0.17, alta / 2 + 0.13, 0.0, ...PANNELLO);
  scatola(c, x + fx * (fonda / 2), y + fy * (fonda / 2), z - alta / 2, z + alta / 2, fx, fy, fonda / 2, larga / 2, ...LANTERNA);
  for (let j = 0; j < 3; j++) {
    const zc = alta / 3 - (j * alta) / 3;
    const davanti = fonda + 0.005;
    // La lente: un disco di otto spicchi, vetro scuro.
    const N = 10;
    for (let k = 0; k < N; k++) {
      const a0 = (2 * Math.PI * k) / N;
      const a1 = (2 * Math.PI * (k + 1)) / N;
      c.triPunti(P(0, zc, davanti), P(Math.cos(a0) * lente, zc + Math.sin(a0) * lente, davanti), P(Math.cos(a1) * lente, zc + Math.sin(a1) * lente, davanti), [fx, fy, 0], ...LENTE);
    }
    // La visiera: mezzo tubo sopra la lente, che sporge in avanti.
    for (let k = 0; k < 5; k++) {
      const a0 = (Math.PI * k) / 5;
      const a1 = (Math.PI * (k + 1)) / 5;
      const r = lente + 0.03;
      const q0 = [Math.cos(a0) * r, zc + Math.sin(a0) * r];
      const q1 = [Math.cos(a1) * r, zc + Math.sin(a1) * r];
      const m = (a0 + a1) / 2;
      c.quad(P(q0[0], q0[1], davanti), P(q1[0], q1[1], davanti), P(q1[0], q1[1], davanti + 0.22), P(q0[0], q0[1], davanti + 0.22), [fy * Math.cos(m), -fx * Math.cos(m), Math.sin(m)], ...LANTERNA);
    }
  }
}

/*
 * Dove non va il marciapiede.
 *
 * «Guarda questo incrocio, i marciapiedi in mezzo alla strada.» Ogni via di
 * città aveva il suo marciapiede da tutti e due i lati, aperto solo dove
 * un'altra via la tocca in un nodo: ma agli incroci le vie si incrociano e
 * si sovrappongono anche senza nodi in comune (le carreggiate divise, i
 * rami di svolta), e il marciapiede passava sull'asfalto delle altre; fra due
 * carreggiate vicine (lo spartitraffico) i due marciapiedi interni si
 * accavallavano, e nei pezzi corti a senso unico dentro l'incrocio
 * attraversavano tutto. Adesso il marciapiede non c'è:
 *  - sull'asfalto di un'altra via (alla stessa quota), come il cordolo vero
 *    che si interrompe all'incrocio;
 *  - dal lato dove, entro [SPARTITRAFFICO_M] dal cordolo, corre un'altra via
 *    quasi parallela (l'altra carreggiata, una complanare): lì c'è al più
 *    lo spartitraffico;
 *  - sui pezzi a senso unico più corti di [PEZZO_INCROCIO_M] attaccati ad
 *    altre vie ai due capi (le svolte e i rami dentro l'incrocio), come
 *    sulle rampe (`_link`, che non lo hanno mai).
 */
export const SPARTITRAFFICO_M = 8;
export const PEZZO_INCROCIO_M = 45;
const PASSO_MARCIAPIEDE_M = 1.5;

/**
 * L'asfalto di tutte le vie [strade] (con [ricche]: le loro linee ricche, e
 * [bordi]: `[sinistra, destra]` dell'asfalto a sinistra della linea), in una
 * griglia: `sotto(x, y, h, salvo)` dice l'asfalto di quale via (non [salvo])
 * copre il punto, `{i, tx, ty}` (il verso di quel pezzo), o null.
 */
export function asfaltoDelleVie(strade, ricche, bordi, cella = 16) {
  const griglia = new Map();
  const pezzi = [];
  strade.forEach((v, i) => {
    if (v.galleria) return;
    const r = ricche[i];
    const [sx, dx] = bordi[i];
    const oc = (sx + dx) / 2;
    const mezza = (sx - dx) / 2;
    for (let k = 1; k < r.length; k++) {
      const a = r[k - 1];
      const b = r[k];
      const na = Math.hypot(a[3], a[4]) || 1;
      const nb = Math.hypot(b[3], b[4]) || 1;
      const ax = a[0] + (a[3] / na) * oc;
      const ay = a[1] + (a[4] / na) * oc;
      const bx = b[0] + (b[3] / nb) * oc;
      const by = b[1] + (b[4] / nb) * oc;
      const l = Math.hypot(bx - ax, by - ay);
      if (l < 1e-6) continue;
      const q = { i, ax, ay, bx, by, l, tx: (bx - ax) / l, ty: (by - ay) / l, mezza, h: (a[2] + b[2]) / 2, ha: a[2], hb: b[2] };
      const n = pezzi.push(q) - 1;
      const m = mezza + 1;
      for (let cx = Math.floor((Math.min(ax, bx) - m) / cella); cx <= Math.floor((Math.max(ax, bx) + m) / cella); cx++) {
        for (let cy = Math.floor((Math.min(ay, by) - m) / cella); cy <= Math.floor((Math.max(ay, by) + m) / cella); cy++) {
          const kk = cx * 100003 + cy;
          let lista = griglia.get(kk);
          if (!lista) griglia.set(kk, (lista = []));
          lista.push(n);
        }
      }
    }
  });
  return {
    sotto(x, y, h, salvo, margine = 0.3) {
      for (const n of griglia.get(Math.floor(x / cella) * 100003 + Math.floor(y / cella)) ?? []) {
        const q = pezzi[n];
        if (q.i === salvo || Math.abs(q.h - h) > 2.5) continue;
        const u = Math.max(0, Math.min(q.l, (x - q.ax) * q.tx + (y - q.ay) * q.ty));
        if (Math.hypot(x - q.ax - q.tx * u, y - q.ay - q.ty * u) < q.mezza + margine) return q;
      }
      return null;
    },
    /**
     * Come [sotto], ma solo sulla striscia vera: fra i due capi del tratto
     * (non nel mezzo disco oltre il capo) e fra i due bordi. Restituisce il
     * tratto e `quota`, quella della via in quel punto.
     */
    sullaStriscia(x, y, h, salvo, margine = 0) {
      for (const n of griglia.get(Math.floor(x / cella) * 100003 + Math.floor(y / cella)) ?? []) {
        const q = pezzi[n];
        if (q.i === salvo || Math.abs(q.h - h) > 2.5) continue;
        const u = (x - q.ax) * q.tx + (y - q.ay) * q.ty;
        if (u < -0.02 || u > q.l + 0.02) continue;
        if (Math.abs((x - q.ax) * q.ty - (y - q.ay) * q.tx) < q.mezza + margine) return { ...q, quota: q.ha + ((q.hb - q.ha) * Math.max(0, Math.min(q.l, u))) / q.l };
      }
      return null;
    },
    /** Se il punto sta sull'asfalto della via [i] (a [margine] metri dal bordo). */
    diVia(x, y, h, i, margine = 0.3) {
      for (const n of griglia.get(Math.floor(x / cella) * 100003 + Math.floor(y / cella)) ?? []) {
        const q = pezzi[n];
        if (q.i !== i || Math.abs(q.h - h) > 2.5) continue;
        const u = Math.max(0, Math.min(q.l, (x - q.ax) * q.tx + (y - q.ay) * q.ty));
        if (Math.hypot(x - q.ax - q.tx * u, y - q.ay - q.ty * u) < q.mezza + margine) return true;
      }
      return false;
    },
  };
}

/**
 * I tratti `[da, a]` (metri lungo la linea ricca [r] della via [i]) dove il
 * marciapiede dal [lato] (1 sinistra, -1 destra), largo [largo] dal [bordo],
 * non va (vedi sopra): sull'asfalto di un'altra via, o con un'altra via quasi
 * parallela a meno di [SPARTITRAFFICO_M] dal cordolo. Solo dove [utile]
 * (`(x, y) => bool`: dentro la tessera).
 */
export function senzaMarciapiede(r, i, lato, bordo, largo, asfalto, utile = () => true) {
  const L = r[r.length - 1][5];
  const out = [];
  const passo = PASSO_MARCIAPIEDE_M;
  let k = 1;
  for (let s = passo / 2; s < L; s += passo) {
    // Il punto a [s] (la linea si percorre una volta sola).
    while (k < r.length - 1 && r[k][5] < s) k++;
    const a0 = r[k - 1];
    const b0 = r[k];
    const f = Math.max(0, Math.min(1, (s - a0[5]) / Math.max(1e-9, b0[5] - a0[5])));
    const p = a0.map((v, j) => v + (b0[j] - v) * f);
    const nl = Math.hypot(p[3], p[4]) || 1;
    const nx = p[3] / nl;
    const ny = p[4] / nl;
    if (!utile(p[0] + nx * bordo, p[1] + ny * bordo)) continue;
    // Il verso della via qui: a destra della normale a sinistra.
    const tx = ny;
    const ty = -nx;
    let no = false;
    for (const d of [0.25, largo / 2, largo - 0.25]) {
      const o = bordo + lato * d;
      if (asfalto.sotto(p[0] + nx * o, p[1] + ny * o, p[2], i)) {
        no = true;
        break;
      }
    }
    for (let d = 0.5; !no && d <= SPARTITRAFFICO_M; d += 1.5) {
      const o = bordo + lato * d;
      const q = asfalto.sotto(p[0] + nx * o, p[1] + ny * o, p[2], i, 0);
      if (q && Math.abs(q.tx * tx + q.ty * ty) > 0.8) no = true;
    }
    if (!no) continue;
    const a = Math.max(0, s - passo / 2 - 0.3);
    const b = Math.min(L, s + passo / 2 + 0.3);
    if (out.length && out[out.length - 1][1] >= a) out[out.length - 1][1] = b;
    else out.push([a, b]);
  }
  return out;
}

/**
 * Il pezzo di linea ricca fra [a] e [b] metri con un punto anche a ogni
 * metro di [tagli] (dove comincia e finisce uno scivolo). Restituisce i
 * punti e quelli da tenere comunque (i capi e i tagli).
 */
export function pezzoConTagli(r, a, b, tagli = []) {
  const pz = pezzoFra(r, a, b);
  const fissi = new Set([pz[0], pz[pz.length - 1]]);
  const dentro = [...new Set(tagli)].filter((s) => s > a + 0.05 && s < b - 0.05).sort((p, q) => p - q);
  if (!dentro.length) return { pz, fissi };
  const out = [];
  let j = 0;
  for (const p of pz) {
    while (j < dentro.length && dentro[j] < p[5] - 1e-6) {
      const q = pezzoFra(r, dentro[j], dentro[j])[0];
      out.push(q);
      fissi.add(q);
      j++;
    }
    if (j < dentro.length && Math.abs(dentro[j] - p[5]) <= 1e-6) {
      fissi.add(p);
      j++;
    }
    out.push(p);
  }
  return { pz: out, fissi };
}

/** La distanza di [p] dal segmento [a]-[b] (`[x, y]`). */
function distanzaSegmento(p, a, b) {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const l2 = dx * dx + dy * dy;
  const t = l2 > 1e-12 ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2)) : 0;
  return Math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dy * t);
}

/**
 * Il pezzo [pz] (linea ricca) con meno punti: si tolgono quelli che non
 * spostano di più di [eps] né il bordo [o1] né quello [o2] (gli spostamenti
 * a sinistra del cordolo e del filo esterno) né la quota. Sulle vie dritte
 * il marciapiede resta di quattro vertici (prima uno ogni punto della via,
 * che dopo i raccordi ne ha uno ogni quattro metri). I [fissi] restano.
 */
export function semplificaPezzo(pz, o1, o2, eps = SEMPLIFICA_M, fissi = new Set()) {
  const n = pz.length;
  if (n <= 2) return pz;
  const sposta = (p, o) => {
    const nl = Math.hypot(p[3], p[4]) || 1;
    return [p[0] + (p[3] / nl) * o, p[1] + (p[4] / nl) * o];
  };
  const A = pz.map((p) => sposta(p, o1));
  const Bq = pz.map((p) => sposta(p, o2));
  const tieni = new Uint8Array(n);
  tieni[0] = 1;
  tieni[n - 1] = 1;
  pz.forEach((p, k) => {
    if (fissi.has(p)) tieni[k] = 1;
  });
  const pila = [];
  let prima = 0;
  for (let k = 1; k < n; k++) {
    if (!tieni[k]) continue;
    pila.push([prima, k]);
    prima = k;
  }
  while (pila.length) {
    const [i, j] = pila.pop();
    if (j - i < 2) continue;
    let peggio = -1;
    let dmax = eps;
    const ds = pz[j][5] - pz[i][5] || 1e-9;
    for (let k = i + 1; k < j; k++) {
      const t = (pz[k][5] - pz[i][5]) / ds;
      const dz = Math.abs(pz[k][2] - (pz[i][2] + (pz[j][2] - pz[i][2]) * t));
      const d = Math.max(dz, distanzaSegmento(A[k], A[i], A[j]), distanzaSegmento(Bq[k], Bq[i], Bq[j]));
      if (d > dmax) {
        dmax = d;
        peggio = k;
      }
    }
    if (peggio < 0) continue;
    tieni[peggio] = 1;
    pila.push([i, peggio], [peggio, j]);
  }
  return pz.filter((_, k) => tieni[k]);
}

/** Il triangolo [i0, i1, i2] di [c], girato in modo che la sua normale vada come [n]. */
function triVerso(c, i0, i1, i2, n) {
  const p = c.p;
  const ux = p[3 * i1] - p[3 * i0];
  const uy = p[3 * i1 + 1] - p[3 * i0 + 1];
  const uz = p[3 * i1 + 2] - p[3 * i0 + 2];
  const vx = p[3 * i2] - p[3 * i0];
  const vy = p[3 * i2 + 1] - p[3 * i0 + 1];
  const vz = p[3 * i2 + 2] - p[3 * i0 + 2];
  const g = (uy * vz - uz * vy) * n[0] + (uz * vx - ux * vz) * n[1] + (ux * vy - uy * vx) * n[2];
  if (g >= 0) c.tri(i0, i1, i2);
  else c.tri(i0, i2, i1);
}

/**
 * Un marciapiede in [c] lungo i punti del cordolo [punti] (`{x, y, nx, ny,
 * zb, w, f, s}`: dove sta il bordo dell'asfalto, la direzione verso il
 * marciapiede, la quota dell'asfalto, la larghezza, 1 dove è alto e 0 sullo
 * scivolo, i metri lungo la via): il piano in cima e la faccia del cordolo
 * verso la strada. Le uv: `u` i metri dal cordolo (sullo scivolo il
 * cordolo non c'è: comincia più in là), `v` i metri lungo.
 */
export function nastroMarciapiede(c, punti) {
  if (punti.length < 2) return;
  const sopra = [];
  const faccia = [];
  for (const q of punti) {
    const f = Math.max(0, Math.min(1, q.f));
    const zt = q.zb + SCIVOLO.alto + (ALTO_MARCIAPIEDE - SCIVOLO.alto) * f;
    const cg = TATTILE[0].map((v, k) => Math.round(v + (PIENO[k] - v) * f));
    const cn = TATTILE[1].map((v, k) => Math.round(v + (PIENO[k] - v) * f));
    const u0 = (CORDOLO_M + 0.06) * (1 - f);
    sopra.push(c.v(q.x, q.y, zt, 0, 0, 1, u0, q.s, cg, cn), c.v(q.x + q.nx * q.w, q.y + q.ny * q.w, zt, 0, 0, 1, Math.max(q.w, u0 + 0.1), q.s, cg, cn));
    faccia.push(c.v(q.x, q.y, q.zb - 0.05, -q.nx, -q.ny, 0, 0, q.s, ...FACCIA), c.v(q.x, q.y, zt, -q.nx, -q.ny, 0, 0, q.s, ...FACCIA));
  }
  for (let k = 1; k < punti.length; k++) {
    const [a0, a1] = [sopra[2 * k - 2], sopra[2 * k - 1]];
    const [b0, b1] = [sopra[2 * k], sopra[2 * k + 1]];
    triVerso(c, a0, a1, b1, [0, 0, 1]);
    triVerso(c, a0, b1, b0, [0, 0, 1]);
    const n = [-(punti[k].nx + punti[k - 1].nx), -(punti[k].ny + punti[k - 1].ny), 0];
    const [f0, f1] = [faccia[2 * k - 2], faccia[2 * k - 1]];
    const [g0, g1] = [faccia[2 * k], faccia[2 * k + 1]];
    triVerso(c, f0, g0, g1, n);
    triVerso(c, f0, g1, f1, n);
  }
}

/**
 * Le bocche delle strisce pedonali: dove il marciapiede scende. [bocche]:
 * `{x, y, tx, ty, mezza}` (il mezzo delle strisce sull'asse della
 * carreggiata, il verso della via, mezza larghezza dell'asfalto).
 * Restituisce `(x, y) => f`: 1 dove il marciapiede è alto, 0 sullo scivolo.
 */
export function scivoli(bocche) {
  return (x, y) => {
    let f = 1;
    for (const b of bocche) {
      const dx = x - b.x;
      const dy = y - b.y;
      if (Math.abs(dx) > b.mezza + 6 && Math.abs(dy) > b.mezza + 6) continue;
      const lungo = Math.abs(dx * b.tx + dy * b.ty);
      const traverso = Math.abs(dx * b.ty - dy * b.tx);
      if (traverso > b.mezza + 2.5 || lungo > SCIVOLO.mezzo + SCIVOLO.rampa) continue;
      f = Math.min(f, Math.max(0, (lungo - SCIVOLO.mezzo) / SCIVOLO.rampa));
    }
    return f;
  };
}

/**
 * L'angolo tondo fra due vie che si incontrano in un nodo, da [A] a [Bv]
 * (in senso antiorario): `{i, k, passo}` (il ramo: la via, il nodo, verso
 * dove va), [strade]/[ricche]/[bordi] come in [asfaltoDelleVie], [sopra]
 * l'altezza dell'asfalto. Il cordolo del lato di [A] verso [Bv] gira, con un
 * arco, in quello di [Bv] verso [A]: i due marciapiedi finiscono dove
 * comincia l'arco, e l'arco ha il suo marciapiede. Restituisce l'arco
 * (`punti`: il cordolo, verso il marciapiede; `C`: lo spigolo che l'arco
 * taglia, dove l'asfalto riempie l'angolo) e dove finiscono i due
 * marciapiedi dritti, o null se lì l'angolo non si fa (le vie quasi dritte o
 * quasi parallele, troppo corte, o un'altra via sull'arco).
 */
export function angoloMarciapiede(A, Bv, strade, ricche, bordi, sopra, asfalto) {
  const capo = (x, lato) => {
    const v = strade[x.i];
    const r = ricche[x.i];
    const L = r[r.length - 1][5];
    const Lvia = v.sVia[v.sVia.length - 1] || L;
    const s = (v.sVia[x.k] * L) / Lvia;
    const bordo = lato > 0 ? bordi[x.i][0] : bordi[x.i][1];
    const p0 = puntoA(r, s, 0);
    const p1 = puntoA(r, Math.max(0, Math.min(L, s + x.passo * 8)), 0);
    const l = Math.hypot(p1[0] - p0[0], p1[1] - p0[1]);
    if (l < 2) return null;
    return { i: x.i, k: x.k, passo: x.passo, lato, s, L, r, bordo, d: [(p1[0] - p0[0]) / l, (p1[1] - p0[1]) / l], K: puntoA(r, s, bordo), w: MARCIAPIEDI[v.hw], z0: sopra(v.hw) };
  };
  const a = capo(A, A.passo);
  const b = capo(Bv, -Bv.passo);
  if (!a || !b) return null;
  const croce = (u, v) => u[0] * v[1] - u[1] * v[0];
  const th = Math.atan2(croce(a.d, b.d), a.d[0] * b.d[0] + a.d[1] * b.d[1]);
  if (th < ANGOLO.minimo || th > ANGOLO.massimo) return null;
  // Lo spigolo: dove si incontrano i due cordoli.
  const e = [b.K[0] - a.K[0], b.K[1] - a.K[1]];
  const cr = croce(a.d, b.d);
  const ta = croce(e, b.d) / cr;
  const tb = croce(e, a.d) / cr;
  if (ta < -1 || tb < -1 || ta > 30 || tb > 30) return null;
  const largo = Math.max(a.w, b.w);
  let raggio = largo + ANGOLO.raggio;
  let lungo = raggio / Math.tan(th / 2);
  if (lungo > ANGOLO.lungo) {
    lungo = ANGOLO.lungo;
    raggio = lungo * Math.tan(th / 2);
  }
  if (raggio < largo + 0.6) return null;
  for (const [x, t] of [
    [a, ta],
    [b, tb],
  ]) {
    x.sT = x.s + x.passo * (t + lungo);
    if (x.sT < 0.5 || x.sT > x.L - 0.5) return null;
    x.T = puntoA(x.r, x.sT, x.bordo);
    // Il verso della via lì, fuori dal nodo.
    x.dT = [x.T[3] * x.passo, x.T[4] * x.passo];
  }
  // L'arco: da dove finisce il marciapiede di [a] a dove comincia quello di
  // [b], tangente ai due cordoli (una conica: il cerchio se i due lati sono uguali).
  const f = [b.T[0] - a.T[0], b.T[1] - a.T[1]];
  const crT = croce(a.dT, b.dT);
  if (Math.abs(crT) < 0.2) return null;
  const al = -croce(f, b.dT) / crT;
  const be = -croce(f, a.dT) / crT;
  if (al < 0.3 || be < 0.3) return null;
  const C = [a.T[0] - a.dT[0] * al, a.T[1] - a.dT[1] * al];
  /* Lo spigolo sta sul bordo delle due vie, e da lì fino all'arco il bordo è
   * dritto. «Toppe d'incrocio fuori dall'asfalto»: dove una via curva prima
   * dell'angolo (le svolte a destra che tagliano l'incrocio) le tangenti nei
   * punti dell'arco si incontravano lontano dalle due vie, e l'asfalto che
   * riempie l'angolo era un triangolo scuro sul prato, con il prato fra lui
   * e le strade. Lì l'angolo tondo non si fa. */
  if (asfalto?.diVia) {
    for (const x of [a, b]) {
      for (const u of [0, 0.35, 0.7]) {
        if (!asfalto.diVia(C[0] + (x.T[0] - C[0]) * u, C[1] + (x.T[1] - C[1]) * u, x.T[2], x.i, 0.6)) return null;
      }
    }
  }
  const thT = Math.atan2(crT, a.dT[0] * b.dT[0] + a.dT[1] * b.dT[1]);
  const om = Math.sin(Math.max(0.2, thT) / 2);
  const N = Math.max(2, Math.ceil((Math.PI - thT) / (Math.PI / 8)));
  const xy = [];
  for (let j = 0; j <= N; j++) {
    const t = j / N;
    const p0 = (1 - t) * (1 - t);
    const p1 = 2 * om * t * (1 - t);
    const p2 = t * t;
    const S = p0 + p1 + p2;
    xy.push([(p0 * a.T[0] + p1 * C[0] + p2 * b.T[0]) / S, (p0 * a.T[1] + p1 * C[1] + p2 * b.T[1]) / S]);
  }
  const punti = [];
  let s = 0;
  for (let j = 0; j <= N; j++) {
    const t = j / N;
    const pa = xy[Math.max(0, j - 1)];
    const pb = xy[Math.min(N, j + 1)];
    const l = Math.hypot(pb[0] - pa[0], pb[1] - pa[1]) || 1;
    // Il marciapiede a destra di chi va da [a] a [b] (verso l'isolato); ai
    // capi proprio come quelli dritti, che i fili esterni si attacchino.
    let nx = (pb[1] - pa[1]) / l;
    let ny = -(pb[0] - pa[0]) / l;
    if (j === 0) [nx, ny] = [-a.dT[1], a.dT[0]];
    if (j === N) [nx, ny] = [b.dT[1], -b.dT[0]];
    if (j) s += Math.hypot(xy[j][0] - xy[j - 1][0], xy[j][1] - xy[j - 1][1]);
    const h = a.T[2] + (b.T[2] - a.T[2]) * t;
    const w = a.w + (b.w - a.w) * t;
    // Nessun'altra via sotto l'arco.
    for (const o of [0.5, w / 2, w - 0.25]) {
      if (asfalto && asfalto.sotto(xy[j][0] + nx * o, xy[j][1] + ny * o, h, -1, 0.1)) return null;
    }
    punti.push({ x: xy[j][0], y: xy[j][1], nx, ny, h, zb: h + a.z0 + (b.z0 - a.z0) * t, w, f: 1, s: a.sT + s });
  }
  // Lo spigolo dell'asfalto che riempie l'angolo, un poco dentro le due vie:
  // fra l'angolo e le strisce dell'asfalto nessuna fessura.
  const bx = -(a.dT[0] + b.dT[0]);
  const by = -(a.dT[1] + b.dT[1]);
  const bl = Math.hypot(bx, by) || 1;
  const riempi = [C[0] + (bx / bl) * 0.3, C[1] + (by / bl) * 0.3];
  return { a, b, C, riempi, zC: (punti[0].zb + punti[N].zb) / 2, punti };
}

/** Su quanti metri, al più, l'asfalto di una via si stringe verso quello della via in cui continua. */
const RASTREMA_M = 30;

/**
 * Dove una via continua in un'altra con l'asfalto più stretto, il suo bordo
 * le va incontro piano invece di finire a scalino.
 *
 * «L'asfalto a destra fa una tacca»: una superstrada con la sua banchina che
 * diventa una strada di città (in OpenStreetMap cambia classe in un nodo), o
 * una carreggiata che perde la corsia di emergenza: il bordo dell'asfalto
 * rientrava di colpo, di un metro e più. Negli ultimi [RASTREMA_M] metri
 * (meno, su una via corta) il bordo più largo si stringe fino a quello della
 * via dopo; quello più stretto resta dov'è. Solo fra due capi soli in un
 * nodo, quasi dritti (la stessa strada), e per differenze da banchina (le
 * corsie che cambiano le mettono in fila i raccordi).
 *
 * Restituisce, per ogni via che si stringe, `{sinistra(s), destra(s),
 * tagli}`: di quanto si spostano i due bordi a [s] metri (a sinistra
 * positivo), e dove servono dei punti.
 */
export function rastrematureDeiCapi(strade, ricche, bordi, tocchi, chiave) {
  const morbido = (u) => {
    const t = Math.max(0, Math.min(1, u));
    return t * t * (3 - 2 * t);
  };
  const out = strade.map(() => null);
  strade.forEach((v, i) => {
    const r = ricche[i];
    const n = v.xyVia.length;
    if (r.length < 2 || n < 2) return;
    const L = r[r.length - 1][5];
    // Per capo: di quanto rientrano il bordo sinistro e il destro, e in quanti metri.
    const capi = [null, null];
    for (const fine of [0, 1]) {
      const nodo = v.xyVia[fine ? n - 1 : 0];
      const altri = (tocchi.get(chiave(nodo)) ?? []).filter((t) => t.i !== i);
      if (altri.length !== 1) continue;
      const o = altri[0];
      const ro = ricche[o.i];
      const no = strade[o.i].xyVia.length;
      if (ro.length < 2 || (o.k !== 0 && o.k !== no - 1)) continue;
      const mio = r[fine ? r.length - 1 : 0];
      const suo = ro[o.k ? ro.length - 1 : 0];
      const norma = (p) => {
        const l = Math.hypot(p[3], p[4]) || 1;
        return [p[3] / l, p[4] / l];
      };
      const [mx, my] = norma(mio);
      const [sx, sy] = norma(suo);
      // La stessa strada: quasi dritta (le normali lungo la stessa linea).
      const cos = mx * sx + my * sy;
      if (Math.abs(cos) < 0.94) continue;
      // I bordi dell'altra visti da questa: il suo mezzo di lato, e girata se va al contrario.
      const diLato = (suo[0] - mio[0]) * mx + (suo[1] - mio[1]) * my;
      const [bs, bd] = bordi[o.i];
      const suoi = cos > 0 ? [diLato + bs, diLato + bd] : [diLato - bd, diLato - bs];
      const [ms, md] = bordi[i];
      // Solo dove l'altra è più stretta, e di poco (una banchina, non una corsia).
      const ds = suoi[0] < ms - 0.15 && ms - suoi[0] < 2.6 ? suoi[0] - ms : 0;
      const dd = suoi[1] > md + 0.15 && suoi[1] - md < 2.6 ? suoi[1] - md : 0;
      if (ds || dd) capi[fine] = { ds, dd, t: Math.min(RASTREMA_M, L * 0.45) };
    }
    if (!capi[0] && !capi[1]) return;
    const peso = (sv, fine) => (capi[fine] ? 1 - morbido((fine ? L - sv : sv) / capi[fine].t) : 0);
    const tagli = [];
    for (const fine of [0, 1]) {
      if (!capi[fine]) continue;
      for (const u of [0.2, 0.4, 0.6, 0.8, 1]) tagli.push(fine ? L - capi[fine].t * u : capi[fine].t * u);
    }
    out[i] = {
      sinistra: (sv) => (capi[0]?.ds ?? 0) * peso(sv, 0) + (capi[1]?.ds ?? 0) * peso(sv, 1),
      destra: (sv) => (capi[0]?.dd ?? 0) * peso(sv, 0) + (capi[1]?.dd ?? 0) * peso(sv, 1),
      tagli,
    };
  });
  return out;
}

/**
 * Di quanto, al più, si gira il taglio in capo a una via per allinearlo a
 * quella in cui continua (il coseno: trenta gradi). Di più è un incrocio; e
 * girato tanto il capo si stringerebbe troppo.
 */
const ALLINEA_COS = Math.cos((30 * Math.PI) / 180);

/**
 * I capi delle vie tagliati come la via in cui continuano.
 *
 * «La carreggiata con rientranze e gradini»: ogni striscia d'asfalto finisce
 * di traverso alla *sua* via. Dove una rampa entra di sbieco in una
 * carreggiata, o una via continua in un'altra piegando, i due tagli non
 * combaciano: da una parte lo spigolo della rampa sporge dal bordo della
 * carreggiata (un dente), dall'altra resta una tacca. Qui il capo di una via
 * si taglia invece lungo la stessa linea della via in cui continua:
 *  - due capi soli in un nodo (la stessa strada, spezzata lì): tutti e due
 *    lungo la bisettrice, come una cornice;
 *  - un ramo a senso unico che entra in una carreggiata o ne esce (l'altra
 *    via lì continua da sola, o ci passa): il ramo come la carreggiata.
 * Cambia le normali ai capi delle linee ricche [ricche] (i bordi, le righe e
 * i marciapiedi le seguono). [tocchi]: chi tocca ogni nodo (`{i, k}` per
 * [chiave] del punto di `xyVia`).
 */
export function allineaICapi(strade, ricche, tocchi, chiave) {
  // La normale della linea ricca [r] nel punto più vicino a [q].
  const normaleA = (r, q) => {
    let meglio = r[0];
    let d = Infinity;
    for (const p of r) {
      const dd = Math.hypot(p[0] - q[0], p[1] - q[1]);
      if (dd < d) [d, meglio] = [dd, p];
    }
    const l = Math.hypot(meglio[3], meglio[4]) || 1;
    return [meglio[3] / l, meglio[4] / l];
  };
  const nuove = [];
  strade.forEach((v, i) => {
    const r = ricche[i];
    const n = v.xyVia.length;
    if (r.length < 2 || n < 2) return;
    for (const fine of [0, 1]) {
      const nodo = v.xyVia[fine ? n - 1 : 0];
      const altri = (tocchi.get(chiave(nodo)) ?? []).filter((t) => t.i !== i);
      if (!altri.length) continue;
      const mia = r[fine ? r.length - 1 : 0];
      const capoDi = (t) => t.k === 0 || t.k === strade[t.i].xyVia.length - 1;
      let nuova = null;
      if (altri.length === 1 && capoDi(altri[0])) {
        // La stessa strada che continua: la bisettrice delle due normali (girata come la mia).
        const o = normaleA(ricche[altri[0].i], nodo);
        const verso = o[0] * mia[3] + o[1] * mia[4] >= 0 ? 1 : -1;
        nuova = [mia[3] + o[0] * verso, mia[4] + o[1] * verso];
      } else if (v.senso) {
        // Un ramo: la via a senso unico che da qui continua da sola (o che qui passa).
        const dopo = altri.filter((t) => strade[t.i].senso && (fine ? t.k < strade[t.i].xyVia.length - 1 : t.k > 0));
        if (dopo.length === 1) nuova = normaleA(ricche[dopo[0].i], nodo);
      }
      if (!nuova) continue;
      const l = Math.hypot(nuova[0], nuova[1]);
      if (l < 1e-6) continue;
      const cos = (nuova[0] * mia[3] + nuova[1] * mia[4]) / l;
      if (cos < ALLINEA_COS) continue;
      nuove.push([mia, nuova[0] / l, nuova[1] / l]);
    }
  });
  // Tutte insieme: ognuna guarda le altre com'erano.
  for (const [p, nx, ny] of nuove) {
    p[3] = nx;
    p[4] = ny;
  }
}

/**
 * La segnaletica di una tessera. [strade]: le vie (vedi `normalizza` in
 * corsie.js) con `xy` (la geometria da disegnare, metri della tessera),
 * `xyVia` (quella vera, per i nodi) e `h` (la quota di ogni punto di `xy`);
 * [nodi]: con `xy`. [sopra(hw)]: quanto sopra la quota sta l'asfalto;
 * [meta]: mezzo lato della tessera. Restituisce le tre geometrie.
 */
export function costruisciSegnaletica({ strade, nodi = [], sopra = () => 0.2, meta, rotonde = [] }) {
  const asfalto = new Costruttore();
  const vernice = new Costruttore();
  const segnali = new Costruttore({ colori: true });
  // Coi colori nei vertici (le facce, gli scivoli) e le uv (le lastre, il cordolo).
  const marciapiedi = new Costruttore({ uv: true, colori: true });
  const dentro = (x, y) => x >= -meta && x <= meta && y >= -meta && y <= meta;
  const righe = new Map();

  // I nodi delle vie: chi tocca chi (sulla geometria vera), e dove.
  const chiave = (q) => Math.round(q[0] * 2) + ',' + Math.round(q[1] * 2);
  const tocchi = new Map();
  strade.forEach((v, i) => {
    v.sVia = progressive(v.xyVia);
    v.xyVia.forEach((q, k) => {
      const kk = chiave(q);
      if (!tocchi.has(kk)) tocchi.set(kk, []);
      tocchi.get(kk).push({ i, k });
    });
  });
  const larghezzaTotale = (v) => larghezzaCorsie(v) + v.margini[0] + v.margini[1];
  /* Le rotonde ([rotonde]: `{x, y, r}`, il centro e il raggio dell'anello):
   * quali vie sono il loro anello, e fin dove arriva il suo asfalto.
   *
   * «E' sbagliato proprio il disegno della rotonda: vedi le strade che ci
   * finiscono dentro». Le vie che arrivano finiscono sulla linea di mezzo
   * dell'anello; in una rotonda piccola i loro bordi, la mezzeria e i
   * marciapiedi passavano sulla carreggiata dell'anello e fino all'isola.
   * Dentro il cerchio dell'anello, di quelle vie non si disegna ne' riga ne'
   * marciapiede: c'e' l'anello. */
  const anelli = rotonde.map((c) => {
    const suoi = new Set();
    let fuori = c.r + 2;
    let dentro = Infinity;
    let z = null;
    strade.forEach((v, i) => {
      if (v.xyVia.length < 3) return;
      if (!v.xyVia.every((q) => Math.abs(Math.hypot(q[0] - c.x, q[1] - c.y) - c.r) < 2.5)) return;
      suoi.add(i);
      fuori = Math.max(fuori, c.r + larghezzaTotale(v) / 2);
      dentro = Math.min(dentro, c.r - larghezzaTotale(v) / 2);
      const h = (v.h ?? []).filter(Number.isFinite);
      if (h.length) z = h.reduce((a, b) => a + b, 0) / h.length + sopra(v.hw);
    });
    return { ...c, suoi, fuori, dentro, z };
  });
  const nellaRotonda = (x, y, i) => anelli.some((c) => !c.suoi.has(i) && Math.hypot(x - c.x, y - c.y) < c.fuori - 0.2);
  // I rami di un nodo: per ogni via che lo tocca, verso dove va (a una decina di metri).
  const ramiDi = (kk) => {
    const out = [];
    for (const { i, k } of tocchi.get(kk) ?? []) {
      const v = strade[i];
      const p = v.xyVia;
      for (const passo of [1, -1]) {
        if (k + passo < 0 || k + passo >= p.length) continue;
        let j = k;
        let d = 0;
        while (j + passo >= 0 && j + passo < p.length && d < 10) {
          d += Math.hypot(p[j + passo][0] - p[j][0], p[j + passo][1] - p[j][1]);
          j += passo;
        }
        const dx = p[j][0] - p[k][0];
        const dy = p[j][1] - p[k][1];
        const l = Math.hypot(dx, dy) || 1;
        out.push({ i, k, passo, dx: dx / l, dy: dy / l, mezza: larghezzaTotale(v) / 2 });
      }
    }
    return out;
  };

  // Le linee da disegnare e l'asfalto di tutte (per dove il marciapiede non va).
  const ricche = strade.map((v) => lineaRicca(v.xy, v.h));
  allineaICapi(strade, ricche, tocchi, chiave);
  const bordiAsfalto = strade.map((v) => {
    const B = bordiCorsie(v);
    return [B.sinistra + v.margini[0], B.destra - v.margini[1]];
  });
  const rastremature = rastrematureDeiCapi(strade, ricche, bordiAsfalto, tocchi, chiave);
  let copertura = null;
  // I pezzi a senso unico corti attaccati ad altre vie ai due capi: dentro l'incrocio.
  const dentroLIncrocio = (v, i) => {
    if (!v.senso || v.sVia[v.sVia.length - 1] > PEZZO_INCROCIO_M) return false;
    const attaccato = (q) => (tocchi.get(chiave(q)) ?? []).some((t) => t.i !== i);
    return attaccato(v.xyVia[0]) && attaccato(v.xyVia[v.xyVia.length - 1]);
  };
  const conMarciapiede = (v, i) => !!MARCIAPIEDI[v.hw] && !v.galleria && !dentroLIncrocio(v, i);

  // ── Gli angoli tondi dei marciapiedi, prima di tutto ────────────────
  // Per ogni nodo, fra due rami vicini (in senso antiorario) di due vie col
  // marciapiede: dove finiscono i due marciapiedi dritti (i loro buchi) e
  // l'arco; si disegnano alla fine, se i due dritti ci arrivano davvero.
  const angoli = [];
  const buchiAngoli = strade.map(() => ({ 1: [], [-1]: [] }));
  const conAngolo = new Set();
  if (strade.some(conMarciapiede)) {
    copertura = asfaltoDelleVie(strade, ricche, bordiAsfalto);
    for (const [kk, elenco] of tocchi) {
      if (new Set(elenco.map((t) => t.i)).size < 2) continue;
      // Tutti i rami, anche quelli senza marciapiede: fra due vicini e basta.
      const rami = ramiDi(kk)
        .map((x) => ({ ...x, ang: Math.atan2(x.dy, x.dx) }))
        .sort((p, q) => p.ang - q.ang);
      for (let j = 0; j < rami.length && rami.length >= 2; j++) {
        const A = rami[j];
        const Bv = rami[(j + 1) % rami.length];
        if (A.i === Bv.i || !conMarciapiede(strade[A.i], A.i) || !conMarciapiede(strade[Bv.i], Bv.i)) continue;
        const ang = angoloMarciapiede(A, Bv, strade, ricche, bordiAsfalto, sopra, copertura);
        if (!ang) continue;
        angoli.push(ang);
        for (const x of [ang.a, ang.b]) {
          buchiAngoli[x.i][x.lato].push(x.passo > 0 ? [x.s, x.sT] : [x.sT, x.s]);
          conAngolo.add(`${x.i}:${x.k}:${x.passo}:${x.lato}`);
        }
      }
    }
  }
  // I marciapiedi dritti (si disegnano alla fine, con gli scivoli) e i
  // pezzi di ogni lato di ogni via (`i:lato`), per gli angoli.
  const daFare = [];
  const pezziMarciapiede = new Map();
  const bocche = [];

  strade.forEach((v, i) => {
    const r = ricche[i];
    const L = r[r.length - 1][5];
    const Lvia = v.sVia[v.sVia.length - 1] || L;
    const daVia = (s) => (s * L) / Lvia;
    const z0 = sopraAsfalto(v, sopra);
    const B = bordiCorsie(v);
    const [mS, mD] = v.margini;

    // ── I buchi delle righe agli incroci ──────────────────────────────
    const buchiTutte = [];
    const buchiLato = { sinistra: [], destra: [] };
    // Quelli dei marciapiedi: dove arriva un'altra strada (col suo
    // marciapiede: un poco di più), salvo dove c'è l'angolo tondo, che ha i suoi.
    const buchiMarciapiede = { 1: [...buchiAngoli[i][1]], [-1]: [...buchiAngoli[i][-1]] };
    v.xyVia.forEach((q, k) => {
      const rami = ramiDi(chiave(q));
      const vie = new Set(rami.map((x) => x.i));
      if (vie.size < 2) return;
      // Dove le carreggiate a senso unico si dividono o si uniscono (uno
      // svincolo) le righe continuano: i raccordi le mettono già in fila.
      if (rami.every((x) => strade[x.i].senso)) return;
      const s = daVia(v.sVia[k]);
      const capo = k === 0 || k === v.xyVia.length - 1;
      const suoi = rami.filter((x) => x.i === i);
      const altri = rami.filter((x) => x.i !== i);
      // Una via che continua (un capo che tocca un capo, quasi dritti, con
      // le stesse corsie) non è un incrocio: le righe vanno avanti.
      if (rami.length <= 2 && capo) {
        const o = altri[0];
        const mio = suoi[0];
        if (o && mio && mio.dx * o.dx + mio.dy * o.dy < -0.85) return;
      }
      const tx = suoi.find((x) => x.passo === 1)?.dx ?? -(suoi[0]?.dx ?? 0);
      const ty = suoi.find((x) => x.passo === 1)?.dy ?? -(suoi[0]?.dy ?? 0);
      if (capo) {
        const R = Math.max(...altri.map((x) => x.mezza)) + 0.5;
        buchiTutte.push([s - R, s + R]);
      }
      for (const o of altri) {
        // Il ramo che va come questa via (la stessa strada dall'altra parte) non apre il bordo.
        const cos = o.dx * tx + o.dy * ty;
        if (Math.abs(cos) > 0.9) continue;
        const sen = tx * o.dy - ty * o.dx;
        const r2 = Math.min(18, o.mezza / Math.max(0.35, Math.abs(sen)) + 0.8);
        buchiLato[sen > 0 ? 'sinistra' : 'destra'].push([s - r2, s + r2]);
        const lato = sen > 0 ? 1 : -1;
        if (!conAngolo.has(`${i}:${k}:-1:${lato}`)) buchiMarciapiede[lato].push([s - r2 - 2.5, s]);
        if (!conAngolo.has(`${i}:${k}:1:${lato}`)) buchiMarciapiede[lato].push([s, s + r2 + 2.5]);
      }
    });

    // ── L'asfalto ──────────────────────────────────────────────────────
    // Coi punti che servono (dopo i raccordi uno ogni quattro metri anche
    // sulle vie dritte): i triangoli risparmiati qui e nelle righe pagano
    // gli angoli tondi dei marciapiedi.
    const stretta = rastremature[i];
    if (stretta) {
      // Con dei punti lungo la rastrematura (su un rettilineo la via ne ha due soli).
      const { pz, fissi } = pezzoConTagli(r, 0, L, stretta.tagli);
      striscia(asfalto, semplificaPezzo(pz, B.sinistra + mS, B.destra - mD, SEMPLIFICA_M * 0.75, fissi), (sv) => B.sinistra + mS + stretta.sinistra(sv), (sv) => B.destra - mD + stretta.destra(sv), z0, meta);
    } else striscia(asfalto, semplificaPezzo(r, B.sinistra + mS, B.destra - mD, SEMPLIFICA_M * 0.75), B.sinistra + mS, B.destra - mD, z0, meta);
    // I capi tondi: dove due vie si incontrano di sbieco non resta un dente.
    for (const fine of [0, 1]) {
      const p = r[fine ? r.length - 1 : 0];
      if (!dentro(p[0], p[1])) continue;
      const nl = Math.hypot(p[3], p[4]) || 1;
      const nx = p[3] / nl;
      const ny = p[4] / nl;
      // (Coi bordi com'è l'asfalto lì: rastremato, se continua in una via più stretta.)
      const bordoS = B.sinistra + mS + (stretta?.sinistra(p[5]) ?? 0);
      const bordoD = B.destra - mD + (stretta?.destra(p[5]) ?? 0);
      const oc = (bordoS + bordoD) / 2;
      const rad = (bordoS - bordoD) / 2;
      const cx = p[0] + nx * oc;
      const cy = p[1] + ny * oc;
      // Verso fuori: avanti alla fine, indietro all'inizio.
      const fx = fine ? ny : -ny;
      const fy = fine ? -nx : nx;
      const N = 6;
      // Dove il capo sta tutto sull'asfalto di un'altra via (la via che
      // continua, quella in cui sbocca) non serve: triangoli risparmiati.
      //
      // Sulla sua striscia vera, però. «Righe sottili di traverso sulla
      // carreggiata»: dove una via continua in un'altra piegando appena, fra
      // le due strisce resta uno spicchio aperto dalla parte di fuori della
      // piega, e il capo tondo è lì per chiuderlo. Ma per sapere se il capo
      // serviva si guardava l'asfalto dell'altra via col suo mezzo disco in
      // fondo, cioè proprio col capo tondo che anche lei, per la stessa
      // ragione, non faceva: nessuna delle due chiudeva lo spicchio, e dalla
      // fessura si vedeva quello che c'è sotto (il cemento della spalla del
      // ponte, una lama chiara).
      copertura ??= asfaltoDelleVie(strade, ricche, bordiAsfalto);
      let coperto = !!copertura.sullaStriscia(cx, cy, p[2], i);
      for (let j = 0; j <= N && coperto; j++) {
        const a = -Math.PI / 2 + (Math.PI * j) / N;
        const ux = Math.cos(a) * fx - Math.sin(a) * fy;
        const uy = Math.cos(a) * fy + Math.sin(a) * fx;
        coperto = !!copertura.sullaStriscia(cx + ux * (rad - 0.15), cy + uy * (rad - 0.15), p[2], i);
      }
      if (coperto) continue;
      /* Dove la via finisce su un'altra che passa (un incrocio a T, o più
       * vie), il capo tondo non va oltre l'asfalto delle altre: una via larga
       * che sbocca su una stretta lo faceva sporgere dall'altra parte, un
       * mezzo disco scuro sul marciapiede di fronte. Fra due vie che si
       * continuano (il dente di una piega) resta intero. */
      const nodo = fine ? v.xyVia[v.xyVia.length - 1] : v.xyVia[0];
      const altre = (tocchi.get(chiave(nodo)) ?? []).filter((t) => t.i !== i);
      const incrocio = altre.length >= 2 || altre.some((t) => t.k > 0 && t.k < strade[t.i].xyVia.length - 1);
      const centro = asfalto.v(cx, cy, p[2] + z0 - 0.004, 0, 0, 1);
      const giro = [];
      for (let j = 0; j <= N; j++) {
        const a = -Math.PI / 2 + (Math.PI * j) / N;
        // (fx, fy) avanti, (-fy, fx) a sinistra di quel verso.
        const ux = Math.cos(a) * fx - Math.sin(a) * fy;
        const uy = Math.cos(a) * fy + Math.sin(a) * fx;
        let rr = rad;
        if (incrocio) {
          rr = 0;
          for (const f of [1, 0.75, 0.5, 0.25]) {
            if (copertura.sotto(cx + ux * rad * f, cy + uy * rad * f, p[2], i, 0)) {
              rr = rad * f;
              break;
            }
          }
        }
        /* Dove il capo finisce sopra un'altra via le sta appena sotto, alla
         * sua quota: in piano alla quota del capo, il mezzo disco di un ponte
         * copriva le righe della rampa che da lì scende (e più in là stava
         * sospeso un palmo sopra il suo asfalto). */
        let z = p[2] + z0 - 0.004;
        const sotto = copertura.sullaStriscia(cx + ux * rr, cy + uy * rr, p[2], i);
        if (sotto) z = Math.min(z, sotto.quota + sopraAsfalto(strade[sotto.i], sopra) - 0.004);
        giro.push(asfalto.v(cx + ux * rr, cy + uy * rr, z, 0, 0, 1));
      }
      for (let j = 1; j <= N; j++) {
        // Girati in su (verso antiorario visto dall'alto).
        const a = asfalto.p;
        const i0 = centro;
        const i1 = giro[j - 1];
        const i2 = giro[j];
        const cr = (a[3 * i1] - a[3 * i0]) * (a[3 * i2 + 1] - a[3 * i0 + 1]) - (a[3 * i1 + 1] - a[3 * i0 + 1]) * (a[3 * i2] - a[3 * i0]);
        if (Math.abs(cr) < 1e-4) continue;
        if (cr >= 0) asfalto.tri(i0, i1, i2);
        else asfalto.tri(i0, i2, i1);
      }
    }
    if (v.galleria) return;

    // ── I marciapiedi, col cordolo verso la strada ─────────────────────
    // Aperti dove arriva un'altra strada; si disegnano alla fine.
    const largoM = MARCIAPIEDI[v.hw];
    if (largoM && !dentroLIncrocio(v, i)) {
      // Fin oltre la tessera: un angolo tondo dentro può finire su un dritto di fuori.
      const fin = meta + largoM + ANGOLO.lungo + 4;
      for (const [lato, bordo] of [
        [1, B.sinistra + mS],
        [-1, B.destra - mD],
      ]) {
        const no = senzaMarciapiede(r, i, lato, bordo, largoM, copertura, (x, y) => Math.abs(x) <= fin && Math.abs(y) <= fin);
        // Nella rotonda il marciapiede dei rami non entra (vedi [nellaRotonda]).
        const inRotonda = [];
        if (anelli.length) {
          for (let s = 0; s <= L; s += 1) {
            const P = puntoA(r, s, bordo + (lato * largoM) / 2);
            if (nellaRotonda(P[0], P[1], i)) inRotonda.push([s - 0.8, s + 0.8]);
          }
        }
        const pezzi = togli([[0, L]], [...buchiTutte, ...buchiMarciapiede[lato], ...no, ...inRotonda]).filter(([a, b]) => b - a >= 1.5);
        pezziMarciapiede.set(`${i}:${lato}`, pezzi);
        for (const [a, b] of pezzi) daFare.push({ i, lato, bordo, largo: largoM, z0, a, b });
      }
    }

    // ── Le righe ───────────────────────────────────────────────────────
    const dz = z0 + 0.02;
    // Dove la riga starebbe sull'asfalto di un'altra via (alla stessa
    // quota, più di sessanta centimetri dentro): dove due carreggiate si
    // dividono e i raccordi non le mettono del tutto in fila, il bordo di
    // una passava di traverso sulle corsie dell'altra.
    copertura ??= asfaltoDelleVie(strade, ricche, bordiAsfalto);
    const sullAltra = (o) => {
      const out = [];
      for (let s = 0; s <= L; s += 1) {
        const P = puntoA(r, s, o);
        if (copertura.sotto(P[0], P[1], P[2], i, -0.6) || nellaRotonda(P[0], P[1], i)) out.push([s - 0.6, s + 0.6]);
      }
      return out;
    };
    const riga = (o, w, buchi, tipo = 'continua', pieno = 3, vuoto = 3) => {
      buchi = [...buchi, ...sullAltra(o)];
      const pezzi = tipo === 'continua' ? togli([[0, L]], buchi) : v.stimata ? trattiniAdattati(L, pieno, vuoto, buchi) : trattini(L, pieno, vuoto, buchi);
      for (const [a, b] of pezzi) {
        if (b - a < 0.2) continue;
        striscia(vernice, semplificaPezzo(pezzoFra(r, a, b), o + w / 2, o - w / 2, SEMPLIFICA_M * 0.75), o + w / 2, o - w / 2, dz, meta);
      }
      righe.set(tipo, (righe.get(tipo) ?? 0) + pezzi.length);
    };
    const g = grande(v.hw) && !rampa(v.hw);
    const [pieno, vuoto] = g ? [4.5, 7.5] : [3, 3];
    const wBordo = g ? RIGHE.bordoGrande : RIGHE.bordo;
    const wCorsia = g ? RIGHE.corsiaGrande : RIGHE.corsia;
    // I bordi: continui, aperti dove arriva un'altra strada.
    riga(B.sinistra - wBordo / 2, wBordo, [...buchiTutte, ...buchiLato.sinistra]);
    riga(B.destra + wBordo / 2, wBordo, [...buchiTutte, ...buchiLato.destra]);
    // La mezzeria fra i due sensi: continua, doppia sulle strade larghe.
    if (v.avanti && v.indietro && !v.condivisa) {
      if (v.avanti + v.indietro >= 4) {
        riga(B.mezzeria + RIGHE.doppia, RIGHE.doppia, buchiTutte);
        riga(B.mezzeria - RIGHE.doppia, RIGHE.doppia, buchiTutte);
      } else riga(B.mezzeria, RIGHE.mezzeria, buchiTutte);
    }
    // Fra le corsie dello stesso senso: tratteggiate; continue dove non si
    // cambia corsia (`change:lanes`); larghe e fitte prima di un'uscita o
    // dopo un'entrata (la corsia di decelerazione o di accelerazione).
    const sinistraAvanti = v.indietro ? B.mezzeria : B.sinistra;
    for (let c = 1; c < v.avanti; c++) {
      const o = sinistraAvanti - c * v.lw;
      const ultima = c === v.avanti - 1;
      const frecceUltima = v.frecce?.[v.avanti - 1] ?? [];
      const esce = ultima && g && frecceUltima.some((f) => f.includes('right'));
      const entra = ultima && g && frecceUltima.some((f) => f === 'merge_to_left');
      const ch = v.cambi;
      const vietato = ch && (ch[c - 1] === 'no' || ch[c - 1] === 'not_right' || ch[c] === 'no' || ch[c] === 'not_left');
      if (vietato) riga(o, wCorsia, buchiTutte);
      else if (esce || entra) riga(o, RIGHE.decelerazione, buchiTutte, 'tratteggiata', 1.2, 1.2);
      else riga(o, wCorsia, buchiTutte, 'tratteggiata', pieno, vuoto);
    }
    for (let c = 1; c < v.indietro; c++) riga(B.mezzeria + c * v.lw, wCorsia, buchiTutte, 'tratteggiata', pieno, vuoto);

    // ── Le frecce, prima della fine della via ──────────────────────────
    const lungaF = g ? 9 : rampa(v.hw) ? 7.5 : 6;
    const distanze = g ? [45, 130] : [22, 55];
    const freccia = (dirs, s, o, avanti) => {
      if (s < lungaF / 2 + 2 || s > L - 2) return;
      const [x, y, h, tx, ty] = puntoA(r, s, o);
      if (!dentro(x, y)) return;
      const verso = avanti ? 1 : -1;
      // La freccia parte da [s] e va verso la fine (o l'inizio, al contrario).
      triangoliPiani(vernice, formaFreccia(dirs, lungaF, Math.min(1.8, v.lw * 0.5)), x, y, h + dz, tx * verso, ty * verso);
    };
    for (const [frecce, avanti] of [
      [v.frecce, true],
      [v.frecceIndietro, false],
    ]) {
      if (!frecce) continue;
      for (const d of distanze) {
        if (d + lungaF > L - 4 && d !== distanze[0]) continue;
        const dd = Math.min(d, Math.max(4, L - lungaF - 6));
        frecce.forEach((dirs, c) => {
          if (!dirs.length) return;
          const o = centroCorsia(v, c, avanti) * (avanti ? 1 : -1);
          if (avanti) freccia(dirs, L - dd - lungaF, o, true);
          else freccia(dirs, dd + lungaF, o, false);
        });
      }
    }
  });

  // ── La zebratura dove una carreggiata si divide ─────────────────────
  // Fra il bordo destro del ramo di sinistra e quello sinistro del ramo di
  // destra (una rampa d'uscita), finché i due sono a meno di [ZEBRATURA_LARGA_M]:
  // strisce di sbieco, come sulle autostrade italiane.
  //
  // Solo nel triangolo, dove i due rami si allargano. «Ancora tutto
  // sbagliato»: a uno svincolo due rampe corrono affiancate a quattro metri
  // per centinaia di metri (lì c'è un cordolo, o il guardrail), e la
  // zebratura andava avanti per tutti e trecento, una scala bianca lunga fra
  // le due strade. Dove la distanza smette di crescere, il triangolo è finito.
  for (const elenco of tocchi.values()) {
    const finiscono = elenco.filter(({ i, k }) => strade[i].senso && k === strade[i].xyVia.length - 1);
    const partono = elenco.filter(({ i, k }) => strade[i].senso && k === 0);
    if (finiscono.length !== 1 || partono.length !== 2) continue;
    const a = strade[finiscono[0].i];
    const pa = a.xyVia;
    const da = Math.atan2(pa[pa.length - 1][1] - pa[Math.max(0, pa.length - 4)][1], pa[pa.length - 1][0] - pa[Math.max(0, pa.length - 4)][0]);
    // La direzione di un ramo a venti metri dal nodo, rispetto a chi arriva.
    const verso20 = (v) => {
      const p = v.xyVia;
      let k = 1;
      let d = 0;
      while (k < p.length - 1) {
        d += Math.hypot(p[k][0] - p[k - 1][0], p[k][1] - p[k - 1][1]);
        if (d >= 20) break;
        k++;
      }
      const t = Math.atan2(p[k][1] - p[0][1], p[k][0] - p[0][0]) - da;
      return Math.atan2(Math.sin(t), Math.cos(t));
    };
    const angolo = (v) => {
      const p = v.xyVia;
      const q = p[Math.min(p.length - 1, 3)];
      const t = Math.atan2(q[1] - p[0][1], q[0] - p[0][0]) - da;
      return Math.atan2(Math.sin(t), Math.cos(t));
    };
    const [sin, des] = partono.map(({ i }) => strade[i]).sort((p, q) => angolo(q) - angolo(p));
    /* Solo dove i due rami partono quasi paralleli (una rampa che esce):
     * dove si aprono subito di molto (una strada che finisce su un'altra, un
     * ramo che gira a uncino) fra loro non c'è una zebratura ma un'isola, e
     * le strisce passavano sopra l'altro ramo fino al prato. */
    if (Math.abs(verso20(sin) - verso20(des)) > ZEBRATURA_APERTA) continue;
    const rS = lineaRicca(sin.xy, sin.h);
    const rD = lineaRicca(des.xy, des.h);
    const LS = rS[rS.length - 1][5];
    const LD = rD[rD.length - 1][5];
    const bS = bordiCorsie(sin).destra;
    const bD = bordiCorsie(des).sinistra;
    // Il bordo di destra del ramo di sinistra, un punto ogni metro.
    const bordoS = [];
    for (let s = 0; s <= Math.min(LS, 300); s += 1) bordoS.push(puntoA(rS, s, bS));
    const dz = sopraAsfalto(des, sopra) + 0.02;
    // Lo spazio fra i due rami, col segno: a destra del bordo del ramo di
    // sinistra. Vicino alla punta i due rami si sovrappongono ancora (i bordi
    // delle corsie si incrociano): lì, prima, le strisce andavano di traverso
    // sulle corsie («righe a scala in mezzo alla strada»), a ogni divisione,
    // e finivano proprio dove il triangolo cominciava.
    let gPrima = -Infinity;
    let aperto = null;
    // Le coppie di bordi del triangolo, da dove si apre: `{P, Q, g, s}`.
    const coppie = [];
    for (let s = 3; s < Math.min(LD, ZEBRATURA_AL_PIU_M); s += 2.5) {
      const P = puntoA(rD, s, bD);
      let Q = null;
      let d = Infinity;
      for (const q of bordoS) {
        const dd = Math.hypot(q[0] - P[0], q[1] - P[1]);
        if (dd < d) {
          d = dd;
          Q = q;
        }
      }
      const [tx, ty] = [P[3], P[4]];
      const g = (P[0] - Q[0]) * ty - (P[1] - Q[1]) * tx;
      if (aperto === null) {
        if (g < 0.8) {
          if (s > 60) break;
          continue;
        }
        aperto = s;
      }
      /* Oltre i quattro metri e mezzo fra i due rami c'è il cordolo
       * dell'isola, non più la vernice: le strisce (e il loro asfalto) si
       * fermano. A sette metri finivano sull'isola, su un pezzo d'asfalto
       * che non toccava l'altro ramo. */
      if (g > ZEBRATURA_LARGA_M) break;
      // Non si allargano più (paralleli, o di nuovo vicini): fine del triangolo.
      if (s - aperto > 15 && g < gPrima + 0.1) break;
      gPrima = Math.max(gPrima, g);
      // Dove un ramo sale e l'altro no, il triangolo è finito (niente strisce sospese).
      if (Math.abs(P[2] - Q[2]) > 0.4) break;
      coppie.push({ P, Q, g, s });
    }
    /* La forma della zebratura.
     *
     * «Ventagli di zebrature»: erano poche strisce lunghe, una ogni cinque
     * metri, tirate dal bordo della rampa verso l'altro ramo senza arrivarci
     * e senza niente attorno: dove l'altro ramo entra subito in una
     * carreggiata larga, sbarre bianche sparse su un mare d'asfalto. Come
     * sulla strada: il cuneo chiuso dalle due righe di bordo (quella del ramo
     * di sinistra spesso non c'è più: sta sull'asfalto della carreggiata in
     * cui entra, vedi `sullAltra`), e dentro le strisce di sbieco, fitte, da
     * una riga all'altra e non oltre. */
    const zVernice = (c) => Math.max(c.P[2], c.Q[2]) + dz;
    // Il bordo di sinistra del cuneo a [sv] metri lungo il ramo di destra (fra una coppia e l'altra).
    const sinistraA = (sv) => {
      let k = 1;
      while (k < coppie.length - 1 && coppie[k].s < sv) k++;
      const [a, b] = [coppie[k - 1], coppie[k]];
      const t = Math.max(0, Math.min(1, (sv - a.s) / (b.s - a.s)));
      return [a.Q[0] + (b.Q[0] - a.Q[0]) * t, a.Q[1] + (b.Q[1] - a.Q[1]) * t];
    };
    for (let k = 1; k < coppie.length; k++) {
      const [prima, ora] = [coppie[k - 1], coppie[k]];
      const { P, Q, g } = ora;
      if (!dentro(P[0], P[1])) continue;
      /* L'asfalto fra i due bordi, sotto le strisce: la zebratura è dipinta
       * sull'asfalto. Prima le strisce del triangolo stavano sul prato fra
       * le due carreggiate (fuori dal loro asfalto anche di due metri). */
      const za = zVernice(prima) - 0.026;
      const zb = zVernice(ora) - 0.026;
      asfalto.quad([prima.Q[0], prima.Q[1], za], [prima.P[0], prima.P[1], za], [P[0], P[1], zb], [Q[0], Q[1], zb], [0, 0, 1]);
      // Le due righe che chiudono il cuneo, dove starebbero quelle di bordo dei due rami.
      const wB = RIGHE.bordo;
      for (const [x, verso] of [
        ['P', -1],
        ['Q', 1],
      ]) {
        const [a, b] = [prima[x], ora[x]];
        // A sinistra di chi va: (-ty, tx). Il ramo di destra sta a destra del suo bordo, quello di sinistra a sinistra.
        const A = [a[0] - a[4] * wB * verso, a[1] + a[3] * wB * verso];
        const Bq = [b[0] - b[4] * wB * verso, b[1] + b[3] * wB * verso];
        const z0 = zVernice(prima);
        const z1 = zVernice(ora);
        if (verso > 0) vernice.quad([a[0], a[1], z0], [b[0], b[1], z1], [Bq[0], Bq[1], z1], [A[0], A[1], z0], [0, 0, 1]);
        else vernice.quad([A[0], A[1], z0], [Bq[0], Bq[1], z1], [b[0], b[1], z1], [a[0], a[1], z0], [0, 0, 1]);
      }
      // La striscia: dal bordo della rampa indietro, di sbieco, fino all'altro bordo.
      const [tx, ty] = [P[3], P[4]];
      const [qx, qy] = sinistraA(ora.s - g);
      if (Math.hypot(qx - P[0], qy - P[1]) < 1.2) continue;
      const w = 0.25;
      const z = zVernice(ora);
      vernice.quad([P[0] - tx * w, P[1] - ty * w, z], [P[0] + tx * w, P[1] + ty * w, z], [qx + tx * w, qy + ty * w, z], [qx - tx * w, qy - ty * w, z], [0, 0, 1]);
    }
  }

  // ── Strisce, linee d'arresto, semafori ─────────────────────────────
  const fatti = new Set();
  // Dove sta ogni semaforo (la cima del primo palo dell'incrocio): sopra la
  // pagina ci mette il suo segno (vedi `aggiornaSegni` in principale.js).
  const semafori = [];
  for (const n of nodi) {
    let semaforoMesso = false;
    const kk = chiave(n.xy);
    const rami = ramiDi(kk);
    if (!rami.length) continue;
    const incrocio = new Set(rami.map((x) => x.i)).size >= 2 || rami.length >= 3;
    const tipo = n.highway;
    if (!['crossing', 'traffic_signals', 'stop', 'give_way'].includes(tipo)) continue;
    // Il verso del segnale sulla via, se lo dice (`direction`).
    const versoDetto = n['traffic_signals:direction'] ?? n.direction;
    for (const ramo of rami) {
      const v = strade[ramo.i];
      const r = lineaRicca(v.xy, v.h);
      const L = r[r.length - 1][5];
      const Lvia = v.sVia[v.sVia.length - 1] || L;
      const s = (v.sVia[ramo.k] * L) / Lvia;
      // Chi arriva al nodo lungo questo ramo: va al contrario del ramo.
      const arrivaAvanti = ramo.passo === -1;
      if (v.senso && !arrivaAvanti) continue;
      if (versoDetto === 'forward' && !arrivaAvanti) continue;
      if (versoDetto === 'backward' && arrivaAvanti) continue;
      const B = bordiCorsie(v);
      const dz = sopraAsfalto(v, sopra) + 0.022;
      // Per chi arriva, in fila: la linea d'arresto, le strisce, l'incrocio.
      // All'incrocio le strisce stanno prima delle altre strade (mai sopra);
      // su una via sola (le strisce a metà strada) sul nodo, e la linea
      // d'arresto un metro prima.
      const altri = rami.filter((x) => x.i !== ramo.i);
      const bordo = incrocio && altri.length ? Math.max(...altri.map((x) => x.mezza)) : null;
      const verso = arrivaAvanti ? -1 : 1;
      const lungoZ = 3;
      const dZebra = bordo === null ? 0 : bordo + 0.8 + lungoZ / 2;
      const dArresto = tipo === 'traffic_signals' ? dZebra + lungoZ / 2 + 1.2 : bordo === null ? 0.5 : bordo + 1.2;
      const sZebra = s + verso * dZebra;
      const sA = s + verso * dArresto;
      if (sA < 0.5 || sA > L - 0.5) continue;
      const chiaveFatta = `${ramo.i}:${Math.round(sA)}:${tipo}`;
      if (fatti.has(chiaveFatta)) continue;
      fatti.add(chiaveFatta);
      // Le strisce pedonali: su tutta la carreggiata, a strisce lungo la strada.
      const zebra = tipo === 'crossing' || tipo === 'traffic_signals';
      const chiaveZebra = `${ramo.i}:${Math.round(sZebra)}:zebra`;
      if (zebra && sZebra > lungoZ / 2 && sZebra < L - lungoZ / 2 && !fatti.has(chiaveZebra)) {
        fatti.add(chiaveZebra);
        // Lo scivolo dei marciapiedi ai due capi (anche se le strisce le fa la tessera accanto).
        const [ba, bb] = bordiAsfalto[ramo.i];
        const [bx, by, , btx, bty] = puntoA(r, sZebra, (ba + bb) / 2);
        bocche.push({ i: ramo.i, s: sZebra, x: bx, y: by, tx: btx, ty: bty, mezza: (ba - bb) / 2 });
        const pz = pezzoFra(r, sZebra - lungoZ / 2, sZebra + lungoZ / 2);
        const m = pz[Math.floor(pz.length / 2)];
        if (dentro(m[0], m[1])) {
          for (let o = B.destra + 0.4; o + 0.5 <= B.sinistra - 0.2; o += 1.0) striscia(vernice, pz, o + 0.5, o, dz, meta * 1.5);
        }
      }
      if (tipo === 'crossing') continue;
      // La linea d'arresto: sulle corsie di chi arriva, prima delle strisce.
      const [oa, ob] = arrivaAvanti ? [v.indietro ? B.mezzeria : B.sinistra, B.destra] : [B.sinistra, B.mezzeria];
      const pa = pezzoFra(r, sA - RIGHE.arresto / 2, sA + RIGHE.arresto / 2);
      const m = pa[0];
      if (!dentro(m[0], m[1])) continue;
      if (tipo === 'give_way') {
        // I denti di squalo: triangoli con la punta verso chi arriva.
        const [x0, y0, h0, tx, ty] = puntoA(r, sA, 0);
        const t2x = tx * -verso;
        const t2y = ty * -verso;
        for (let o = Math.min(oa, ob) + 0.3; o + 0.5 <= Math.max(oa, ob) - 0.1; o += 0.9) {
          const c = o + 0.25;
          const nlx = -ty;
          const nly = tx;
          const bx = x0 + nlx * c;
          const by = y0 + nly * c;
          vernice.triPunti(
            [bx + nlx * 0.25, by + nly * 0.25, h0 + dz],
            [bx - nlx * 0.25, by - nly * 0.25, h0 + dz],
            [bx + t2x * 0.6, by + t2y * 0.6, h0 + dz],
            [0, 0, 1],
          );
        }
      } else {
        striscia(vernice, pa, oa - 0.1, ob + 0.1, dz, meta * 1.5);
      }
      // Il semaforo: un palo a destra di chi arriva, con la lanterna verso di lui.
      if (tipo === 'traffic_signals') {
        const lato = arrivaAvanti ? B.destra - 1.0 : B.sinistra + 1.0;
        const [px, py, ph, tx, ty] = puntoA(r, sA, lato);
        // La lanterna guarda chi arriva.
        const fx = tx * verso;
        const fy = ty * verso;
        const { palo, raggioPalo, alta, fonda, sbraccio, sopraCorsie } = SEMAFORO;
        // Le corsie di chi arriva: quante, e dov'è il loro mezzo (dal palo, verso la strada).
        const corsieQui = arrivaAvanti ? v.avanti : v.indietro;
        const mezzoCorsie = (oa + ob) / 2;
        const largo = corsieQui >= 2 || (bordo ?? 0) * 2 > 15;
        // Verso la strada dal palo: la normale della via, dalla parte delle corsie.
        const nx = -ty * Math.sign(mezzoCorsie - lato);
        const ny = tx * Math.sign(mezzoCorsie - lato);
        const braccio = Math.abs(mezzoCorsie - lato);
        let cima = ph + palo + alta;
        if (largo) {
          // Il palo a sbraccio: alto, col braccio sopra le corsie e la lanterna appesa.
          cilindro(segnali, [px, py, ph], [px, py, ph + sbraccio], raggioPalo * 1.6, 8, ...PALO);
          const zb = ph + sbraccio - 0.25;
          cilindro(segnali, [px, py, zb], [px + nx * (braccio + 0.4), py + ny * (braccio + 0.4), zb], raggioPalo * 1.1, 6, ...PALO);
          const hx = px + nx * braccio;
          const hy = py + ny * braccio;
          lanterna(segnali, hx - fx * 0.15, hy - fy * 0.15, ph + sopraCorsie + alta / 2, fx, fy);
          // E la lanterna di ripetizione sul palo, all'altezza di sempre.
          lanterna(segnali, px + fx * (raggioPalo * 1.6), py + fy * (raggioPalo * 1.6), ph + palo + alta / 2, fx, fy);
          cima = ph + sbraccio + 0.3;
        } else {
          cilindro(segnali, [px, py, ph], [px, py, ph + palo + 0.2], raggioPalo, 8, ...PALO);
          lanterna(segnali, px - fx * (fonda / 2), py - fy * (fonda / 2), ph + palo + alta / 2, fx, fy);
        }
        const z1 = cima;
        if (!semaforoMesso && dentro(px, py)) {
          semafori.push(px, py, z1 + 0.3);
          semaforoMesso = true;
        }
      }
    }
  }
  // ── I marciapiedi: i dritti, con gli scivoli; poi gli angoli tondi ──
  const scivolo = scivoli(bocche);
  for (const { i, lato, bordo, largo, z0, a, b } of daFare) {
    const r = ricche[i];
    // I punti dove comincia e finisce lo scivolo, per le strisce di questa via.
    const tagli = [];
    for (const q of bocche) {
      if (q.i !== i) continue;
      const m = SCIVOLO.mezzo;
      tagli.push(q.s - m - SCIVOLO.rampa, q.s - m, q.s + m, q.s + m + SCIVOLO.rampa);
    }
    const { pz, fissi } = pezzoConTagli(r, a, b, tagli);
    const pochi = semplificaPezzo(pz, bordo, bordo + lato * largo, SEMPLIFICA_M, fissi);
    for (const pezzo of ritagliaLinea(pochi, -meta, -meta, meta, meta)) {
      if (pezzo.length < 2) continue;
      nastroMarciapiede(
        marciapiedi,
        pezzo.map((p) => {
          const nl = Math.hypot(p[3], p[4]) || 1;
          const nx = p[3] / nl;
          const ny = p[4] / nl;
          const x = p[0] + nx * bordo;
          const y = p[1] + ny * bordo;
          return { x, y, nx: nx * lato, ny: ny * lato, zb: p[2] + z0, w: largo, f: scivolo(x, y), s: p[5] };
        }),
      );
    }
  }
  for (const ang of angoli) {
    // Una tessera sola (quella dello spigolo), e solo se i due marciapiedi
    // dritti arrivano proprio dove comincia l'arco.
    if (!dentro(ang.C[0], ang.C[1])) continue;
    const arriva = (x) => (pezziMarciapiede.get(`${x.i}:${x.lato}`) ?? []).some(([p0, p1]) => Math.abs((x.passo > 0 ? p0 : p1) - x.sT) < 1e-6);
    if (!arriva(ang.a) || !arriva(ang.b)) continue;
    nastroMarciapiede(
      marciapiedi,
      ang.punti.map((q) => ({ ...q, f: scivolo(q.x, q.y) })),
    );
    // L'asfalto nell'angolo, fra lo spigolo dei due bordi e l'arco.
    const ic = asfalto.v(ang.riempi[0], ang.riempi[1], ang.zC - 0.004, 0, 0, 1);
    const giro = ang.punti.map((q) => asfalto.v(q.x, q.y, q.zb - 0.004, 0, 0, 1));
    for (let j = 1; j < giro.length; j++) triVerso(asfalto, ic, giro[j - 1], giro[j], [0, 0, 1]);
  }
  // L'isola delle rotonde: un'aiuola tonda e rialzata, col cordolo, dove
  // dentro l'anello si vedevano pezzi di prato e di terra.
  for (const c of anelli) {
    if (!c.suoi.size || c.z === null || !dentro(c.x, c.y)) continue;
    const raggio = Math.max(0.8, Math.min(c.dentro, c.r) - 0.15);
    const N = 36;
    const z0 = c.z - 0.02;
    const z1 = c.z + ISOLA_ALTA;
    const verde = [[132, 170, 98], [52, 72, 44]];
    const cordolo = [[214, 214, 218], [92, 96, 104]];
    const centro = segnali.v(c.x, c.y, z1, 0, 0, 1, 0, 0, verde[0], verde[1]);
    const giro = [];
    for (let j = 0; j <= N; j++) {
      const a = (2 * Math.PI * j) / N;
      giro.push([Math.cos(a), Math.sin(a)]);
    }
    for (let j = 1; j <= N; j++) {
      const [ax, ay] = giro[j - 1];
      const [bx, by] = giro[j];
      const A = segnali.v(c.x + ax * raggio, c.y + ay * raggio, z1, 0, 0, 1, 0, 0, verde[0], verde[1]);
      const B = segnali.v(c.x + bx * raggio, c.y + by * raggio, z1, 0, 0, 1, 0, 0, verde[0], verde[1]);
      segnali.tri(centro, A, B);
      // Il cordolo: la fascia di lato, verso fuori.
      const nx = (ax + bx) / 2;
      const ny = (ay + by) / 2;
      const a0 = segnali.v(c.x + ax * raggio, c.y + ay * raggio, z0, nx, ny, 0, 0, 0, cordolo[0], cordolo[1]);
      const b0 = segnali.v(c.x + bx * raggio, c.y + by * raggio, z0, nx, ny, 0, 0, 0, cordolo[0], cordolo[1]);
      const a1 = segnali.v(c.x + ax * raggio, c.y + ay * raggio, z1, nx, ny, 0, 0, 0, cordolo[0], cordolo[1]);
      const b1 = segnali.v(c.x + bx * raggio, c.y + by * raggio, z1, nx, ny, 0, 0, 0, cordolo[0], cordolo[1]);
      segnali.tri(a0, b0, b1);
      segnali.tri(a0, b1, a1);
    }
  }
  return { asfalto, vernice, segnali, marciapiedi, righe, semafori };
}
