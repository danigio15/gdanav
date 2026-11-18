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

/** Larghezze delle righe (m): un poco più larghe del codice, che da lontano non spariscano. */
export const RIGHE = { corsia: 0.18, corsiaGrande: 0.2, bordo: 0.2, bordoGrande: 0.25, mezzeria: 0.2, doppia: 0.16, decelerazione: 0.5, arresto: 0.5 };

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
  for (const pezzo of ritagliaLinea(r, -meta, -meta, meta, meta)) {
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

const PALO = [[70, 76, 86], [40, 44, 52]];
const LANTERNA = [[38, 42, 50], [22, 25, 30]];
const LUCI = [
  [[230, 48, 40], [255, 70, 60]],
  [[120, 100, 40], [90, 75, 30]],
  [[40, 90, 60], [30, 70, 45]],
];

/**
 * La segnaletica di una tessera. [strade]: le vie (vedi `normalizza` in
 * corsie.js) con `xy` (la geometria da disegnare, metri della tessera),
 * `xyVia` (quella vera, per i nodi) e `h` (la quota di ogni punto di `xy`);
 * [nodi]: con `xy`. [sopra(hw)]: quanto sopra la quota sta l'asfalto;
 * [meta]: mezzo lato della tessera. Restituisce le tre geometrie.
 */
export function costruisciSegnaletica({ strade, nodi = [], sopra = () => 0.2, meta }) {
  const asfalto = new Costruttore();
  const vernice = new Costruttore();
  const segnali = new Costruttore({ colori: true });
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

  strade.forEach((v, i) => {
    const r = lineaRicca(v.xy, v.h);
    const L = r[r.length - 1][5];
    const Lvia = v.sVia[v.sVia.length - 1] || L;
    const daVia = (s) => (s * L) / Lvia;
    const z0 = sopra(v.hw);
    const B = bordiCorsie(v);
    const [mS, mD] = v.margini;

    // ── I buchi delle righe agli incroci ──────────────────────────────
    const buchiTutte = [];
    const buchiLato = { sinistra: [], destra: [] };
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
      }
    });

    // ── L'asfalto ──────────────────────────────────────────────────────
    striscia(asfalto, r, B.sinistra + mS, B.destra - mD, z0, meta);
    // I capi tondi: dove due vie si incontrano di sbieco non resta un dente.
    for (const fine of [0, 1]) {
      const p = r[fine ? r.length - 1 : 0];
      if (!dentro(p[0], p[1])) continue;
      const nl = Math.hypot(p[3], p[4]) || 1;
      const nx = p[3] / nl;
      const ny = p[4] / nl;
      const oc = (B.sinistra + mS + B.destra - mD) / 2;
      const rad = (B.sinistra + mS - (B.destra - mD)) / 2;
      const cx = p[0] + nx * oc;
      const cy = p[1] + ny * oc;
      // Verso fuori: avanti alla fine, indietro all'inizio.
      const fx = fine ? ny : -ny;
      const fy = fine ? -nx : nx;
      const centro = asfalto.v(cx, cy, p[2] + z0 - 0.004, 0, 0, 1);
      const N = 8;
      const giro = [];
      for (let j = 0; j <= N; j++) {
        const a = -Math.PI / 2 + (Math.PI * j) / N;
        // (fx, fy) avanti, (-fy, fx) a sinistra di quel verso.
        const ux = Math.cos(a) * fx - Math.sin(a) * fy;
        const uy = Math.cos(a) * fy + Math.sin(a) * fx;
        giro.push(asfalto.v(cx + ux * rad, cy + uy * rad, p[2] + z0 - 0.004, 0, 0, 1));
      }
      for (let j = 1; j <= N; j++) {
        // Girati in su (verso antiorario visto dall'alto).
        const a = asfalto.p;
        const i0 = centro;
        const i1 = giro[j - 1];
        const i2 = giro[j];
        const cr = (a[3 * i1] - a[3 * i0]) * (a[3 * i2 + 1] - a[3 * i0 + 1]) - (a[3 * i1 + 1] - a[3 * i0 + 1]) * (a[3 * i2] - a[3 * i0]);
        if (cr >= 0) asfalto.tri(i0, i1, i2);
        else asfalto.tri(i0, i2, i1);
      }
    }
    if (v.galleria) return;

    // ── Le righe ───────────────────────────────────────────────────────
    const dz = z0 + 0.02;
    const riga = (o, w, buchi, tipo = 'continua', pieno = 3, vuoto = 3) => {
      const pezzi = tipo === 'continua' ? togli([[0, L]], buchi) : trattini(L, pieno, vuoto, buchi);
      for (const [a, b] of pezzi) {
        if (b - a < 0.2) continue;
        striscia(vernice, pezzoFra(r, a, b), o + w / 2, o - w / 2, dz, meta);
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
  // destra (una rampa d'uscita), finché i due sono a meno di sette metri:
  // strisce di sbieco, come sulle autostrade italiane.
  for (const elenco of tocchi.values()) {
    const finiscono = elenco.filter(({ i, k }) => strade[i].senso && k === strade[i].xyVia.length - 1);
    const partono = elenco.filter(({ i, k }) => strade[i].senso && k === 0);
    if (finiscono.length !== 1 || partono.length !== 2) continue;
    const a = strade[finiscono[0].i];
    const pa = a.xyVia;
    const da = Math.atan2(pa[pa.length - 1][1] - pa[Math.max(0, pa.length - 4)][1], pa[pa.length - 1][0] - pa[Math.max(0, pa.length - 4)][0]);
    const angolo = (v) => {
      const p = v.xyVia;
      const q = p[Math.min(p.length - 1, 3)];
      const t = Math.atan2(q[1] - p[0][1], q[0] - p[0][0]) - da;
      return Math.atan2(Math.sin(t), Math.cos(t));
    };
    const [sin, des] = partono.map(({ i }) => strade[i]).sort((p, q) => angolo(q) - angolo(p));
    const rS = lineaRicca(sin.xy, sin.h);
    const rD = lineaRicca(des.xy, des.h);
    const LS = rS[rS.length - 1][5];
    const LD = rD[rD.length - 1][5];
    const bS = bordiCorsie(sin).destra;
    const bD = bordiCorsie(des).sinistra;
    // Il bordo di destra del ramo di sinistra, un punto ogni metro.
    const bordoS = [];
    for (let s = 0; s <= Math.min(LS, 300); s += 1) bordoS.push(puntoA(rS, s, bS));
    const dz = sopra(des.hw) + 0.02;
    for (let s = 3; s < Math.min(LD, 300); s += 5) {
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
      if (d > 7) break;
      if (d < 0.8 || !dentro(P[0], P[1])) continue;
      // Di sbieco: dal bordo della rampa indietro verso la punta del triangolo.
      const [tx, ty] = [P[3], P[4]];
      const qx = Q[0] - tx * d * 0.8;
      const qy = Q[1] - ty * d * 0.8;
      const w = 0.25;
      const z = Math.max(P[2], Q[2]) + dz;
      vernice.quad([P[0] - tx * w, P[1] - ty * w, z], [P[0] + tx * w, P[1] + ty * w, z], [qx + tx * w, qy + ty * w, z], [qx - tx * w, qy - ty * w, z], [0, 0, 1]);
    }
  }

  // ── Strisce, linee d'arresto, semafori ─────────────────────────────
  const fatti = new Set();
  for (const n of nodi) {
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
      const dz = sopra(v.hw) + 0.022;
      // All'incrocio la linea si ferma prima delle altre strade; su una via
      // sola (una striscia a metà strada) sul nodo.
      const altri = rami.filter((x) => x.i !== ramo.i);
      const R = incrocio && altri.length ? Math.max(...altri.map((x) => x.mezza)) + 1.2 : 0;
      const verso = arrivaAvanti ? -1 : 1;
      const sz = s + verso * R;
      if (sz < 0.5 || sz > L - 0.5) continue;
      const chiaveFatta = `${ramo.i}:${Math.round(sz)}:${tipo}`;
      if (fatti.has(chiaveFatta)) continue;
      fatti.add(chiaveFatta);
      // Le strisce pedonali: su tutta la carreggiata, a strisce lungo la strada.
      const zebra = tipo === 'crossing' || tipo === 'traffic_signals';
      const lungoZ = 3;
      const sZebra = tipo === 'crossing' ? s : sz + verso * (lungoZ / 2 + 0.5);
      if (zebra && sZebra > lungoZ / 2 && sZebra < L - lungoZ / 2 && (tipo !== 'crossing' || !fatti.has(`${ramo.i}:${Math.round(s)}:zebra`))) {
        fatti.add(`${ramo.i}:${Math.round(s)}:zebra`);
        const pz = pezzoFra(r, sZebra - lungoZ / 2, sZebra + lungoZ / 2);
        const m = pz[Math.floor(pz.length / 2)];
        if (dentro(m[0], m[1])) {
          for (let o = B.destra + 0.4; o + 0.5 <= B.sinistra - 0.2; o += 1.0) striscia(vernice, pz, o + 0.5, o, dz, meta * 1.5);
        }
      }
      if (tipo === 'crossing') continue;
      // La linea d'arresto: sulle corsie di chi arriva, prima delle strisce.
      const sA = tipo === 'traffic_signals' ? sz - verso * 0.6 : sz;
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
      // Il semaforo: un palo a destra di chi arriva, con le tre luci verso di lui.
      if (tipo === 'traffic_signals') {
        const lato = arrivaAvanti ? B.destra - 0.9 : B.sinistra + 0.9;
        const [px, py, ph, tx, ty] = puntoA(r, sA, lato);
        const fx = tx * verso;
        const fy = ty * verso;
        scatola(segnali, px, py, ph, ph + 3.4, fx, fy, 0.08, 0.08, ...PALO);
        scatola(segnali, px + fx * 0.05, py + fy * 0.05, ph + 2.3, ph + 3.5, fx, fy, 0.2, 0.22, ...LANTERNA);
        LUCI.forEach(([cg, cn], j) => {
          const z = ph + 3.25 - j * 0.38;
          const qx = px + fx * 0.26;
          const qy = py + fy * 0.26;
          const lx = -fy * 0.13;
          const ly = fx * 0.13;
          segnali.quad([qx + lx, qy + ly, z - 0.13], [qx - lx, qy - ly, z - 0.13], [qx - lx, qy - ly, z + 0.13], [qx + lx, qy + ly, z + 0.13], [fx, fy, 0], cg, cn);
        });
      }
    }
  }
  return { asfalto, vernice, segnali, righe };
}
