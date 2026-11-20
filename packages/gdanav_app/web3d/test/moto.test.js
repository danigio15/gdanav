import assert from 'node:assert/strict';
import test from 'node:test';
import { Moto, angoloVerso, smorza } from '../src/moto.js';

test('smorza e angoloVerso', () => {
  assert.equal(smorza(0, 10, 0, 100), 0);
  assert.ok(smorza(0, 10, 100, 100) > 6);
  assert.equal(angoloVerso(350, 10, 0.5), 0);
  assert.equal(angoloVerso(10, 350, 1), 350);
});

test("l'auto va avanti con la velocità fra una lettura e l'altra", () => {
  const m = new Moto();
  m.posizione({ metri: 100, v: 20, quando: 0 });
  assert.equal(m.passo(0).s, 100);
  let s = 100;
  for (let t = 33; t <= 1000; t += 33) s = m.passo(t).s;
  assert.ok(s > 105 && s <= 120.5, `avanti (${s})`);
});

test('a velocità costante la freccia sta sulla posizione, non dietro', () => {
  // «Alcune volte è prima e altre dopo la posizione reale.»
  const m = new Moto();
  let s = 0;
  for (let t = 0; t <= 10000; t += 33) {
    if (t % 1000 < 33) m.posizione({ metri: 14 * (t / 1000), v: 14, quando: t });
    s = m.passo(t).s;
  }
  assert.ok(Math.abs(s - 140) < 1, `a 10 s deve stare a 140 m, sta a ${s.toFixed(1)}`);
});

test('frenando si ferma dove si ferma l\'auto, e oltre va solo quanto non si può sapere; mai indietro', () => {
  const m = new Moto();
  let s = 0;
  let massimo = 0;
  let indietro = 0;
  // 14 m/s per 5 s, poi frena fino a fermarsi a 80 m.
  for (let t = 0; t <= 13000; t += 33) {
    if (t % 1000 < 33) {
      const k = t / 1000;
      const metri = k <= 5 ? 14 * k : Math.min(80, 70 + 10 * (1 - Math.pow(1 - Math.min(1, (k - 5) / 2), 2)));
      const v = k <= 5 ? 14 : Math.max(0, 14 * (1 - (k - 5) / 2));
      m.posizione({ metri, v, quando: t });
    }
    const prima = s;
    s = m.passo(t).s;
    indietro = Math.max(indietro, prima - s);
    massimo = Math.max(massimo, s);
  }
  // Fino alla lettura dopo (un secondo) la frenata non si sa: l'ultima
  // lettura (70 m a 14 m/s) porta a 84 m. Oltre quello, poco.
  assert.ok(massimo < 87.5, `troppo oltre: ${massimo.toFixed(1)}`);
  // «Quando mi fermo la freccia va avanti e poi ritorna indietro»: no.
  assert.ok(indietro < 0.01, `è tornata indietro di ${indietro.toFixed(2)} m`);
  assert.ok(s >= 80 - 0.5 && s <= 87.5, `ferma a 80 o poco oltre, sta a ${s.toFixed(1)}`);
});

test('non torna mai indietro per poco, salta per tanto', () => {
  const m = new Moto();
  m.posizione({ metri: 100, v: 0, quando: 0 });
  m.passo(0);
  m.posizione({ metri: 98, v: 0, quando: 100 });
  assert.equal(m.passo(200).s, 100, 'resta lì: da ferma il GPS balla di qualche metro');
  m.posizione({ metri: 400, v: 0, quando: 300 });
  assert.equal(m.passo(300).s, 400, 'salta avanti');
});

test('ferma e arrivata', () => {
  const m = new Moto();
  assert.ok(m.fermo);
  m.posizione({ metri: 10, v: 0, quando: 0 });
  m.passo(0);
  assert.ok(m.fermo);
  m.posizione({ metri: 10, v: 5, quando: 0 });
  assert.ok(!m.fermo);
});

test('al semaforo, ferma un poco avanti alla lettura, è arrivata: la scena smette di disegnare', () => {
  const m = new Moto();
  // Andando a 15 m/s, poi il GPS dice ferma (e la freccia è già un poco oltre).
  let t = 0;
  for (let i = 0; i < 5; i++) {
    m.posizione({ metri: 100 + 15 * i, v: 15, quando: t });
    for (let k = 0; k < 30; k++) m.passo((t += 1000 / 30));
  }
  assert.ok(!m.fermo, 'andando non è ferma');
  const dove = 100 + 15 * 4 + 2;
  // La freccia resta dove si è fermata, un poco avanti: non torna indietro.
  let fermata = null;
  for (let i = 0; i < 12; i++) {
    m.posizione({ metri: dove, v: 0, quando: t });
    for (let k = 0; k < 30; k++) m.passo((t += 1000 / 30));
    if (i === 8) fermata = m.s;
  }
  // (Qui da 15 m/s a ferma di colpo: oltre gli otto metri torna, fino a lì.)
  assert.ok(m.s >= dove && m.s - dove <= 8.05, `ferma poco avanti: ${(m.s - dove).toFixed(2)}`);
  assert.ok(Math.abs(m.s - fermata) < 0.01, `ferma, resta lì (${fermata.toFixed(2)} → ${m.s.toFixed(2)})`);
  assert.ok(m.fermo, 'ferma: niente più fotogrammi');
  // Il GPS che da ferma balla (sotto la freccia) non la risveglia; una lettura in marcia sì.
  for (const balla of [2, 0.5, 1.5]) {
    m.posizione({ metri: dove + balla, v: 0, quando: t });
    m.passo((t += 33));
    assert.ok(m.fermo, `il GPS a ${balla} m`);
  }
  m.posizione({ metri: dove + 1, v: 4, quando: t });
  assert.ok(!m.fermo);
});

test('senza percorso: x, y e la rotta', () => {
  const m = new Moto();
  m.posizione({ metri: null, v: 10, x: 0, y: 0, rotta: 90, quando: 0 });
  const p = m.passo(1000);
  assert.ok(Math.abs(p.x - 10) < 1e-6 && Math.abs(p.y) < 1e-6);
});

test('senza percorso non torna mai indietro: il GPS che balla e le letture a 1 Hz', () => {
  // «Va a scatti»: verso nord a 10 m/s, una lettura al secondo, che balla
  // di due metri avanti e indietro. Prima la freccia inseguiva il punto e a
  // ogni lettura un poco indietro tornava indietro lungo la strada.
  const m = new Moto();
  const balla = [0, 2, -2, 1.5, -1.8, 2, -2, 0.5, -1, 2, -2];
  let y = null;
  let peggio = 0;
  let vMin = Infinity;
  let vMax = 0;
  for (let t = 0; t <= 10000; t += 33) {
    if (t % 1000 < 33) {
      const k = Math.round(t / 1000);
      m.posizione({ metri: null, v: 10, x: 0, y: 10 * k + balla[k], rotta: 0, quando: t });
    }
    const p = m.passo(t);
    if (y !== null && t > 1500) {
      peggio = Math.min(peggio, p.y - y);
      vMin = Math.min(vMin, (p.y - y) / 0.033);
      vMax = Math.max(vMax, (p.y - y) / 0.033);
    }
    y = p.y;
  }
  assert.ok(peggio >= 0, `mai indietro (${peggio.toFixed(3)} m in un fotogramma)`);
  assert.ok(vMin > 4 && vMax < 18, `la velocità mostrata resta vicina a quella vera (${vMin.toFixed(1)}–${vMax.toFixed(1)} m/s)`);
  assert.ok(Math.abs(y - 100) < 4, `a 10 s sta vicino ai 100 m (${y.toFixed(1)})`);
});

test('senza percorso, ferma un poco avanti alla lettura: resta lì, ed è arrivata', () => {
  const m = new Moto();
  m.posizione({ metri: null, v: 0, x: 0, y: 2, rotta: 0, quando: 0 });
  for (let t = 0; t <= 3000; t += 33) m.passo(t);
  // Il GPS balla indietro di due metri: la freccia non torna indietro.
  m.posizione({ metri: null, v: 0, x: 0, y: 0, rotta: 0, quando: 3000 });
  let p = null;
  for (let t = 3000; t <= 6000; t += 33) p = m.passo(t);
  assert.ok(Math.abs(p.y - 2) < 0.01, `resta a 2 m (${p.y.toFixed(2)})`);
  assert.equal(m.fermo, true);
  // Di lato invece ci va: la strada è lì.
  m.posizione({ metri: null, v: 0, x: 1, y: 0, rotta: 0, quando: 6000 });
  for (let t = 6000; t <= 9000; t += 33) p = m.passo(t);
  assert.ok(Math.abs(p.x - 1) < 0.05, `di lato sì (${p.x.toFixed(2)})`);
  // Sei metri indietro: resta lì, come i navigatori.
  m.posizione({ metri: null, v: 0, x: 1, y: -4, rotta: 0, quando: 9000 });
  for (let t = 9000; t <= 12000; t += 33) p = m.passo(t);
  assert.ok(Math.abs(p.y - 2) < 0.01, `sei metri: resta a 2 m (${p.y.toFixed(2)})`);
  // Oltre gli otto metri torna, piano.
  m.posizione({ metri: null, v: 0, x: 1, y: -25, rotta: 0, quando: 12000 });
  for (let t = 12000; t <= 20000; t += 33) p = m.passo(t);
  assert.ok(p.y < -16.5 && p.y > -17.2, `torna fino a otto metri dalla lettura (${p.y.toFixed(2)})`);
});

test('alle svolte, fermi o quasi, la freccia non gira prima dell\'auto', async () => {
  const { svolteDi } = await import('../src/moto.js');
  // Una L: 100 m verso est, poi 100 m verso nord. La svolta a 100 m.
  const linea = {
    s: [0, 100, 200],
    lunghezza: 200,
    a(m) {
      const q = Math.max(0, Math.min(200, m));
      return q <= 100 ? [q, 0] : [100, q - 100];
    },
  };
  const svolte = svolteDi(linea);
  assert.equal(svolte.length, 1);
  assert.ok(Math.abs(svolte[0] - 100) < 1);

  // Fermi a 6 m dall'angolo, col GPS che si aggancia oltre l'angolo e la
  // stima che va avanti: la freccia aspetta prima della svolta.
  const m = new Moto();
  m.svolte = svolte;
  m.posizione({ metri: 94, v: 0.2, quando: 1000, lettura: { metri: 94, alle: 950, v: 0.2 }, adesso: 1000 });
  m.passo(1000);
  m.posizione({ metri: 104, v: 0.2, quando: 2000, lettura: { metri: 104, alle: 1950, v: 0.2 }, adesso: 2000 });
  // Il GPS dice 104 (oltre l'angolo) ma andando piano: è passata davvero?
  // Sì, l'ultima lettura è oltre: la freccia può andare.
  assert.equal(m.primaDellaSvolta(103), Infinity);
  // Una stima avanti con l'ultima lettura prima dell'angolo: si aspetta.
  m.posizione({ metri: 95, v: 0.2, quando: 3000, lettura: { metri: 95, alle: 2950, v: 0.2 }, adesso: 3000 });
  assert.equal(m.primaDellaSvolta(103), 99);
  for (let t = 3000; t < 6000; t += 16) assert.ok(m.passo(t).s <= 99.01, `a ${t} ms oltre l'angolo`);
  // Andando (sopra 3 m/s) la svolta si fa, e non si tiene.
  m.posizione({ metri: 95, v: 8, quando: 7000, lettura: { metri: 95, alle: 6950, v: 8 }, adesso: 7000 });
  assert.equal(m.primaDellaSvolta(103), Infinity);
});

test('il profilo che si rifà non fa saltare la freccia: ci arriva piano', async () => {
  const { Raccordo } = await import('../src/moto.js');
  // «La navigazione continua a non essere fluida: va a scatti.» Il profilo
  // nuovo, dove si è, sposta di tre metri più in là del vecchio.
  const vecchio = { nome: 'vecchio' };
  const nuovo = { nome: 'nuovo' };
  const valori = (p, s) => (p === vecchio ? [0, 0, 1] : [3, 0, 1.5]);
  const r = new Raccordo(450);
  assert.deepEqual(r.passo(vecchio, 100, valori, 33), [0, 0, 0]);
  // Al cambio la correzione è la differenza: si resta dov'era.
  const [x, , z] = r.passo(nuovo, 100, valori, 33);
  assert.ok(Math.abs(x + 3) < 1e-9 && Math.abs(z + 0.5) < 1e-9, `${x}, ${z}`);
  // E si spegne: mai un passo più grande di quello di un fotogramma morbido.
  let prima = x;
  for (let t = 0; t < 3000; t += 33) {
    const [cx] = r.passo(nuovo, 100, valori, 33);
    assert.ok(Math.abs(cx - prima) < 0.25, `un salto di ${(cx - prima).toFixed(2)} m in un fotogramma`);
    prima = cx;
  }
  assert.ok(Math.abs(prima) < 0.01, `dopo tre secondi resta ${prima}`);
  // Un percorso nuovo (oltre otto metri) non si raccorda.
  const lontano = { nome: 'lontano' };
  const r2 = new Raccordo(450);
  r2.passo(vecchio, 10, (p) => (p === vecchio ? [0, 0, 0] : [20, 0, 0]), 33);
  assert.deepEqual(r2.passo(lontano, 10, (p) => (p === vecchio ? [0, 0, 0] : [20, 0, 0]), 33), [0, 0, 0]);
});

test('senza percorso e senza velocità dall\'app, la freccia va con le letture e non resta indietro', () => {
  // «Senza navigazione di nuovo fermo, non cammina»: l'app mandava zero
  // (la velocità rimasta dalla guida finita), e la freccia restava indietro.
  const m = new Moto();
  let t = 0;
  let y = 0;
  for (let k = 0; k < 10; k++) {
    m.posizione({ metri: null, v: 0, x: 0, y: 10 * k, rotta: 0, quando: t, adesso: t });
    for (let f = 0; f < 30; f++) {
      t += 1000 / 30;
      y = m.passo(t).y;
    }
  }
  // Dopo dieci secondi a 10 m/s: sulla lettura portata avanti, non trenta metri dietro.
  assert.ok(y > 95, `la freccia è a ${y.toFixed(1)} m`);
});

test('da fermi il GPS che balla non fa partire la freccia', () => {
  const m = new Moto();
  let t = 0;
  let y = 0;
  const balli = [0, 2.5, -1, 3, 0.5, -2, 2, 1, -1.5, 2.5];
  for (const b of balli) {
    m.posizione({ metri: null, v: 0, x: b * 0.5, y: b, rotta: 0, quando: t, adesso: t });
    for (let f = 0; f < 30; f++) {
      t += 1000 / 30;
      y = m.passo(t).y;
    }
  }
  assert.ok(y < 4, `la freccia è andata a ${y.toFixed(1)} m`);
});
