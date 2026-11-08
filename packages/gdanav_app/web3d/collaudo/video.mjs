// Un video della guida in 3D: l'auto che avanza lungo il percorso di un
// caso del collaudo, un fotogramma alla volta col tempo finto della pagina
// (`gdanav3d.prova.passo`), così il video è fluido anche se WebGL qui è in
// software. Una posizione al secondo, come il GPS; in mezzo l'auto la porta
// avanti la pagina, come sul telefono.
//
//   NODE_USE_ENV_PROXY=1 node collaudo/video.mjs cartella caso da a [km/h] [notte]
//
// Vuole `percorso-<caso>.json` nella cartella (lo scrive collaudo.mjs);
// scrive `<caso>-video.mp4` (serve ffmpeg).
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { ARGOMENTI_CHROMIUM, apri, aspetta, playwright, servitore } from './pagina.mjs';

const [cartella, caso, da, a, kmh = '60', momento = 'giorno'] = process.argv.slice(2);
const uscita = path.resolve(cartella);
const rotta = JSON.parse(fs.readFileSync(path.join(uscita, `percorso-${caso}.json`), 'utf8'));
const v = +kmh / 3.6;
const FPS = 25;
const fotogrammi = Math.ceil(((+a - +da) / v) * FPS);
const notte = momento === 'notte';
const dir = path.join(uscita, `video-${caso}-${momento}`);
fs.rmSync(dir, { recursive: true, force: true });
fs.mkdirSync(dir, { recursive: true });

const { chromium } = await playwright();
const { porta, chiudi } = await servitore();
const browser = await chromium.launch({ args: ARGOMENTI_CHROMIUM });
const { page, posizione } = await apri(browser, { porta, cartella: uscita, rotta, caso: { metri: +da }, notte, nome: `video-${caso}` });
// Le tessere di tutto il tratto, prima di partire: la fine e poi l'inizio.
for (const m of [+a, (+a + +da) / 2, +da]) {
  await posizione(m, 0);
  await page.waitForTimeout(2000);
  await aspetta(page);
}
await page.waitForTimeout(3000);
const T0 = 2e12;
await posizione(+da, v, T0);
await page.evaluate((t) => window.gdanav3d.prova.passo(t, 0), T0);
for (let i = 0; i < fotogrammi; i++) {
  const t = T0 + (i * 1000) / FPS;
  if (i % FPS === 0 && i) await posizione(+da + (v * (t - T0)) / 1000, v, t);
  await page.evaluate(
    ([t]) =>
      new Promise((fatto) => {
        window.__mappa.once('render', () => setTimeout(fatto, 0));
        window.gdanav3d.prova.passo(t, 1000 / 25);
      }),
    [t],
  );
  await page.screenshot({ path: path.join(dir, `f${String(i).padStart(4, '0')}.png`), timeout: 180000 });
}
await browser.close();
chiudi();
const mp4 = path.join(uscita, `${caso}-video-${momento}.mp4`);
execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS), '-i', path.join(dir, 'f%04d.png'), '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-movflags', '+faststart', mp4]);
fs.rmSync(dir, { recursive: true, force: true });
console.log('scritto', mp4, fotogrammi, 'fotogrammi');
