import assert from 'node:assert/strict';
import test from 'node:test';
import { LIMITI, NASTRI, costruisciTessera, stimaTriangoli, bufferDellaTessera } from '../src/tessera.js';
import { ALTEZZA_LIVELLO, SPESSORE_IMPALCATO } from '../src/elevazione.js';
import { cavalcavia, cavalcaviaConRampa, cavalcaviaDueCarreggiate, sottopasso, sottopassoConNome } from './finte.js';

const X = 8605;
const Y = 5860;

test('una tessera con un cavalcavia: strade, ponte, piloni, edificio, alberi', () => {
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  assert.equal(t.chiave, `14/${X}/${Y}`);
  for (const k of Object.keys(t.strade)) assert.ok(NASTRI.includes(k));
  assert.ok(t.strade.motorway, 'il nastro dell’autostrada');
  assert.ok(t.strade['primary2-ponte'], 'il ponte ha il suo asfalto');
  assert.ok(t.opere && t.opere.indici.length > 0, 'parapetti e travi');
  assert.ok(t.capitelli.length / 16 > 3, 'i piloni sotto il ponte');
  assert.equal(t.conti.edificiFatti, 2);
  // Il capannone sotto il cavalcavia non buca l'impalcato.
  const zTetti = [...t.tetti.posizioni].filter((_, k) => k % 3 === 2);
  assert.ok(Math.max(...zTetti) < 12.5 && zTetti.some((z) => z <= ALTEZZA_LIVELLO - SPESSORE_IMPALCATO - 0.5), `tetti ${Math.min(...zTetti)}..${Math.max(...zTetti)}`);
  // Il nome del ponte, all'altezza dell'impalcato.
  assert.equal(t.etichette.length, 1);
  assert.equal(t.etichette[0].nome, 'Cavalcavia Bacula');
  assert.ok(t.etichette[0].h > 6.5);
  assert.ok(t.conti.alberi > 10, 'gli alberi nel parco');
  // I segmenti: il ponte a un livello sopra l’autostrada, che resta a terra.
  const s = t.segmenti;
  let sopra = 0;
  let terra = 0;
  for (let i = 0; i < s.length; i += 8) {
    const mx = (s[i] + s[i + 3]) / 2;
    const my = (s[i + 1] + s[i + 4]) / 2;
    if (Math.abs(mx) < 3 && Math.abs(my) < 40) sopra = Math.max(sopra, s[i + 2]);
    if (Math.abs(my) < 1 && Math.abs(mx) > 20 && Math.abs(mx) < 200) terra = Math.max(terra, s[i + 2]);
  }
  assert.ok(sopra > 7, `il ponte in quota (${sopra})`);
  assert.ok(terra < 0.5, `l’autostrada a terra (${terra})`);
  // Nessun pilone in mezzo all’autostrada.
  for (let i = 0; i < t.fusti.length; i += 16) assert.ok(Math.abs(t.fusti[i + 13]) > 6, 'pilone fuori dalla carreggiata');
  assert.equal(t.conti.triangoli, stimaTriangoli(t));
  assert.ok(bufferDellaTessera(t).length > 10);
});

test('sempre la stessa tessera: gli alberi nascono negli stessi posti', () => {
  const a = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  const b = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  assert.deepEqual([...a.alberi.tronchi], [...b.alberi.tronchi]);
  const c = costruisciTessera({ z: 14, x: X + 1, y: Y, livelli: { '0,0': cavalcavia() } });
  assert.notDeepEqual([...a.alberi.tronchi.slice(0, 32)], [...c.alberi.tronchi.slice(0, 32)]);
});

test('ridotta: niente alberi né lampioni, meno triangoli', () => {
  const pieno = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  const ridotto = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() }, dettaglio: 'ridotto' });
  assert.equal(ridotto.conti.alberi, 0);
  assert.equal(ridotto.conti.lampioni, 0);
  assert.ok(ridotto.conti.triangoli < pieno.conti.triangoli);
  assert.equal(LIMITI.ridotto.alberi, 0);
});

test('i limiti: gli alberi non passano il tetto della tessera', () => {
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() }, limiti: { alberi: 5 } });
  assert.ok(t.conti.alberi <= 5);
});

test('senza la tessera di mezzo non si fa niente', () => {
  assert.throws(() => costruisciTessera({ z: 14, x: X, y: Y, livelli: {} }));
});

test('sotto il cavalcavia: un pilone per lato della strada di sotto, nessuno sopra', () => {
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcavia() } });
  const ys = [];
  for (let i = 0; i < t.fusti.length; i += 16) if (Math.abs(t.fusti[i + 12]) < 3) ys.push(t.fusti[i + 13]);
  // L'autostrada è larga 11,5 m: i piloni a qualche metro dal bordo, da tutte e due le parti.
  assert.ok(ys.some((y) => y > 6 && y < 13), `a nord (${ys})`);
  assert.ok(ys.some((y) => y < -6 && y > -13), `a sud (${ys})`);
  // E il ponte sopra ha la luce per passarci sotto: almeno 5 m fra l'asfalto e il ventre.
  let ponte = 0;
  for (let i = 0; i < t.segmenti.length; i += 8) {
    if (t.segmenti[i + 7] & 32 && Math.abs(t.segmenti[i + 1]) < 8) ponte = Math.max(ponte, t.segmenti[i + 2]);
  }
  const luce = ponte - SPESSORE_IMPALCATO - 0.24;
  assert.ok(luce >= 5.5, `luce sotto il cavalcavia: ${luce}`);
});

test('il cavalcavia sopra due carreggiate: un pilone nello spartitraffico, e l\'ombra sotto', () => {
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcaviaDueCarreggiate() } });
  const segni = [];
  for (let i = 0; i < t.segmenti.length; i += 8) {
    if (!(t.segmenti[i + 7] & 32) && Math.abs(t.segmenti[i]) > 50) segni.push(t.segmenti[i + 1]);
  }
  const ya = Math.min(...segni);
  const yb = Math.max(...segni);
  assert.ok(yb - ya > 15, `due carreggiate (${ya}, ${yb})`);
  const ys = [];
  for (let i = 0; i < t.fusti.length; i += 16) if (Math.abs(t.fusti[i + 12]) < 12) ys.push(t.fusti[i + 13]);
  const meta = (ya + yb) / 2;
  assert.ok(ys.some((y) => Math.abs(y - meta) < 1.5), `nello spartitraffico (${meta}: ${ys})`);
  assert.ok(ys.some((y) => y > yb + 6) && ys.some((y) => y < ya - 6), `ai due lati (${ys})`);
  assert.ok(t.ombrePonti && t.ombrePonti.indici.length >= 12, 'l\'ombra morbida sotto il ponte');
});

test('il sottopasso: un nastro di galleria, gli imbocchi, e i segmenti per il percorso', () => {
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': sottopasso() } });
  assert.ok(t.strade.galleria, 'il nastro della galleria');
  assert.ok(t.opere && t.opere.indici.length / 3 >= 2 * (5 * 2 * 3 + 2), 'due imbocchi');
  let galleria = 0;
  for (let i = 0; i < t.segmenti.length; i += 8) if (t.segmenti[i + 7] & 64) galleria++;
  assert.ok(galleria > 10);
  // Sotto il viale: la galleria sta più in basso della strada che la copre.
  const zg = Math.max(...[...t.strade.galleria.posizioni].filter((_, k) => k % 3 === 2));
  const zv = Math.min(...[...t.strade.secondary === undefined ? t.strade.primary2.posizioni : t.strade.primary2.posizioni].filter((_, k) => k % 3 === 2));
  assert.ok(zg < zv, `galleria ${zg} sotto la strada ${zv}`);
});

test('un ponte spezzato in due sopra la strada: niente spalla in mezzo alla carreggiata', () => {
  const l = cavalcavia();
  // Lo stesso cavalcavia, ma in due pezzi che si toccano sopra l'autostrada.
  l.transportation = {
    ...l.transportation,
    length: 5,
    feature: (i) =>
      i < 2
        ? cavalcavia().transportation.feature(i === 0 ? 0 : 1)
        : i === 2
          ? { type: 2, properties: { class: 'primary', brunnel: 'bridge', layer: 1 }, loadGeometry: () => [[{ x: 2048, y: 2600 }, { x: 2048, y: 2048 }]] }
          : i === 3
            ? { type: 2, properties: { class: 'primary', brunnel: 'bridge', layer: 1 }, loadGeometry: () => [[{ x: 2048, y: 2048 }, { x: 2048, y: 1500 }]] }
            : cavalcavia().transportation.feature(3),
  };
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': l } });
  // Nessun pezzo di cemento sull'asfalto dell'autostrada (|y| < 6 m) sotto i 4 m.
  const p = t.opere.posizioni;
  for (let i = 0; i < p.length; i += 3) {
    if (Math.abs(p[i + 1]) < 5.5 && p[i + 2] < 4 && Math.abs(p[i]) < 6) assert.fail(`cemento in carreggiata a ${p[i]}, ${p[i + 1]}, ${p[i + 2]}`);
  }
});

test('i nomi delle rampe in quota li scrive il 3D, in quota; quelli a terra MapLibre', () => {
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': cavalcaviaConRampa() } });
  const rampa = t.etichette.find((e) => e.nome === 'Rampa Bacula');
  assert.ok(rampa, `la rampa ha il suo nome (${t.etichette.map((e) => e.nome)})`);
  assert.ok(rampa.h > 2.5, `in quota: ${rampa.h}`);
  assert.ok(t.nascosti.includes('Rampa Bacula') && t.nascosti.includes('Cavalcavia Bacula'));
  assert.ok(!t.nascosti.includes('Autostrada dei Laghi'), 'la strada a terra la scrive MapLibre');
  assert.ok(!t.etichette.some((e) => e.nome === 'Autostrada dei Laghi'));
});

test('il nome di una strada con un sottopasso: fuori dalla galleria, mai sopra', () => {
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': sottopassoConNome() } });
  assert.ok(t.nascosti.includes('Viale Lunigiana'), 'MapLibre lo tace');
  const e = t.etichette.find((q) => q.nome === 'Viale Lunigiana');
  assert.ok(e, 'il 3D lo scrive');
  // La galleria va da y = 2600 a 1500 nella tessera: in metri intorno al centro.
  const inGalleria = t.segmenti;
  let dentro = false;
  for (let i = 0; i < inGalleria.length; i += 8) {
    if (!(inGalleria[i + 7] & 64)) continue;
    const ax = inGalleria[i];
    const ay = inGalleria[i + 1];
    const bx = inGalleria[i + 3];
    const by = inGalleria[i + 4];
    const L2 = (bx - ax) ** 2 + (by - ay) ** 2 || 1;
    const u = Math.max(0, Math.min(1, ((e.x - ax) * (bx - ax) + (e.y - ay) * (by - ay)) / L2));
    if (Math.hypot(ax + (bx - ax) * u - e.x, ay + (by - ay) * u - e.y) < 6) dentro = true;
  }
  assert.ok(!dentro, `il nome non sta sopra la galleria (${e.x}, ${e.y})`);
  assert.ok(e.h < 1, 'a terra');
});
