import assert from 'node:assert/strict';
import test from 'node:test';
import { codeOrdinate, decodifica } from '../src/messaggi.js';
import { PASSO_30, PASSO_60, Ritmo, valutaPrestazioni, valutaWebgl } from '../src/capacita.js';

test('i messaggi buoni passano, quelli storti no', () => {
  assert.ok(decodifica({ v: 1, tipo: 'opzioni', notte: false, vista: 'inclinata', auto: '#d62a26' }));
  assert.ok(decodifica('{"v":1,"tipo":"pausa","si":true}'));
  assert.ok(decodifica({ v: 1, tipo: 'percorso', punti: [9, 45, 9.1, 45.1], code: [[0, 10, 2]] }));
  assert.ok(decodifica({ v: 1, tipo: 'percorso', punti: null }));
  assert.ok(decodifica({ v: 1, tipo: 'posizione', lat: 45, lon: 9, rotta: 10, metri: null, velocita: 3, quando: 1 }));
  assert.equal(decodifica({ v: 2, tipo: 'pausa', si: true }), null, 'altra versione');
  assert.equal(decodifica({ v: 1, tipo: 'boh' }), null);
  assert.equal(decodifica('{non json'), null);
  assert.equal(decodifica({ v: 1, tipo: 'percorso', punti: [9, 45, 9.1] }), null, 'coppie dispari');
  assert.equal(decodifica({ v: 1, tipo: 'posizione', lat: 95, lon: 9, rotta: 0, metri: null, velocita: 0, quando: 1 }), null);
  assert.equal(decodifica({ v: 1, tipo: 'posizione', lat: 45, lon: 9, rotta: 0, metri: null, velocita: NaN, quando: 1 }), null);
  assert.equal(decodifica({ v: 1, tipo: 'manovra', da: 20, a: 10 }), null);
  assert.ok(decodifica({ v: 1, tipo: 'manovra', da: null, a: null }));
  assert.equal(decodifica({ v: 1, tipo: 'camera', modo: 'vola' }), null);
});

test("la velocità dall'auto e gli edifici dall'app passano (prima si scartavano)", () => {
  // Come li manda l'app: `msgVelocita` e `msgEdifici` in lib/mappa/ponte_3d.dart.
  assert.ok(decodifica({ v: 1, tipo: 'velocita', ms: 13.4, alle: 1731234567890 }));
  assert.equal(decodifica({ v: 1, tipo: 'velocita', ms: -1, alle: 1 }), null);
  assert.ok(decodifica({ v: 1, tipo: 'edifici', z: 14, x: 8838, y: 6144, dati: 'GtfwBQ==' }));
  assert.ok(decodifica({ v: 1, tipo: 'edifici', z: 14, x: 8838, y: 6144, dati: null }));
  assert.equal(decodifica({ v: 1, tipo: 'edifici', z: 14, x: 1.5, y: 6144, dati: null }), null);
});

test('le code ordinate, con livelli da 1 a 4', () => {
  assert.deepEqual(codeOrdinate([[50, 60, 9], [10, 20, 1], [30, 30, 2], [5, 8, 0]]), [[10, 20, 1], [50, 60, 4]]);
});

test('WebGL: software e senza WebGL 2 non vanno', () => {
  assert.deepEqual(valutaWebgl({ webgl2: true, maxTrama: 8192, renderer: 'Adreno (TM) 619' }), { ok: true, motivo: null });
  assert.equal(valutaWebgl({ webgl2: false }).motivo, 'webgl2');
  assert.equal(valutaWebgl({ webgl2: true, maxTrama: 8192, renderer: 'Google SwiftShader' }).motivo, 'software');
  assert.equal(valutaWebgl({ webgl2: true, maxTrama: 2048, renderer: 'x' }).motivo, 'trame');
  assert.equal(valutaWebgl({ webgl2: true, maxTrama: 8192, renderer: 'Mali', memoria: 1 }).motivo, 'memoria');
});

test('le prestazioni: lento sotto i 20 fotogrammi', () => {
  assert.equal(valutaPrestazioni([33, 33]), null, 'troppo pochi');
  const veloce = valutaPrestazioni(new Array(100).fill(33));
  assert.ok(!veloce.lento && Math.abs(veloce.fps - 30.3) < 0.1);
  assert.ok(valutaPrestazioni(new Array(100).fill(60)).lento);
  assert.ok(valutaPrestazioni([...new Array(80).fill(33), ...new Array(20).fill(200)]).lento, 'scatti');
});

test('il percorso coi metri: tanti quanti i punti', () => {
  assert.ok(decodifica({ v: 1, tipo: 'percorso', punti: [9, 45, 9.1, 45.1], metri: [0, 13000] }));
  assert.equal(decodifica({ v: 1, tipo: 'percorso', punti: [9, 45, 9.1, 45.1], metri: [0] }), null);
});

test("le opzioni dicono se la pagina è sull'auto", () => {
  assert.ok(decodifica({ v: 1, tipo: 'opzioni', notte: false, inAuto: true }));
  assert.equal(decodifica({ v: 1, tipo: 'opzioni', notte: false, inAuto: 'si' }), null);
});

test('trenta o sessanta: dal passo vero dei fotogrammi, non dal tempo dei comandi', () => {
  // Un telefono che disegna un fotogramma al più ogni [capace] ms: va al
  // passo voluto, o più piano se non ce la fa.
  const r = new Ritmo();
  let t = 0;
  const corri = (secondi, capace, v = 10) => {
    for (const fine = t + secondi * 1000; t < fine; ) {
      t += Math.max(r.intervallo(v), capace);
      r.disegnato(t, r.intervallo(v));
    }
  };
  corri(3, 10);
  assert.equal(r.intervallo(10), PASSO_60, 'ce la fa: sessanta');
  assert.equal(r.intervallo(1), PASSO_30, 'da fermi trenta');
  corri(5, 10);
  assert.equal(r.intervallo(10), PASSO_60);
  // La scheda grafica non ci sta più dietro (un fotogramma ogni 25 ms, anche
  // se i comandi costano poco): si torna a trenta, e non si riprova subito.
  corri(3, 25);
  assert.equal(r.intervallo(10), PASSO_30);
  corri(10, 25);
  assert.equal(r.intervallo(10), PASSO_30, 'si riprova più tardi');
  // Passato il tempo si riprova; va male di nuovo, e si aspetta il doppio.
  corri(12, 25);
  assert.equal(r.attesa, 80000);
  // Un telefono che non sta dietro nemmeno a trenta: trenta, sempre.
  const lento = new Ritmo();
  t = 0;
  for (let i = 0; i < 2000; i++) {
    t += 45;
    lento.disegnato(t, lento.intervallo(10));
  }
  assert.equal(lento.intervallo(10), PASSO_30);
  // Le pause (la mappa ferma) non contano.
  const p = new Ritmo();
  for (let i = 0; i < 100; i++) p.disegnato(i * 1000, PASSO_30);
  assert.equal(p.campioni, 0);
});

test("sull'auto sempre trenta", () => {
  const r = new Ritmo({ fisso30: true });
  for (let i = 1; i < 300; i++) r.disegnato(i * PASSO_30, r.intervallo(20));
  assert.equal(r.intervallo(20), PASSO_30);
});
