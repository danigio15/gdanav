// La verifica delle strade 3D su tessere vere (OpenFreeMap): gli errori
// geometrici che si vedono guidando, contati, per controllare una modifica
// su tanti svincoli invece che a occhio su uno.
//   node collaudo/verifica-strade.mjs <lon> <lat> [nome]
// La tessera z14 lì e quelle a est e a sud (per i bordi). Conta:
// - pendenza: tratti più ripidi del 12% (uno scalino fra due quote);
// - compenetrati: due carreggiate una sopra l'altra a meno di 4,5 m;
// - pilone: un pilone sull'asfalto di una strada più bassa;
// - bordo: la stessa strada a quote diverse di qua e di là del bordo.
// DETTAGLI=n stampa i primi n; SALVA=<file> li scrive in JSON.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const W = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const { VectorTile } = await import(`${W}/node_modules/@mapbox/vector-tile/index.js`);
const Pbf = (await import(`${W}/node_modules/pbf/index.js`)).default;
const { scarica } = await import(`${W}/collaudo/strada.mjs`);
const { costruisciTessera } = await import(`${W}/src/tessera.js`);
const { sistemaTessera } = await import(`${W}/src/geo.js`);
const z = 14;
const tj = JSON.parse((await scarica('https://tiles.openfreemap.org/planet')).corpo.toString());
const strati = new Map();
async function strato(x, y) {
  const k = x + ',' + y;
  if (!strati.has(k)) {
    const r = await scarica(tj.tiles[0].replace('{z}', z).replace('{x}', x).replace('{y}', y));
    strati.set(k, r.stato === 200 ? new VectorTile(new Pbf(new Uint8Array(r.corpo))).layers : {});
  }
  return strati.get(k);
}
export async function costruisci(X, Y) {
  const livelli = {};
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) livelli[`${dx},${dy}`] = await strato(X + dx, Y + dy);
  const t = costruisciTessera({ z, x: X, y: Y, livelli, grafo: true });
  const sys = sistemaTessera(z, X, Y);
  // In metri «globali» (mercatore in metri della tessera di mezzo): per confrontare le vicine.
  const ox = (X + 0.5) * sys.lato, oy = -(Y + 0.5) * sys.lato;
  const segs = [];
  const S = t.segmenti;
  for (let k = 0; k < S.length; k += 8) segs.push({ a: [S[k] + ox, S[k + 1] + oy, S[k + 2]], b: [S[k + 3] + ox, S[k + 4] + oy, S[k + 5]], w: S[k + 6], f: S[k + 7] });
  const piloni = [];
  for (let i = 0; i < t.fusti.length; i += 16) piloni.push({ x: t.fusti[i + 12] + ox, y: t.fusti[i + 13] + oy, h: Math.hypot(t.fusti[i + 8], t.fusti[i + 9], t.fusti[i + 10]) + 0.8 });
  return { t, sys, segs, piloni, ox, oy, X, Y };
}
const lonLat = (sys, X, Y, gx, gy) => {
  // dai metri globali a lon/lat (per i rapporti)
  const n = 2 ** z;
  const mx = gx / sys.lato / n, my = -gy / sys.lato / n;
  return [mx * 360 - 180, (Math.atan(Math.sinh(Math.PI * (1 - 2 * my))) * 180) / Math.PI];
};
const dentro = (T, p) => Math.abs(p[0] - T.ox) < T.sys.lato / 2 && Math.abs(p[1] - T.oy) < T.sys.lato / 2;
function distSeg(px, py, a, b) {
  const ex = b[0] - a[0], ey = b[1] - a[1];
  const l2 = ex * ex + ey * ey;
  const u = l2 ? Math.max(0, Math.min(1, ((px - a[0]) * ex + (py - a[1]) * ey) / l2)) : 0;
  return [Math.hypot(px - a[0] - ex * u, py - a[1] - ey * u), a[2] + (b[2] - a[2]) * u];
}
export function controlla(T) {
  const err = [];
  const metti = (tipo, x, y, info) => err.push({ tipo, ll: lonLat(T.sys, T.X, T.Y, x, y).map((v) => +v.toFixed(5)), info });
  const G = 20;
  const griglia = new Map();
  T.segs.forEach((s, i) => {
    const xs = [Math.floor(Math.min(s.a[0], s.b[0]) / G), Math.floor(Math.max(s.a[0], s.b[0]) / G)];
    const ys = [Math.floor(Math.min(s.a[1], s.b[1]) / G), Math.floor(Math.max(s.a[1], s.b[1]) / G)];
    for (let gx = xs[0]; gx <= xs[1]; gx++) for (let gy = ys[0]; gy <= ys[1]; gy++) {
      const k = gx + ',' + gy;
      if (!griglia.has(k)) griglia.set(k, []);
      griglia.get(k).push(i);
    }
  });
  const vicini = (x, y) => {
    const out = new Set();
    for (let ax = -1; ax <= 1; ax++) for (let ay = -1; ay <= 1; ay++) for (const i of griglia.get(Math.floor(x / G) + ax + ',' + (Math.floor(y / G) + ay)) || []) out.add(i);
    return out;
  };
  // A. Pendenza
  for (const s of T.segs) {
    if (!dentro(T, s.a)) continue;
    const l = Math.hypot(s.b[0] - s.a[0], s.b[1] - s.a[1]);
    if (l < 2) continue;
    const p = Math.abs(s.b[2] - s.a[2]) / l;
    if (p > 0.12) metti('pendenza', (s.a[0] + s.b[0]) / 2, (s.a[1] + s.b[1]) / 2, `${(p * 100).toFixed(0)}% ${s.a[2].toFixed(1)}→${s.b[2].toFixed(1)} cls${s.f & 15}${s.f & 32 ? ' ponte' : ''}${s.f & 16 ? ' rampa' : ''}`);
  }
  // B. Impalcati che si compenetrano: due strade una sopra l'altra a meno di 4,5 m (e più di 0,8).
  T.segs.forEach((s, i) => {
    if (!dentro(T, s.a) || s.f & 64) return;
    const m = [(s.a[0] + s.b[0]) / 2, (s.a[1] + s.b[1]) / 2, (s.a[2] + s.b[2]) / 2];
    for (const j of vicini(m[0], m[1])) {
      if (j <= i) continue;
      const o = T.segs[j];
      if (o.f & 64) continue;
      const [d, zo] = distSeg(m[0], m[1], o.a, o.b);
      const dz = Math.abs(zo - m[2]);
      if (d < Math.min(s.w, o.w) / 2 && dz > 0.8 && dz < 4.5) metti('compenetrati', m[0], m[1], `dz ${dz.toFixed(1)} (${m[2].toFixed(1)}/${zo.toFixed(1)}) cls${s.f & 15}/${o.f & 15}`);
    }
  });
  // D. Piloni sull'asfalto di una strada più bassa
  for (const p of T.piloni) {
    if (!dentro(T, [p.x, p.y])) continue;
    for (const j of vicini(p.x, p.y)) {
      const o = T.segs[j];
      const [d, zo] = distSeg(p.x, p.y, o.a, o.b);
      if (d < o.w / 2 - 0.3 && zo < p.h - 3) {
        metti('pilone', p.x, p.y, `su strada a ${zo.toFixed(1)} (pilone ${p.h.toFixed(1)}) cls${o.f & 15}`);
        break;
      }
    }
  }
  return err;
}
// C. Bordi: la stessa strada alla stessa quota di qua e di là.
export function bordo(A, B, asse) {
  const err = [];
  // la linea di confine
  const c = asse === 'x' ? A.ox + A.sys.lato / 2 : A.oy - A.sys.lato / 2;
  const tagli = (T) => {
    const out = [];
    for (const s of T.segs) {
      const va = asse === 'x' ? s.a[0] - c : s.a[1] - c;
      const vb = asse === 'x' ? s.b[0] - c : s.b[1] - c;
      if (va * vb > 0 || va === vb) continue;
      const u = va / (va - vb);
      out.push({ p: [s.a[0] + (s.b[0] - s.a[0]) * u, s.a[1] + (s.b[1] - s.a[1]) * u, s.a[2] + (s.b[2] - s.a[2]) * u], d: Math.atan2(s.b[1] - s.a[1], s.b[0] - s.a[0]), f: s.f });
    }
    return out;
  };
  const ta = tagli(A), tb = tagli(B);
  for (const q of ta) {
    const cand = tb.filter((r) => Math.hypot(r.p[0] - q.p[0], r.p[1] - q.p[1]) < 1.5 && (r.f & 15) === (q.f & 15) && (r.f & 96) === (q.f & 96));
    if (!cand.length) continue;
    const best = cand.reduce((m, r) => (Math.abs(r.p[2] - q.p[2]) < Math.abs(m.p[2] - q.p[2]) ? r : m));
    if (Math.abs(best.p[2] - q.p[2]) > 0.5) err.push({ tipo: 'bordo', ll: lonLat(A.sys, A.X, A.Y, q.p[0], q.p[1]).map((v) => +v.toFixed(5)), info: `${q.p[2].toFixed(1)} | ${best.p[2].toFixed(1)} cls${q.f & 15}${q.f & 32 ? ' ponte' : ''}` });
  }
  return err;
}
if (import.meta.url === `file://${process.argv[1]}`) {
  const [lon, lat] = [+process.argv[2], +process.argv[3]];
  const X = Math.floor(((lon + 180) / 360) * 2 ** z);
  const Y = Math.floor(((1 - Math.log(Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180)) / Math.PI) / 2) * 2 ** z);
  const A = await costruisci(X, Y), E = await costruisci(X + 1, Y), S = await costruisci(X, Y + 1);
  const tutti = [...controlla(A), ...bordo(A, E, 'x'), ...bordo(A, S, 'y')];
  const conti = {};
  for (const e of tutti) conti[e.tipo] = (conti[e.tipo] ?? 0) + 1;
  console.log(process.argv[4] ?? '', X, Y, 'strade', A.segs.length, 'piloni', A.piloni.length, JSON.stringify(conti));
  if (process.env.DETTAGLI) for (const e of tutti.slice(0, +process.env.DETTAGLI)) console.log(' ', e.tipo, e.ll.join(','), e.info);
  if (process.env.SALVA) fs.writeFileSync(process.env.SALVA, JSON.stringify(tutti));
}
