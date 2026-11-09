import assert from 'node:assert/strict';
import test from 'node:test';
import { IndiceSegmenti, Linea, Origine, Profilo, nastro, profiloDi, quote, riempiQuote } from '../src/percorso.js';

/** Segmenti finti: [x0,y0,z0,x1,y1,z1,w,codice]. */
function indice(segmenti) {
  const i = new IndiceSegmenti();
  i.aggiungi('t', new Float32Array(segmenti.flat()), 0, 0, 1);
  return i;
}

// Un viadotto a 7 m sopra una strada a terra, sulla stessa linea in pianta
// (come una rampa che corre sopra la carreggiata), e la rampa che sale.
const SEG = [
  [-400, 0, 0, 0, 0, 0, 10, 1],
  [0, 0, 0, 400, 0, 0, 10, 1],
  [-400, 2, 0, -130, 2, 0, 7, 17],
  [-130, 2, 0, 0, 2, 7, 7, 17],
  [0, 2, 7, 400, 2, 7, 7, 49],
];

test('la linea: metri, punti, direzione, proiezione', () => {
  const l = new Linea([0, 0, 100, 0, 100, 100]);
  assert.equal(l.lunghezza, 200);
  assert.deepEqual(l.a(150).slice(0, 2), [100, 50]);
  assert.ok(Math.abs(l.direzione(50, 5)) < 1e-9);
  const p = l.proietta(60, 10);
  assert.equal(p.s, 60);
  assert.equal(p.d, 10);
});

test('chi sale sul viadotto ci resta; chi sta sotto resta sotto', () => {
  const i = indice(SEG);
  // Sulla rampa (y = 2): sale e resta a 7 m anche dove sotto c'è la strada.
  const su = [];
  for (let x = -300; x <= 300; x += 4) su.push([x, 2]);
  const h = quote(su, i);
  assert.ok(Math.abs(h[0]) < 0.3, 'parte da terra');
  assert.ok(Math.abs(h[h.length - 1] - 7) < 0.3, `finisce sul viadotto (${h[h.length - 1]})`);
  // Sotto (y = -1): resta a terra, anche col viadotto a tre metri.
  const giu = [];
  for (let x = -300; x <= 300; x += 4) giu.push([x, -1]);
  const g = quote(giu, i);
  assert.ok(Math.max(...g.map((v, k) => (giu[k][0] > 100 ? v : 0))) < 0.5, 'sotto il viadotto a terra');
});

test('sotto un cavalcavia di sbieco la linea resta a terra, anche cambiando carreggiata', () => {
  // La strada a terra lungo x, interrotta fra 80 e 160 (il percorso lì passa
  // di lato, da una carreggiata alla rampa); sopra, a 8 m, un cavalcavia
  // che la taglia a 35°, largo 20 m.
  const a = (35 * Math.PI) / 180;
  const i = indice([
    [-300, 0, 0, 80, 0, 0, 10, 1],
    [160, 0, 0, 400, 0, 0, 10, 1],
    [120 - 300 * Math.cos(a), -300 * Math.sin(a), 8, 120 + 300 * Math.cos(a), 300 * Math.sin(a), 8, 20, 49],
  ]);
  const punti = [];
  for (let x = -100; x <= 300; x += 4) punti.push([x, 0]);
  const h = riempiQuote(quote(punti, i));
  assert.ok(Math.max(...h) < 0.5, `la linea sale sul ponte (${Math.max(...h).toFixed(1)} m)`);
});

test('la linea si appoggia sulla strada: tre metri di lato tornano in mezzo', () => {
  // «In alcuni punti la linea del percorso non è sulla strada.»
  const i = indice([[-400, 0, 0, 400, 0, 0, 10, 1]]);
  const l = new Linea([-300, 3, 300, 3]);
  const p = profiloDi(l, 0, 600, i);
  const [dx, dy] = p.sposta(300);
  assert.ok(Math.abs(dx) < 0.1 && Math.abs(dy + 3) < 0.1, `spostamento ${dx.toFixed(2)}, ${dy.toFixed(2)}`);
  const n = nastro(l, p, 250, 350, 4, 0.6);
  const ys = [];
  for (let k = 1; k < n.posizioni.length; k += 3) ys.push(n.posizioni[k]);
  const mezzo = (Math.max(...ys) + Math.min(...ys)) / 2;
  assert.ok(Math.abs(mezzo) < 0.2, `il nastro sta in mezzo alla strada (${mezzo.toFixed(2)})`);
  // Lontano dalle strade (oltre sei metri) non si sposta.
  const lontana = profiloDi(new Linea([-300, 20, 300, 20]), 0, 600, i);
  assert.deepEqual(lontana.sposta(300), [0, 0]);
});

test('i buchi: corti si riempiono, lunghi tornano a terra', () => {
  const h = riempiQuote([7, NaN, NaN, 7]);
  assert.ok(h.every((v) => Math.abs(v - 7) < 0.01));
  const lungo = riempiQuote([7, ...new Array(100).fill(NaN)], 50);
  assert.ok(lungo[lungo.length - 1] < 0.01);
});

test('il profilo e il nastro: quote, larghezza, code nette', () => {
  const l = new Linea([-300, 2, 300, 2]);
  const p = profiloDi(l, 0, 600, indice(SEG));
  assert.ok(p.quota(500) > 6.5);
  assert.ok(p.quota(10) < 0.5);
  const n = nastro(l, p, 0, 600, 4, 0.6, { code: [[100, 200, 3]] });
  assert.equal(n.posizioni.length / 3, n.uv.length / 2);
  // A ogni cambio di coda due stazioni: il colore cambia netto.
  const livelli = [...n.livelli];
  assert.ok(livelli.includes(3) && livelli.includes(0));
  const cambio = n.uv.findIndex((v, k) => k % 2 === 1 && v === 100);
  assert.ok(cambio > 0);
  for (let k = 0; k < n.indici.length; k += 3) {
    const lv = [n.indici[k], n.indici[k + 1], n.indici[k + 2]].map((v) => n.livelli[v]);
    assert.ok(lv.every((v) => v === lv[0]), 'un triangolo ha un livello solo');
  }
  // Largo 4 m.
  assert.ok(Math.abs(Math.hypot(n.posizioni[0] - n.posizioni[3], n.posizioni[1] - n.posizioni[4]) - 4) < 1e-4);
});

test('il profilo fuori dalla finestra tiene il capo', () => {
  const p = new Profilo(100, 4, Float64Array.from([1, 2, 3]));
  assert.equal(p.quota(0), 1);
  assert.equal(p.quota(106), 2.5);
  assert.equal(p.quota(1000), 3);
});

test("l'origine: metri e ritorno", () => {
  const o = new Origine(9.087, 45.517);
  const [x, y] = o.daLonLat(9.1, 45.52);
  assert.ok(x > 900 && x < 1100 && y > 300 && y < 360);
  const [lon, lat] = o.lonLat(x, y);
  assert.ok(Math.abs(lon - 9.1) < 1e-9 && Math.abs(lat - 45.52) < 1e-9);
});

test("l'indice: si toglie una tessera", () => {
  const i = indice(SEG);
  assert.ok(i.candidati(100, 0, 1, 0).length > 0);
  assert.ok(i.copre(0, 0));
  i.togli('t');
  assert.equal(i.candidati(100, 0, 1, 0).length, 0);
  assert.ok(i.vuoto);
});

test('la linea coi metri della guida: le posizioni seguono quelli', () => {
  const l = new Linea([0, 0, 100, 0, 200, 0], [0, 104, 208]);
  assert.equal(l.lunghezza, 208);
  assert.deepEqual(l.a(52).slice(0, 2), [50, 0]);
  assert.deepEqual(l.a(156).slice(0, 2), [150, 0]);
});

test('in galleria: i punti lo sanno, e il nastro lì ha il livello +10', () => {
  const i = new IndiceSegmenti();
  i.aggiungi('t', new Float32Array([-300, 0, 0, -50, 0, 0, 10, 3, -50, 0, 0.06, 50, 0, 0.06, 10, 3 + 64, 50, 0, 0, 300, 0, 0, 10, 3]), 0, 0, 1);
  const l = new Linea([-300, 0, 300, 0]);
  const p = profiloDi(l, 0, 600, i);
  assert.equal(p.gallerie.length, 1);
  const [da, a] = p.gallerie[0];
  assert.ok(Math.abs(da - 250) < 5 && Math.abs(a - 350) < 5, `${da}..${a}`);
  const n = nastro(l, p, 0, 600, 4, 0.6);
  assert.ok([...n.livelli].some((v) => v >= 10) && [...n.livelli].some((v) => v === 0));
});
