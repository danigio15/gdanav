// La scena three.js: materiali, trame, le tessere costruite, il percorso
// all'altezza delle strade e l'auto rossa. Il disegno lo chiama lo strato
// di MapLibre (`principale.js`), con la sua telecamera.

import * as THREE from 'three';
import { generatore } from './caso.js';
import { CAMPATA, NASTRI, PERIODO_STRADA, PIANO } from './tessera.js';
import { GIORNO, NOTTE, SOLE } from './tavolozza.js';

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

/** Le facciate: quattro campate per quattro piani; il giorno e le finestre accese di notte. */
function trameFacciata(stile, seme) {
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
  const r = generatore(seme);
  for (let i = 0; i < 3000; i++) {
    g.fillStyle = `rgba(0,0,0,${r() * 0.05})`;
    g.fillRect(r() * Wp, r() * Wp, 2, 2);
  }
  const caldi = ['#ffd27a', '#ffe0a3', '#fff1cf', '#ffc46b', '#cfe1ff'];
  for (let fy = 0; fy < N; fy++) {
    for (let bx = 0; bx < N; bx++) {
      const x0 = bx * CW;
      const y0 = fy * CW;
      let wx0;
      let wx1;
      let wy0;
      let wy1;
      if (stile === 'uffici') [wx0, wx1, wy0, wy1] = [3, 61, 10, 52];
      else if (stile === 'industria') {
        [wx0, wx1, wy0, wy1] = [0, 64, 14, 30];
        if (fy % 2) {
          g.fillStyle = 'rgba(0,0,0,0.10)';
          g.fillRect(x0 + 31, y0, 2, CW);
          continue;
        }
      } else [wx0, wx1, wy0, wy1] = [18, 46, 12, 50];
      const tono = 40 + Math.floor(r() * 30);
      g.fillStyle = stile === 'uffici' ? `rgb(${tono + 40},${tono + 62},${tono + 85})` : `rgb(${tono},${tono + 8},${tono + 20})`;
      g.fillRect(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
      const gr = g.createLinearGradient(0, y0 + wy0, 0, y0 + wy1);
      gr.addColorStop(0, 'rgba(255,255,255,0.28)');
      gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr;
      g.fillRect(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
      g.strokeStyle = 'rgba(255,255,255,0.9)';
      g.lineWidth = 2;
      g.strokeRect(x0 + wx0, y0 + wy0, wx1 - wx0, wy1 - wy0);
      if (stile === 'uffici') {
        g.fillStyle = 'rgba(220,225,230,0.9)';
        g.fillRect(x0 + 31, y0 + wy0, 2, wy1 - wy0);
      }
      if (stile === 'residenziale') {
        g.fillStyle = 'rgba(0,0,0,0.25)';
        g.fillRect(x0 + wx0 - 2, y0 + wy1, wx1 - wx0 + 4, 3);
        g.fillStyle = 'rgba(0,0,0,0.08)';
        g.fillRect(x0 + wx0 - 7, y0 + wy0, 6, wy1 - wy0);
        g.fillRect(x0 + wx1 + 1, y0 + wy0, 6, wy1 - wy0);
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
  float t = fract((vUv.y - w * 1.1) / uPasso);
  float chev = (1.0 - smoothstep(0.0, 0.06, abs(t - 0.06) - 0.03)) * (1.0 - smoothstep(0.50, 0.56, e)) * uFrecce;
  c = mix(c, vec3(1.0), chev * 0.92);
  float a = 1.0 - smoothstep(0.93, 1.0, e);
  a *= smoothstep(uInizio, uInizio + 6.0, vUv.y);
  a *= mix(1.0, 0.45 + 0.35 * step(0.5, fract(vUv.y / 8.0)), galleria);
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
      chioma: new THREE.IcosahedronGeometry(1, 0),
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
    };
    // Il «fantasma» del percorso: lo stesso nastro, disegnato solo dove
    // qualcosa ci sta davanti (un cavalcavia, un edificio), più tenue.
    this.uniformiFantasma = { ...this.uniformiPercorso, uInizio: { value: -1e9 }, uOpacita: { value: 0.5 } };
    this.uniformiRisparmio = {
      uCore: { value: colore('#4ADE80') },
      uBordo: { value: colore('#166534') },
      uLargo: { value: 4 },
      uPasso: { value: 16 },
      uNotte: { value: 0 },
      uInizio: { value: -1e9 },
      uFrecce: { value: 0 },
      uOpacita: { value: 1 },
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
    this.emisferica.color.set(notte ? 0x4a5d8c : 0xdbe8ff);
    this.emisferica.groundColor.set(notte ? 0x141a26 : 0x8d917f);
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
    // Le ombre vincono sull'asfalto (che ha il suo polygonOffset), non sul resto.
    m.ombre = new THREE.MeshBasicMaterial({ color: 0x0c1220, transparent: true, opacity: P.ombra, depthWrite: true, depthFunc: THREE.LessDepth, fog: true, polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -6 });
    ['residenziale', 'uffici', 'industria'].forEach((s, i) => {
      const [mappa, luci] = trameFacciata(s, 11 + i * 7);
      m['facciata-' + s] = new THREE.MeshLambertMaterial({
        map: mappa,
        vertexColors: true,
        emissiveMap: luci,
        emissive: notte ? 0xffffff : 0x000000,
        emissiveIntensity: notte ? 1.25 : 0,
      });
      // Per la scala delle trame: una campata e un piano.
      m['facciata-' + s].userData = { campata: CAMPATA, piano: PIANO };
    });
    m.tetti = new THREE.MeshLambertMaterial({ vertexColors: true });
    m.fusto = new THREE.MeshLambertMaterial({ color: P.pilone });
    m.capitello = new THREE.MeshLambertMaterial({ color: P.trave });
    m.tronco = new THREE.MeshLambertMaterial({ color: notte ? '#3a2e26' : '#6b5241' });
    m.chioma = new THREE.MeshLambertMaterial({ flatShading: true, color: notte ? 0xe6e6e6 : 0xffffff });
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
    m.percorsoFantasma = nastro(FRAMMENTO_NASTRO, this.uniformiFantasma, { depthFunc: THREE.GreaterDepth });
    // L'auto sotto un ponte: la sua sagoma rossa, sempre in vista.
    m.autoFantasma = new THREE.MeshBasicMaterial({ color: notte ? 0xff5a4f : 0xe0392f, transparent: true, opacity: 0.62, depthWrite: false, depthFunc: THREE.GreaterDepth, fog: false });
    m.alone = nastro(FRAMMENTO_ALONE, this.uniformiPercorso, { blending: notte ? THREE.AdditiveBlending : THREE.NormalBlending });
    m.freccia = nastro(FRAMMENTO_FRECCIA, {}, { polygonOffset: true, polygonOffsetFactor: -3, polygonOffsetUnits: -6 });
    m.punta = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, depthWrite: false });
    m.risparmio = nastro(FRAMMENTO_NASTRO, this.uniformiRisparmio, { polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -3 });
    m.traffico = nastro(FRAMMENTO_CODA, { uNotte: { value: notte ? 1 : 0 } }, { polygonOffset: true, polygonOffsetFactor: -1, polygonOffsetUnits: -2 });
    return m;
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
    if (t.opere) aggiungi('opere', new THREE.Mesh(geometria(t.opere, notte)), 3);
    for (const [s, d] of Object.entries(t.facciate)) aggiungi('facciata-' + s, new THREE.Mesh(geometria(d, notte)), 3);
    if (t.tetti) aggiungi('tetti', new THREE.Mesh(geometria(t.tetti, notte)), 3);
    const g = this.geo;
    if (t.fusti.length) aggiungi('fusto', istanze(g.fusto, null, t.fusti), 3);
    if (t.capitelli.length) aggiungi('capitello', istanze(g.capitello, null, t.capitelli), 3);
    const a = t.alberi;
    if (a.tronchi.length) aggiungi('tronco', istanze(g.tronco, null, a.tronchi), 3);
    if (a.chiome.length) {
      aggiungi('chioma', istanze(g.chioma, null, a.chiome, a.coloriChiome), 3);
      aggiungi('chioma', istanze(g.chioma, null, a.chiome2, a.coloriChiome2), 3);
    }
    if (a.coni.length) aggiungi('chioma', istanze(g.cono, null, a.coni, a.coloriConi), 3);
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

  /** L'auto: rossa (o del colore scelto), che sul percorso blu si vede. */
  creaAuto(colore = '#d62a26') {
    this.colorAuto = colore;
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
    const sh = tela(64, 64);
    const sg = sh.getContext('2d');
    const gr = sg.createRadialGradient(32, 32, 4, 32, 32, 32);
    gr.addColorStop(0, 'rgba(0,0,0,0.55)');
    gr.addColorStop(1, 'rgba(0,0,0,0)');
    sg.fillStyle = gr;
    sg.fillRect(0, 0, 64, 64);
    const ombra = new THREE.Mesh(new THREE.PlaneGeometry(L * 1.25, W * 1.6), new THREE.MeshBasicMaterial({ map: trama(sh, false), transparent: true, depthWrite: false }));
    ombra.position.z = 0.05;
    ombra.renderOrder = 8;
    g.add(ombra);
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
    a.rotation.set(0, 0, 0);
    a.rotateZ(dir);
    a.rotateY(-pendenza);
  }

  /**
   * I segni in quota: icone (autovelox, meta) e nomi dei ponti all'altezza
   * dell'impalcato, sempre sopra (come i simboli di MapLibre), grandi uguali
   * a ogni distanza. [segni]: `{chiave, x, y, z, immagine, w, h}` (w e h in
   * punti dello schermo; l'immagine è una bitmap o una tela).
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
        sp.renderOrder = 60;
        this.segni.set(g.chiave, sp);
        this.mondo.add(sp);
      }
      sp.position.set(g.x, g.y, g.z);
      sp.userData.w = g.w;
      sp.userData.h = g.h;
    }
    for (const [k, sp] of this.segni) {
      if (tieni.has(k)) continue;
      this.mondo.remove(sp);
      sp.material.dispose();
      this.segni.delete(k);
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
