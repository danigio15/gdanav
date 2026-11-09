// I colori della mappa 3D, di giorno e di notte: quelli di `stile.dart`,
// spostati un poco per la luce del 3D (il prototipo approvato).

export const GIORNO = {
  sfondo: '#E5E7E1',
  abitato: '#E1E3DE',
  industria: '#D6D9D8',
  prato: '#CBE2BA',
  bosco: '#B7D6A3',
  acqua: '#A9D7F6',
  cielo: '#5d9be0',
  orizzonte: '#d9e7f4',
  nebbia: '#e2eaf1',
  nebbiaDa: 450,
  nebbiaA: 3200,
  asfalto: '#959ba3',
  asfaltoGrande: '#8c939c',
  // Sui ponti l'asfalto è più chiaro: l'impalcato si stacca dalle strade sotto.
  asfaltoPonte: '#adb2b8',
  asfaltoPonteGrande: '#a6acb3',
  righe: '#ffffff',
  cemento: '#d6d3cc',
  trave: '#b9b6ae',
  pilone: '#cfccc4',
  percorso: '#27A2F8',
  percorsoBordo: '#0A6CC2',
  ombra: 0.32,
  // L'ombra in più sotto i ponti (alone e nucleo).
  ombraPonte: 0.2,
};

export const NOTTE = {
  sfondo: '#28324A',
  abitato: '#2B3550',
  industria: '#2F3A52',
  prato: '#24403A',
  bosco: '#213B33',
  acqua: '#1F4468',
  cielo: '#08122b',
  orizzonte: '#2b3b63',
  nebbia: '#1d2740',
  nebbiaDa: 250,
  nebbiaA: 2300,
  asfalto: '#4a5366',
  asfaltoGrande: '#535d72',
  asfaltoPonte: '#66708a',
  asfaltoPonteGrande: '#6c7690',
  righe: '#f2f5fa',
  cemento: '#59606c',
  trave: '#3f4550',
  pilone: '#4f5562',
  percorso: '#3AB0FF',
  percorsoBordo: '#0B5AA6',
  ombra: 0.2,
  ombraPonte: 0.16,
};

/** I colori delle facciate e dei tetti, per stile di edificio. */
export const FACCIATE = {
  residenziale: {
    giorno: ['#dccaa8', '#e6d6b9', '#cc9273', '#b9705a', '#ece6db', '#d2b892', '#d9ab84', '#c4ab90', '#bf8a68'],
    notte: ['#8c8378', '#91877a', '#7d6a5f', '#806155', '#8d8a85', '#86786a', '#8c8378', '#91877a', '#7d6a5f'],
  },
  uffici: {
    giorno: ['#a9b8c6', '#c9ced4', '#97a4b0', '#bcc7cf'],
    notte: ['#6f7987', '#7a828c', '#6f7987', '#7a828c'],
  },
  industria: {
    giorno: ['#cfd2d5', '#bcc1c7', '#d8d3ca', '#b8a48d', '#c9b9a2', '#a7b2bd', '#d9d9d6'],
    notte: ['#7f838a', '#767b82', '#857c70', '#7f838a', '#767b82', '#857c70', '#7f838a'],
  },
};

export const TETTI = {
  giorno: ['#858990', '#94918c', '#a0594a', '#8f8a84', '#7a7f86'],
  notte: ['#3c414b', '#424852', '#3c414b', '#424852', '#3c414b'],
  industriaGiorno: ['#8c9095', '#9a9893', '#80868c', '#a3a099', '#767b80'],
  industriaNotte: ['#4a4f58', '#4a4f58', '#4a4f58', '#4a4f58', '#4a4f58'],
};

/**
 * Le chiome (colore, peso): verdi veri, scuri e chiari, qualcuno oliva, pochi
 * più gialli. «Questi alberi così sono orrendi»: le chiome d'autunno del
 * prototipo (arancio, rosso, giallo) facevano un bosco di cartone colorato.
 */
export const CHIOME = [
  ['#4b6b34', 16],
  ['#56783a', 14],
  ['#3f5e2f', 12],
  ['#62823f', 10],
  ['#4f6a3c', 9],
  ['#6b8a46', 7],
  ['#5a6f35', 6],
  ['#38522c', 6],
  ['#7a8f45', 3],
  ['#8a8a42', 2],
];

/** Da «#rrggbb» a [r, g, b] (0..255). */
export function rgb(esa) {
  const v = parseInt(esa.slice(1), 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

/** Il sole: da dove viene (gradi da nord, in senso orario) e quanto è alto. */
export const SOLE = { azimut: 248, altezza: 36 };

/** Di quanto si sposta l'ombra di un punto alto un metro: verso est e verso nord. */
export function spostamentoOmbra() {
  const az = (SOLE.azimut * Math.PI) / 180;
  const el = (SOLE.altezza * Math.PI) / 180;
  const k = 1 / Math.tan(el);
  // L'ombra va dalla parte opposta al sole.
  return [-Math.sin(az) * k, -Math.cos(az) * k];
}
