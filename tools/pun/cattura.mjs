// Cosa chiama davvero la mappa della PUN, oggi.
//
// onData catturava i dati aprendo la pagina con un browser automatico e
// registrando le risposte di
//   https://api.portal.piattaformaunicanazionale.it/v1/chargepoints/public/map/search
// Nell'ottobre 2024 la PUN ha cambiato qualcosa e la loro estrazione si è
// fermata. Qui si fa lo stesso — si apre la mappa pubblica come la apre
// chiunque — e si scrive ogni chiamata che la pagina fa verso il suo
// backend: metodo, indirizzo, corpo della richiesta, stato, inizio della
// risposta. È il contratto dell'API di oggi, letto dal suo stesso cliente.
//
// Non manda credenziali e non ne ha. Una visita, come quella di una persona.

import puppeteer from 'puppeteer';
import fs from 'node:fs';

const PAGINE = [
  'https://www.piattaformaunicanazionale.it/',
  'https://www.piattaformaunicanazionale.it/idr',
];
const chiamate = [];
const righe = [];
const scrivi = (t) => { console.log(t); righe.push(t); };

const browser = await puppeteer.launch({ args: ['--no-sandbox'] });
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1400, height: 900 });
  page.on('response', async (risposta) => {
    const r = risposta.request();
    const url = r.url();
    // Il backend: tutto quello che non è la pagina, i suoi file o le mappe di base.
    if (!/api\.portal|chargepoint|charge-point|\/v1\/|\/v2\/|\/api\//i.test(url)) return;
    if (/\.(js|css|png|svg|woff2?|ico)(\?|$)/i.test(url)) return;
    let corpo = '';
    try { corpo = (await risposta.text()).slice(0, 600); } catch { corpo = '(corpo non leggibile)'; }
    chiamate.push({
      metodo: r.method(),
      url,
      richiesta: (r.postData() || '').slice(0, 600),
      intestazioni: Object.fromEntries(
        Object.entries(r.headers()).filter(([k]) => /auth|key|token|x-|content-type|origin|referer/i.test(k)),
      ),
      stato: risposta.status(),
      tipo: risposta.headers()['content-type'] || '',
      corpo,
    });
  });

  for (const indirizzo of PAGINE) {
    scrivi(`\n### apro ${indirizzo}`);
    try {
      await page.goto(indirizzo, { waitUntil: 'networkidle2', timeout: 60000 });
    } catch (e) {
      scrivi(`  non si è caricata del tutto: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 8000));
  }

  // Se la mappa carica i punti solo per la zona inquadrata, si prova a
  // cercare Napoli dalla casella di ricerca, se c'è.
  try {
    const casella = await page.$('input[type="search"], input[placeholder*="erca"], input[placeholder*="ndirizzo"]');
    if (casella) {
      scrivi('\n### cerco «Centro Direzionale Napoli» nella casella');
      await casella.type('Centro Direzionale Napoli', { delay: 40 });
      await page.keyboard.press('Enter');
      await new Promise((r) => setTimeout(r, 10000));
    } else {
      scrivi('\n### nessuna casella di ricerca trovata');
    }
  } catch (e) {
    scrivi(`  ricerca non riuscita: ${e.message}`);
  }
} finally {
  await browser.close();
}

scrivi(`\n### ${chiamate.length} chiamate al backend\n`);
const viste = new Set();
for (const c of chiamate) {
  const chiave = `${c.metodo} ${c.url.split('?')[0]}`;
  if (viste.has(chiave) && viste.size > 25) continue;
  viste.add(chiave);
  scrivi(`${c.metodo} ${c.url}`);
  scrivi(`  stato ${c.stato} · ${c.tipo}`);
  // Le intestazioni si nominano ma non si stampano: se ci fosse un token, non
  // deve finire in un log pubblico.
  const nomi = Object.keys(c.intestazioni);
  if (nomi.length) scrivi(`  intestazioni: ${nomi.join(', ')}`);
  if (c.richiesta) scrivi(`  corpo inviato: ${c.richiesta}`);
  scrivi(`  risposta: ${c.corpo.replace(/\s+/g, ' ').slice(0, 400)}`);
  scrivi('');
}

fs.writeFileSync(process.env.USCITA || 'pun_api.txt', righe.join('\n') + '\n');
console.log(`::notice title=PUN API::${chiamate.length} chiamate al backend registrate`);
