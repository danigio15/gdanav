// Per il collaudo: la pagina impacchettata (assets/web3d) in Chromium, con
// un'app finta che le manda quello che le manda GdANav: lo stile vero
// (`stile.dart`), le icone, il percorso, una meta, un autovelox, la
// posizione. Lo usano `collaudo.mjs` (le foto) e `video.mjs` (i video).
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { scarica } from './strada.mjs';

const qui = path.dirname(fileURLToPath(import.meta.url));
const pagine = path.join(qui, '..', '..', 'assets', 'web3d');

export const ARGOMENTI_CHROMIUM = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl'];

export async function playwright() {
  return import(process.env.PLAYWRIGHT ?? '/opt/node-tools/node_modules/playwright/index.js').then((m) => m.default ?? m);
}

/** Lo stile vero dell'app, dalla copia in [cartella] o da `dart`. */
export function stile(cartella, scuro) {
  const f = path.join(cartella, `stile-${scuro ? 'scuro' : 'chiaro'}.json`);
  if (!fs.existsSync(f)) {
    execFileSync('dart', ['run', path.join(qui, 'stile.dart'), f, scuro ? 'scuro' : 'chiaro'], { cwd: path.join(qui, '..', '..'), stdio: 'ignore' });
  }
  return JSON.parse(fs.readFileSync(f, 'utf8'));
}

/** Un servitore per la pagina impacchettata; restituisce la porta. */
export async function servitore() {
  const TIPI = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
  const s = http.createServer((req, res) => {
    const p = path.join(pagine, decodeURIComponent(req.url.split('?')[0]));
    if (!p.startsWith(pagine) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) {
      res.writeHead(404);
      return res.end();
    }
    res.writeHead(200, { 'Content-Type': TIPI[path.extname(p)] ?? 'application/octet-stream' });
    fs.createReadStream(p).pipe(res);
  });
  await new Promise((r) => s.listen(0, '127.0.0.1', r));
  return { porta: s.address().port, chiudi: () => s.close() };
}

/** Il punto a [metri] lungo i punti `[lon, lat, …]`, con la rotta (gradi). */
export function lungo(punti, metri) {
  let s = 0;
  for (let i = 2; i < punti.length; i += 2) {
    const dx = (punti[i] - punti[i - 2]) * 111320 * Math.cos((punti[i + 1] * Math.PI) / 180);
    const dy = (punti[i + 1] - punti[i - 1]) * 110540;
    const d = Math.hypot(dx, dy);
    if (s + d >= metri && d > 0) {
      const t = (metri - s) / d;
      return [punti[i - 2] + (punti[i] - punti[i - 2]) * t, punti[i - 1] + (punti[i + 1] - punti[i - 1]) * t, ((Math.atan2(dx, dy) * 180) / Math.PI + 360) % 360];
    }
    s += d;
  }
  return [punti.at(-2), punti.at(-1), 0];
}

/**
 * Apre la pagina per [caso] (`{punti, code, manovra}`) e le manda tutto;
 * restituisce `{page, ctx, manda, posizione, messaggi}`.
 */
export async function apri(browser, { porta, cartella, rotta, caso, notte, larghezza = 390, altezza = 844, vista = 'inclinata', nome, sinistra = 0 }) {
  const ctx = await browser.newContext({ viewport: { width: larghezza, height: altezza }, deviceScaleFactor: 2 });
  await ctx.route(/https:\/\/(tiles\.openfreemap\.org|api\.tomtom\.com)\/.*/, async (route) => {
    try {
      const r = await scarica(route.request().url());
      await route.fulfill({ status: r.stato === 200 ? 200 : r.stato, body: r.corpo, headers: { 'content-type': r.tipo, 'access-control-allow-origin': '*' } });
    } catch {
      await route.fulfill({ status: 503, body: '' });
    }
  });
  const page = await ctx.newPage();
  const messaggi = [];
  const errori = [];
  page.on('console', (m) => {
    if (m.type() === 'error') console.log(`[${nome}]`, m.text().slice(0, 300));
  });
  page.on('pageerror', (e) => {
    errori.push(e.message);
    console.log(`[${nome}] errore`, e.message, (e.stack ?? '').split('\n').slice(0, 3).join(' | '));
  });
  await page.exposeFunction('__ascolta', (t) => messaggi.push(JSON.parse(t)));
  await page.goto(`http://127.0.0.1:${porta}/index.html?prova=1&software=1`);
  const manda = (m) => page.evaluate((x) => window.gdanav3d.ricevi(x), { v: 1, ...m });
  await manda({ tipo: 'opzioni', notte, vista, auto: '#d62a26' });
  await manda({ tipo: 'stile', stile: stile(cartella, notte) });
  for (const [n, png] of Object.entries(await icone(page))) await manda({ tipo: 'immagine', nome: n, png, ratio: 3 });
  const punti = rotta.punti;
  await manda({ tipo: 'percorso', punti, code: caso.code ?? [] });
  if (caso.manovra) await manda({ tipo: 'manovra', da: caso.manovra[0], a: caso.manovra[1] });
  await manda({ tipo: 'sorgente', id: 'gdanav-arrivo', dati: { type: 'FeatureCollection', features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: [punti.at(-2), punti.at(-1)] }, properties: {} }] } });
  // Un autovelox davanti all'auto, sul percorso.
  const av = lungo(punti, caso.metri + (caso.autovelox ?? 350));
  await manda({ tipo: 'sorgente', id: 'gdanav-segnalazioni', dati: { type: 'FeatureCollection', features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: av.slice(0, 2) }, properties: { id: 'a1', tipo: 'autovelox', icona: 'autovelox-fisso' } }] } });
  // Una sosta di ricarica e una tappa (anche su un viadotto: si alzano sull'impalcato).
  const fc = (features) => ({ type: 'FeatureCollection', features });
  const punto = (m, properties) => ({ type: 'Feature', geometry: { type: 'Point', coordinates: lungo(punti, m).slice(0, 2) }, properties });
  const qp = caso.puntiInQuota ?? [];
  await manda({ tipo: 'sorgente', id: 'gdanav-colonnine', dati: fc(qp.filter((q) => q.tipo === 'sosta').map((q, i) => punto(q.metri, { id: `c${i}`, nome: 'Colonnina', stato: 'libera', sosta: true, numero: i + 1, potenza: 150 }))) });
  await manda({ tipo: 'sorgente', id: 'gdanav-tappe', dati: fc(qp.filter((q) => q.tipo === 'tappa').map((q, i) => punto(q.metri, { numero: i + 1, nome: 'Tappa' }))) });
  const posizione = async (metri, v, quando = Date.now()) => {
    const p = lungo(punti, metri);
    await manda({ tipo: 'posizione', lat: p[1], lon: p[0], rotta: p[2], metri, velocita: v, zoom: caso.zoom ?? 17.9, quando });
  };
  // Di traverso il cruscotto copre la sinistra: l'auto nella parte libera.
  await manda({ tipo: 'camera', modo: 'segui', sopra: 0, sinistra });
  return { page, ctx, manda, posizione, messaggi, errori };
}

/** Aspetta le tessere e il percorso in 3D. */
export async function aspetta(page, minime = 3) {
  const t0 = Date.now();
  let diag = null;
  for (;;) {
    diag = await page.evaluate(() => window.gdanav3d.diagnosi());
    const vicine = diag.tessere.filter((t) => t.visibile).length;
    if ((diag.pronta && vicine >= minime && diag.profilo) || Date.now() - t0 > 240000) break;
    await page.waitForTimeout(1500);
  }
  return diag;
}

/** Le icone che l'app manda (qui disegnate al volo): bandiera e autovelox. */
export async function icone(page) {
  return page.evaluate(() => {
    const png = (w, h, disegna) => {
      const c = document.createElement('canvas');
      c.width = w;
      c.height = h;
      disegna(c.getContext('2d'));
      return c.toDataURL('image/png').split(',')[1];
    };
    return {
      'arrivo-bandiera': png(96, 120, (g) => {
        g.fillStyle = '#333';
        g.fillRect(14, 10, 6, 108);
        for (let i = 0; i < 6; i++) {
          for (let j = 0; j < 4; j++) {
            g.fillStyle = (i + j) % 2 ? '#111' : '#fff';
            g.fillRect(20 + i * 12, 12 + j * 12, 12, 12);
          }
        }
        g.strokeStyle = '#111';
        g.strokeRect(20, 12, 72, 48);
      }),
      'autovelox-fisso': png(120, 132, (g) => {
        g.fillStyle = '#fff';
        g.beginPath();
        g.roundRect(6, 6, 108, 100, 24);
        g.fill();
        g.fillStyle = '#E53935';
        g.beginPath();
        g.roundRect(14, 14, 92, 84, 18);
        g.fill();
        g.fillStyle = '#fff';
        g.fillRect(36, 42, 48, 30);
        g.fillStyle = '#E53935';
        g.beginPath();
        g.arc(60, 57, 10, 0, 7);
        g.fill();
        g.fillStyle = '#fff';
        g.beginPath();
        g.moveTo(48, 104);
        g.lineTo(72, 104);
        g.lineTo(60, 128);
        g.fill();
      }),
    };
  });
}

/** Quanti punti rossi (l'auto) ci sono attorno a [x, y] nella foto [png]. */
export async function rossoAttorno(page, x, y, raggio = 16) {
  return page.evaluate(
    async ([x, y, r]) => {
      const c = window.__mappa.getCanvas();
      const k = c.width / c.clientWidth;
      const t = document.createElement('canvas');
      t.width = t.height = 2 * r * k;
      const g = t.getContext('2d');
      g.drawImage(c, (x - r) * k, (y - r) * k, 2 * r * k, 2 * r * k, 0, 0, 2 * r * k, 2 * r * k);
      const d = g.getImageData(0, 0, t.width, t.height).data;
      let n = 0;
      for (let i = 0; i < d.length; i += 4) if (d[i] > 150 && d[i + 1] < 120 && d[i + 2] < 120 && d[i] - d[i + 1] > 70) n++;
      return n;
    },
    [x, y, raggio],
  );
}
