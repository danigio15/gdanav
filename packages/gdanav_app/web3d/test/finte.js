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
    building: strato([
      { tipo: 3, p: { render_height: 12 }, g: [[[300, 300], [300, 400], [400, 400], [400, 300], [300, 300]]] },
      // Un capannone di 20 m proprio sotto il cavalcavia: si ferma sotto.
      { tipo: 3, p: { render_height: 20 }, g: [[[2020, 1700], [2020, 1760], [2080, 1760], [2080, 1700], [2020, 1700]]] },
    ]),
    transportation_name: strato([{ p: { class: 'primary', brunnel: 'bridge', name: 'Cavalcavia Bacula' }, g: [[[2048, 2600], [2048, 1500]]] }]),
    park: strato([{ tipo: 3, p: { class: 'park' }, g: [[[3000, 3000], [3000, 3800], [3800, 3800], [3800, 3000], [3000, 3000]]] }]),
  };
}

/** Il cavalcavia sopra un'autostrada a due carreggiate, con lo spartitraffico in mezzo. */
export function cavalcaviaDueCarreggiate() {
  const t = cavalcavia();
  t.transportation = strato([
    { p: { class: 'motorway', oneway: 1 }, g: [[[0, 2048], [4096, 2048]]] },
    { p: { class: 'motorway', oneway: 1 }, g: [[[4096, 2092], [0, 2092]]] },
    { p: { class: 'primary' }, g: [[[2070, 4096], [2070, 2600]]] },
    { p: { class: 'primary', brunnel: 'bridge', layer: 1 }, g: [[[2070, 2600], [2070, 1500]]] },
    { p: { class: 'primary' }, g: [[[2070, 1500], [2070, 0]]] },
  ]);
  return t;
}

/**
 * Il cavalcavia coi nomi come li danno le tessere: la rampa che sale al
 * ponte (non segnata come ponte) col suo nome, e la strada a terra lontana.
 */
export function cavalcaviaConRampa() {
  const t = cavalcavia();
  t.transportation_name = strato([
    { p: { class: 'primary', brunnel: 'bridge', name: 'Cavalcavia Bacula' }, g: [[[2048, 2600], [2048, 1500]]] },
    { p: { class: 'primary', name: 'Rampa Bacula' }, g: [[[2048, 3300], [2048, 2600]]] },
    { p: { class: 'motorway', name: 'Autostrada dei Laghi' }, g: [[[0, 2048], [1200, 2048]]] },
  ]);
  return t;
}

/** Un ponte lungo 1400 px (circa 600 m) da ovest a est, col suo nome. */
export function ponteLungo(nome) {
  return {
    transportation: strato([
      { p: { class: 'motorway', oneway: 1 }, g: [[[0, 2048], [1348, 2048]]] },
      { p: { class: 'motorway', oneway: 1, brunnel: 'bridge', layer: 1 }, g: [[[1348, 2048], [2748, 2048]]] },
      { p: { class: 'motorway', oneway: 1 }, g: [[[2748, 2048], [4096, 2048]]] },
    ]),
    // Come nelle tessere vere: il nome sulla linea intera, senza «brunnel».
    transportation_name: strato([{ p: { class: 'motorway', name: nome }, g: [[[0, 2048], [4096, 2048]]] }]),
  };
}

/** Un sottopasso: una strada in galleria sotto un viale, con le rampe aperte ai capi. */
export function sottopassoConNome() {
  const t = sottopasso();
  // Le tessere uniscono il pezzo in galleria e quelli aperti in una linea sola.
  t.transportation_name = strato([{ p: { class: 'primary', name: 'Viale Lunigiana' }, g: [[[2048, 4096], [2048, 0]]] }]);
  return t;
}

/** Un sottopasso: una strada in galleria sotto un viale, con le rampe aperte ai capi. */
export function sottopasso() {
  return {
    transportation: strato([
      { p: { class: 'primary' }, g: [[[2048, 4096], [2048, 2600]]] },
      { p: { class: 'primary', brunnel: 'tunnel', layer: -1 }, g: [[[2048, 2600], [2048, 1500]]] },
      { p: { class: 'primary' }, g: [[[2048, 1500], [2048, 0]]] },
      { p: { class: 'secondary' }, g: [[[0, 2048], [4096, 2048]]] },
    ]),
  };
}

/**
 * I byte di una tessera vettoriale (Mapbox Vector Tile 2) con gli strati
 * [strati] (`{nome: [{tipo, p, g}, …]}`, come [strato]): per provare il
 * lavoratore, che le tessere le riceve così.
 */
export async function byteTessera(strati) {
  const { default: Pbf } = await import('pbf');
  const pbf = new Pbf();
  const zz = (n) => (n << 1) ^ (n >> 31);
  for (const [nome, elementi] of Object.entries(strati)) {
    const chiavi = [];
    const valori = [];
    const indice = (arr, v) => {
      const k = arr.findIndex((x) => x === v);
      if (k >= 0) return k;
      arr.push(v);
      return arr.length - 1;
    };
    pbf.writeMessage(3, (_, p) => {
      p.writeVarintField(15, 2);
      p.writeStringField(1, nome);
      for (const e of elementi) {
        const tipo = e.tipo ?? 2;
        p.writeMessage(2, (__, q) => {
          const tag = [];
          for (const [k, v] of Object.entries(e.p ?? {})) tag.push(indice(chiavi, k), indice(valori, v));
          q.writePackedVarint(2, tag);
          q.writeVarintField(3, tipo);
          const geo = [];
          let cx = 0;
          let cy = 0;
          for (const linea0 of e.g) {
            const chiusa = tipo === 3 && linea0.length > 1 && linea0[0][0] === linea0.at(-1)[0] && linea0[0][1] === linea0.at(-1)[1];
            const linea = chiusa ? linea0.slice(0, -1) : linea0;
            linea.forEach(([x, y], i) => {
              if (i === 0) geo.push(1 | (1 << 3));
              else if (i === 1) geo.push(2 | ((linea.length - 1) << 3));
              geo.push(zz(x - cx), zz(y - cy));
              cx = x;
              cy = y;
            });
            if (tipo === 3) geo.push(7 | (1 << 3));
          }
          q.writePackedVarint(4, geo);
        });
      }
      for (const k of chiavi) p.writeStringField(3, k);
      for (const v of valori) {
        p.writeMessage(4, (___, q) => {
          if (typeof v === 'string') q.writeStringField(1, v);
          else if (typeof v === 'boolean') q.writeBooleanField(7, v);
          else if (Number.isInteger(v)) q.writeSVarintField(6, v);
          else q.writeDoubleField(3, v);
        });
      }
      p.writeVarintField(5, 4096);
    });
  }
  const b = pbf.finish();
  return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
}
