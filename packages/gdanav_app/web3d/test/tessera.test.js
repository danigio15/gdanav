import assert from 'node:assert/strict';
import test from 'node:test';
import { bufferDellaTessera, costruisciTessera, iSottopassi, LIMITI, NASTRI, stimaTriangoli } from '../src/tessera.js';
import { ALTEZZA_LIVELLO, SPESSORE_IMPALCATO, altezzaViadotto } from '../src/elevazione.js';
import { cavalcavia, cavalcaviaConRampa, cavalcaviaDueCarreggiate, ponteLungo, sottopasso, sottopassoConNome, strato } from './finte.js';

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

test('un viadotto lungo sta alto sulla valle; un ponte qualunque altrettanto lungo resta al suo livello', () => {
  assert.equal(altezzaViadotto(150), 0);
  assert.equal(altezzaViadotto(1000), 45);
  assert.equal(altezzaViadotto(5000), 60);
  const quota = (t) => {
    let h = 0;
    for (let i = 0; i < t.segmenti.length; i += 8) if (Math.abs(t.segmenti[i]) < 30 && t.segmenti[i + 7] & 32) h = Math.max(h, t.segmenti[i + 2]);
    return h;
  };
  const alto = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': ponteLungo('Viadotto Aglio') } });
  const genova = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': ponteLungo('(Ponte san Giorgio) A10 dir. Genova') } });
  const basso = costruisciTessera({ z: 14, x: X, y: Y, livelli: { '0,0': ponteLungo('Tangenziale di Bologna') } });
  assert.ok(quota(genova) > 20, `il ponte di Genova in alto: ${quota(genova)}`);
  assert.ok(quota(alto) > 20, `il viadotto in alto: ${quota(alto)}`);
  assert.ok(Math.abs(quota(basso) - ALTEZZA_LIVELLO) < 1, `il ponte qualunque al primo livello: ${quota(basso)}`);
  // I piloni del viadotto alto sono più grossi (la scala del fusto).
  let grosso = 0;
  for (let i = 0; i < alto.fusti.length; i += 16) grosso = Math.max(grosso, Math.hypot(alto.fusti[i], alto.fusti[i + 1]));
  assert.ok(grosso > 1.6, `pilone grosso: ${grosso}`);
});

test('un sottopasso non ha gli imbocchi di una galleria', () => {
  // «Mancano i cavalcavia»: la stradina che passa sotto l'autostrada (in
  // galleria per trenta metri) aveva due scatole di cemento ai lati.
  const nodi = [];
  const feats = [];
  const strada = (punti, piu = {}) => {
    const fi = feats.length;
    const idx = punti.map(([x, y]) => {
      let i = nodi.findIndex((n) => n.x === x && n.y === y);
      if (i < 0) i = nodi.push({ x, y, feats: [] }) - 1;
      if (!nodi[i].feats.includes(fi)) nodi[i].feats.push(fi);
      return i;
    });
    feats.push({ cls: 'minor', galleria: false, nodi: idx, ...piu });
    return feats[fi];
  };
  // Il sottopasso: strada aperta, due pezzi in galleria (uno per carreggiata), strada aperta.
  strada([[-100, 0], [-25, 0]]);
  const a = strada([[-25, 0], [0, 0]], { galleria: true });
  const b = strada([[0, 0], [25, 0]], { galleria: true });
  strada([[25, 0], [100, 0]]);
  // Una galleria vera: trecento metri.
  strada([[0, 500], [100, 500]]);
  const lunga = strada([[100, 500], [400, 500]], { galleria: true });
  strada([[400, 500], [500, 500]]);
  // Una galleria tagliata dal bordo dei dati: corta qui, ma chissà quanto lunga.
  strada([[0, 900], [50, 900]]);
  const tagliata = strada([[50, 900], [90, 900]], { galleria: true });
  // E una ferrovia in galleria non c'entra.
  strada([[0, 1200], [10, 1200]], { cls: 'rail' });
  const treno = strada([[10, 1200], [30, 1200]], { cls: 'rail', galleria: true });
  strada([[30, 1200], [60, 1200]], { cls: 'rail' });
  const s = iSottopassi(nodi, feats);
  assert.ok(s.has(a) && s.has(b), 'i due pezzi del sottopasso');
  assert.ok(!s.has(lunga), 'una galleria lunga resta una galleria');
  assert.ok(!s.has(tagliata), 'tagliata dal bordo: non si sa');
  assert.ok(!s.has(treno));
  assert.equal(s.size, 2);
});

test('un casello: la pensilina sta su pilastri sopra le corsie, non è un palazzo', () => {
  // «Verifica i caselli autostradali e tangenziale»: gli edifici veri hanno
  // anche le pensiline dei caselli, e la scena le tirava su come palazzi con
  // le finestre di traverso sulla strada.
  const quadro = (x0, y0, x1, y1) => [[[x0, y0], [x0, y1], [x1, y1], [x1, y0], [x0, y0]]];
  const livelli = {
    '0,0': {
      transportation: strato([
        // La tangenziale a pedaggio, da ovest a est in mezzo alla tessera.
        { p: { class: 'motorway', oneway: 1, toll: 1 }, g: [[[0, 2048], [4096, 2048]]] },
        // E una stradina che entra in un capannone: quello resta un capannone.
        { p: { class: 'minor' }, g: [[[3000, 0], [3000, 1000]]] },
      ]),
      building: strato([
        { tipo: 3, p: { render_height: 8 }, g: quadro(1950, 2010, 2150, 2090) },
        { tipo: 3, p: { render_height: 9 }, g: quadro(2960, 400, 3040, 500) },
        { tipo: 3, p: { render_height: 12 }, g: quadro(300, 300, 400, 400) },
      ]),
    },
  };
  const t = costruisciTessera({ z: 14, x: X, y: Y, livelli });
  assert.equal(t.conti.edificiFatti, 3);
  // I metri di un punto della tessera, dal suo centro.
  const lat = Math.atan(Math.sinh(Math.PI * (1 - (2 * (Y + 0.5)) / 2 ** 14)));
  const k = (40075016.686 * Math.cos(lat)) / 2 ** 14 / 4096;
  const sopraLaPensilina = (x, y) => Math.abs(x) < 102 * k && Math.abs(y) < 44 * k;
  // Il tetto della pensilina: fra 5,4 e 6,1 metri, niente a terra.
  const zPensilina = [];
  const P = t.tetti.posizioni;
  for (let i = 0; i < P.length; i += 3) if (sopraLaPensilina(P[i], P[i + 1])) zPensilina.push(P[i + 2]);
  assert.ok(zPensilina.length > 12, 'il tetto e la fascia della pensilina');
  assert.ok(Math.min(...zPensilina) > 5.3 && Math.max(...zPensilina) < 6.2, `la pensilina fra ${Math.min(...zPensilina)} e ${Math.max(...zPensilina)} m`);
  // Nessuna facciata lì: sotto si passa. Le altre due case le hanno, da terra.
  let facciateLi = 0;
  let facciateATerra = 0;
  for (const g of Object.values(t.facciate)) {
    for (let i = 0; i < g.posizioni.length; i += 3) {
      if (sopraLaPensilina(g.posizioni[i], g.posizioni[i + 1])) facciateLi++;
      else if (g.posizioni[i + 2] < 0.5) facciateATerra++;
    }
  }
  assert.equal(facciateLi, 0, 'nessun muro sulle corsie');
  assert.ok(facciateATerra >= 16, `il capannone e la casa hanno i muri da terra (${facciateATerra})`);
  // I pilastri: ci sono, arrivano al ventre della pensilina, e nessuno sta sulla corsia.
  const O = t.opere.posizioni;
  let pilastri = 0;
  for (let i = 0; i < O.length; i += 3) {
    if (!sopraLaPensilina(O[i], O[i + 1])) continue;
    pilastri++;
    assert.ok(O[i + 2] < 5.45, `un pilastro più alto della pensilina (${O[i + 2]})`);
    assert.ok(Math.abs(O[i + 1]) > 6, `un pilastro in mezzo alla strada (${O[i + 1].toFixed(1)} m dal mezzo)`);
  }
  assert.ok(pilastri >= 4 * 20, `i pilastri (${pilastri} vertici)`);
});
