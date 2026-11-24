// Le parti pure della vista «Corsie» (`corsie.js`), su geometrie inventate
// in metri: nessun posto vero.
import assert from 'node:assert/strict';
import test from 'node:test';
import {
  IndiceCorsie,
  centroCorsia,
  corsiaDellAuto,
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
  riquadroCorsie,
  scegliCorsia,
  scostamentoPosa,
  sensoUnico,
  zoomCorsie,
  PIU_VICINO_CORSIE,
  ZOOM_MASSIMO_CORSIE,
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

/** Delle vie inventate in metri (`g` già in metri), pronte per [IndiceCorsie]. */
function inMetri(vie) {
  const strade = vie.map(normalizza);
  for (const v of strade) {
    v.xy = [];
    for (let i = 0; i < v.ll.length; i += 2) v.xy.push([v.ll[i], v.ll[i + 1]]);
    v.llVia = v.ll;
  }
  return new IndiceCorsie(strade);
}

test('senza percorso l\'auto sta nella sua corsia, a destra, non sulla riga di mezzo', () => {
  // Una via a doppio senso verso nord (una corsia per senso, 3 m), disegnata da sud a nord.
  const indice = inMetri([{ id: 1, hw: 'residential', g: [0, -300, 0, 300] }]);
  // Verso nord: la corsia di destra, 1,5 m a est (a destra = spostamento negativo).
  assert.ok(vicino(corsiaDellAuto(indice, 0, 0, 0), -1.5), `nord ${corsiaDellAuto(indice, 0, 0, 0)}`);
  // Verso sud, sulla stessa via: 1,5 m a ovest, che per chi va a sud è ancora la destra.
  assert.ok(vicino(corsiaDellAuto(indice, 0, 0, 180), -1.5));
  // Col GPS mezzo metro a est, verso nord: un metro in più a destra, sempre al mezzo della corsia.
  assert.ok(vicino(corsiaDellAuto(indice, 0.5, 0, 0), -1));
  // Di traverso, o lontano: niente.
  assert.equal(corsiaDellAuto(indice, 0, 0, 90), null);
  assert.equal(corsiaDellAuto(indice, 30, 0, 0), null);
  // Un senso unico a tre corsie: la più a destra; contromano niente.
  const uno = inMetri([{ id: 2, hw: 'primary', lanes: '3', oneway: 'yes', g: [0, -300, 0, 300] }]);
  assert.ok(vicino(corsiaDellAuto(uno, 0, 0, 0), -3.25));
  assert.equal(corsiaDellAuto(uno, 0, 0, 180), null);
  // Una corsia sola per i due sensi: nel mezzo.
  const stretta = inMetri([{ id: 3, hw: 'residential', lanes: '1', g: [0, -300, 0, 300] }]);
  assert.ok(vicino(corsiaDellAuto(stretta, 0, 0, 0), 0));
});

test('il riquadro di un messaggio corsie: vie, nodi, alberi; niente se è vuoto', () => {
  assert.deepEqual(riquadroCorsie({ strade: [{ g: [1, 2, 3, 4] }], nodi: [{ g: [0, 5] }], alberi: [[4, 1]] }), [0, 1, 4, 5]);
  assert.equal(riquadroCorsie({ strade: [] }), null);
});

test('vista «Corsie»: il tetto dello zoom vale per quello automatico, i tasti vanno oltre', () => {
  // In auto lo zoom di partenza era già sul tetto: «+» e «−» non cambiavano
  // niente, e premendo «−» si finiva lontani.
  const base = 19.5;
  assert.equal(zoomCorsie(base), ZOOM_MASSIMO_CORSIE);
  assert.equal(zoomCorsie(base + 1, 1), ZOOM_MASSIMO_CORSIE + 1);
  assert.equal(zoomCorsie(base - 1, -1), ZOOM_MASSIMO_CORSIE - 1);
  // Sotto il tetto, come prima: più vicino di PIU_VICINO_CORSIE.
  assert.equal(zoomCorsie(16), 16 + PIU_VICINO_CORSIE);
});

test('fra due rampe affiancate la fascia non salta dall\'una all\'altra', () => {
  // Due rampe a una corsia che partono dallo stesso nodo e poi corrono
  // affiancate a sette metri; la linea del calcolatore (una corda) va piano
  // dall'una all'altra. Prima, a metà, la via sotto passava a quella accanto
  // e la fascia saltava di lato sopra il parapetto.
  const indice = inMetri([
    { id: 1, hw: 'motorway_link', oneway: 'yes', g: [0, 0, 0, -400] },
    { id: 2, hw: 'motorway_link', oneway: 'yes', g: [0, 0, 7, -40, 7, -400] },
  ]);
  const punti = [];
  for (let s = 0; s <= 400; s += 4) punti.push([0.5 + (6 * s) / 400, -s]);
  const r = corsieLungoIlPercorso(punti, indice, { passo: 4 });
  const usate = new Set([...r.vie].filter((v) => v >= 0));
  assert.equal(usate.size, 1, `vie usate: ${[...usate]}`);
  // Il mezzo della corsia non fa mai un salto di lato.
  const centri = r.centri.filter(Boolean);
  for (let k = 1; k < centri.length; k++) {
    const salto = Math.abs(centri[k][0] - centri[k - 1][0]);
    assert.ok(salto < 1.5, `salto di ${salto.toFixed(1)} m al punto ${k}`);
  }
});

test('dove le due vie si toccano, il percorso passa dall\'una all\'altra', () => {
  // Una via che finisce e un'altra che parte dal suo capo, di sbieco: il
  // percorso le fa tutte e due.
  const indice = inMetri([
    { id: 1, hw: 'primary', oneway: 'yes', g: [0, 0, 0, -200] },
    { id: 2, hw: 'primary', oneway: 'yes', g: [0, -200, 60, -380] },
  ]);
  const punti = [];
  for (let s = 0; s <= 200; s += 4) punti.push([0, -s]);
  for (let s = 4; s <= 180; s += 4) punti.push([(60 * s) / 180, -200 - s]);
  const r = corsieLungoIlPercorso(punti, indice, { passo: 4 });
  const usate = new Set([...r.vie].filter((v) => v >= 0));
  assert.equal(usate.size, 2);
});

test('una rampa che entra o esce in mezzo alla carreggiata prende la corsia dalla sua parte', () => {
  // La carreggiata a due corsie non è spezzata dove le rampe la toccano:
  // una entra da destra in (0, 0), una esce a destra in (400, 0).
  const strade = [
    { id: 1, hw: 'trunk', oneway: 'yes', lanes: '2', g: [-400, 0, 0, 0, 400, 0, 800, 0] },
    { id: 2, hw: 'trunk_link', oneway: 'yes', g: [-300, -60, -120, -14, 0, 0] },
    { id: 3, hw: 'trunk_link', oneway: 'yes', g: [400, 0, 520, -14, 700, -60] },
    // E una da sinistra, più avanti (in un altro punto: un nodo in più sulla stessa via non c'è, ne serve un'altra).
    { id: 4, hw: 'trunk', oneway: 'yes', lanes: '2', g: [-400, 300, 0, 300, 400, 300] },
    { id: 5, hw: 'trunk_link', oneway: 'yes', g: [-300, 360, -120, 314, 0, 300] },
  ].map(normalizza);
  for (const v of strade) {
    v.xy = [];
    for (let i = 0; i < v.ll.length; i += 2) v.xy.push([v.ll[i], v.ll[i + 1]]);
  }
  const [carreggiata, entra, esce, , daSinistra] = strade;
  const r = raccordi(strade);
  // La corsia di destra della carreggiata: mezza corsia a destra della linea.
  const destra = centroCorsia(carreggiata, 1);
  assert.ok(destra < -1.5);
  assert.ok(vicino(r[1].o1, destra), `chi entra finisce sulla corsia di destra (${r[1].o1})`);
  assert.ok(r[1].t1 > 30 && r[1].t0 === 0);
  assert.ok(vicino(r[2].o0, destra), `chi esce parte dalla corsia di destra (${r[2].o0})`);
  assert.ok(r[2].t0 > 30 && r[2].t1 === 0);
  assert.ok(vicino(r[4].o1, centroCorsia(strade[3], 0)), `chi entra da sinistra finisce sulla corsia di sinistra (${r[4].o1})`);
  assert.deepEqual(r[0], { o0: 0, t0: 0, o1: 0, t1: 0 }, 'la carreggiata che passa resta dov’è');
  assert.ok(entra && esce && daSinistra);
});

test('a doppio senso la banchina è la stessa dei due sensi unici in cui la strada si divide', () => {
  const rampa = normalizza({ id: 1, hw: 'trunk_link', g: [0, 0, 100, 0] });
  const ramo = normalizza({ id: 2, hw: 'trunk_link', oneway: 'yes', g: [100, 0, 200, 0] });
  assert.ok(!rampa.senso && rampa.avanti === 1 && rampa.indietro === 1);
  assert.equal(rampa.margini[0], ramo.margini[1], 'a sinistra, la destra di chi va al contrario');
  assert.equal(rampa.margini[1], ramo.margini[1]);
  const superstrada = normalizza({ id: 3, hw: 'trunk', g: [0, 0, 100, 0] });
  const carreggiata = normalizza({ id: 4, hw: 'trunk', oneway: 'yes', lanes: '2', g: [100, 0, 200, 0] });
  assert.equal(superstrada.margini[1], carreggiata.margini[1]);
  assert.equal(superstrada.margini[0], carreggiata.margini[1]);
  // Le strade di città restano com'erano.
  assert.deepEqual(normalizza({ id: 5, hw: 'tertiary', g: [0, 0, 100, 0] }).margini, [0.35, 0.35]);
});
