import assert from 'node:assert/strict';
import test from 'node:test';
import { codeOrdinate, decodifica } from '../src/messaggi.js';
import { valutaPrestazioni, valutaWebgl } from '../src/capacita.js';

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
