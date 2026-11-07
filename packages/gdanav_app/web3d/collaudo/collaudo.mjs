// Il collaudo della mappa 3D in un browser vero (Chromium senza schermo,
// WebGL in software): la pagina impacchettata con un'app finta (vedi
// `pagina.mjs`), un percorso vero per ogni caso, e per ognuno le foto
// (telefono di giorno e di notte, dall'alto in panoramica, da vicino) e i
// controlli: la tela non vuota, i triangoli nel budget, l'auto che si vede
// (anche sotto un cavalcavia), la luce sotto i cavalcavia.
//
//   NODE_USE_ENV_PROXY=1 node collaudo/collaudo.mjs [cartella] [caso…]
//
// Le tessere scaricate restano in CACHE_TESSERE. Serve Playwright
// (PLAYWRIGHT: dove sta) e `dart` per lo stile. Ogni caso scrive il suo
// esito (`collaudo-<caso>.json`) appena fatto, e il percorso
// (`percorso-<caso>.json`) per le immagini col cruscotto di Flutter.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ARGOMENTI_CHROMIUM, apri, aspetta, lungo, playwright, rossoAttorno, servitore } from './pagina.mjs';
import { SPESSORE_IMPALCATO } from '../src/elevazione.js';
import { daMetriPrototipo, percorso, percorsoAttraverso, percorsoDaTratto } from './strada.mjs';

const qui = path.dirname(fileURLToPath(import.meta.url));
const uscita = path.resolve(process.argv[2] ?? path.join(qui, 'uscita'));
const scelti = process.argv.slice(3);
/** SOLO_VISTE=1: solo la panoramica e la foto da vicino (per rifarle in fretta). */
const soloViste = process.env.SOLO_VISTE === '1';
fs.mkdirSync(uscita, { recursive: true });

/** I casi: come si fa il percorso, dove sta l'auto, le foto in più. */
export const CASI = {
  rho: {
    nome: 'Rho/Pero (MI): A4 Fiera Est → rampa sul viadotto A52 → cavalcavia di secondo livello → A8',
    centro: [9.087, 45.5172],
    percorso: () =>
      percorso(
        [9.087, 45.5172],
        [
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
        1,
      ),
    // Sulla rampa che sale verso il viadotto (il prototipo: 1790 m).
    metri: () => 1790,
    manovra: [2939, 3064],
    code: [[2300, 2600, 2]],
    extra: (r) => [{ nome: 'viadotto-secondo-livello', metri: r.metriMassima - 70 }],
    orizzontale: true,
  },
  roma: {
    nome: 'Roma, GRA: svincolo A24, la rampa in viadotto',
    centro: [12.6, 41.917],
    percorso: () => percorsoDaTratto([12.6, 41.917], [12.6123, 41.91944], [12.6123, 41.92175]),
    metri: (r) => r.metriTratto + 60,
  },
  bologna: {
    nome: 'Bologna, Casalecchio: tangenziale, A1 e la rampa sul cavalcavia',
    centro: [11.252, 44.488],
    percorso: () => percorsoDaTratto([11.252, 44.488], [11.24528, 44.49018], [11.2467, 44.49107]),
    metri: (r) => r.metriTratto + 60,
    code: [[700, 900, 1]],
  },
  cavalcavia: {
    nome: 'Bologna, Borgo Panigale: in autostrada sotto un cavalcavia',
    centro: [11.272, 44.502],
    percorso: () => percorsoAttraverso([11.272, 44.502], [11.27196, 44.50218], { prima: 500, dopo: 450 }),
    // L'auto proprio sotto il ponte: deve vedersi lo stesso.
    metri: (r) => r.metriPunto + 3,
    extra: (r) => [{ nome: 'prima-del-cavalcavia', metri: r.metriPunto - 70 }],
    luce: true,
  },
  napoli: {
    nome: 'Napoli, Capodichino: svincolo su tre livelli',
    centro: [14.276, 40.865],
    percorso: () => percorsoDaTratto([14.276, 40.865], [14.2758, 40.86368], [14.27554, 40.86549]),
    metri: (r) => r.metriTratto + 110,
  },
  torino: {
    nome: 'Torino, corso Francia: il quadrifoglio',
    centro: [7.58, 45.096],
    percorso: () => percorsoDaTratto([7.58, 45.096], [7.57714, 45.0985], [7.57742, 45.0989], { ponte: false, rampa: true }),
    metri: (r) => r.metriTratto + 150,
  },
  genova: {
    nome: 'Genova, viadotto San Giorgio sulla valle del Polcevera',
    centro: [8.887, 44.426],
    percorso: () => percorsoDaTratto([8.887, 44.426], [8.89189, 44.42457], [8.88152, 44.4278], { ponte: true, rampa: false, prima: 500, dopo: 500 }),
    metri: (r) => r.metriTratto + 300,
  },
  sottopasso: {
    nome: 'Milano: il sottopasso, in galleria sotto il viale',
    centro: [9.208, 45.49],
    percorso: () => percorsoDaTratto([9.208, 45.49], [9.20946, 45.48949], [9.20738, 45.49054], { ponte: false, rampa: false, galleria: true, prima: 450, dopo: 400 }),
    metri: (r) => r.metriTratto - 50,
    extra: (r) => [{ nome: 'dentro-la-galleria', metri: r.metriTratto + 60 }],
  },
};

const { chromium } = await playwright();
const { porta, chiudi } = await servitore();
const browser = await chromium.launch({ args: ARGOMENTI_CHROMIUM });

/** La foto, e se si vede l'auto e quanto è libera la tela. */
async function foto(page, file) {
  await page.screenshot({ path: file, timeout: 180000 });
  return page.evaluate(() => {
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
    return { colori: colori.size, deviazione: Math.round(Math.sqrt(s2 / n - media * media)) };
  });
}

async function autoVisibile(page) {
  const a = await page.evaluate(() => window.gdanav3d.prova.schermoAuto());
  if (!a) return { visibile: false };
  return { ...a, rossi: await rossoAttorno(page, a.x, a.y), visibile: (await rossoAttorno(page, a.x, a.y)) > 12 };
}

/** Una vista libera (senza seguire l'auto): panoramica o da vicino. */
async function vista(page, centro, zoom, pitch, bearing) {
  await page.evaluate(
    ([c, z, p, b]) =>
      new Promise((fatto) => {
        window.gdanav3d.ricevi({ v: 1, tipo: 'camera', modo: 'libera' });
        window.__mappa.jumpTo({ center: c, zoom: z, pitch: p, bearing: b, padding: { top: 0, bottom: 0, left: 0, right: 0 } });
        window.__mappa.once('idle', fatto);
      }),
    [centro, zoom, pitch, bearing],
  );
}

const risultati = [];
for (const [chiave, caso] of Object.entries(CASI)) {
  if (scelti.length && !scelti.includes(chiave)) continue;
  const fileP = path.join(uscita, `percorso-${chiave}.json`);
  if (!fs.existsSync(fileP)) {
    const r = await caso.percorso();
    fs.writeFileSync(fileP, JSON.stringify(r));
  }
  const rotta = JSON.parse(fs.readFileSync(fileP, 'utf8'));
  const metri = caso.metri(rotta);
  rotta.auto = metri;
  rotta.nome = caso.nome;
  fs.writeFileSync(fileP, JSON.stringify(rotta));
  const c = { ...caso, metri };
  for (const notte of soloViste ? [false] : [false, true]) {
    const momento = notte ? 'notte' : 'giorno';
    const nome = `${chiave}-${momento}`;
    const { page, ctx, posizione, errori } = await apri(browser, { porta, cartella: uscita, rotta, caso: c, notte, nome });
    await posizione(metri, 0);
    await aspetta(page);
    await page.waitForTimeout(2500);
    await posizione(metri, 0);
    await page.waitForTimeout(1500);
    const tela = await foto(page, path.join(uscita, soloViste ? `${chiave}-prova.png` : `${chiave}-telefono-${momento}.png`));
    const auto = await autoVisibile(page);
    const diag = await page.evaluate(() => window.gdanav3d.diagnosi());
    const quote = await page.evaluate(() => window.gdanav3d.prova.quoteQui());
    const sopra = quote ? quote.strade.filter((h) => h > quote.auto + 3) : [];
    const luce = sopra.length ? Math.min(...sopra) - SPESSORE_IMPALCATO - quote.auto : null;
    const esito = {
      caso: chiave,
      notte,
      nome: caso.nome,
      lunghezza: Math.round(rotta.lunghezza),
      metri: Math.round(metri),
      tessere: diag.tessere.length,
      triangoli: diag.triangoli,
      budget: diag.budget,
      quotaAuto: +(quote?.auto ?? 0).toFixed(2),
      quotaMassima: diag.profilo?.max,
      luceSottoIlPonte: luce === null ? null : +luce.toFixed(2),
      tela,
      auto,
      errori: errori.length,
    };
    esito.ok =
      tela.colori > 120 && tela.deviazione > 12 && diag.triangoli <= diag.budget && auto.visibile && (!caso.luce || (luce !== null && luce >= 5.5));
    // Le foto in più, di giorno: altri punti del percorso, la panoramica, da vicino.
    if (!notte) {
      for (const e of soloViste ? [] : (caso.extra?.(rotta) ?? [])) {
        await posizione(e.metri, 0);
        await page.waitForTimeout(2500);
        await aspetta(page);
        await posizione(e.metri, 0);
        await page.waitForTimeout(1500);
        await foto(page, path.join(uscita, `${chiave}-telefono-${e.nome}.png`));
        esito[e.nome] = await autoVisibile(page);
        esito.ok &&= esito[e.nome].visibile;
      }
      // L'auto torna al punto del caso: le viste libere la inquadrano lì.
      await posizione(metri, 0);
      await page.waitForTimeout(1000);
      const [lon, lat, rottaG] = lungo(rotta.punti, metri + 120);
      await vista(page, [lon, lat], 16.15, 56, rottaG - 35);
      await page.waitForTimeout(2000);
      await foto(page, path.join(uscita, `${chiave}-panoramica.png`));
      // Da vicino: di lato all'auto, che le rampe e i piloni si vedano di profilo.
      const [lon2, lat2, rottaV] = lungo(rotta.punti, metri + 25);
      await vista(page, [lon2, lat2], 17.55, 64, rottaV + 90);
      await page.waitForTimeout(2000);
      await foto(page, path.join(uscita, `${chiave}-da-vicino.png`));
    }
    await ctx.close();
    // Il telefono di traverso.
    if (caso.orizzontale && !soloViste) {
      const o = await apri(browser, { porta, cartella: uscita, rotta, caso: c, notte, nome: `${nome}-orizzontale`, larghezza: 844, altezza: 390 });
      await o.posizione(metri, 0);
      await aspetta(o.page);
      await o.page.waitForTimeout(2500);
      await o.posizione(metri, 0);
      await o.page.waitForTimeout(1500);
      await foto(o.page, path.join(uscita, `${chiave}-orizzontale-${momento}.png`));
      await o.ctx.close();
    }
    risultati.push(esito);
    if (!soloViste) fs.writeFileSync(path.join(uscita, `collaudo-${chiave}-${momento}.json`), JSON.stringify(esito, null, 2));
    console.log(JSON.stringify(esito));
  }
}
await browser.close();
chiudi();
const male = risultati.filter((r) => !r.ok);
console.log(male.length ? `NON VA: ${male.map((r) => `${r.caso}/${r.notte ? 'notte' : 'giorno'}`).join(', ')}` : `Tutto bene: ${risultati.length} casi.`);
process.exit(male.length ? 1 : 0);
