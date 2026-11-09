// I colori della mappa 3D, di giorno e di notte: quelli di `stile.dart`,
// spostati un poco per la luce del 3D (il prototipo approvato).

export const GIORNO = {
  // Il suolo caldo e chiaro, come le mappe vere: «non hanno caricato
  // l'immagine, sono grigi» — il grigio-verde uniforme di prima sembrava una
  // mappa che non si era ancora disegnata.
  sfondo: '#EEE9DF',
  abitato: '#E9E3D7',
  industria: '#E2DED6',
  prato: '#C3DEA4',
  bosco: '#A7CC8A',
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
  ombra: 0.2,
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
    // I colori delle città italiane: ocra, giallo, rosa, terracotta, panna,
    // bianco, grigio pietra. «Sempre uguali»: erano nove beige quasi uguali.
    giorno: ['#ecd9a8', '#f0dfb4', '#e6c48c', '#efc9b4', '#e8b8a0', '#d9a07e', '#f3ecdf', '#f6f3ee', '#e3dccf', '#d8d4cc', '#f1e1c9', '#e9cfae', '#dfe0d6', '#efd6c4'],
    notte: ['#8c8270', '#91877a', '#86745e', '#8a7468', '#866a5e', '#7d6252', '#8d8a85', '#91908c', '#86817a', '#7f7c77', '#8c8378', '#86786a', '#80817b', '#8a7a70'],
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
  // I coppi delle case italiane, in tante sfumature; qualche tetto piano
  // chiaro. Da sopra l'edificio si legge, e la città non è grigia.
  // Metà coppi, metà terrazzi piani (a Napoli quasi tutti): tutto rosso
  // faceva un tappeto uniforme.
  giorno: ['#b8654c', '#c4775b', '#a95b45', '#c9866a', '#b56f57', '#bd6a4f', '#d6d1c8', '#cfc9bf', '#ddd6ca', '#c9c4bb', '#e0dbd2', '#d3cbbd'],
  notte: ['#4a3d3b', '#4f4240', '#463a38', '#524542', '#4a3e3c', '#4a3d3b', '#424852', '#40454e', '#454a53', '#3f444d', '#474c55', '#43474f'],
  industriaGiorno: ['#e8e2d6', '#ece7dc', '#e2dccf', '#efe9de', '#dfd8ca'],
  // Gli uffici e le torri: tetti piani, chiari e freddi.
  ufficiGiorno: ['#d3d8dd', '#dce0e4', '#cdd3d9', '#d8dcdf'],
  ufficiNotte: ['#3c414b', '#424852', '#3c414b', '#424852'],
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
// Il sole alto: le ombre delle torri restano corte (lunghe coprivano interi
// isolati di grigio, come una mappa non caricata).
export const SOLE = { azimut: 248, altezza: 50 };

/** Di quanto si sposta l'ombra di un punto alto un metro: verso est e verso nord. */
export function spostamentoOmbra() {
  const az = (SOLE.azimut * Math.PI) / 180;
  const el = (SOLE.altezza * Math.PI) / 180;
  const k = 1 / Math.tan(el);
  // L'ombra va dalla parte opposta al sole.
  return [-Math.sin(az) * k, -Math.cos(az) * k];
}
