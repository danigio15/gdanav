// Impacchetta la mappa 3D per l'app: un file JS, un CSS e la pagina, sotto
// `assets/web3d/` del pacchetto (dentro l'app, niente codice da internet:
// regola 2.5.2 dell'App Store). Il lavoratore (le tessere 3D) viaggia dentro
// il JS come testo.
//
//   node build.mjs              rifà i file in assets/web3d/
//   node build.mjs --controlla  dice se quelli committati sono uguali alla
//                               sorgente (esce con 1 se no)
import * as esbuild from 'esbuild';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const qui = path.dirname(fileURLToPath(import.meta.url));
const destinazione = path.join(qui, '..', 'assets', 'web3d');
const controlla = process.argv.includes('--controlla');
const uscita = controlla ? fs.mkdtempSync(path.join(os.tmpdir(), 'web3d-')) : destinazione;
const pacchetto = (nome) => JSON.parse(fs.readFileSync(path.join(qui, 'node_modules', nome, 'package.json'), 'utf8')).version;

const comune = { bundle: true, minify: !process.env.LEGGIBILE, target: ['es2020', 'chrome90', 'safari15'], legalComments: 'eof', logLevel: 'warning' };

const lavoratore = await esbuild.build({ ...comune, entryPoints: [path.join(qui, 'src', 'lavoratore.js')], format: 'iife', write: false });
const codiceLavoratore = lavoratore.outputFiles[0].text;

/*
 * Una correzione a MapLibre 5.6.0: con la mappa molto inclinata le tessere
 * vicine alla telecamera hanno uno zoom più alto delle altre, e per quelle
 * `children()` dà un figlio solo; il codice ne leggeva quattro e si
 * fermava con «Cannot read properties of undefined (reading 'key')»,
 * perdendo il fotogramma. Qui si guarda quanti figli ci sono davvero (le
 * versioni nuove hanno riscritto tutto questo pezzo). Se il pezzo non si
 * trova, il pacchetto non si fa: vuol dire che MapLibre è cambiata.
 */
const ERRATO = 'if(o[e[0].key]&&o[e[1].key]&&o[e[2].key]&&o[e[3].key])continue';
const GIUSTO = 'if(e.every(c=>o[c.key]))continue';
const correzioneMaplibre = {
  name: 'gdanav-correzione-maplibre',
  setup(b) {
    b.onLoad({ filter: /maplibre-gl[\\/]dist[\\/]maplibre-gl\.js$/ }, ({ path: f }) => {
      const testo = fs.readFileSync(f, 'utf8');
      if (testo.split(ERRATO).length !== 2) throw new Error('MapLibre: il pezzo da correggere non c’è (o c’è due volte)');
      return { contents: testo.replace(ERRATO, GIUSTO), loader: 'js' };
    });
  },
};

const virtuale = {
  name: 'gdanav-lavoratore',
  setup(b) {
    b.onResolve({ filter: /^gdanav:lavoratore$/ }, () => ({ path: 'lavoratore', namespace: 'gdanav' }));
    b.onLoad({ filter: /.*/, namespace: 'gdanav' }, () => ({ contents: `export default ${JSON.stringify(codiceLavoratore)};`, loader: 'js' }));
  },
};

fs.mkdirSync(uscita, { recursive: true });
await esbuild.build({
  ...comune,
  entryPoints: { gdanav3d: path.join(qui, 'src', 'principale.js') },
  outdir: uscita,
  format: 'iife',
  plugins: [virtuale, correzioneMaplibre],
  banner: {
    js: `/* GdANav 3D: file generato da packages/gdanav_app/web3d (node build.mjs), non modificare. maplibre-gl ${pacchetto('maplibre-gl')}, three ${pacchetto('three')}. */`,
    css: '/* GdANav 3D: file generato da packages/gdanav_app/web3d (node build.mjs), non modificare. */',
  },
});
fs.copyFileSync(path.join(qui, 'src', 'index.html'), path.join(uscita, 'index.html'));

const file = ['index.html', 'gdanav3d.js', 'gdanav3d.css'];
if (controlla) {
  const diversi = file.filter((f) => {
    const a = path.join(destinazione, f);
    return !fs.existsSync(a) || !fs.readFileSync(a).equals(fs.readFileSync(path.join(uscita, f)));
  });
  fs.rmSync(uscita, { recursive: true, force: true });
  if (diversi.length) {
    console.error(`assets/web3d non è aggiornato (${diversi.join(', ')}): rifallo con «npm run build».`);
    process.exit(1);
  }
  console.log('assets/web3d è uguale alla sorgente.');
} else {
  for (const f of file) console.log(f, (fs.statSync(path.join(uscita, f)).size / 1024).toFixed(0), 'KB');
}
