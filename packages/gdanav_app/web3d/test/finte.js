// Tessere vettoriali finte, con la stessa forma di @mapbox/vector-tile:
// `layers[nome].feature(i)` con `type`, `properties`, `loadGeometry()`.
export function strato(elementi) {
  return {
    length: elementi.length,
    feature: (i) => ({
      type: elementi[i].tipo ?? 2,
      properties: elementi[i].p,
      loadGeometry: () => elementi[i].g.map((linea) => linea.map(([x, y]) => ({ x, y }))),
    }),
  };
}

/**
 * Un incrocio a due livelli in mezzo alla tessera: un'autostrada a terra da
 * ovest a est, e una strada che le passa sopra da sud a nord su un ponte
 * (layer 1), con le rampe a terra prima e dopo.
 */
export function cavalcavia() {
  return {
    transportation: strato([
      { p: { class: 'motorway', oneway: 1 }, g: [[[0, 2048], [4096, 2048]]] },
      { p: { class: 'primary' }, g: [[[2048, 4096], [2048, 2600]]] },
      { p: { class: 'primary', brunnel: 'bridge', layer: 1 }, g: [[[2048, 2600], [2048, 1500]]] },
      { p: { class: 'primary' }, g: [[[2048, 1500], [2048, 0]]] },
    ]),
    building: strato([{ tipo: 3, p: { render_height: 12 }, g: [[[300, 300], [300, 400], [400, 400], [400, 300], [300, 300]]] }]),
    park: strato([{ tipo: 3, p: { class: 'park' }, g: [[[3000, 3000], [3000, 3800], [3800, 3800], [3800, 3000], [3000, 3000]]] }]),
  };
}
