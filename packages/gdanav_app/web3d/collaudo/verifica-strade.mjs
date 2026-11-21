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
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const W = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const { VectorTile } = await import(`${W}/node_modules/@mapbox/vector-tile/index.js`);
const Pbf = (await import(`${W}/node_modules/pbf/index.js`)).default;
const { scarica } = await import(`${W}/collaudo/strada.mjs`);
const { costruisciTessera } = await import(`${W}/src/tessera.js`);
const { asfaltoDelleCorsie, preparaCorsie, IndiceCorsie, corsieLungoIlPercorso } = await import(`${W}/src/corsie.js`);
const { IndiceSegmenti, Linea, profiloDi, fasciaSullaCorsia, levigaFascia, dentroLAsfalto } = await import(`${W}/src/percorso.js`);
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
// Le corsie del relay (la vista «Corsie»), dalle nove tessere attorno.
const relay = new Map();
async function corsieRelay(x, y) {
  const k = x + ',' + y;
  if (!relay.has(k)) {
    // Con curl: passa dal proxy dell'ambiente, se c'è.
    const f = path.join(os.tmpdir(), `relay-corsie-14-${x}-${y}.json`);
    if (!fs.existsSync(f)) {
      try {
        execFileSync('curl', ['-s', '-f', '-o', f, `https://gdanav.gdahome.org/v1/corsie/14/${x}/${y}`]);
      } catch {
        relay.set(k, null);
        return null;
      }
    }
    relay.set(k, JSON.parse(fs.readFileSync(f, 'utf8')));
  }
  return relay.get(k);
}
export async function costruisci(X, Y, { corsie = !process.env.SENZA_CORSIE } = {}) {
  const livelli = {};
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) livelli[`${dx},${dy}`] = await strato(X + dx, Y + dy);
  let datiCorsie = null;
  if (corsie) {
    const unite = { strade: new Map(), nodi: new Map(), alberi: new Map(), filari: [] };
    for (let dx = -1; dx <= 1; dx++) {
      for (let dy = -1; dy <= 1; dy++) {
        const d = await corsieRelay(X + dx, Y + dy);
        if (!d) continue;
        for (const v of d.strade ?? []) unite.strade.set(v.id, v);
        for (const n of d.nodi ?? []) unite.nodi.set(n.id, n);
        for (const a of d.alberi ?? []) unite.alberi.set(a.join(), a);
      }
    }
    datiCorsie = preparaCorsie({ strade: [...unite.strade.values()], nodi: [...unite.nodi.values()], alberi: [...unite.alberi.values()], filari: [] });
  }
  const t = costruisciTessera({ z, x: X, y: Y, livelli, grafo: true, datiCorsie, vistaCorsie: !!datiCorsie });
  const sys = sistemaTessera(z, X, Y);
  // In metri «globali» (mercatore in metri della tessera di mezzo): per confrontare le vicine.
  const ox = (X + 0.5) * sys.lato, oy = -(Y + 0.5) * sys.lato;
  const segs = [];
  const S = t.segmenti;
  const L = t.grafo.latiSegmenti;
  for (let k = 0; k < S.length; k += 8) segs.push({ a: [S[k] + ox, S[k + 1] + oy, S[k + 2]], b: [S[k + 3] + ox, S[k + 4] + oy, S[k + 5]], w: S[k + 6], f: S[k + 7], lati: L ? [L[k / 4], L[k / 4 + 1]] : [S[k + 6] / 2, S[k + 6] / 2] });
  const piloni = [];
  for (let i = 0; i < t.fusti.length; i += 16) piloni.push({ x: t.fusti[i + 12] + ox, y: t.fusti[i + 13] + oy, h: Math.hypot(t.fusti[i + 8], t.fusti[i + 9], t.fusti[i + 10]) + 0.8 });
  // Le vie con le corsie: i loro punti in metri globali, con la quota.
  const corsieVie = (t.grafo.corsie ?? []).map((v) => ({ id: v.id, hw: v.hw, ponte: !!v.ponte, galleria: !!v.galleria, w: (v.avanti + v.indietro) * v.lw, p: v.xy.map(([x, y], k) => [x + ox, y + oy, v.h[k]]) }));
  // Gli edifici della tessera di mezzo: i contorni in metri locali.
  const edifici = [];
  for (const [chiaveOff, layers] of Object.entries(livelli)) {
    const B = layers?.building;
    if (!B) continue;
    const [ddx, ddy] = chiaveOff.split(',').map(Number);
    for (let i = 0; i < B.length; i++) {
      const f = B.feature(i);
      if (f.type !== 3) continue;
      let verso = 0;
      for (const anello of f.loadGeometry()) {
        let area = 0;
        for (let j = 0, m = anello.length - 1; j < anello.length; m = j++) area += (anello[m].x - anello[j].x) * (anello[j].y + anello[m].y);
        if (!area) continue;
        if (!verso) verso = Math.sign(area);
        if (Math.sign(area) !== verso) continue; // un cortile
        edifici.push(anello.map((q) => sys.metri((X + ddx) * 4096 + q.x, (Y + ddy) * 4096 + q.y)));
      }
    }
  }
  return { t, sys, segs, piloni, corsieVie, ox, oy, X, Y, datiCorsie, edifici };
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
// La mezza larghezza disegnata di `s` (nel suo punto `p`) dalla parte del punto `q`.
function lato(s, p, q) {
  const ex = s.b[0] - s.a[0], ey = s.b[1] - s.a[1];
  const c = ex * (q[1] - p[1]) - ey * (q[0] - p[0]);
  // Se `q` è proprio sulla linea, la più larga.
  if (Math.abs(c) < 1e-6) return Math.max(...s.lati);
  return c > 0 ? s.lati[0] : s.lati[1];
}
const proietta = (p, o) => {
  const fx = o.b[0] - o.a[0], fy = o.b[1] - o.a[1];
  const u = Math.max(0, Math.min(1, ((p[0] - o.a[0]) * fx + (p[1] - o.a[1]) * fy) / (fx * fx + fy * fy || 1)));
  return [o.a[0] + fx * u, o.a[1] + fy * u];
};
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
    // I pezzi che seguono sulla stessa linea non sono un'altra strada (su
    // una strada larga i pezzi corti stanno tutti dentro la mezza larghezza).
    const seguito = new Set();
    for (let k = i + 1; k < T.segs.length && k <= i + 6; k++) {
      const p = T.segs[k - 1].b, q = T.segs[k].a;
      if (Math.hypot(p[0] - q[0], p[1] - q[1]) > 0.01) break;
      seguito.add(k);
    }
    for (const j of vicini(m[0], m[1])) {
      if (j <= i || seguito.has(j)) continue;
      const o = T.segs[j];
      if (o.f & 64) continue;
      const [d, zo] = distSeg(m[0], m[1], o.a, o.b);
      const dz = Math.abs(zo - m[2]);
      if (dz <= 0.8 || dz >= 4.5 || d >= Math.min(s.w, o.w) / 2) continue;
      // Con le larghezze disegnate (dove le carreggiate si stringono una
      // dall'altra): si compenetrano se i due nastri entrano uno nell'altro.
      const q = proietta(m, o);
      if (lato(s, m, q) + lato(o, q, m) - d < 0.3) continue;
      metti('compenetrati', m[0], m[1], `dz ${dz.toFixed(1)} (${m[2].toFixed(1)}/${zo.toFixed(1)}) cls${s.f & 15}/${o.f & 15}`);
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
  // G. Gli spigoli: dove una strada gira più di 20° in un punto che non è un incrocio.
  {
    const { nodi, feats } = T.t.grafo;
    for (const f of feats) {
      if (f.cls === 'service' && ['parking_aisle', 'driveway', 'drive-through'].includes(f.sv)) continue;
      for (let k = 1; k < f.nodi.length - 1; k++) {
        const b = nodi[f.nodi[k]];
        if (b.adj.length !== 2) continue;
        const a = nodi[f.nodi[k - 1]];
        const c = nodi[f.nodi[k + 1]];
        if (Math.hypot(b.x - a.x, b.y - a.y) < 1 || Math.hypot(c.x - b.x, c.y - b.y) < 1) continue;
        const t1 = Math.atan2(b.y - a.y, b.x - a.x);
        const t2 = Math.atan2(c.y - b.y, c.x - b.x);
        const giro = Math.abs(Math.atan2(Math.sin(t2 - t1), Math.cos(t2 - t1)));
        if (giro > (20 * Math.PI) / 180 && dentro(T, [b.x + T.ox, b.y + T.oy])) metti('spigolo', b.x + T.ox, b.y + T.oy, `${((giro * 180) / Math.PI).toFixed(0)}° ${f.cls}`);
      }
    }
  }
  // H. Le case sull'asfalto: il bordo di una strada (a terra) dentro un edificio.
  {
    const { nodi, feats } = T.t.grafo;
    const GE = 25;
    const ge = new Map();
    T.edifici.forEach((poly, i) => {
      const xs = poly.map((q) => q[0]);
      const ys = poly.map((q) => q[1]);
      for (let gx = Math.floor(Math.min(...xs) / GE); gx <= Math.floor(Math.max(...xs) / GE); gx++) {
        for (let gy = Math.floor(Math.min(...ys) / GE); gy <= Math.floor(Math.max(...ys) / GE); gy++) {
          const kk = gx + ',' + gy;
          if (!ge.has(kk)) ge.set(kk, []);
          ge.get(kk).push(i);
        }
      }
    });
    const dentroPoly = (x, y, poly) => {
      let d = false;
      for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        const [xi, yi] = poly[i];
        const [xj, yj] = poly[j];
        if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) d = !d;
      }
      return d;
    };
    for (const f of feats) {
      // (Come il disegno: i passi carrai e i parcheggi non si disegnano.)
      if (f.ponte || f.galleria || f.cls === 'rail' || (f.cls === 'service' && ['parking_aisle', 'driveway', 'drive-through'].includes(f.sv))) continue;
      let ultimo = -1e9;
      let s = 0;
      for (let k = 1; k < f.nodi.length; k++) {
        const a = nodi[f.nodi[k - 1]];
        const b = nodi[f.nodi[k]];
        const l = Math.hypot(b.x - a.x, b.y - a.y);
        if (!l) continue;
        const nx = -(b.y - a.y) / l;
        const ny = (b.x - a.x) / l;
        for (let t = 0; t < l; t += 2) {
          const px = a.x + ((b.x - a.x) * t) / l;
          const py = a.y + ((b.y - a.y) * t) / l;
          if (s + t - ultimo < 30 || !dentro(T, [px + T.ox, py + T.oy]) || a.h > 1) continue;
          const vicini0 = ge.get(Math.floor(px / GE) + ',' + Math.floor(py / GE)) ?? [];
          // Un androne: la strada nei dati passa sotto il palazzo.
          if (vicini0.some((i) => dentroPoly(px, py, T.edifici[i]))) continue;
          for (const lato of [1, -1]) {
            const lw = f.larghezze ? f.larghezze[k - 1][lato > 0 ? 0 : 1] + (f.larghezze[k][lato > 0 ? 0 : 1] - f.larghezze[k - 1][lato > 0 ? 0 : 1]) * (t / l) : f.w / 2;
            // (Una strada stretta a meno di un metro fra due case che si
            // toccano è un passaggio: non c'è asfalto da far entrare.)
            if (lw < 0.5) continue;
            const qx = px + nx * lato * (lw - 0.4);
            const qy = py + ny * lato * (lw - 0.4);
            const lista = ge.get(Math.floor(qx / GE) + ',' + Math.floor(qy / GE)) ?? [];
            if (lista.some((i) => dentroPoly(qx, qy, T.edifici[i]))) {
              metti('casa-su-strada', qx + T.ox, qy + T.oy, `${f.cls} larga ${f.w.toFixed(1)} m`);
              ultimo = s + t;
              break;
            }
          }
        }
        s += l;
      }
    }
  }
  // E. Le corsie: salti lungo una via, una via sopra un'altra a meno di
  // 4,5 m, una via staccata dall'asfalto della mappa sotto di lei.
  for (const v of T.corsieVie) {
    for (let k = 1; k < v.p.length; k++) {
      const [a, b] = [v.p[k - 1], v.p[k]];
      if (!dentro(T, a)) continue;
      const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (l < 2) continue;
      const p = Math.abs(b[2] - a[2]) / l;
      if (p > 0.12) metti('corsie-pendenza', (a[0] + b[0]) / 2, (a[1] + b[1]) / 2, `${(p * 100).toFixed(0)}% ${a[2].toFixed(1)}→${b[2].toFixed(1)} ${v.hw}${v.ponte ? ' ponte' : ''} ${v.id}`);
    }
  }
  const GC = 20;
  const gc = new Map();
  T.corsieVie.forEach((v, vi) => {
    for (let k = 1; k < v.p.length; k++) {
      const key = Math.floor(v.p[k][0] / GC) + ',' + Math.floor(v.p[k][1] / GC);
      if (!gc.has(key)) gc.set(key, []);
      gc.get(key).push([vi, k]);
    }
  });
  T.corsieVie.forEach((v, vi) => {
    if (v.galleria) return;
    for (let k = 1; k < v.p.length; k++) {
      const m = [(v.p[k - 1][0] + v.p[k][0]) / 2, (v.p[k - 1][1] + v.p[k][1]) / 2, (v.p[k - 1][2] + v.p[k][2]) / 2];
      if (!dentro(T, m)) continue;
      const visti = new Set();
      for (let ax = -1; ax <= 1; ax++) {
        for (let ay = -1; ay <= 1; ay++) {
          for (const [wi, j] of gc.get(Math.floor(m[0] / GC) + ax + ',' + (Math.floor(m[1] / GC) + ay)) || []) {
            if (wi <= vi || visti.has(wi)) continue;
            const o = T.corsieVie[wi];
            if (o.galleria) continue;
            const [d, zo] = distSeg(m[0], m[1], o.p[j - 1], o.p[j]);
            const dz = Math.abs(zo - m[2]);
            if (d < Math.min(v.w, o.w) / 2 && dz > 0.8 && dz < 4.5) {
              visti.add(wi);
              metti('corsie-compenetrate', m[0], m[1], `dz ${dz.toFixed(1)} (${m[2].toFixed(1)}/${zo.toFixed(1)}) ${v.hw}/${o.hw} ${v.id}/${o.id}`);
            }
          }
        }
      }
    }
  });
  return err;
}
// F. Il percorso nella vista «Corsie», come lo disegna l'app (`sullaCorsia`
// in principale.js), lungo percorsi veri: dalle rampe e dai ponti della
// tessera, seguendo le vie del relay per 400 m. Salti di quota della fascia
// e spostamenti di lato bruschi (lo zig-zag).
export function percorsi(T, quanti = 60) {
  const err = [];
  if (!T.datiCorsie?.strade?.length) return err;
  const { sys } = T;
  const strade = T.datiCorsie.strade.map((v) => ({ ...v, xy: [] }));
  for (const v of strade) for (let i = 0; i < v.llVia.length; i += 2) v.xy.push(sys.daLonLat(v.llVia[i], v.llVia[i + 1]));
  const indiceCorsie = new IndiceCorsie(strade);
  const indice = new IndiceSegmenti();
  indice.aggiungi('t', T.t.segmenti, 0, 0, 1);
  const asfalto = nastriDisegnati(T);
  const meta = sys.lato / 2;
  const qui = (q) => Math.abs(q[0]) < meta && Math.abs(q[1]) < meta;
  const chiave = (q) => Math.round(q[0] * 2) + ',' + Math.round(q[1] * 2);
  const partono = new Map();
  for (const v of strade) {
    if (!v.senso) continue;
    const k = chiave(v.xy[0]);
    if (!partono.has(k)) partono.set(k, []);
    partono.get(k).push(v);
  }
  // Avanti per 400 m: al primo nodo la via scelta da [scegli] (la più
  // dritta, la più a destra, la più a sinistra), poi la più dritta.
  const segui = (v0, scegli) => {
    const pts = [...v0.xy];
    let lungo = 0;
    for (let k = 1; k < pts.length; k++) lungo += Math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]);
    const usate = new Set([v0]);
    let primo = true;
    while (lungo < 400) {
      const a = pts[pts.length - 2];
      const b = pts[pts.length - 1];
      const dir = Math.atan2(b[1] - a[1], b[0] - a[0]);
      const scelte = [];
      for (const w of partono.get(chiave(b)) ?? []) {
        if (usate.has(w) || w.xy.length < 2) continue;
        const d = Math.atan2(w.xy[1][1] - w.xy[0][1], w.xy[1][0] - w.xy[0][0]);
        const t = Math.atan2(Math.sin(d - dir), Math.cos(d - dir));
        if (Math.abs(t) < 2.2) scelte.push([t, w]);
      }
      if (!scelte.length) break;
      const tutte = primo ? scelte : scelte.filter(([t]) => Math.abs(t) < 1.2);
      if (!tutte.length) break;
      const w = (primo ? scegli : 'dritta') === 'dritta' ? tutte.reduce((m, c) => (Math.abs(c[0]) < Math.abs(m[0]) ? c : m))[1] : scegli === 'destra' ? tutte.reduce((m, c) => (c[0] < m[0] ? c : m))[1] : tutte.reduce((m, c) => (c[0] > m[0] ? c : m))[1];
      primo = false;
      usate.add(w);
      for (let k = 1; k < w.xy.length; k++) {
        lungo += Math.hypot(w.xy[k][0] - pts[pts.length - 1][0], w.xy[k][1] - pts[pts.length - 1][1]);
        pts.push(w.xy[k]);
      }
    }
    return [pts, lungo];
  };
  const avvii = strade.filter((v) => v.senso && v.xy.some(qui) && (/_link$/.test(v.hw) || v.xy.length >= 2)).slice(0, quanti);
  const visti = new Set();
  for (const v0 of avvii) {
    for (const scegli of ['dritta', 'destra', 'sinistra']) {
      const [pts, lungo] = segui(v0, scegli);
      if (lungo < 60) continue;
      const firma = pts.map(chiave).join('|');
      if (visti.has(firma)) continue;
      visti.add(firma);
      // Come la linea vera del percorso: quella del calcolatore (TomTom) sta
      // qualche metro di lato e taglia gli angoli agli incroci.
      for (const [nome, linea] of [
        ['osm', new Linea(pts.flat())],
        ['di lato', new Linea(comeTomTom(pts, 3.5, 7).flat())],
        ['dall\'altro lato', new Linea(comeTomTom(pts, -3.5, 7).flat())],
      ]) {
        fasciaDelPercorso(linea, nome, v0, scegli);
      }
    }
  }
  function fasciaDelPercorso(linea, nome, v0, scegli) {
    const L = linea.lunghezza;
    const profilo = profiloDi(linea, 0, L, indice, 4);
    if (!profilo?.dx) return;
    const pr = profilo.piuFitto(2);
    const n = pr.dx.length;
    const asse = [];
    const punti = [];
    for (let k = 0; k < n; k++) {
      const [x, y] = linea.a(pr.s0 + k * pr.passo);
      asse.push([x, y]);
      punti.push([x + pr.dx[k], y + pr.dy[k]]);
    }
    const r = corsieLungoIlPercorso(punti, indiceCorsie, { passo: pr.passo, s0: pr.s0 });
    // Come la disegna l'app (`sullaCorsia` in principale.js), dentro l'asfalto.
    const sullaStrada = levigaFascia(punti, fasciaSullaCorsia(punti, r, pr.passo), pr.passo);
    const dentro = dentroLAsfalto(sullaStrada, pr.h, (x, y, h) => [...indice.asfaltoVicino(x, y, h), ...asfaltoDelleCorsie(indiceCorsie, x, y)]);
    const fascia = levigaFascia(asse, dentro, pr.passo);
    const metti = (tipo, q, info) => {
      const mx = sys.mx + q[0] * sys.s;
      const my = sys.my - q[1] * sys.s;
      err.push({ tipo, ll: [+(mx * 360 - 180).toFixed(5), +((Math.atan(Math.sinh(Math.PI * (1 - 2 * my))) * 180) / Math.PI).toFixed(5)], info: `${info} via ${v0.id} ${scegli} ${nome}` });
    };
    let ultimo = -Infinity;
    let ultimoFuori = -Infinity;
    // (Non gli ultimi metri: lì la fascia finisce.)
    for (let k = 2; k < n - 4; k++) {
      const sk = pr.s0 + k * pr.passo;
      // La fascia sull'asfalto disegnato (non in galleria: lì è sotto terra).
      if (qui(fascia[k]) && !pr.galleria?.[k] && sk - ultimoFuori >= 30 && sk > 10) {
        const fuori = asfalto.fuori(fascia[k][0], fascia[k][1], pr.h[k]);
        if (fuori > 0.8) {
          metti('percorso-fuori', fascia[k], `${fuori.toFixed(1)} m fuori dall'asfalto`);
          ultimoFuori = sk;
        }
      }
      if (!qui(asse[k]) || sk - ultimo < 30) continue;
      const pend = Math.abs(pr.h[k] - pr.h[k - 1]) / pr.passo;
      // Lo spostamento di lato fra due punti, tolto l'andare avanti.
      const tx = asse[k][0] - asse[k - 1][0];
      const ty = asse[k][1] - asse[k - 1][1];
      const tl = Math.hypot(tx, ty) || 1;
      const o = (q, a) => ((q[0] - a[0]) * -ty + (q[1] - a[1]) * tx) / tl;
      const dl = Math.abs(o(fascia[k], asse[k]) - o(fascia[k - 1], asse[k - 1]));
      // Alle svolte (il percorso gira più di 20° in dieci metri) «di lato»
      // cambia verso: lì la fascia fa la sua curva, non conta.
      const a0 = asse[Math.max(0, k - 3)];
      const a1 = asse[k];
      const a2 = asse[Math.min(n - 1, k + 3)];
      const giro = Math.abs(Math.atan2((a1[0] - a0[0]) * (a2[1] - a1[1]) - (a1[1] - a0[1]) * (a2[0] - a1[0]), (a1[0] - a0[0]) * (a2[0] - a1[0]) + (a1[1] - a0[1]) * (a2[1] - a1[1])));
      if (giro > (20 * Math.PI) / 180 && pend <= 0.12) continue;
      if (pend > 0.12) {
        metti('percorso-pendenza', asse[k], `${(pend * 100).toFixed(0)}% ${pr.h[k - 1].toFixed(1)}→${pr.h[k].toFixed(1)}`);
        ultimo = sk;
      } else if (dl > 0.9) {
        metti('percorso-di-lato', asse[k], `${dl.toFixed(1)} m in 2 m`);
        ultimo = sk;
      }
    }
  }
  return err;
}
/**
 * Una linea come quella di un calcolatore di percorsi con altre mappe: [lato]
 * metri di lato (a destra se positivo) e, agli spigoli che girano più di 25°,
 * l'angolo tagliato [taglio] metri prima e dopo.
 */
export function comeTomTom(pts, lato, taglio) {
  const fitti = [];
  for (let k = 1; k < pts.length; k++) {
    const [a, b] = [pts[k - 1], pts[k]];
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
    const m = Math.max(1, Math.ceil(l / 2));
    for (let q = 0; q < m; q++) fitti.push([a[0] + ((b[0] - a[0]) * q) / m, a[1] + ((b[1] - a[1]) * q) / m]);
  }
  fitti.push(pts.at(-1));
  const passi = Math.round(taglio / 2);
  const tagliati = fitti.map((p) => [...p]);
  for (let k = passi; k < fitti.length - passi; k++) {
    const a = fitti[k - passi];
    const b = fitti[k];
    const c = fitti[k + passi];
    const giro = Math.abs(Math.atan2((b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]), (b[0] - a[0]) * (c[0] - b[0]) + (b[1] - a[1]) * (c[1] - b[1])));
    if (giro < (25 * Math.PI) / 180) continue;
    for (let q = k - passi + 1; q < k + passi; q++) {
      const t = (q - (k - passi)) / (2 * passi);
      tagliati[q] = [a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t];
    }
    k += passi;
  }
  return tagliati.map((p, k) => {
    const a = tagliati[Math.max(0, k - 1)];
    const b = tagliati[Math.min(tagliati.length - 1, k + 1)];
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
    return [p[0] + ((b[1] - a[1]) / l) * lato, p[1] - ((b[0] - a[0]) / l) * lato];
  });
}
/**
 * Le strade disegnate della tessera, per sapere se un punto sta
 * sull'asfalto: `fuori(x, y, h)` dice di quanti metri il punto sta fuori dal
 * nastro più vicino a quella quota (0 se ci sta sopra).
 */
function nastriDisegnati(T) {
  const S = T.t.segmenti;
  const L = T.t.grafo.latiSegmenti;
  const G = 10;
  const griglia = new Map();
  for (let k = 0; k < S.length; k += 8) {
    const i = k / 8;
    for (let gx = Math.floor(Math.min(S[k], S[k + 3]) / G); gx <= Math.floor(Math.max(S[k], S[k + 3]) / G); gx++) {
      for (let gy = Math.floor(Math.min(S[k + 1], S[k + 4]) / G); gy <= Math.floor(Math.max(S[k + 1], S[k + 4]) / G); gy++) {
        const c = gx + ',' + gy;
        if (!griglia.has(c)) griglia.set(c, []);
        griglia.get(c).push(i);
      }
    }
  }
  /* Nella vista «Corsie» il nastro di sempre non c'e' dove ci sono le
   * corsie vere: c'e' il loro asfalto, spesso piu' largo della strada della
   * mappa. Un punto sopra un suo triangolo e' sull'asfalto. */
  const A = T.t.corsie?.asfalto;
  const triangoli = new Map();
  if (A) {
    const P = A.posizioni;
    const I = A.indici;
    for (let k = 0; k < I.length; k += 3) {
      const [a, b, c] = [I[k], I[k + 1], I[k + 2]];
      const xs = [P[3 * a], P[3 * b], P[3 * c]];
      const ys = [P[3 * a + 1], P[3 * b + 1], P[3 * c + 1]];
      for (let gx = Math.floor(Math.min(...xs) / G); gx <= Math.floor(Math.max(...xs) / G); gx++) {
        for (let gy = Math.floor(Math.min(...ys) / G); gy <= Math.floor(Math.max(...ys) / G); gy++) {
          const cella = gx + ',' + gy;
          if (!triangoli.has(cella)) triangoli.set(cella, []);
          triangoli.get(cella).push(k);
        }
      }
    }
  }
  const sullAsfaltoDelleCorsie = (x, y, h) => {
    if (!A) return false;
    const P = A.posizioni;
    const I = A.indici;
    for (const k of triangoli.get(Math.floor(x / G) + ',' + Math.floor(y / G)) ?? []) {
      const [a, b, c] = [I[k], I[k + 1], I[k + 2]];
      const [ax, ay, az, bx, by, cx, cy] = [P[3 * a], P[3 * a + 1], P[3 * a + 2], P[3 * b], P[3 * b + 1], P[3 * c], P[3 * c + 1]];
      if (Math.abs(az - h) > 2.5) continue;
      const d1 = (x - bx) * (ay - by) - (ax - bx) * (y - by);
      const d2 = (x - cx) * (by - cy) - (bx - cx) * (y - cy);
      const d3 = (x - ax) * (cy - ay) - (cx - ax) * (y - ay);
      const neg = d1 < 0 || d2 < 0 || d3 < 0;
      const pos = d1 > 0 || d2 > 0 || d3 > 0;
      if (!(neg && pos)) return true;
    }
    return false;
  };
  return {
    fuori(x, y, h) {
      if (sullAsfaltoDelleCorsie(x, y, h)) return 0;
      let meglio = Infinity;
      for (let ox = -2; ox <= 2; ox++) {
        for (let oy = -2; oy <= 2; oy++) {
          for (const i of griglia.get(Math.floor(x / G) + ox + ',' + (Math.floor(y / G) + oy)) ?? []) {
            const k = 8 * i;
            const ex = S[k + 3] - S[k];
            const ey = S[k + 4] - S[k + 1];
            const l2 = ex * ex + ey * ey || 1;
            const u = Math.max(0, Math.min(1, ((x - S[k]) * ex + (y - S[k + 1]) * ey) / l2));
            const qh = S[k + 2] + (S[k + 5] - S[k + 2]) * u;
            if (Math.abs(qh - h) > 2.5) continue;
            const px = S[k] + ex * u;
            const py = S[k + 1] + ey * u;
            const d = Math.hypot(x - px, y - py);
            // Il lato del nastro dalla parte del punto.
            const sinistra = ex * (y - py) - ey * (x - px) > 0;
            const mezza = L ? L[2 * i + (sinistra ? 0 : 1)] : S[k + 6] / 2;
            meglio = Math.min(meglio, Math.max(0, d - mezza));
          }
        }
      }
      return meglio;
    },
  };
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
  const tutti = [...controlla(A), ...bordo(A, E, 'x'), ...bordo(A, S, 'y'), ...percorsi(A)];
  const conti = {};
  for (const e of tutti) conti[e.tipo] = (conti[e.tipo] ?? 0) + 1;
  console.log(process.argv[4] ?? '', X, Y, 'strade', A.segs.length, 'piloni', A.piloni.length, JSON.stringify(conti));
  if (process.env.DETTAGLI) for (const e of tutti.slice(0, +process.env.DETTAGLI)) console.log(' ', e.tipo, e.ll.join(','), e.info);
  if (process.env.SALVA) fs.writeFileSync(process.env.SALVA, JSON.stringify(tutti));
}
