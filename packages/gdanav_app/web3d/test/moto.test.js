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

test('frenando si ferma dove si ferma l\'auto, e oltre va solo quanto non si può sapere', () => {
  const m = new Moto();
  let s = 0;
  let massimo = 0;
  // 14 m/s per 5 s, poi frena fino a fermarsi a 80 m.
  for (let t = 0; t <= 13000; t += 33) {
    if (t % 1000 < 33) {
      const k = t / 1000;
      const metri = k <= 5 ? 14 * k : Math.min(80, 70 + 10 * (1 - Math.pow(1 - Math.min(1, (k - 5) / 2), 2)));
      const v = k <= 5 ? 14 : Math.max(0, 14 * (1 - (k - 5) / 2));
      m.posizione({ metri, v, quando: t });
    }
    s = m.passo(t).s;
    massimo = Math.max(massimo, s);
  }
  // Fino alla lettura dopo (un secondo) la frenata non si sa: l'ultima
  // lettura (70 m a 14 m/s) porta a 84 m. Oltre quello, poco.
  assert.ok(massimo < 87.5, `troppo oltre: ${massimo.toFixed(1)}`);
  assert.ok(Math.abs(s - 80) <= 3.2, `ferma a 80, sta a ${s.toFixed(1)}`);
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

test('senza percorso: x, y e la rotta', () => {
  const m = new Moto();
  m.posizione({ metri: null, v: 10, x: 0, y: 0, rotta: 90, quando: 0 });
  const p = m.passo(1000);
  assert.ok(Math.abs(p.x - 10) < 1e-6 && Math.abs(p.y) < 1e-6);
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
