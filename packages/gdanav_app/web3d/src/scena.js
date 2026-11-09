// La scena three.js: materiali, trame, le tessere costruite, il percorso
// all'altezza delle strade e l'auto rossa. Il disegno lo chiama lo strato
// di MapLibre (`principale.js`), con la sua telecamera.

import * as THREE from 'three';
import { mergeVertices } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { generatore } from './caso.js';
import { CAMPATA, NASTRI, PERIODO_STRADA, PIANO, STILI_FACCIATA } from './tessera.js';
import { GIORNO, NOTTE, SOLE } from './tavolozza.js';


/**
 * La chioma di una latifoglia: una sfera un poco bitorzoluta (80 triangoli,
 * 20 quella piccola accanto) con le normali morbide; non l'icosaedro a facce piatte di prima.
 */
function chiomaMorbida(dettaglio = 1) {
  const g = new THREE.IcosahedronGeometry(1, dettaglio);
  g.deleteAttribute('normal');
  g.deleteAttribute('uv');
  const p = g.getAttribute('position');
  const v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    // Bitorzoli fissi (dalla posizione, uguali per i vertici in comune).
    const k = 1 + 0.09 * Math.sin(v.x * 5.3 + v.y * 2.1) * Math.cos(v.z * 4.7 - v.x * 1.3);
    v.multiplyScalar(k);
    p.setXYZ(i, v.x, v.y, v.z);
  }
  // Le facce sono separate: si uniscono i vertici per avere le normali morbide.
  const unita = mergeVertices(g);
  unita.computeVertexNormals();
  return unita;
}

const tela = (w, h) => {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
};

function trama(c, ripeti = true) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = ripeti ? THREE.RepeatWrapping : THREE.ClampToEdgeWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  t.generateMipmaps = true;
  return t;
}

// ─── Gli alberi dipinti ───────────────────────────────────────────────────
//
// «Lo vedo sempre a cartone, lo voglio realistico: gli alberi non sono
// così.» Le chiome erano solidi (icosaedri, poi sfere): da vicino sempre
// palline. Adesso ogni albero è un'immagine dipinta qui, una volta sola —
// migliaia di foglie a piccoli tocchi, la luce da sinistra in alto, l'ombra
// dentro e sotto la chioma, il tronco coi rami — su un rettangolo che guarda
// sempre la telecamera (ruota solo attorno al suo asse, come un albero vero).
// Quattro alberi diversi: tre latifoglie e un abete. Due triangoli l'uno.

/** Le celle dell'atlante: larghe e alte, in pixel. */
const CELLA_L = 256;
const CELLA_A = 344;

/** L'atlante degli alberi: tre latifoglie e un abete, uno accanto all'altro. */
function atlanteAlberi() {
  const c = tela(CELLA_L * 4, CELLA_A);
  const g = c.getContext('2d');
  dipingiLatifoglia(g, 0, generatore(11), ['#2c4a22', '#4c7034', '#7da24c', '#a9c56a'], 0.46, 0.4);
  dipingiLatifoglia(g, CELLA_L, generatore(23), ['#29431f', '#43682e', '#6f9442', '#9cba5c'], 0.42, 0.44);
  dipingiLatifoglia(g, CELLA_L * 2, generatore(37), ['#33461f', '#57702f', '#87a046', '#b7c66c'], 0.36, 0.5);
  dipingiAbete(g, CELLA_L * 3, generatore(51));
  const t = trama(c, false);
  t.anisotropy = 1;
  return t;
}

/** Un colore fra quelli di [scala] (dal più scuro al più chiaro), con [l] fra 0 e 1. */
function tono(scala, l, r) {
  const x = Math.max(0, Math.min(0.999, l)) * (scala.length - 1);
  const i = Math.floor(x);
  const a = rgbDi(scala[i]);
  const b = rgbDi(scala[i + 1]);
  const t = x - i;
  const n = (r() - 0.5) * 18;
  return `rgb(${[0, 1, 2].map((k) => Math.round(a[k] + (b[k] - a[k]) * t + n)).join(',')})`;
}

function rgbDi(esa) {
  const v = parseInt(esa.slice(1), 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

/** Il tronco e due rami, dal basso al [fino] (frazione dell'altezza dall'alto). */
function tronco(g, cx, r, fino, largo) {
  const base = CELLA_A - 2;
  const cima = CELLA_A * fino;
  const grad = g.createLinearGradient(cx - largo, 0, cx + largo, 0);
  grad.addColorStop(0, '#5a4636');
  grad.addColorStop(0.45, '#46372b');
  grad.addColorStop(1, '#2a211a');
  g.fillStyle = grad;
  g.beginPath();
  g.moveTo(cx - largo, base);
  g.lineTo(cx - largo * 0.45, cima);
  g.lineTo(cx + largo * 0.45, cima);
  g.lineTo(cx + largo, base);
  g.closePath();
  g.fill();
  g.strokeStyle = '#3a2d22';
  for (const lato of [-1, 1]) {
    g.lineWidth = largo * 0.5;
    g.beginPath();
    const y0 = cima + (base - cima) * (0.25 + r() * 0.15);
    g.moveTo(cx, y0);
    g.quadraticCurveTo(cx + lato * largo * 2, y0 - 20, cx + lato * largo * (3 + r() * 2), y0 - 45 - r() * 20);
    g.stroke();
  }
}

/**
 * Una latifoglia nella cella che parte da [x0]: la chioma fatta di grappoli
 * ([raggio] e [alto]: quanto è larga e dove sta il centro, in frazioni).
 */
function dipingiLatifoglia(g, x0, r, scala, raggio, alto) {
  const cx = x0 + CELLA_L / 2;
  tronco(g, cx, r, alto + 0.12, CELLA_L * 0.035);
  const cy = CELLA_A * alto;
  const rx = CELLA_L * raggio;
  const ry = CELLA_A * (alto - 0.03);
  // I grappoli: cerchi dentro l'ellisse della chioma.
  const grappoli = [];
  for (let i = 0; i < 26; i++) {
    const a = r() * Math.PI * 2;
    const d = Math.sqrt(r()) * 0.72;
    const gr = (0.22 + r() * 0.18) * rx;
    grappoli.push({ x: cx + Math.cos(a) * d * (rx - gr * 0.6), y: cy + Math.sin(a) * d * (ry - gr * 0.6), r: gr });
  }
  // Prima l'ombra dentro la chioma, poi le foglie: le più scure dietro.
  const tocchi = [];
  for (let i = 0; i < 2600; i++) {
    const q = grappoli[Math.floor(r() * grappoli.length)];
    const a = r() * Math.PI * 2;
    const d = Math.sqrt(r());
    const x = q.x + Math.cos(a) * d * q.r;
    const y = q.y + Math.sin(a) * d * q.r;
    // Luce: dal grappolo (sinistra in alto) e dalla chioma (in alto più luce).
    const lg = -((x - q.x) * 0.6 + (y - q.y) * 0.8) / q.r;
    const lc = 1 - (y - (cy - ry)) / (2 * ry);
    const l = 0.18 + 0.38 * (lg * 0.5 + 0.5) * d + 0.4 * lc + (r() - 0.5) * 0.18;
    tocchi.push({ x, y, l, s: 2.2 + r() * 3.6, a: r() * Math.PI });
  }
  tocchi.sort((p, q) => p.l - q.l);
  for (const t of tocchi) {
    g.fillStyle = tono(scala, t.l, r);
    g.beginPath();
    g.ellipse(t.x, t.y, t.s, t.s * 0.62, t.a, 0, Math.PI * 2);
    g.fill();
  }
}

/** Un abete: palchi di rami dal basso alla punta, più scuri dentro. */
function dipingiAbete(g, x0, r) {
  const cx = x0 + CELLA_L / 2;
  tronco(g, cx, r, 0.9, CELLA_L * 0.03);
  const scala = ['#1d3420', '#2c4a2c', '#3f6337', '#5f8148'];
  const cima = 6;
  const base = CELLA_A * 0.9;
  const tocchi = [];
  for (let i = 0; i < 2600; i++) {
    const t = Math.pow(r(), 0.8);
    const y = cima + t * (base - cima);
    // I palchi: la larghezza va a dente di sega, più larga in basso.
    const palco = (t * 7) % 1;
    const largo = CELLA_L * 0.44 * t * (0.72 + 0.28 * palco);
    const x = cx + (r() * 2 - 1) * largo;
    const lato = (cx - x) / Math.max(1, largo);
    const l = 0.15 + 0.35 * (1 - t) + 0.25 * (lato * 0.5 + 0.5) + 0.3 * palco + (r() - 0.5) * 0.15;
    tocchi.push({ x, y, l, s: 2 + r() * 3, a: r() * 0.6 - 0.3 });
  }
  tocchi.sort((p, q) => p.l - q.l);
  for (const t of tocchi) {
    g.fillStyle = tono(scala, t.l, r);
    g.beginPath();
    g.ellipse(t.x, t.y, t.s * 1.4, t.s * 0.55, t.a, 0, Math.PI * 2);
    g.fill();
  }
}

const VERTICE_ALBERO = `
#include <common>
#include <fog_pars_vertex>
uniform float uPrima;
uniform float uQuante;
varying vec2 vUv;
varying vec3 vTinta;
void main() {
  mat4 m = modelMatrix * instanceMatrix;
  vec3 base = (m * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
  float largo = length((m * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
  float alto = length((m * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
  // La destra della telecamera, in pianta: l'albero gira solo attorno al suo asse.
  vec2 d = vec2(viewMatrix[0][0], viewMatrix[1][0]);
  vec3 destra = vec3(d / max(length(d), 1e-6), 0.0);
  vec3 mondo = base + destra * position.x * largo + vec3(0.0, 0.0, position.y * alto);
  vec4 mvPosition = viewMatrix * vec4(mondo, 1.0);
  gl_Position = projectionMatrix * mvPosition;
  // Quale albero dell'atlante, e girato o no: dal posto, sempre lo stesso.
  float h = fract(sin(dot(floor(base.xy * 0.7), vec2(12.9898, 78.233))) * 43758.5453);
  float cella = uPrima + floor(h * uQuante);
  float u = fract(h * 7.0) < 0.5 ? uv.x : 1.0 - uv.x;
  vUv = vec2((cella + u) / 4.0, uv.y);
  #ifdef USE_INSTANCING_COLOR
    vTinta = instanceColor;
  #else
    vTinta = vec3(1.0);
  #endif
  #include <fog_vertex>
}`;

const FRAMMENTO_ALBERO = `
#include <common>
#include <fog_pars_fragment>
uniform sampler2D uAtlante;
uniform float uNotte;
varying vec2 vUv;
varying vec3 vTinta;
void main() {
  vec4 t = texture2D(uAtlante, vUv);
  if (t.a < 0.5) discard;
  vec3 c = t.rgb * vTinta * mix(1.0, 0.5, uNotte);
  gl_FragColor = vec4(c, 1.0);
  #include <colorspace_fragment>
  #include <fog_fragment>
}`;

/** Il materiale degli alberi dipinti: [prima] la prima cella, [quante] fra cui scegliere. */
function materialeAlberi(atlante, notte, prima, quante) {
  return new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([
      THREE.UniformsLib.fog,
      { uAtlante: { value: null }, uNotte: { value: notte ? 1 : 0 }, uPrima: { value: prima }, uQuante: { value: quante } },
    ]),
    vertexShader: VERTICE_ALBERO,
    fragmentShader: FRAMMENTO_ALBERO,
    side: THREE.DoubleSide,
    fog: true,
  });
}

/** La trama d'asfalto di un tipo di strada, con le righe. */
function tramaStrada(nome, P, notte) {
  const ponte = nome.endsWith('-ponte');
  const tipo = nome === 'galleria' ? 'plain' : nome.replace('-ponte', '');
  const W = 128;
  const H = 512;
  const c = tela(W, H);
  const g = c.getContext('2d');
  const grande = tipo === 'motorway' || tipo === 'trunk' || tipo === 'ramp';
  g.fillStyle = ponte ? (grande ? P.asfaltoPonteGrande : P.asfaltoPonte) : grande ? P.asfaltoGrande : P.asfalto;
  g.fillRect(0, 0, W, H);
  const r = generatore(tipo.length * 977);
  for (let i = 0; i < 2600; i++) {
    const v = (r() - 0.5) * (notte ? 14 : 22);
    const b = v > 0 ? 255 : 0;
    g.fillStyle = `rgba(${b},${b},${b},${Math.abs(v) / 255})`;
    g.fillRect(r() * W, r() * H, 1 + r() * 2, 1 + r() * 2);
  }
  if (tipo !== 'rail') {
    g.fillStyle = notte ? 'rgba(0,0,0,0.06)' : 'rgba(0,0,0,0.05)';
    for (const x of [0.25, 0.42, 0.58, 0.75]) g.fillRect(x * W - 4, 0, 8, H);
  }
  g.fillStyle = P.righe;
  const riga = (x, tratteggio, wpx = 3, pieno = 4.5, periodo = 12) => {
    if (!tratteggio) {
      g.fillRect(x * W - wpx / 2, 0, wpx, H);
      return;
    }
    for (let k = 0; k < PERIODO_STRADA / periodo; k++) {
      g.fillRect(x * W - wpx / 2, ((k * periodo) / PERIODO_STRADA) * H, wpx, (pieno / PERIODO_STRADA) * H);
    }
  };
  if (tipo === 'motorway') {
    riga(0.05, false);
    riga(0.95, false);
    riga(0.35, true);
    riga(0.65, true);
  } else if (tipo === 'trunk') {
    riga(0.05, false);
    riga(0.95, false);
    riga(0.5, true);
  } else if (tipo === 'ramp') {
    riga(0.07, false);
    riga(0.93, false);
  } else if (tipo === 'primary2') {
    riga(0.04, false, 2);
    riga(0.96, false, 2);
    riga(0.5, true, 3, 3, 6);
  } else if (tipo === 'primary1') {
    riga(0.05, false, 2);
    riga(0.95, false, 2);
    riga(0.5, true, 3, 3, 6);
  } else if (tipo === 'tertiary') {
    riga(0.5, true, 2, 3, 6);
  } else if (tipo === 'rail') {
    g.fillStyle = notte ? '#3b3a3d' : '#8e8781';
    g.fillRect(0, 0, W, H);
    for (let i = 0; i < 1600; i++) {
      g.fillStyle = `rgba(${r() < 0.5 ? '255,255,255' : '0,0,0'},${r() * 0.12})`;
      g.fillRect(r() * W, r() * H, 2, 2);
    }
    g.fillStyle = notte ? '#3d3530' : '#6e5c4e';
    for (let k = 0; k < 20; k++) g.fillRect(14, (k * H) / 20, W - 28, (H / 20) * 0.35);
    g.fillStyle = notte ? '#9aa0aa' : '#c8ccd2';
    g.fillRect(W * 0.3 - 2, 0, 4, H);
    g.fillRect(W * 0.7 - 2, 0, 4, H);
  }
  return trama(c);
}

/**
 * Le facciate: quattro campate per quattro piani; il giorno e le finestre
 * accese di notte. «Vedo gli edifici sempre uguali»: una sola trama per
 * tipo faceva una città di fotocopie. Ora ogni tipo ha i suoi modelli
 * ([variante], vedi `VARIANTI_FACCIATA`):
 *
 *  - residenziale 0: finestre con le persiane verdi aperte;
 *  - residenziale 1: portefinestre con i balconi e la ringhiera, persiane marroni;
 *  - residenziale 2: palazzo d'epoca, finestre con la cornice e il timpano,
 *    una fascia a ogni piano;
 *  - residenziale 3: anni '70, finestre a nastro e balconi continui;
 *  - uffici 0: vetrata a griglia; uffici 1: nastri di vetro e marcapiani;
 *  - industria: finestre alte a nastro.
 *
 * La trama è bianca dove c'è il muro: il colore lo dà l'edificio.
 */
function trameFacciata(stile, seme, variante = 0) {
  const N = 4;
  const CW = 64;
  const Wp = N * CW;
  const c = tela(Wp, Wp);
  const e = tela(Wp, Wp);
  const g = c.getContext('2d');
  const h = e.getContext('2d');
  g.fillStyle = '#ffffff';
  g.fillRect(0, 0, Wp, Wp);
  h.fillStyle = '#000';
  h.fillRect(0, 0, Wp, Wp);
  const r = generatore(seme + variante * 101);
  // L'intonaco: macchie leggere, più fitte in basso (lo sporco della strada).
  for (let i = 0; i < 3500; i++) {
    g.fillStyle = `rgba(0,0,0,${r() * 0.05})`;
    g.fillRect(r() * Wp, r() * Wp, 2 + r() * 3, 2 + r() * 3);
  }
  const caldi = ['#ffd27a', '#ffe0a3', '#fff1cf', '#ffc46b', '#cfe1ff'];
  const persiane = variante === 1 ? ['#6e4a33', '#7a5236', '#654330'] : ['#4d7550', '#557d57', '#466c4a'];
  const vetro = (x, y, w, hh, freddo = false) => {
    const tono = 40 + Math.floor(r() * 30);
    g.fillStyle = freddo ? `rgb(${tono + 95},${tono + 115},${tono + 135})` : `rgb(${tono},${tono + 8},${tono + 20})`;
    g.fillRect(x, y, w, hh);
    const gr = g.createLinearGradient(0, y, 0, y + hh);
    gr.addColorStop(0, 'rgba(255,255,255,0.28)');
    gr.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = gr;
    g.fillRect(x, y, w, hh);
  };
  const anta = (x, y, w, hh) => {
    g.fillStyle = persiane[Math.floor(r() * persiane.length)];
    g.fillRect(x, y, w, hh);
    g.fillStyle = 'rgba(0,0,0,0.22)';
    for (let k = y + 3; k < y + hh - 1; k += 4) g.fillRect(x + 1, k, w - 2, 1);
  };
  for (let fy = 0; fy < N; fy++) {
    for (let bx = 0; bx < N; bx++) {
      const x0 = bx * CW;
      const y0 = fy * CW;
      let wx0;
      let wx1;
      let wy0;
      let wy1;
      if (stile === 'uffici' && variante === 1) {
        [wx0, wx1, wy0, wy1] = [0, 64, 8, 42];
        vetro(x0, y0 + wy0, CW, wy1 - wy0, true);
        g.fillStyle = 'rgba(210,218,226,0.95)';
        g.fillRect(x0 + 31, y0 + wy0, 2, wy1 - wy0);
        g.fillStyle = 'rgba(0,0,0,0.16)';
        g.fillRect(x0, y0 + wy1, CW, 3);
      } else if (stile === 'uffici') {
        [wx0, wx1, wy0, wy1] = [3, 61, 10, 52];
        vetro(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0, true);
        g.strokeStyle = 'rgba(255,255,255,0.9)';
        g.lineWidth = 2;
        g.strokeRect(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
        g.fillStyle = 'rgba(220,225,230,0.9)';
        g.fillRect(x0 + 31, y0 + wy0, 2, wy1 - wy0);
      } else if (stile === 'industria') {
        [wx0, wx1, wy0, wy1] = [0, 64, 14, 30];
        if (fy % 2) {
          g.fillStyle = 'rgba(0,0,0,0.10)';
          g.fillRect(x0 + 31, y0, 2, CW);
          continue;
        }
        vetro(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
      } else if (variante === 1) {
        // Portafinestra, balcone e ringhiera.
        [wx0, wx1, wy0, wy1] = [23, 41, 8, 58];
        vetro(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
        anta(x0 + wx0 - 9, y0 + wy0, 8, wy1 - wy0);
        anta(x0 + wx1 + 1, y0 + wy0, 8, wy1 - wy0);
        g.fillStyle = 'rgba(0,0,0,0.38)';
        g.fillRect(x0 + 8, y0 + 59, 48, 4);
        g.fillStyle = 'rgba(40,40,40,0.75)';
        g.fillRect(x0 + 8, y0 + 44, 48, 2);
        for (let k = x0 + 9; k < x0 + 56; k += 4) g.fillRect(k, y0 + 44, 1, 15);
      } else if (variante === 2) {
        // Palazzo d'epoca: cornice, timpano, fascia al piano.
        [wx0, wx1, wy0, wy1] = [21, 43, 16, 52];
        g.fillStyle = 'rgba(0,0,0,0.13)';
        g.fillRect(x0 + wx0 - 4, y0 + wy0 - 4, wx1 - wx0 + 8, wy1 - wy0 + 8);
        g.fillStyle = '#ffffff';
        g.fillRect(x0 + wx0 - 2, y0 + wy0 - 2, wx1 - wx0 + 4, wy1 - wy0 + 4);
        vetro(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
        g.fillStyle = 'rgba(0,0,0,0.3)';
        g.fillRect(x0 + wx0 - 5, y0 + wy0 - 8, wx1 - wx0 + 10, 3);
        g.fillRect(x0 + wx0 - 3, y0 + wy1 + 3, wx1 - wx0 + 6, 3);
        g.fillStyle = 'rgba(0,0,0,0.12)';
        g.fillRect(x0, y0 + 61, CW, 3);
      } else if (variante === 3) {
        // Anni '70: finestra larga e balcone continuo col parapetto pieno.
        [wx0, wx1, wy0, wy1] = [6, 58, 12, 38];
        vetro(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
        g.fillStyle = 'rgba(255,255,255,0.85)';
        g.fillRect(x0 + 31, y0 + wy0, 2, wy1 - wy0);
        g.fillStyle = 'rgba(0,0,0,0.2)';
        g.fillRect(x0, y0 + 42, CW, 18);
        g.fillStyle = 'rgba(0,0,0,0.4)';
        g.fillRect(x0, y0 + 60, CW, 4);
      } else {
        // Finestre con le persiane aperte e il davanzale.
        [wx0, wx1, wy0, wy1] = [22, 42, 12, 50];
        vetro(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
        if (r() < 0.85) {
          anta(x0 + wx0 - 10, y0 + wy0, 9, wy1 - wy0);
          anta(x0 + wx1 + 1, y0 + wy0, 9, wy1 - wy0);
        } else anta(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
        g.fillStyle = 'rgba(0,0,0,0.3)';
        g.fillRect(x0 + wx0 - 3, y0 + wy1, wx1 - wx0 + 6, 3);
      }
      const accesa = r() < (stile === 'industria' ? 0.25 : stile === 'uffici' ? 0.45 : 0.42);
      if (accesa) {
        h.fillStyle = caldi[Math.floor(r() * caldi.length)];
        h.globalAlpha = 0.55 + r() * 0.45;
        h.fillRect(x0 + wx0 + 1, y0 + wy0 + 1, wx1 - wx0 - 2, wy1 - wy0 - 2);
        h.globalAlpha = 1;
        if (stile === 'residenziale' && r() < 0.5) {
          h.fillStyle = 'rgba(0,0,0,0.6)';
          h.fillRect(x0 + wx0 + 1, y0 + wy0 + 1, wx1 - wx0 - 2, (wy1 - wy0) * (0.2 + r() * 0.5));
        }
      }
    }
  }
  g.fillStyle = 'rgba(0,0,0,0.06)';
  for (let fy = 0; fy < N; fy++) g.fillRect(0, fy * CW, Wp, 3);
  return [trama(c), trama(e)];
}

/** Il bit dello stencil delle ombre a terra (vedi `Scena.materiali`). */
export const BIT_OMBRA = 0x80;

/** Una geometria three.js dai dati del lavoratore. */
function geometria(d, notte) {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(d.posizioni, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(d.normali, 3, true));
  if (d.uv) g.setAttribute('uv', new THREE.BufferAttribute(d.uv, 2));
  if (d.colori) {
    g.userData.colori = [new THREE.BufferAttribute(d.colori, 3, true), new THREE.BufferAttribute(d.coloriNotte, 3, true)];
    g.setAttribute('color', g.userData.colori[notte ? 1 : 0]);
  }
  g.setIndex(new THREE.BufferAttribute(d.indici, 1));
  g.computeBoundingSphere();
  return g;
}

function istanze(geo, materiale, matrici, colori) {
  const n = matrici.length / 16;
  const m = new THREE.InstancedMesh(geo, materiale, n);
  m.instanceMatrix = new THREE.InstancedBufferAttribute(matrici, 16);
  if (colori) m.instanceColor = new THREE.InstancedBufferAttribute(Float32Array.from(colori, (v) => v / 255), 3);
  m.computeBoundingSphere();
  return m;
}

const VERTICE_NASTRO = `
attribute float livello;
varying vec2 vUv;
varying float vLivello;
void main() {
  vUv = uv;
  vLivello = livello;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;

/** Il nastro del percorso: celeste, bordo blu, frecce bianche, la coda in mezzo. */
const FRAMMENTO_NASTRO = `
uniform vec3 uCore;
uniform vec3 uBordo;
uniform float uLargo;
uniform float uPasso;
uniform float uNotte;
uniform float uInizio;
uniform float uFrecce;
uniform float uOpacita;
uniform float uSotto;
varying vec2 vUv;
varying float vLivello;
void main() {
  float e = abs(vUv.x - 0.5) * 2.0;
  // In galleria (+10): il percorso si vede «dentro», più tenue e tratteggiato.
  float galleria = vLivello > 9.5 ? 1.0 : 0.0;
  float livello = vLivello - galleria * 10.0;
  vec3 c = mix(uCore, uBordo, smoothstep(0.70, 0.80, e));
  c = mix(c, vec3(1.0), 0.18 * (1.0 - smoothstep(0.0, 0.45, e)));
  // La coda: una striscia in mezzo, il celeste ai lati (come in stile.dart).
  if (livello > 0.5) {
    vec3 coda = livello < 1.5 ? vec3(0.976, 0.659, 0.145) : livello < 2.5 ? vec3(0.937, 0.424, 0.0) : livello < 3.5 ? vec3(0.827, 0.184, 0.184) : vec3(0.482, 0.122, 0.122);
    c = mix(c, coda, 1.0 - smoothstep(0.46, 0.52, e));
  }
  float w = abs(vUv.x - 0.5) * uLargo;
  // La punta in avanti: in mezzo più avanti, ai lati più indietro («le frecce
  // sul percorso sono al contrario»: era la punta indietro).
  float t = fract((vUv.y + w * 1.1) / uPasso);
  float chev = (1.0 - smoothstep(0.0, 0.06, abs(t - 0.06) - 0.03)) * (1.0 - smoothstep(0.50, 0.56, e)) * uFrecce * (1.0 - uSotto);
  c = mix(c, vec3(1.0), chev * 0.92);
  float a = 1.0 - smoothstep(0.93, 1.0, e);
  a *= smoothstep(uInizio, uInizio + 6.0, vUv.y);
  // In galleria quasi piena, con un tratteggio leggero: «rendi più visibile la
  // linea nelle gallerie» (prima metà tenue, a strisce).
  a *= mix(1.0, 0.82 + 0.18 * step(0.5, fract(vUv.y / 8.0)), galleria);
  // Il tratto coperto (sotto un cavalcavia, dietro un palazzo): tratteggiato
  // e senza frecce, così si capisce che passa sotto e non sopra.
  a *= mix(1.0, 0.1 + 0.9 * step(0.5, fract(vUv.y / 6.0)), uSotto);
  gl_FragColor = vec4(c * (1.0 + 0.35 * uNotte), a * 0.97 * uOpacita);
  #include <colorspace_fragment>
}`;

const FRAMMENTO_ALONE = `
uniform vec3 uCore;
uniform float uNotte;
uniform float uInizio;
varying vec2 vUv;
varying float vLivello;
void main() {
  float e = abs(vUv.x - 0.5) * 2.0;
  float a = exp(-e * e * 5.0) * (uNotte > 0.5 ? 0.55 : 0.28);
  a *= smoothstep(uInizio, uInizio + 10.0, vUv.y);
  gl_FragColor = vec4(uCore * (uNotte > 0.5 ? 1.2 : 1.0), a);
  #include <colorspace_fragment>
}`;

const FRAMMENTO_FRECCIA = `
varying vec2 vUv;
varying float vLivello;
void main() {
  float e = abs(vUv.x - 0.5) * 2.0;
  vec3 c = mix(vec3(1.0), vec3(0.043, 0.235, 0.47), step(0.62, e));
  gl_FragColor = vec4(c, 1.0);
  #include <colorspace_fragment>
}`;

const FRAMMENTO_CODA = `
uniform float uNotte;
varying vec2 vUv;
varying float vLivello;
void main() {
  float e = abs(vUv.x - 0.5) * 2.0;
  vec3 c = vLivello < 1.5 ? vec3(0.961, 0.651, 0.137) : vec3(0.898, 0.188, 0.165);
  float a = (1.0 - smoothstep(0.75, 1.0, e)) * 0.92;
  gl_FragColor = vec4(c * (1.0 + 0.2 * uNotte), a);
  #include <colorspace_fragment>
}`;

/** Il colore da «#rrggbb» per three.js. */
const colore = (h) => new THREE.Color(h);

export class Scena {
  constructor() {
    this.scena = new THREE.Scene();
    this.mondo = new THREE.Group();
    this.scena.add(this.mondo);
    this.tessere = new Map();
    this.notte = null;
    this.emisferica = new THREE.HemisphereLight(0xdbe8ff, 0x8d917f, 1.35);
    this.sole = new THREE.DirectionalLight(0xfff0d8, 2.3);
    const az = (SOLE.azimut * Math.PI) / 180;
    const el = (SOLE.altezza * Math.PI) / 180;
    this.sole.position.set(Math.sin(az) * Math.cos(el), Math.cos(az) * Math.cos(el), Math.sin(el));
    // Le luci valgono anche per lo strato dell'auto (livello 1, sopra i nomi).
    this.emisferica.layers.enableAll();
    this.sole.layers.enableAll();
    this.scena.add(this.emisferica, this.sole);
    this.scena.fog = new THREE.Fog(0xe2eaf1, 400, 3000);
    // La foschia lontana sopra il suolo di MapLibre.
    this.materialeFoschia = new THREE.ShaderMaterial({
      uniforms: { uColor: { value: colore('#e2eaf1') }, uNear: { value: 1 }, uFar: { value: 2 } },
      transparent: true,
      depthWrite: false,
      vertexShader: 'varying float vD; void main(){ vec4 mv = modelViewMatrix*vec4(position,1.0); vD = -mv.z; gl_Position = projectionMatrix*mv; }',
      fragmentShader: `uniform vec3 uColor; uniform float uNear; uniform float uFar; varying float vD; void main(){ float f = smoothstep(uNear,uFar,vD); gl_FragColor = vec4(uColor, f*0.95);
#include <colorspace_fragment>
}`,
    });
    this.foschia = new THREE.Mesh(new THREE.PlaneGeometry(60000, 60000), this.materialeFoschia);
    this.foschia.position.z = 0.01;
    this.foschia.renderOrder = -10;
    this.foschia.frustumCulled = false;
    this.scena.add(this.foschia);
    // Le geometrie delle istanze, uguali per tutte le tessere.
    const fusto = new THREE.CylinderGeometry(0.75, 0.85, 1, 12, 1, true);
    fusto.rotateX(Math.PI / 2);
    fusto.translate(0, 0, 0.5);
    const capitello = new THREE.BoxGeometry(1, 1, 1);
    capitello.translate(0, 0, 0.5);
    const tronco = new THREE.CylinderGeometry(0.13, 0.2, 1, 5, 1, true);
    tronco.rotateX(Math.PI / 2);
    tronco.translate(0, 0, 0.5);
    const cono = new THREE.ConeGeometry(1, 1, 7, 1, true);
    cono.rotateX(Math.PI / 2);
    cono.translate(0, 0, 0.5);
    const palo = new THREE.CylinderGeometry(0.09, 0.13, 1, 6, 1, true);
    palo.rotateX(Math.PI / 2);
    palo.translate(0, 0, 0.5);
    this.geo = {
      fusto,
      capitello,
      tronco,
      // Il rettangolo di un albero dipinto: largo 1, da terra (0) alla cima (1).
      albero: (() => {
        const q = new THREE.PlaneGeometry(1, 1);
        q.translate(0, 0.5, 0);
        return q;
      })(),
      chioma: chiomaMorbida(),
      // La chioma piccola accanto: meno triangoli, morbida uguale.
      chioma2: chiomaMorbida(0),
      cono,
      palo,
      testa: new THREE.BoxGeometry(1, 1, 1),
      pozza: new THREE.PlaneGeometry(1, 1),
    };
    this.uniformiPercorso = {
      uCore: { value: colore(GIORNO.percorso) },
      uBordo: { value: colore(GIORNO.percorsoBordo) },
      uLargo: { value: 4.6 },
      uPasso: { value: 16 },
      uNotte: { value: 0 },
      uInizio: { value: -1e9 },
      uFrecce: { value: 1 },
      uOpacita: { value: 1 },
      uSotto: { value: 0 },
    };
    // Il «fantasma» del percorso: lo stesso nastro, disegnato solo dove
    // qualcosa ci sta davanti (un cavalcavia, un edificio), tenue e
    // tratteggiato. Quasi pieno (85%) sembrava passare sopra il ponte: «la
    // linea non può salire sul ponte se la strada è sotto».
    this.uniformiFantasma = { ...this.uniformiPercorso, uInizio: { value: -1e9 }, uOpacita: { value: 0.32 }, uSotto: { value: 1 } };
    // Gli edifici di vetro attorno all'auto (vedi [vetroVicino]).
    this.uniformiEdifici = {
      uAuto: { value: new THREE.Vector2(1e9, 1e9) },
      uDir: { value: new THREE.Vector2(1, 0) },
      // Dov'è l'auto sullo schermo (coordinate -1..1 e profondità), e lo schermo in pixel.
      uAutoSchermo: { value: new THREE.Vector3(0, -2, -1) },
      uSchermo: { value: new THREE.Vector2(1, 1) },
      uFinestreTenui: { value: 0.45 },
      // Un po' di luce propria sui tetti di giorno: chiari come da sopra.
      uLuceTetti: { value: 0.12 },
    };
    this.uniformiRisparmio = {
      uCore: { value: colore('#4ADE80') },
      uBordo: { value: colore('#166534') },
      uLargo: { value: 4 },
      uPasso: { value: 16 },
      uNotte: { value: 0 },
      uInizio: { value: -1e9 },
      uFrecce: { value: 0 },
      uOpacita: { value: 1 },
      uSotto: { value: 0 },
    };
    this.uniformiFatto = {
      uCore: { value: colore('#7f9fc9') },
      uBordo: { value: colore('#4f6f99') },
      uLargo: { value: 3.6 },
      uPasso: { value: 16 },
      uNotte: { value: 0 },
      uInizio: { value: -1e9 },
      uFrecce: { value: 0 },
      uOpacita: { value: 0.85 },
      uSotto: { value: 0 },
    };
    this.nastri = {};
    this.colorAuto = '#d62a26';
    this.impostaNotte(false);
  }

  /** Giorno o notte: luci, nebbia, materiali, colori degli edifici. */
  impostaNotte(notte) {
    if (this.notte === notte) return;
    this.notte = notte;
    const P = notte ? NOTTE : GIORNO;
    this.P = P;
    // Di notte le finestre accese restano tutte.
    this.uniformiEdifici.uFinestreTenui.value = notte ? 0 : 0.45;
    this.uniformiEdifici.uLuceTetti.value = notte ? 0 : 0.12;
    this.emisferica.color.set(notte ? 0x4a5d8c : 0xdbe8ff);
    this.emisferica.groundColor.set(notte ? 0x141a26 : 0xc4bcae);
    this.emisferica.intensity = notte ? 0.75 : 1.35;
    this.sole.color.set(notte ? 0x9db2ff : 0xfff0d8);
    this.sole.intensity = notte ? 0.5 : 2.3;
    this.scena.fog.color.set(P.nebbia);
    this.materialeFoschia.uniforms.uColor.value.set(P.nebbia);
    for (const u of [this.uniformiPercorso, this.uniformiRisparmio]) u.uNotte.value = notte ? 1 : 0;
    this.uniformiPercorso.uCore.value.set(P.percorso);
    this.uniformiPercorso.uBordo.value.set(P.percorsoBordo);
    const vecchi = this.mat;
    this.mat = this.materiali(notte, P);
    this.rivestiNastri();
    // Le tessere già costruite: materiali nuovi, colori della notte o del giorno.
    for (const t of this.tessere.values()) this.vestiTessera(t);
    if (vecchi) for (const m of Object.values(vecchi)) if (m.dispose) m.dispose();
    if (this.auto) this.creaAuto(this.colorAuto);
  }

  materiali(notte, P) {
    const m = {};
    for (const tipo of NASTRI) {
      m['strada-' + tipo] = new THREE.MeshLambertMaterial({ map: tramaStrada(tipo, P, notte), polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -2 });
    }
    // La galleria: la strada che passa sotto, scura e un poco trasparente.
    Object.assign(m['strada-galleria'], { transparent: true, opacity: notte ? 0.5 : 0.55, depthWrite: false });
    m['strada-galleria'].color.set(notte ? 0x3a3f4a : 0x5d636c);
    m.opere = new THREE.MeshLambertMaterial({ vertexColors: true, side: THREE.DoubleSide });
    // Un poco di luce propria, nel colore del cemento: anche il fianco in
    // ombra di un ponte tiene il cordolo chiaro e la trave scura.
    const lucePropria = notte ? 0.12 : 0.24;
    m.opere.onBeforeCompile = (sh) => {
      sh.fragmentShader = sh.fragmentShader.replace(
        '#include <emissivemap_fragment>',
        `#include <emissivemap_fragment>
        totalEmissiveRadiance += diffuseColor.rgb * ${lucePropria.toFixed(2)};`,
      );
    };
    m.opere.customProgramCacheKey = () => 'opere-' + lucePropria;
    // Le ombre vincono sull'asfalto (che ha il suo polygonOffset), non sul resto.
    m.ombre = new THREE.MeshBasicMaterial({ color: 0x0c1220, transparent: true, opacity: P.ombra, depthWrite: true, depthFunc: THREE.LessDepth, fog: true, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -6 });
    m.ombrePonti = m.ombre.clone();
    m.ombrePonti.opacity = P.ombraPonte;
    // Ogni punto del suolo si scurisce una volta sola: l'ombra di un muro e
    // quella del tetto si sovrappongono, e col solo depth test litigavano a
    // righe («palazzi trasparenti»). Il bit alto dello stencil segna i punti
    // già in ombra; `principale.js` lo pulisce prima e dopo la scena.
    Object.assign(m.ombre, {
      stencilWrite: true,
      stencilRef: BIT_OMBRA,
      stencilFuncMask: BIT_OMBRA,
      stencilWriteMask: BIT_OMBRA,
      stencilFunc: THREE.NotEqualStencilFunc,
      stencilZPass: THREE.ReplaceStencilOp,
      depthWrite: false,
    });
    // Sotto gli alberi una macchia tonda e sfumata: più scura al centro.
    const to = tela(64, 64);
    const tg = to.getContext('2d');
    const go = tg.createRadialGradient(32, 32, 0, 32, 32, 32);
    go.addColorStop(0, 'rgba(255,255,255,1)');
    go.addColorStop(0.3, 'rgba(255,255,255,0.75)');
    go.addColorStop(0.65, 'rgba(255,255,255,0.25)');
    go.addColorStop(1, 'rgba(255,255,255,0)');
    tg.fillStyle = go;
    tg.fillRect(0, 0, 64, 64);
    m.ombreAlberi = new THREE.MeshBasicMaterial({ color: 0x0c1220, alphaMap: trama(to, false), transparent: true, opacity: P.ombra, depthWrite: false, fog: true, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -6 });
    STILI_FACCIATA.forEach((s) => {
      const [stile, variante] = s.split('-');
      const [mappa, luci] = trameFacciata(stile, 11 + ['residenziale', 'uffici', 'industria'].indexOf(stile) * 7, Number(variante));
      m['facciata-' + s] = new THREE.MeshLambertMaterial({
        map: mappa,
        vertexColors: true,
        emissiveMap: luci,
        emissive: notte ? 0xffffff : 0x000000,
        emissiveIntensity: notte ? 1.25 : 0,
      });
      // Per la scala delle trame: una campata e un piano.
      m['facciata-' + s].userData = { campata: CAMPATA, piano: PIANO };
      this.vetroVicino(m['facciata-' + s], 'facciata-' + s);
    });
    m.tetti = new THREE.MeshLambertMaterial({ vertexColors: true });
    this.vetroVicino(m.tetti, 'tetti');
    m.fusto = new THREE.MeshLambertMaterial({ color: P.pilone });
    m.capitello = new THREE.MeshLambertMaterial({ color: P.trave });
    m.tronco = new THREE.MeshLambertMaterial({ color: notte ? '#2e2823' : '#4f4238' });
    // Le chiome morbide (niente facce piatte), più scure sotto e dentro: la
    // luce del cielo arriva dall'alto, sotto la chioma c'è ombra.
    m.chioma = new THREE.MeshLambertMaterial({ color: notte ? 0xd8d8d8 : 0xffffff });
    m.chioma.onBeforeCompile = (sh) => {
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', `#include <common>
          varying float vAltoChioma;`)
        .replace('#include <begin_vertex>', `#include <begin_vertex>
          vAltoChioma = position.z;`);
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', `#include <common>
          varying float vAltoChioma;`)
        .replace('#include <color_fragment>', `#include <color_fragment>
          diffuseColor.rgb *= mix(0.55, 1.08, smoothstep(-1.0, 0.9, vAltoChioma));`);
    };
    m.chioma.customProgramCacheKey = () => 'chioma-ombra';
    this.atlanteAlberi ??= atlanteAlberi();
    m.foglie = materialeAlberi(this.atlanteAlberi, notte, 0, 3);
    m.foglie.uniforms.uAtlante.value = this.atlanteAlberi;
    m.abeti = materialeAlberi(this.atlanteAlberi, notte, 3, 1);
    m.abeti.uniforms.uAtlante.value = this.atlanteAlberi;
    m.palo = new THREE.MeshLambertMaterial({ color: notte ? 0x3b4250 : 0x8d949e });
    m.testa = notte ? new THREE.MeshBasicMaterial({ color: 0xffd9a0 }) : new THREE.MeshLambertMaterial({ color: 0x9aa1aa });
    if (notte) {
      const gc = tela(64, 64);
      const gg = gc.getContext('2d');
      const gr = gg.createRadialGradient(32, 32, 0, 32, 32, 32);
      gr.addColorStop(0, 'rgba(255,225,170,1)');
      gr.addColorStop(0.25, 'rgba(255,190,110,0.45)');
      gr.addColorStop(1, 'rgba(255,170,90,0)');
      gg.fillStyle = gr;
      gg.fillRect(0, 0, 64, 64);
      m.bagliore = new THREE.PointsMaterial({ size: 1, map: trama(gc, false), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, sizeAttenuation: true, fog: false });
      const pc = tela(128, 128);
      const pg = pc.getContext('2d');
      const g2 = pg.createRadialGradient(64, 64, 0, 64, 64, 64);
      g2.addColorStop(0, 'rgba(255,200,130,0.42)');
      g2.addColorStop(0.6, 'rgba(255,190,120,0.12)');
      g2.addColorStop(1, 'rgba(255,180,110,0)');
      pg.fillStyle = g2;
      pg.fillRect(0, 0, 128, 128);
      m.pozza = new THREE.MeshBasicMaterial({ map: trama(pc, false), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4 });
    }
    const nastro = (frammento, uniformi, extra = {}) =>
      new THREE.ShaderMaterial({ uniforms: uniformi, vertexShader: VERTICE_NASTRO, fragmentShader: frammento, transparent: true, depthWrite: false, ...extra });
    m.percorso = nastro(FRAMMENTO_NASTRO, this.uniformiPercorso, { polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -4 });
    // Spinto verso la telecamera: compare solo dove qualcosa sta davvero
    // davanti (un ponte, un palazzo). A pari con l'asfalto lì sotto il
    // confronto di profondità vinceva e perdeva a chiazze: l'«effetto glitch»
    // sotto i ponti.
    m.percorsoFantasma = nastro(FRAMMENTO_NASTRO, this.uniformiFantasma, {
      depthFunc: THREE.GreaterDepth,
      polygonOffset: true,
      polygonOffsetFactor: -6,
      polygonOffsetUnits: -40,
    });
    // L'auto sotto un ponte: la sua sagoma rossa, sempre in vista.
    m.autoFantasma = new THREE.MeshBasicMaterial({ color: notte ? 0xff5a4f : 0xe0392f, transparent: true, opacity: 0.62, depthWrite: false, depthFunc: THREE.GreaterDepth, fog: false, polygonOffset: true, polygonOffsetFactor: -6, polygonOffsetUnits: -40 });
    m.alone = nastro(FRAMMENTO_ALONE, this.uniformiPercorso, { blending: notte ? THREE.AdditiveBlending : THREE.NormalBlending });
    m.freccia = nastro(FRAMMENTO_FRECCIA, {}, { polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -6 });
    m.punta = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, depthWrite: false });
    m.risparmio = nastro(FRAMMENTO_NASTRO, this.uniformiRisparmio, { polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -3 });
    // La strada già fatta: un blu più tenue e stretto, senza frecce, sotto il
    // percorso (come `percorso-fatto` sulla mappa piatta).
    m.fatto = nastro(FRAMMENTO_NASTRO, this.uniformiFatto, { polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -2 });
    m.traffico = nastro(FRAMMENTO_CODA, { uNotte: { value: notte ? 1 : 0 } }, { polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -2 });
    return m;
  }

  /**
   * Gli edifici per la guida: «deve essere bello da vedere e utile; viene
   * usato guidando, quindi informazioni e strada sempre ben visibili».
   *
   *  - Di giorno le finestre appena accennate: la facciata resta una
   *    superficie pulita, il disegno delle finestre non fa rumore (di notte
   *    restano, accese).
   *  - Più scure verso terra, un poco più chiare in alto: la luce del cielo e
   *    l'ombra della strada danno volume senza effetto «cartone».
   *  - Pieni dappertutto, tranne dove coprono l'auto sullo schermo: lì, e
   *    solo nelle parti davanti a lei, diventano trasparenti, come nei giochi
   *    di guida. Prima erano di vetro (a puntini, poi liscio) tutti quelli
   *    attorno all'auto, e la città sembrava un acquario.
   */
  vetroVicino(materiale, nome) {
    const u = this.uniformiEdifici;
    const facciata = nome.startsWith('facciata');
    materiale.onBeforeCompile = (sh) => {
      Object.assign(sh.uniforms, u);
      sh.vertexShader = sh.vertexShader
        .replace(
          '#include <common>',
          `#include <common>
          varying float vQuota;
          varying vec2 vPiano;`,
        )
        .replace(
          '#include <worldpos_vertex>',
          `#include <worldpos_vertex>
          vQuota = transformed.z;
          vPiano = transformed.xy;`,
        );
      sh.fragmentShader = sh.fragmentShader
        .replace(
          '#include <common>',
          `#include <common>
          varying float vQuota;
          varying vec2 vPiano;
          uniform vec3 uAutoSchermo;
          uniform vec2 uSchermo;
          uniform float uFinestreTenui;`,
        )
        .replace(
          '#include <map_fragment>',
          facciata
            ? `#ifdef USE_MAP
              vec4 finestre = texture2D(map, vMapUv);
              diffuseColor *= mix(finestre, vec4(1.0), uFinestreTenui);
            #endif`
            : '#include <map_fragment>',
        )
        .replace(
          '#include <color_fragment>',
          facciata
            ? `#include <color_fragment>
          // Il piano terra (negozi, portoni) più scuro e netto, poi la luce
          // che sale piano: la casa poggia a terra.
          diffuseColor.rgb *= mix(0.8, 1.0, smoothstep(3.3, 3.6, vQuota)) * mix(0.86, 1.0, smoothstep(0.0, 14.0, vQuota)) * mix(1.0, 1.05, smoothstep(14.0, 60.0, vQuota));`
            : `#include <color_fragment>
          // I tetti: a chiazze leggere (guaine, ghiaia, coppi rifatti), non
          // una lastra liscia che sembra un buco nella mappa.
          {
            vec2 q = floor(vPiano * 0.35);
            float n = fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
            vec2 q2 = floor(vPiano * 1.3);
            float n2 = fract(sin(dot(q2, vec2(39.346, 11.135))) * 24634.6345);
            diffuseColor.rgb *= 0.97 + 0.04 * n + 0.02 * n2;
          }`,
        )
        .replace(
          '#include <opaque_fragment>',
          `{
            // Solo dove copre davvero l'auto sullo schermo (un cerchio
            // attorno a lei) e solo le parti davanti a lei. Prima la zona
            // scendeva fino al bordo e sbavava i palazzi di lato.
            vec2 ndc = gl_FragCoord.xy / uSchermo * 2.0 - 1.0;
            vec2 p = vec2((ndc.x - uAutoSchermo.x) * uSchermo.x / uSchermo.y, ndc.y - uAutoSchermo.y);
            float d = length(p);
            float davanti = step(gl_FragCoord.z, uAutoSchermo.z * 0.5 + 0.5 - 0.00002);
            diffuseColor.a *= 1.0 - 0.7 * davanti * (1.0 - smoothstep(0.09, 0.15, d));
          }
          #include <opaque_fragment>`,
        )
        .replace(
          '#include <emissivemap_fragment>',
          facciata
            ? '#include <emissivemap_fragment>'
            : `#include <emissivemap_fragment>
          totalEmissiveRadiance += diffuseColor.rgb * uLuceTetti;`,
        )
        .replace('uniform float uFinestreTenui;', 'uniform float uFinestreTenui;\n          uniform float uLuceTetti;');
    };
    materiale.transparent = true;
    materiale.depthWrite = true;
    // Le pareti da tutte e due le parti: nelle tessere qualche contorno è
    // girato al contrario (o un cortile è scritto come un edificio), e la
    // parete girata spariva: il tetto restava sospeso sul vuoto.
    materiale.side = THREE.DoubleSide;
    materiale.customProgramCacheKey = () => 'guida-' + nome;
  }

  /** Una tessera fatta dal lavoratore, messa al suo posto nella scena. */
  aggiungiTessera(t, x, y, k) {
    this.togliTessera(t.chiave);
    const gruppo = new THREE.Group();
    gruppo.position.set(x, y, 0);
    gruppo.scale.set(k, k, 1);
    const voce = { chiave: t.chiave, gruppo, dati: t, mesh: [] };
    const notte = this.notte;
    const aggiungi = (nome, oggetto, ordine = 0) => {
      oggetto.userData.nome = nome;
      oggetto.renderOrder = ordine;
      oggetto.matrixAutoUpdate = false;
      oggetto.updateMatrix();
      gruppo.add(oggetto);
      voce.mesh.push(oggetto);
    };
    for (const [tipo, d] of Object.entries(t.strade)) aggiungi('strada-' + tipo, new THREE.Mesh(geometria(d, notte)), 1);
    if (t.ombre) {
      const o = new THREE.Mesh(geometria(t.ombre, notte));
      o.position.z = 0.4;
      aggiungi('ombre', o, 2);
    }
    if (t.ombrePonti) {
      const o = new THREE.Mesh(geometria(t.ombrePonti, notte));
      o.position.z = 0.46;
      aggiungi('ombrePonti', o, 2);
    }
    if (t.ombreAlberi) {
      const o = new THREE.Mesh(geometria(t.ombreAlberi, notte));
      o.position.z = 0.42;
      aggiungi('ombreAlberi', o, 2);
    }
    if (t.opere) aggiungi('opere', new THREE.Mesh(geometria(t.opere, notte)), 3);
    for (const [s, d] of Object.entries(t.facciate)) aggiungi('facciata-' + s, new THREE.Mesh(geometria(d, notte)), 3);
    if (t.tetti) aggiungi('tetti', new THREE.Mesh(geometria(t.tetti, notte)), 3);
    const g = this.geo;
    if (t.fusti.length) aggiungi('fusto', istanze(g.fusto, null, t.fusti), 3);
    if (t.capitelli.length) aggiungi('capitello', istanze(g.capitello, null, t.capitelli), 3);
    // Gli alberi dipinti: un'immagine per albero (vedi [atlanteAlberi]).
    const a = t.alberi;
    // Girano nella GPU: la sfera dei confini di three.js non li contiene, e
    // la tessera intera è già nel campo quando si disegna.
    const dipinti = (dati, colori) => {
      const i = istanze(g.albero, null, dati, colori);
      i.frustumCulled = false;
      return i;
    };
    if (a.foglie?.length) aggiungi('foglie', dipinti(a.foglie, a.coloriFoglie), 3);
    if (a.abeti?.length) aggiungi('abeti', dipinti(a.abeti, a.coloriAbeti), 3);
    if (t.pali.length) {
      aggiungi('palo', istanze(g.palo, null, t.pali), 3);
      aggiungi('testa', istanze(g.testa, null, t.teste), 3);
    }
    this.tessere.set(t.chiave, voce);
    this.vestiTessera(voce);
    this.mondo.add(gruppo);
    return voce;
  }

  /** I materiali (e le luci della notte) di una tessera. */
  vestiTessera(voce) {
    const m = this.mat;
    for (const o of voce.mesh) {
      o.material = m[o.userData.nome] ?? m.opere;
      const c = o.geometry.userData.colori;
      if (c) o.geometry.setAttribute('color', c[this.notte ? 1 : 0]);
    }
    // Di notte i lampioni si accendono: il bagliore e la pozza di luce.
    for (const o of voce.luci ?? []) {
      voce.gruppo.remove(o);
      if (o.isPoints) o.geometry.dispose();
    }
    voce.luci = [];
    const l = voce.dati.luci;
    if (this.notte && l.length) {
      const pg = new THREE.BufferGeometry();
      pg.setAttribute('position', new THREE.BufferAttribute(l, 3));
      const punti = new THREE.Points(pg, m.bagliore);
      punti.renderOrder = 20;
      const n = l.length / 3;
      const pozze = new THREE.InstancedMesh(this.geo.pozza, m.pozza, n);
      const M = new THREE.Matrix4();
      for (let i = 0; i < n; i++) {
        M.makeScale(30, 30, 1).setPosition(l[3 * i], l[3 * i + 1], l[3 * i + 2] - 9.77);
        pozze.setMatrixAt(i, M);
      }
      pozze.computeBoundingSphere();
      pozze.renderOrder = 4;
      for (const o of [punti, pozze]) {
        voce.gruppo.add(o);
        voce.luci.push(o);
      }
    }
  }

  togliTessera(chiave) {
    const v = this.tessere.get(chiave);
    if (!v) return;
    this.mondo.remove(v.gruppo);
    for (const o of [...v.mesh, ...(v.luci ?? [])]) {
      // Le geometrie delle istanze sono in comune: si buttano solo le matrici.
      if (o.isInstancedMesh) o.dispose();
      else o.geometry.dispose();
    }
    this.tessere.delete(chiave);
  }

  /** Accende o spegne una tessera (il budget dei triangoli). */
  mostraTessera(chiave, si) {
    const v = this.tessere.get(chiave);
    if (v) v.gruppo.visible = si;
  }

  /** Sposta le tessere quando cambia l'origine della scena. */
  spostaTessera(chiave, x, y, k) {
    const v = this.tessere.get(chiave);
    if (!v) return;
    v.gruppo.position.set(x, y, 0);
    v.gruppo.scale.set(k, k, 1);
  }

  /**
   * Un nastro (percorso, alone, freccia, risparmio, traffico) dai dati di
   * `nastro()`; null lo toglie.
   */
  impostaNastro(nome, dati, materiale, ordine) {
    const vecchio = this.nastri[nome];
    if (vecchio) {
      this.mondo.remove(vecchio);
      vecchio.geometry.dispose();
      delete this.nastri[nome];
    }
    if (nome === 'percorso' && this.nastri.fantasma) {
      this.mondo.remove(this.nastri.fantasma);
      delete this.nastri.fantasma;
    }
    if (!dati || !dati.indici.length) return;
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(dati.posizioni, 3));
    g.setAttribute('uv', new THREE.BufferAttribute(dati.uv, 2));
    g.setAttribute('livello', new THREE.BufferAttribute(dati.livelli, 1));
    g.setIndex(new THREE.BufferAttribute(dati.indici, 1));
    g.computeBoundingSphere();
    const mesh = new THREE.Mesh(g, this.mat[materiale]);
    mesh.userData.materiale = materiale;
    mesh.renderOrder = ordine;
    this.nastri[nome] = mesh;
    this.mondo.add(mesh);
    if (nome === 'percorso') {
      const vecchio2 = this.nastri.fantasma;
      if (vecchio2) this.mondo.remove(vecchio2);
      const f = new THREE.Mesh(g, this.mat.percorsoFantasma);
      f.userData.materiale = 'percorsoFantasma';
      f.renderOrder = 40;
      this.nastri.fantasma = f;
      this.mondo.add(f);
    }
  }

  /** La punta della freccia di manovra in [x, y, z], girata come [dir]. */
  impostaPunta(p) {
    if (this.punta) {
      this.mondo.remove(this.punta);
      this.punta.geometry.dispose();
      this.punta = null;
    }
    if (!p) return;
    const [x, y, z, dir] = p;
    const nx = -Math.sin(dir);
    const ny = Math.cos(dir);
    const tx = Math.cos(dir);
    const ty = Math.sin(dir);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute([x + nx * 3.6, y + ny * 3.6, z, x - nx * 3.6, y - ny * 3.6, z, x + tx * 7, y + ty * 7, z], 3));
    g.setIndex([0, 1, 2]);
    this.punta = new THREE.Mesh(g, this.mat.punta);
    this.punta.renderOrder = 7;
    this.mondo.add(this.punta);
  }

  /** I materiali nuovi anche per i nastri (dopo giorno ↔ notte). */
  rivestiNastri() {
    for (const m of Object.values(this.nastri)) m.material = this.mat[m.userData.materiale];
    if (this.punta) this.punta.material = this.mat.punta;
  }

  /**
   * L'auto: rossa (o del colore scelto), che sul percorso blu si vede. Con
   * [simbolo] `freccia` è la freccia arancione scelta fra i simboli: «quando
   * parte il percorso continua a uscire l'auto, invece ho impostato la
   * freccia».
   */
  creaAuto(colore = '#d62a26', simbolo = this.formaAuto ?? 'auto') {
    this.colorAuto = colore;
    this.formaAuto = simbolo;
    if (simbolo === 'freccia') return this.creaFreccia();
    const vecchia = this.auto;
    const g = new THREE.Group();
    const notte = this.notte;
    const tinta = new THREE.Color(colore);
    if (notte) tinta.multiplyScalar(0.84);
    const corpo = new THREE.MeshPhongMaterial({ color: tinta, shininess: 90, specular: 0x666666 });
    const vetro = new THREE.MeshPhongMaterial({ color: 0x1a2230, shininess: 120, specular: 0x8899aa });
    const scuro = new THREE.MeshLambertMaterial({ color: 0x15171b });
    const L = 4.6;
    const W = 1.9;
    const forma = (pts) => {
      const s = new THREE.Shape();
      pts.forEach(([px, py], i) => (i ? s.lineTo(px, py) : s.moveTo(px, py)));
      return s;
    };
    const sotto = new THREE.ExtrudeGeometry(
      forma([[2.3, 0.32], [2.35, 0.62], [2.18, 0.86], [0.95, 0.98], [-1.95, 1.02], [-2.3, 0.92], [-2.33, 0.36]]),
      { depth: W - 0.16, bevelEnabled: true, bevelThickness: 0.08, bevelSize: 0.06, bevelSegments: 2, steps: 1 },
    );
    sotto.translate(0, 0, -(W - 0.16) / 2);
    const abitacolo = new THREE.ExtrudeGeometry(forma([[1.0, 0.95], [0.32, 1.44], [-1.15, 1.46], [-1.9, 1.0]]), {
      depth: W * 0.84,
      bevelEnabled: true,
      bevelThickness: 0.04,
      bevelSize: 0.04,
      bevelSegments: 1,
    });
    abitacolo.translate(0, 0, -W * 0.42);
    const tetto = new THREE.ExtrudeGeometry(forma([[0.25, 1.43], [0.3, 1.5], [-1.1, 1.52], [-1.18, 1.44]]), { depth: W * 0.8, bevelEnabled: false });
    tetto.translate(0, 0, -W * 0.4);
    const dentro = new THREE.Group();
    dentro.add(new THREE.Mesh(sotto, corpo), new THREE.Mesh(abitacolo, vetro), new THREE.Mesh(tetto, corpo));
    const ruota = new THREE.CylinderGeometry(0.36, 0.36, 0.28, 18);
    ruota.rotateX(Math.PI / 2);
    const cerchio = new THREE.CylinderGeometry(0.22, 0.22, 0.3, 12);
    cerchio.rotateX(Math.PI / 2);
    const cerchi = new THREE.MeshPhongMaterial({ color: 0xc9ced6, shininess: 60 });
    for (const [px, pz] of [[1.45, W / 2 - 0.12], [1.45, -W / 2 + 0.12], [-1.45, W / 2 - 0.12], [-1.45, -W / 2 + 0.12]]) {
      const w = new THREE.Mesh(ruota, scuro);
      w.position.set(px, 0.36, pz);
      dentro.add(w);
      const rr = new THREE.Mesh(cerchio, cerchi);
      rr.position.set(px, 0.36, pz * 1.02);
      dentro.add(rr);
    }
    const fari = new THREE.MeshBasicMaterial({ color: 0xfff6e0 });
    const stop = new THREE.MeshBasicMaterial({ color: notte ? 0xff2a2a : 0xd01818 });
    for (const pz of [0.62, -0.62]) {
      const h = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.12, 0.38), fari);
      h.position.set(2.33, 0.72, pz);
      dentro.add(h);
    }
    const coda = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.1, W * 0.86), stop);
    coda.position.set(-2.34, 0.8, 0);
    dentro.add(coda);
    dentro.rotation.x = Math.PI / 2;
    g.add(dentro);
    // La sagoma: le stesse forme, disegnate solo dove qualcosa copre l'auto.
    const sagoma = new THREE.Group();
    sagoma.rotation.x = Math.PI / 2;
    for (const geo of [sotto, abitacolo, tetto]) {
      const ms = new THREE.Mesh(geo, this.mat.autoFantasma);
      ms.renderOrder = 41;
      sagoma.add(ms);
    }
    g.add(sagoma);
    // L'ombra sotto l'auto, morbida.
    g.add(this.ombraAuto(L * 1.25, W * 1.6));
    if (notte) {
      const lc = tela(128, 128);
      const lg = lc.getContext('2d');
      const g2 = lg.createRadialGradient(64, 64, 2, 64, 64, 64);
      g2.addColorStop(0, 'rgba(255,236,190,0.55)');
      g2.addColorStop(1, 'rgba(255,236,190,0)');
      lg.fillStyle = g2;
      lg.fillRect(0, 0, 128, 128);
      const pozza = new THREE.Mesh(new THREE.PlaneGeometry(26, 9), new THREE.MeshBasicMaterial({ map: trama(lc, false), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
      pozza.position.set(15, 0, 0.12);
      pozza.renderOrder = 9;
      g.add(pozza);
    }
    g.scale.setScalar(2.0);
    this.sostituisciAuto(g, vecchia);
  }

  /** L'ombra morbida sotto l'auto o la freccia, lunga [l] e larga [w]. */
  ombraAuto(l, w) {
    const sh = tela(64, 64);
    const sg = sh.getContext('2d');
    const gr = sg.createRadialGradient(32, 32, 4, 32, 32, 32);
    gr.addColorStop(0, 'rgba(0,0,0,0.55)');
    gr.addColorStop(1, 'rgba(0,0,0,0)');
    sg.fillStyle = gr;
    sg.fillRect(0, 0, 64, 64);
    const ombra = new THREE.Mesh(new THREE.PlaneGeometry(l, w), new THREE.MeshBasicMaterial({ map: trama(sh, false), transparent: true, depthWrite: false }));
    ombra.position.z = 0.05;
    ombra.renderOrder = 8;
    return ombra;
  }

  /**
   * La freccia, come il simbolo della mappa di sempre (`freccia.png`): la
   * metà sinistra arancio chiaro, la destra arancio scuro, il bordo bianco.
   * Sta appena sopra la strada, girata dove si va, grande come l'auto.
   */
  creaFreccia() {
    const vecchia = this.auto;
    const g = new THREE.Group();
    const scura = this.notte ? 0.86 : 1;
    const piatto = (pts, alto, basso = 0) => {
      const s = new THREE.Shape();
      pts.forEach(([px, py], i) => (i ? s.lineTo(px, py) : s.moveTo(px, py)));
      const geo = new THREE.ExtrudeGeometry(s, { depth: alto - basso, bevelEnabled: false });
      geo.translate(0, 0, basso);
      return geo;
    };
    const tinta = (hex) => {
      const c = new THREE.Color(hex);
      c.multiplyScalar(scura);
      return new THREE.MeshPhongMaterial({ color: c, shininess: 70, specular: 0x553322 });
    };
    // In avanti è +x, come l'auto; la punta davanti, la tacca dietro.
    const punta = [2.5, 0];
    const sinistra = [-2.0, 1.55];
    const tacca = [-0.95, 0];
    const destra = [-2.0, -1.55];
    const bordo = piatto([[2.95, 0], [-2.38, 1.9], [-1.0, 0.36], [-1.0, -0.36], [-2.38, -1.9]], 0.34);
    const chiara = piatto([punta, sinistra, tacca], 0.52, 0.1);
    const scuraMeta = piatto([punta, tacca, destra], 0.52, 0.1);
    const dentro = new THREE.Group();
    dentro.add(
      new THREE.Mesh(bordo, new THREE.MeshPhongMaterial({ color: 0xffffff, shininess: 40 })),
      new THREE.Mesh(chiara, tinta('#ff8a2a')),
      new THREE.Mesh(scuraMeta, tinta('#e8470e')),
    );
    dentro.position.z = 0.25;
    g.add(dentro);
    // La sagoma, dove qualcosa la copre: come per l'auto.
    const sagoma = new THREE.Group();
    sagoma.position.z = 0.25;
    for (const geo of [bordo]) {
      const ms = new THREE.Mesh(geo, this.mat.autoFantasma);
      ms.renderOrder = 41;
      sagoma.add(ms);
    }
    g.add(sagoma);
    g.add(this.ombraAuto(6.2, 4.6));
    g.scale.setScalar(2.4);
    this.sostituisciAuto(g, vecchia);
  }

  /** Mette [g] al posto di [vecchia], nello stesso punto, e la butta. */
  sostituisciAuto(g, vecchia) {
    // L'auto si disegna nel suo strato, sopra i nomi di MapLibre (livello 1).
    g.traverse((o) => o.layers.set(this.autoCoperta ? 0 : 1));
    g.visible = vecchia ? vecchia.visible : false;
    if (vecchia) {
      g.position.copy(vecchia.position);
      g.rotation.copy(vecchia.rotation);
      this.mondo.remove(vecchia);
      vecchia.traverse((o) => {
        if (o.isMesh && o.material !== this.mat?.autoFantasma) {
          o.geometry.dispose();
          o.material.map?.dispose();
          o.material.dispose();
        }
      });
    }
    this.auto = g;
    this.mondo.add(g);
  }

  /** L'auto in [x, y, z], girata come [dir] (radianti), inclinata di [pendenza]. */
  mettiAuto(x, y, z, dir, pendenza = 0) {
    if (!this.auto) this.creaAuto(this.colorAuto);
    const a = this.auto;
    a.visible = true;
    a.position.set(x, y, z + 0.26);
    this.uniformiEdifici.uAuto.value.set(x, y);
    this.uniformiEdifici.uDir.value.set(Math.cos(dir), Math.sin(dir));
    a.rotation.set(0, 0, 0);
    a.rotateZ(dir);
    a.rotateY(-pendenza);
  }

  /**
   * I segni in quota: icone (autovelox, meta) e nomi dei ponti all'altezza
   * dell'impalcato, sempre sopra (come i simboli di MapLibre), grandi uguali
   * a ogni distanza. [segni]: `{chiave, x, y, z, immagine, w, h}` (w e h in
   * punti dello schermo; l'immagine è una bitmap o una tela). Con `sopra`
   * il segno sta nei livelli dell'auto, disegnati sopra i nomi e i cartelli
   * di MapLibre (le persone di casa: un cartello «A52» non le copre).
   */
  impostaSegni(segni) {
    this.segni ??= new Map();
    this.trameSegni ??= new Map();
    const tieni = new Set();
    for (const g of segni) {
      tieni.add(g.chiave);
      let sp = this.segni.get(g.chiave);
      if (!sp) {
        let t = this.trameSegni.get(g.immagine);
        if (!t) {
          t = new THREE.Texture(g.immagine);
          t.colorSpace = THREE.SRGBColorSpace;
          t.needsUpdate = true;
          this.trameSegni.set(g.immagine, t);
        }
        sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, depthTest: false, depthWrite: false, sizeAttenuation: false, transparent: true, fog: false }));
        sp.center.set(0.5, g.centro ?? 0);
        this.segni.set(g.chiave, sp);
        this.mondo.add(sp);
      }
      sp.renderOrder = 60;
      sp.layers.set(g.sopra ? 1 : 0);
      sp.position.set(g.x, g.y, g.z);
      sp.userData.w = g.w;
      sp.userData.h = g.h;
      sp.userData.elemento = g.elemento ?? null;
    }
    this.segniSopra = segni.some((g) => g.sopra);
    for (const [k, sp] of this.segni) {
      if (tieni.has(k)) continue;
      this.mondo.remove(sp);
      sp.material.dispose();
      this.segni.delete(k);
    }
  }

  /**
   * I segni che si coprono sullo schermo: resta il più importante (le icone
   * prima dei nomi, poi il più vicino), gli altri si nascondono finché non
   * si spostano. [camera] è già quella del fotogramma; [W]×[H] in punti.
   */
  sfoltisciSegni(camera, W, H, occupati = []) {
    if (!this.segni?.size) return;
    const v = new THREE.Vector3();
    const voci = [];
    for (const sp of this.segni.values()) {
      sp.getWorldPosition(v).project(camera);
      const x = ((v.x + 1) / 2) * W;
      const y = ((1 - v.y) / 2) * H;
      const w = sp.userData.w;
      const h = sp.userData.h;
      const cy = sp.center.y;
      voci.push({
        sp,
        fuori: v.z > 1 || v.z < -1,
        r: [x - w / 2 - 3, y - h * (1 - cy) - 3, x + w / 2 + 3, y + h * cy + 3],
        // Le icone (si toccano) prima dei nomi, poi il più vicino.
        peso: (sp.userData.elemento ? 0 : 10) + v.z,
      });
    }
    voci.sort((a, b) => a.peso - b.peso);
    // Quello che c'è già (l'auto): i nomi non ci vanno sopra.
    const presi = [...occupati];
    for (const q of voci) {
      const libero = !q.fuori && !presi.some((p) => q.r[0] < p[2] && q.r[2] > p[0] && q.r[1] < p[3] && q.r[3] > p[1]);
      // Un'icona si vede sempre; un nome solo se non copre niente.
      q.sp.visible = q.sp.userData.elemento ? !q.fuori : libero;
      if (q.sp.visible) presi.push(q.r);
    }
  }

  /** Le dimensioni dei segni per questo fotogramma ([p11] della proiezione, [alto] in punti). */
  scalaSegni(p11, alto) {
    if (!this.segni) return;
    const k = 2 / (p11 * alto);
    for (const sp of this.segni.values()) sp.scale.set(sp.userData.w * k, sp.userData.h * k, 1);
  }

  /** Quanti triangoli disegna adesso (le istanze contano ognuna). */
  get triangoli() {
    let n = 0;
    for (const t of this.tessere.values()) if (t.gruppo.visible) n += t.dati.conti.triangoli;
    return n;
  }
}
