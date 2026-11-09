import assert from 'node:assert/strict';
import test from 'node:test';
import { SORGENTE_OLTRE, STRATI_SOSTITUITI, ZOOM_3D, adattaStile } from '../src/stile3d.js';

const stile = {
  version: 8,
  sources: { openmaptiles: {}, traffico: {} },
  layers: [
    { id: 'sfondo', type: 'background', paint: { 'background-color': '#fff' } },
    { id: 'autostrade', type: 'line', paint: {} },
    { id: 'edifici-3d', type: 'fill-extrusion', layout: { visibility: 'none' }, paint: {} },
    { id: 'percorso', type: 'line', paint: {} },
    { id: 'nomi-strade', type: 'symbol', layout: { 'text-field': ['get', 'name'] }, paint: {} },
    { id: 'segnalazioni', type: 'symbol', layout: {}, paint: {} },
    { id: 'io', type: 'symbol', layout: {}, paint: {} },
  ],
};

test('da vicino il 3D al posto di strade, percorso e segnaposto', () => {
  const s = adattaStile(stile, { notte: false });
  const id = s.layers.map((l) => l.id);
  assert.ok(!id.includes('edifici-3d'), 'gli edifici di MapLibre non servono');
  for (const l of s.layers) if (STRATI_SOSTITUITI.includes(l.id)) assert.equal(l.maxzoom, ZOOM_3D);
  assert.equal(s.layers.find((l) => l.id === 'segnalazioni').maxzoom, undefined, 'le icone restano sempre');
  assert.equal(stile.layers.find((l) => l.id === 'autostrade').maxzoom, undefined, "l'originale non si tocca");
});

test('i nomi in piedi e non sui ponti; i cartelli; il traffico che si scarica', () => {
  const s = adattaStile(stile, { notte: true });
  const nomi = s.layers.find((l) => l.id === 'nomi-strade');
  assert.deepEqual(nomi.filter, ['match', ['coalesce', ['get', 'brunnel'], ''], ['bridge', 'tunnel'], false, true]);
  assert.equal(nomi.layout['text-pitch-alignment'], 'viewport');
  const id = s.layers.map((l) => l.id);
  assert.equal(id[id.indexOf('nomi-strade') + 1], 'scudi');
  assert.ok(id.indexOf('traffico-fonte-3d') < id.indexOf('nomi-strade'));
  assert.equal(s.layers.find((l) => l.id === 'sfondo').paint['background-color'], '#28324A');
});

test('oltre il tratto del 3D il percorso continua, piatto e più stretto, con le code', () => {
  /* «Ad un certo punto la linea si interrompe, non si vede più»: da vicino il
   * percorso lo fa il 3D, ma solo per un tratto davanti all'auto. Oltre, gli
   * stessi strati del percorso su una sorgente che ha solo quel pezzo. */
  const larghezza = ['interpolate', ['exponential', 1.6], ['zoom'], 12, 10, 18, 30];
  const s = adattaStile(
    {
      version: 8,
      sources: { 'gdanav-percorso': {}, 'gdanav-code': {} },
      layers: [
        { id: 'percorso', type: 'line', source: 'gdanav-percorso', paint: { 'line-width': larghezza } },
        { id: 'code', type: 'line', source: 'gdanav-code', paint: { 'line-width': larghezza } },
        { id: 'percorso-frecce', type: 'symbol', source: 'gdanav-percorso', layout: {} },
      ],
    },
    { notte: false },
  );
  assert.deepEqual(s.sources[SORGENTE_OLTRE].data.features, []);
  const oltre = s.layers.filter((l) => l.source === SORGENTE_OLTRE);
  assert.deepEqual(
    oltre.map((l) => l.id),
    ['percorso-oltre', 'code-oltre', 'percorso-frecce-oltre'],
  );
  for (const l of oltre) {
    assert.equal(l.minzoom, ZOOM_3D, 'da vicino, dove il resto lo fa il 3D');
    assert.equal(l.maxzoom, undefined);
  }
  // Più stretto, e le soglie dello zoom restano quelle.
  const w = oltre[0].paint['line-width'];
  assert.deepEqual([w[3], w[5]], [12, 18]);
  assert.ok(w[4] < 10 && w[6] < 30);
  // Le code hanno il livello, il percorso no: ognuno i suoi.
  assert.deepEqual(oltre[1].filter, ['has', 'livello']);
  assert.deepEqual(oltre[0].filter, ['!', ['has', 'livello']]);
});
