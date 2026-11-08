// Le foto del percorso oltre il tratto del 3D: «ad un certo punto la linea
// si interrompe, non si vede più». La guida a 200 m dall'inizio del percorso
// di Rho (scritto da collaudo.mjs), poi la mappa spostata dove il 3D finisce:
// lì il percorso continua piatto, con le code. Di giorno e di notte.
//
//   ICONA=freccia NODE_USE_ENV_PROXY=1 node collaudo/oltre.mjs cartella
import fs from 'node:fs';
import path from 'node:path';
import { ARGOMENTI_CHROMIUM, apri, aspetta, lungo, playwright, servitore } from './pagina.mjs';
const uscita = process.argv[2];
const rotta = JSON.parse(fs.readFileSync(path.join(uscita, 'percorso-rho.json'), 'utf8'));
const { chromium } = await playwright();
const browser = await chromium.launch({ args: ARGOMENTI_CHROMIUM });
const { porta } = await servitore();
const caso = { metri: 200, code: [[900, 1300, 3], [2850, 3150, 2]] };
for (const notte of [false, true]) {
  const { page, ctx, posizione } = await apri(browser, { porta, cartella: uscita, rotta, caso, notte, nome: 'oltre' });
  await posizione(200, 0);
  await aspetta(page);
  await page.waitForTimeout(2500);
  await posizione(200, 0);
  await page.waitForTimeout(2000);
  await page.screenshot({ path: path.join(uscita, `segui-${notte ? 'notte' : 'giorno'}.png`) });
  // Avanti, dove il 3D finisce (200 - 80 + 2600 = 2720 m).
  const [lon, lat, r] = lungo(rotta.punti, 2720);
  await page.evaluate(([c, b]) => new Promise((f) => {
    window.gdanav3d.ricevi({ v: 1, tipo: 'camera', modo: 'libera' });
    window.__mappa.jumpTo({ center: c, zoom: 16.3, pitch: 50, bearing: b, padding: { top: 0, bottom: 0, left: 0, right: 0 } });
    window.__mappa.once('idle', f);
  }), [[lon, lat], r]);
  await page.waitForTimeout(2500);
  await page.screenshot({ path: path.join(uscita, `oltre-${notte ? 'notte' : 'giorno'}.png`) });
  await ctx.close();
}
await browser.close();
process.exit(0);
