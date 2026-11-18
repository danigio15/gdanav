// Le parti pure della vista «Corsie» (`corsie.js`), su geometrie inventate
// in metri: nessun posto vero.
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  IndiceCorsie,
  centroCorsia,
  corsieAdatte,
  corsieDi,
  corsieLungoIlPercorso,
  direzioneManovra,
  frecceCorsie,
  larghezzaCorsia,
  liscia,
  normalizza,
  raccordi,
  riempi,
  scegliCorsia,
  scostamentoPosa,
  sensoUnico,
} from '../src/corsie.js';
import { decodifica } from '../src/messaggi.js';

const vicino = (a, b, e = 1e-6) => Math.abs(a - b) <= e;

test('la larghezza di una corsia secondo la classe', () => {
  assert.equal(larghezzaCorsia('motorway'), 3.75);
  assert.equal(larghezzaCorsia('motorway_link'), 3.5);
  assert.equal(larghezzaCorsia('trunk'), 3.5);
  assert.equal(larghezzaCorsia('primary'), 3.25);
  assert.equal(larghezzaCorsia('tertiary_link'), 3.25);
  assert.equal(larghezzaCorsia('residential'), 3.0);
});

test('quante corsie: dai tag, o quelle della classe', () => {
  assert.deepEqual(corsieDi({ hw: 'motorway' }), { avanti: 2, indietro: 0, condivisa: false }, "l'autostrada è a senso unico, due corsie");
  assert.deepEqual(corsieDi({ hw: 'motorway_link' }), { avanti: 1, indietro: 0, condivisa: false });
  assert.deepEqual(corsieDi({ hw: 'primary', lanes: '3' }), { avanti: 2, indietro: 1, condivisa: false });
  assert.deepEqual(corsieDi({ hw: 'primary', lanes: '4', 'lanes:backward': '1' }), { avanti: 3, indietro: 1, condivisa: false });
  assert.deepEqual(corsieDi({ hw: 'residential', lanes: '1' }), { avanti: 1, indietro: 0, condivisa: true });
  assert.deepEqual(corsieDi({ hw: 'residential' }), { avanti: 1, indietro: 1, condivisa: false });
  assert.deepEqual(corsieDi({ hw: 'secondary', oneway: 'yes', lanes: 'tre' }), { avanti: 1, indietro: 0, condivisa: false }, 'un numero storto non vale');
  assert.equal(sensoUnico({ hw: 'residential', junction: 'roundabout' }), 1);
  assert.equal(sensoUnico({ hw: 'motorway', oneway: 'no' }), 0);
  assert.equal(sensoUnico({ hw: 'primary', oneway: '-1' }), -1);
});

test('una via a senso unico al contrario si gira, coi tag avanti e indietro', () => {
  const v = normalizza({ id: 1, hw: 'primary', oneway: '-1', g: [0, 0, 10, 0, 20, 0], 'turn:lanes:backward': 'left|right', lanes: '2' });
  assert.deepEqual(v.ll, [20, 0, 10, 0, 0, 0]);
  assert.equal(v.senso, 1);
  assert.deepEqual(v.frecce, [['left'], ['right']]);
});

test('le frecce di turn:lanes, da sinistra a destra', () => {
  assert.deepEqual(frecceCorsie('left;through||right'), [['left', 'through'], [], ['right']]);
  assert.deepEqual(frecceCorsie('none|through;slight_right|boh'), [[], ['through', 'slight_right'], []]);
  assert.equal(frecceCorsie(undefined), null);
  // Le frecce che non tornano col numero delle corsie non si usano.
  assert.equal(normalizza({ id: 2, hw: 'primary', oneway: 'yes', lanes: '2', 'turn:lanes': 'left|through|right', g: [0, 0, 1, 0] }).frecce, null);
});

test('dove sono le corsie rispetto alla linea della via', () => {
  // `placement=middle_of:2` su quattro corsie: il mezzo delle corsie mezza corsia a destra della linea.
  assert.ok(vicino(scostamentoPosa('middle_of:2', 4, 0, 3.75), -1.875));
  assert.ok(vicino(scostamentoPosa('right_of:1', 2, 0, 3), 3 - 3));
  assert.equal(scostamentoPosa(undefined, 3, 0, 3.75), 0);
  const due = normalizza({ id: 3, hw: 'tertiary', g: [0, 0, 1, 0] });
  // Una corsia per senso: chi va avanti sta mezza corsia a destra, e così chi torna.
  assert.ok(vicino(centroCorsia(due, 0, true), -1.625));
  assert.ok(vicino(centroCorsia(due, 0, false), -1.625));
  const tre = normalizza({ id: 4, hw: 'motorway', lanes: '3', g: [0, 0, 1, 0] });
  assert.ok(vicino(centroCorsia(tre, 0), 3.75));
  assert.ok(vicino(centroCorsia(tre, 2), -3.75));
});

test('le corsie buone per una manovra, e quale prendere', () => {
  const uscita = frecceCorsie('|||slight_right');
  assert.deepEqual(corsieAdatte(uscita, 'slight_right'), [3]);
  assert.deepEqual(corsieAdatte(uscita, 'through'), [0, 1, 2]);
  assert.equal(scegliCorsia(4, 'through', [0, 1, 2]), 2, 'in Italia si tiene la destra');
  const incrocio = frecceCorsie('left|left;through|right');
  assert.deepEqual(corsieAdatte(incrocio, 'left'), [0, 1]);
  assert.equal(scegliCorsia(3, 'left', corsieAdatte(incrocio, 'left')), 0, 'a sinistra la più a sinistra');
  assert.equal(scegliCorsia(3, 'right'), 2);
  // Frecce che non dicono niente della manovra: le corsie dritte.
  assert.deepEqual(corsieAdatte(frecceCorsie('left|through'), 'right'), [1]);
});

test('la manovra conta anche l’ordine dei rami', () => {
  assert.equal(direzioneManovra(-11, [0]), 'slight_right', "la rampa d'uscita parte di poco ma è il ramo di destra");
  assert.equal(direzioneManovra(0, [-11]), 'through', 'chi resta in autostrada va dritto');
  assert.equal(direzioneManovra(-90, [0, 90]), 'right');
  assert.equal(direzioneManovra(85, [0]), 'left');
  assert.equal(direzioneManovra(2, [90, -90]), 'through');
  assert.equal(direzioneManovra(-140, [0]), 'sharp_right');
});

/** Un'uscita inventata: quattro corsie (l'ultima esce), poi tre dritte e una rampa a destra. */
function uscitaInventata() {
  const strade = [
    { id: 1, hw: 'motorway', lanes: '4', 'turn:lanes': '|||slight_right', g: [-600, 0, 0, 0] },
    { id: 2, hw: 'motorway', lanes: '3', g: [0, 0, 600, 0] },
    { id: 3, hw: 'motorway_link', g: [0, 0, 100, -25, 300, -110] },
  ].map(normalizza);
  for (const v of strade) {
    v.xy = [];
    for (let i = 0; i < v.ll.length; i += 2) v.xy.push([v.ll[i], v.ll[i + 1]]);
    v.llVia = v.ll;
  }
  const r = raccordi(strade);
  strade.forEach((v, i) => (v.raccordo = r[i]));
  return strade;
}

test('dove la carreggiata si divide, ogni ramo parte dalle sue corsie', () => {
  const [a, dritta, rampa] = uscitaInventata();
  // La rampa parte dalla corsia più a destra delle quattro (centrate sulla linea).
  assert.ok(vicino(rampa.raccordo.o0, centroCorsia(a, 3)), `rampa ${rampa.raccordo.o0}`);
  assert.ok(rampa.raccordo.t0 > 30);
  // Le tre dritte continuano le tre di sinistra: mezza corsia a sinistra.
  assert.ok(vicino(dritta.raccordo.o0, 1.875), `dritta ${dritta.raccordo.o0}`);
  assert.equal(a.raccordo.t1, 0, 'chi arriva resta dov’è');
});

test('il percorso che esce prende la corsia di decelerazione, quello dritto no', () => {
  const strade = uscitaInventata();
  const indice = new IndiceCorsie(strade);
  const lungo = (pezzi) => {
    const punti = [];
    for (const [a, b] of pezzi) {
      const n = Math.round(Math.hypot(b[0] - a[0], b[1] - a[1]) / 4);
      for (let k = punti.length ? 1 : 0; k <= n; k++) punti.push([a[0] + ((b[0] - a[0]) * k) / n, a[1] + ((b[1] - a[1]) * k) / n]);
    }
    return punti;
  };
  const esce = corsieLungoIlPercorso(
    lungo([
      [[-400, 0], [0, 0]],
      [[0, 0], [100, -25]],
    ]),
    indice,
  );
  assert.equal(esce.manovre.length, 1);
  assert.equal(esce.manovre[0].dir, 'slight_right');
  // Cento metri prima della divisione: sulla quarta corsia, 5,6 m a destra della linea.
  assert.equal(esce.corsie[75], 3);
  assert.ok(vicino(esce.sposta[75], centroCorsia(strade[0], 3), 0.05), `esce ${esce.sposta[75]}`);
  const dritto = corsieLungoIlPercorso(
    lungo([
      [[-400, 0], [0, 0]],
      [[0, 0], [300, 0]],
    ]),
    indice,
  );
  assert.equal(dritto.corsie[75], 2, 'la terza corsia: la più a destra che va dritta');
  assert.ok(vicino(dritto.sposta[75], centroCorsia(strade[0], 2), 0.05));
});

test('i suggerimenti di chi fa il percorso vincono sulle frecce', () => {
  const strade = uscitaInventata();
  const punti = [];
  for (let x = -400; x <= 0; x += 4) punti.push([x, 0]);
  for (let k = 1; k <= 25; k++) punti.push([k * 4, -k]);
  const r = corsieLungoIlPercorso(punti, new IndiceCorsie(strade), { suggerimenti: [{ s: 400, giuste: [false, false, true, true] }] });
  assert.equal(r.corsie[75], 3, 'fra le giuste, la più a destra per uscire');
});

test('i buchi si riempiono in linea retta, poi tutto si leviga', () => {
  assert.deepEqual([...riempi(Float64Array.from([NaN, 1, NaN, NaN, 4, NaN]))], [1, 1, 2, 3, 4, 4]);
  const scalino = liscia([0, 0, 0, 0, 3, 3, 3, 3], 1);
  for (let k = 1; k < 8; k++) assert.ok(scalino[k] >= scalino[k - 1]);
  assert.ok(scalino[3] > 0 && scalino[4] < 3);
});

test('i messaggi della vista «Corsie»', () => {
  assert.ok(decodifica({ v: 1, tipo: 'opzioni', notte: false, corsie: true }));
  assert.equal(decodifica({ v: 1, tipo: 'opzioni', notte: false, corsie: 'sì' }), null);
  const dati = { v: 1, strade: [{ id: 1, hw: 'primary', g: [10, 40, 10.001, 40], lanes: '2' }], nodi: [{ id: 2, g: [10, 40], highway: 'crossing' }] };
  assert.ok(decodifica({ v: 1, tipo: 'corsie', dati }));
  assert.ok(decodifica({ v: 1, tipo: 'corsie', dati: { ...dati, alberi: [[10, 40]], filari: [{ id: 3, g: [10, 40, 10.001, 40] }] } }));
  assert.equal(decodifica({ v: 1, tipo: 'corsie', dati: { ...dati, alberi: [[10]] } }), null, 'un albero senza latitudine');
  assert.equal(decodifica({ v: 1, tipo: 'corsie', dati: { strade: [{ hw: 'primary', g: [10, 40, 10.1] }] } }), null, 'coppie dispari');
  assert.equal(decodifica({ v: 1, tipo: 'corsie', dati: { v: 2, strade: [] } }), null, 'altra versione del formato');
  assert.ok(decodifica({ v: 1, tipo: 'manovra', da: 10, a: 100, corsie: [false, true], dove: 55 }));
  assert.equal(decodifica({ v: 1, tipo: 'manovra', da: 10, a: 100, corsie: 'destra' }), null);
});

test('il traffico sulla fascia della corsia: i colori delle code, solo sul tratto in coda', async () => {
  const { COLORI_CODA, glslColoreCoda } = await import('../src/tavolozza.js');
  const { Linea, Profilo, nastro } = await import('../src/percorso.js');
  // Gli stessi colori della linea del traffico sulla mappa (lo strato `code`).
  assert.deepEqual(COLORI_CODA, ['#F9A825', '#EF6C00', '#D32F2F', '#7B1F1F']);
  // Il GLSL generato, valutato in JavaScript: livello → colore.
  const colore = (livello) => {
    const vec3 = (r, g, b) => [r, g, b];
    // eslint-disable-next-line no-new-func
    return new Function('livello', 'vec3', `return ${glslColoreCoda()};`)(livello, vec3);
  };
  const daEsa = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);
  for (const [livello, esa] of [
    [1, '#F9A825'],
    [2, '#EF6C00'],
    [3, '#D32F2F'],
    [4, '#7B1F1F'],
  ]) {
    colore(livello).forEach((c, k) => assert.ok(Math.abs(c - daEsa(esa)[k]) < 0.002, `livello ${livello}`));
  }
  // La fascia: il livello della coda solo fra 100 e 300 metri.
  const linea = new Linea([0, 0, 500, 0]);
  const profilo = new Profilo(0, 4, new Array(126).fill(0));
  const n = nastro(linea, profilo, 0, 500, 2.7, 0.3, { code: [[100, 300, 2]] });
  for (let i = 0; i < n.livelli.length; i++) {
    const s = n.uv[2 * i + 1];
    if (s > 101 && s < 299) assert.equal(n.livelli[i], 2, `in coda a ${s}`);
    if (s < 99 || s > 301) assert.equal(n.livelli[i], 0, `libera a ${s}`);
  }
});
