import assert from 'node:assert/strict';
import test from 'node:test';
import { STRATI_SOSTITUITI, ZOOM_3D, adattaStile } from '../src/stile3d.js';

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
