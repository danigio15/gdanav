// Le foto della scena 3D sullo schermo dell'auto: largo e basso (1280×480),
// con la scheda di Android Auto a sinistra. Con lo spazio delle schede giusto
// e con quello sbagliato di prima (in punti dell'auto, tre volte troppo: la
// WebView con la densità del telefono), per vedere la differenza.
//
//   NODE_USE_ENV_PROXY=1 node collaudo/in-auto.mjs cartella
import fs from 'node:fs';
import path from 'node:path';
import { ARGOMENTI_CHROMIUM, apri, aspetta, playwright, servitore } from './pagina.mjs';

const uscita = process.argv[2];
const rotta = JSON.parse(fs.readFileSync(path.join(uscita, 'percorso-rho.json'), 'utf8'));
const { chromium } = await playwright();
const browser = await chromium.launch({ args: ARGOMENTI_CHROMIUM });
const { porta } = await servitore();
const metri = Number(process.env.METRI ?? 900);
const casi = (process.env.CASI ?? 'auto-giusta,auto-sbagliata').split(',').map((nome) =>
  nome === 'auto-sbagliata'
    ? { nome, sinistra: 1200, sopra: 300, zoom: 17.9 }
    : { nome, sinistra: 400, sopra: 0, zoom: Number(process.env.ZOOM ?? 17.9), pitch: Number(nome.match(/pitch(\d+)/)?.[1] ?? 0) || undefined },
);
for (const c of casi) {
  const { page, ctx, posizione, manda } = await apri(browser, {
    porta,
    cartella: uscita,
    rotta,
    caso: { metri, code: [], zoom: c.zoom },
    notte: false,
    nome: c.nome,
    larghezza: 1280,
    altezza: 480,
    sinistra: c.sinistra,
  });
  await manda({ tipo: 'camera', modo: 'segui', sopra: c.sopra, sinistra: c.sinistra, ...(c.pitch ? { pitch: c.pitch } : {}) });
  await posizione(metri, 0);
  await aspetta(page);
  await page.waitForTimeout(2500);
  await posizione(metri, 0);
  await page.waitForTimeout(2500);
  await page.screenshot({ path: path.join(uscita, `${c.nome}.png`), timeout: 180000 });
  await ctx.close();
}
await browser.close();
process.exit(0);
