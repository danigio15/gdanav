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
    // Chiari e caldi, poco saturi: si vedono come case, non tirano l'occhio.
    giorno: ['#ece3d3', '#f1e9dc', '#e3cdb5', '#dcc0a6', '#f3efe8', '#e6d5bf', '#e8d2bb', '#ddd2c3', '#e2c9b0'],
    notte: ['#8c8378', '#91877a', '#7d6a5f', '#806155', '#8d8a85', '#86786a', '#8c8378', '#91877a', '#7d6a5f'],
  },
  uffici: {
    giorno: ['#d5dde6', '#e2e6eb', '#cbd5df', '#dbe2e9'],
    notte: ['#6f7987', '#7a828c', '#6f7987', '#7a828c'],
  },
  industria: {
    giorno: ['#e1e3e5', '#d8dbdf', '#e5e1d9', '#d6cdc1', '#ded6ca', '#d3d9df', '#e7e7e5'],
    notte: ['#7f838a', '#767b82', '#857c70', '#7f838a', '#767b82', '#857c70', '#7f838a'],
  },
};

export const TETTI = {
  // Più chiari dei muri: da sopra l'edificio si legge.
  giorno: ['#c7cacf', '#d0cdc8', '#c08a7a', '#cbc6bf', '#c0c4c9'],
  notte: ['#3c414b', '#424852', '#3c414b', '#424852', '#3c414b'],
  industriaGiorno: ['#cdd0d4', '#d4d2cd', '#c6cacf', '#d6d3cd', '#c2c6ca'],
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
