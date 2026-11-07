// Le immagini dello schermo dell'auto (Android Auto e CarPlay): lo stile
// dell'auto com'era e con l'aspetto della mappa 3D, disegnati da MapLibre
// GL JS nel browser al posto di MapLibre Native (lo stile è lo stesso
// JSON). Lo stesso percorso di Rho/Pero del collaudo, l'auto a 1790 m.
//
//   NODE_USE_ENV_PROXY=1 node collaudo/auto.mjs cartella
//
// Vuole `percorso-rho.json` nella cartella (lo scrive collaudo.mjs).
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { scarica } from './strada.mjs';

const qui = path.dirname(fileURLToPath(import.meta.url));
const uscita = path.resolve(process.argv[2] ?? path.join(qui, 'uscita'));
const segnaposto = path.join(qui, '..', '..', 'assets', 'segnaposto');
const maplibre = path.join(qui, '..', 'node_modules', 'maplibre-gl', 'dist');
const { chromium } = await import(process.env.PLAYWRIGHT ?? '/opt/node-tools/node_modules/playwright/index.js').then((m) => m.default ?? m);

function stile(scuro, aspetto3d) {
  const f = path.join(uscita, `stile-auto-${scuro ? 'scuro' : 'chiaro'}${aspetto3d ? '-3d' : ''}.json`);
  if (!fs.existsSync(f)) {
    const a = [path.join(qui, 'stile.dart'), f, scuro ? 'scuro' : 'chiaro', 'auto', ...(aspetto3d ? ['3d'] : [])];
    execFileSync('dart', ['run', ...a], { cwd: path.join(qui, '..', '..'), stdio: 'ignore' });
  }
  return JSON.parse(fs.readFileSync(f, 'utf8'));
}

const pagina = `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="/ml/maplibre-gl.css">
<style>html,body,#m{margin:0;height:100%}.maplibregl-ctrl-attrib{display:none}</style></head>
<body><div id="m"></div><script src="/ml/maplibre-gl.js"></script></body></html>`;
const servitore = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  if (u === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    return res.end(pagina);
  }
  const f = u.startsWith('/ml/') ? path.join(maplibre, u.slice(4)) : u.startsWith('/sp/') ? path.join(segnaposto, u.slice(4)) : null;
  if (!f || !fs.existsSync(f)) {
    res.writeHead(404);
    return res.end();
  }
  res.writeHead(200, { 'Content-Type': f.endsWith('.js') ? 'text/javascript' : f.endsWith('.css') ? 'text/css' : 'image/png' });
  fs.createReadStream(f).pipe(res);
});
await new Promise((r) => servitore.listen(0, '127.0.0.1', r));
const porta = servitore.address().port;
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const rotta = JSON.parse(fs.readFileSync(path.join(uscita, 'percorso-rho.json'), 'utf8'));

for (const [schermo, w, h] of [
  ['android-auto', 1280, 720],
  ['carplay', 1280, 720],
]) {
  for (const scuro of [false, true]) {
    for (const aspetto3d of [false, true]) {
      // Android Auto di giorno e di notte, CarPlay come lo vuole Apple: lo si mostra di notte.
      if (schermo === 'carplay' && !scuro) continue;
      const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1.5 });
      await ctx.route(/https:\/\/tiles\.openfreemap\.org\/.*/, async (route) => {
        const r = await scarica(route.request().url());
        await route.fulfill({ status: r.stato, body: r.corpo, headers: { 'content-type': r.tipo, 'access-control-allow-origin': '*' } });
      });
      const page = await ctx.newPage();
      await page.goto(`http://127.0.0.1:${porta}/`);
      await page.evaluate(
        async ([s, punti, icona]) => {
          // L'auto a 1790 m lungo il percorso, e da lì il pezzo che resta.
          const c = [];
          let m = 0;
          let qui = null;
          let rotta = 0;
          for (let i = 2; i < punti.length; i += 2) {
            const dx = (punti[i] - punti[i - 2]) * 111320 * Math.cos((punti[i + 1] * Math.PI) / 180);
            const dy = (punti[i + 1] - punti[i - 1]) * 110540;
            const d = Math.hypot(dx, dy);
            if (!qui && m + d >= 1790) {
              const t = (1790 - m) / d;
              qui = [punti[i - 2] + (punti[i] - punti[i - 2]) * t, punti[i - 1] + (punti[i + 1] - punti[i - 1]) * t];
              rotta = ((Math.atan2(dx, dy) * 180) / Math.PI + 360) % 360;
              c.push(qui);
            }
            if (qui) c.push([punti[i], punti[i + 1]]);
            m += d;
          }
          const mappa = new maplibregl.Map({ container: 'm', style: s, center: qui, zoom: 16.6, pitch: 60, bearing: rotta, attributionControl: false, fadeDuration: 0, canvasContextAttributes: { preserveDrawingBuffer: true } });
          window.__m = mappa;
          await new Promise((r) => mappa.on('load', r));
          const img = new Image();
          img.src = `/sp/${icona}.png`;
          await img.decode();
          mappa.addImage(icona, img, { pixelRatio: 3 });
          mappa.getSource('gdanav-percorso').setData({ type: 'Feature', geometry: { type: 'LineString', coordinates: c }, properties: {} });
          mappa.getSource('gdanav-io').setData({ type: 'Feature', geometry: { type: 'Point', coordinates: qui }, properties: { icona, rotta } });
          mappa.setPadding({ top: 0, bottom: 0, left: 420, right: 0 });
          mappa.jumpTo({ center: qui });
          if (mappa.getLayer('edifici-3d')) mappa.setLayoutProperty('edifici-3d', 'visibility', 'visible');
          if (mappa.getLayer('edifici')) mappa.setLayoutProperty('edifici', 'visibility', 'none');
          await new Promise((r) => {
            const iv = setInterval(() => {
              if (mappa.areTilesLoaded()) {
                clearInterval(iv);
                r();
              }
            }, 300);
          });
        },
        [stile(scuro, aspetto3d), rotta.punti, aspetto3d ? 'auto_rossa' : 'freccia'],
      );
      await page.waitForTimeout(1500);
      const f = path.join(uscita, `${schermo}-${scuro ? 'notte' : 'giorno'}-${aspetto3d ? 'aspetto-3d' : 'prima'}.png`);
      await page.screenshot({ path: f });
      console.log('scritto', f);
      await ctx.close();
    }
  }
}
await browser.close();
servitore.close();
