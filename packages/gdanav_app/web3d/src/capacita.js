// Il telefono ce la fa? Prima di partire, cosa offre WebGL; poi, nei primi
// secondi di guida, a quanti fotogrammi va davvero. Sotto la soglia la
// mappa 3D si spegne da sola e torna quella di sempre.

/** Fotogrammi al secondo sotto i quali il 3D non vale la pena. */
export const FPS_MINIMI = 20;

/**
 * Cosa dice WebGL del telefono ([info]: dal contesto): se va bene, e
 * perché no. Un rendering software (SwiftShader, llvmpipe) è troppo lento
 * per un telefono vero; serve almeno WebGL 2 e trame da 4096.
 */
export function valutaWebgl(info) {
  if (!info || !info.webgl2) return { ok: false, motivo: 'webgl2' };
  if ((info.maxTrama ?? 0) < 4096) return { ok: false, motivo: 'trame' };
  const r = `${info.renderer ?? ''}`.toLowerCase();
  if (!info.software && /(swiftshader|llvmpipe|softpipe|software)/.test(r)) return { ok: false, motivo: 'software' };
  if (info.memoria !== undefined && info.memoria < 2) return { ok: false, motivo: 'memoria' };
  return { ok: true, motivo: null };
}

/**
 * Le prestazioni dai tempi fra un fotogramma e l'altro (ms), presi mentre
 * la mappa si muove: la mediana e il 90° percentile. Lento se la mediana
 * sta sotto [FPS_MINIMI], o se un fotogramma su dieci ci mette più di 120 ms.
 */
export function valutaPrestazioni(intervalli) {
  const v = intervalli.filter((x) => x > 0 && x < 2000).sort((a, b) => a - b);
  if (v.length < 30) return null;
  const mediana = v[Math.floor(v.length / 2)];
  const p90 = v[Math.floor(v.length * 0.9)];
  const fps = 1000 / mediana;
  return { fps: Math.round(fps * 10) / 10, p90: Math.round(p90), lento: fps < FPS_MINIMI || p90 > 120 };
}
