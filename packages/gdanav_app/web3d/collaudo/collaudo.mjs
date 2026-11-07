// Il collaudo della mappa 3D in un browser vero (Chromium senza schermo,
// WebGL in software): la pagina impacchettata (assets/web3d) con un ponte
// finto al posto dell'app, che manda lo stile vero (`stile.dart`), un
// percorso, la posizione dell'auto che avanza. Per ogni caso: una foto, e le
// misure (triangoli, tempo di disegno, tela non vuota).
//
//   NODE_USE_ENV_PROXY=1 node collaudo/collaudo.mjs [cartella] [caso…]
//
// I casi: rho (Rho/Pero, A4 → viadotto A52 → A8, il prototipo), roma (GRA,
// svincolo A24), bologna (Casalecchio). Le tessere scaricate restano in
// CACHE_TESSERE. Serve Playwright (PLAYWRIGHT: dove sta) e `dart` per lo stile.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { daMetriPrototipo, percorso, percorsoDaRampa, scarica } from './strada.mjs';

const qui = path.dirname(fileURLToPath(import.meta.url));
const pagine = path.join(qui, '..', '..', 'assets', 'web3d');
const uscita = path.resolve(process.argv[2] ?? path.join(qui, 'uscita'));
const scelti = process.argv.slice(3);
fs.mkdirSync(uscita, { recursive: true });

const { chromium } = await import(process.env.PLAYWRIGHT ?? '/opt/node-tools/node_modules/playwright/index.js').then((m) => m.default ?? m);

// ── I casi ──────────────────────────────────────────────────────────────
const CASI = {
  rho: {
    nome: 'Rho/Pero (MI): A4 Fiera Est → viadotto A52 → A8',
    centro: [9.087, 45.5172],
    via: [
      [1500, -235.9, 'motorway', false],
      [1100, -252.7, undefined, true],
      [330, -293, undefined, true],
      [38, -275, undefined, true],
      [426, 1010, undefined, undefined],
      [540, 1193, undefined, true],
      [750, 1229, undefined, true],
    ].map(([x, y, cls, rampa]) => {
      const [lon, lat] = daMetriPrototipo(x, y);
      return { lon, lat, cls, rampa };
    }),
    // Dove sta l'auto nelle foto: sulla rampa che sale, prima dell'uscita (il prototipo: 1790 m).
    metri: 1790,
    manovra: [2939, 3064],
    code: [[2300, 2600, 2]],
  },
  roma: {
    nome: 'Roma, GRA: svincolo A24 (rampa in viadotto)',
    centro: [12.6, 41.917],
    rampa: [[12.6123, 41.91944], [12.6123, 41.92175]],
    metri: 560,
    code: [],
  },
  bologna: {
    nome: 'Bologna, Casalecchio: tangenziale e A1',
    centro: [11.252, 44.488],
    rampa: [[11.24528, 44.49018], [11.2467, 44.49107]],
    metri: 560,
    code: [[700, 900, 1]],
  },
};

// ── Lo stile vero dell'app ──────────────────────────────────────────────
function stile(scuro) {
  const f = path.join(uscita, `stile-${scuro ? 'scuro' : 'chiaro'}.json`);
  if (!fs.existsSync(f)) {
    execFileSync('dart', ['run', path.join(qui, 'stile.dart'), f, scuro ? 'scuro' : 'chiaro'], { cwd: path.join(qui, '..', '..'), stdio: 'inherit' });
  }
  return JSON.parse(fs.readFileSync(f, 'utf8'));
}

// ── Un servitore per la pagina impacchettata ────────────────────────────
const TIPI = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' };
const servitore = http.createServer((req, res) => {
  const p = path.join(pagine, decodeURIComponent(req.url.split('?')[0]));
  if (!p.startsWith(pagine) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) {
    res.writeHead(404);
    return res.end();
  }
  res.writeHead(200, { 'Content-Type': TIPI[path.extname(p)] ?? 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});
await new Promise((r) => servitore.listen(0, '127.0.0.1', r));
const porta = servitore.address().port;

const browser = await chromium.launch({
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-webgl'],
});

/** Le icone che l'app manda (qui disegnate al volo): bandiera e autovelox. */
async function icone(page) {
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
        for (let i = 0; i < 6; i++) for (let j = 0; j < 4; j++) {
          g.fillStyle = (i + j) % 2 ? '#111' : '#fff';
          g.fillRect(20 + i * 12, 12 + j * 12, 12, 12);
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

const risultati = [];
for (const [chiave, caso] of Object.entries(CASI)) {
  if (scelti.length && !scelti.includes(chiave)) continue;
  const fileP = path.join(uscita, `percorso-${chiave}.json`);
  if (!fs.existsSync(fileP)) {
    const r = caso.rampa ? await percorsoDaRampa(caso.centro, ...caso.rampa) : await percorso(caso.centro, caso.via, 1);
    fs.writeFileSync(fileP, JSON.stringify({ punti: r.punti, lunghezza: r.lunghezza, quotaMassima: r.quotaMassima }));
  }
  const rotta = JSON.parse(fs.readFileSync(fileP, 'utf8'));
  for (const notte of [false, true]) {
    const nome = `${chiave}-${notte ? 'notte' : 'giorno'}`;
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
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
    page.on('console', (m) => {
      if (m.type() === 'error') console.log(`[${nome}]`, m.text().slice(0, 300));
    });
    page.on('pageerror', (e) => console.log(`[${nome}] errore`, e.message));
    await page.exposeFunction('__ascolta', (t) => messaggi.push(JSON.parse(t)));
    await page.goto(`http://127.0.0.1:${porta}/index.html?prova=1&software=1`);
    const manda = (m) => page.evaluate((x) => window.gdanav3d.ricevi(x), { v: 1, ...m });
    await manda({ tipo: 'opzioni', notte, vista: 'inclinata', auto: '#d62a26' });
    await manda({ tipo: 'stile', stile: stile(notte) });
    for (const [n, png] of Object.entries(await icone(page))) await manda({ tipo: 'immagine', nome: n, png, ratio: 3 });
    const punti = rotta.punti;
    const fine = [punti.at(-2), punti.at(-1)];
    await manda({ tipo: 'percorso', punti, code: caso.code });
    if (caso.manovra) await manda({ tipo: 'manovra', da: caso.manovra[0], a: caso.manovra[1] });
    await manda({ tipo: 'sorgente', id: 'gdanav-arrivo', dati: { type: 'FeatureCollection', features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: fine }, properties: {} }] } });
    // Un autovelox 350 m davanti all'auto, sul percorso.
    const davanti = await page.evaluate(([pp, m]) => {
      let s = 0;
      for (let i = 2; i < pp.length; i += 2) {
        const dx = (pp[i] - pp[i - 2]) * 111320 * Math.cos((pp[i + 1] * Math.PI) / 180);
        const dy = (pp[i + 1] - pp[i - 1]) * 110540;
        const d = Math.hypot(dx, dy);
        if (s + d >= m) {
          const t = (m - s) / d;
          return [pp[i - 2] + (pp[i] - pp[i - 2]) * t, pp[i - 1] + (pp[i + 1] - pp[i - 1]) * t, (Math.atan2(dx, dy) * 180) / Math.PI];
        }
        s += d;
      }
      return [pp.at(-2), pp.at(-1), 0];
    }, [punti, caso.metri + 350]);
    await manda({ tipo: 'sorgente', id: 'gdanav-segnalazioni', dati: { type: 'FeatureCollection', features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: davanti.slice(0, 2) }, properties: { id: 'a1', tipo: 'autovelox', icona: 'autovelox-fisso' } }] } });
    const posizione = async (metri, v) => {
      const p = await page.evaluate(([pp, m]) => {
        let s = 0;
        for (let i = 2; i < pp.length; i += 2) {
          const dx = (pp[i] - pp[i - 2]) * 111320 * Math.cos((pp[i + 1] * Math.PI) / 180);
          const dy = (pp[i + 1] - pp[i - 1]) * 110540;
          const d = Math.hypot(dx, dy);
          if (s + d >= m) {
            const t = (m - s) / d;
            return [pp[i - 2] + (pp[i] - pp[i - 2]) * t, pp[i - 1] + (pp[i + 1] - pp[i - 1]) * t, ((Math.atan2(dx, dy) * 180) / Math.PI + 360) % 360];
          }
          s += d;
        }
        return [pp.at(-2), pp.at(-1), 0];
      }, [punti, metri]);
      await manda({ tipo: 'posizione', lat: p[1], lon: p[0], rotta: p[2], metri, velocita: v, zoom: 17.9, quando: Date.now() });
    };
    await manda({ tipo: 'camera', modo: 'segui', sopra: 0 });
    await posizione(caso.metri, 0);
    const t0 = Date.now();
    let diag = null;
    for (;;) {
      diag = await page.evaluate(() => window.gdanav3d.diagnosi());
      const vicine = diag.tessere.filter((t) => t.visibile).length;
      if ((diag.pronta && vicine >= 3 && diag.profilo) || Date.now() - t0 > 240000) break;
      await page.waitForTimeout(1500);
    }
    await page.waitForTimeout(2500);
    await posizione(caso.metri, 0);
    await page.waitForTimeout(1200);
    const foto = path.join(uscita, `${nome}.png`);
    await page.screenshot({ path: foto });
    // La tela non è vuota: quanti colori diversi, e quanto variano.
    const tela = await page.evaluate(() => {
      const c = window.__mappa.getCanvas();
      const t = document.createElement('canvas');
      t.width = 120;
      t.height = 260;
      const g = t.getContext('2d');
      g.drawImage(c, 0, 0, 120, 260);
      const d = g.getImageData(0, 0, 120, 260).data;
      const colori = new Set();
      let s = 0;
      let s2 = 0;
      const n = d.length / 4;
      for (let i = 0; i < d.length; i += 4) {
        const l = 0.3 * d[i] + 0.59 * d[i + 1] + 0.11 * d[i + 2];
        s += l;
        s2 += l * l;
        colori.add((d[i] >> 4) * 256 + (d[i + 1] >> 4) * 16 + (d[i + 2] >> 4));
      }
      const media = s / n;
      return { colori: colori.size, deviazione: Math.sqrt(s2 / n - media * media) };
    });
    // Il moto: l'auto avanza a 25 m/s per otto secondi; si misurano i fotogrammi.
    const intervalli = await page.evaluate(
      ([pp, m0]) =>
        new Promise((fatto) => {
          const out = [];
          let ultimo = null;
          const giro = (t) => {
            if (ultimo !== null) out.push(t - ultimo);
            ultimo = t;
            if (out.length < 400 && t - inizio < 8000) requestAnimationFrame(giro);
            else fatto(out);
          };
          const inizio = performance.now();
          requestAnimationFrame(giro);
        }),
      [punti, caso.metri],
    ).catch(() => []);
    // Nel frattempo una posizione al secondo (fuori dalla pagina non si può: si fa prima).
    const dopo = await page.evaluate(() => window.gdanav3d.diagnosi());
    const esito = {
      caso: chiave,
      notte,
      nome: caso.nome,
      foto,
      lunghezza: Math.round(rotta.lunghezza),
      tessere: dopo.tessere.map((t) => ({ chiave: t.chiave, dettaglio: t.dettaglio, triangoli: t.triangoli, visibile: t.visibile, ms: t.conti?.ms })),
      triangoli: dopo.triangoli,
      budget: dopo.budget,
      msDisegno: Math.round(dopo.msDisegno ?? 0),
      fotogrammiMs: intervalli.length ? Math.round(intervalli.slice().sort((a, b) => a - b)[Math.floor(intervalli.length / 2)]) : null,
      quotaAuto: dopo.auto?.z,
      profiloMax: dopo.profilo?.max,
      tela,
      messaggi: messaggi.map((m) => m.tipo),
      log: dopo.log.filter((r) => /errore|scartato|lavoratore/.test(r)),
      ok: tela.colori > 200 && tela.deviazione > 12 && dopo.triangoli <= dopo.budget && dopo.tessere.length > 0,
    };
    risultati.push(esito);
    console.log(JSON.stringify({ ...esito, tessere: esito.tessere.length }));
    // Anche in movimento: l'auto avanza di 200 m, la telecamera la segue.
    if (!notte) {
      for (let k = 1; k <= 4; k++) {
        await posizione(caso.metri + k * 50, 25);
        await page.waitForTimeout(600);
      }
      await page.waitForTimeout(1500);
      await page.screenshot({ path: path.join(uscita, `${nome}-200m.png`) });
    }
    await ctx.close();
  }
}
fs.writeFileSync(path.join(uscita, 'collaudo.json'), JSON.stringify(risultati, null, 2));
await browser.close();
servitore.close();
const male = risultati.filter((r) => !r.ok);
console.log(male.length ? `NON VA: ${male.map((r) => `${r.caso}/${r.notte ? 'notte' : 'giorno'}`).join(', ')}` : `Tutto bene: ${risultati.length} casi.`);
process.exit(male.length ? 1 : 0);
