// Un costruttore di geometrie a indici: vertici (posizione, normale, uv,
// colore di giorno e di notte) e triangoli. Lavora con numeri semplici, così
// si usa anche nel lavoratore e nelle prove, senza three.js.

export class Costruttore {
  constructor({ uv = false, colori = false } = {}) {
    this.conUv = uv;
    this.conColori = colori;
    this.p = [];
    this.n = [];
    this.t = [];
    this.c = [];
    this.cn = [];
    this.i = [];
  }

  get vertici() {
    return this.p.length / 3;
  }

  get triangoli() {
    return this.i.length / 3;
  }

  /** Un vertice; restituisce il suo indice. [cg]/[cn]: colori 0..255. */
  v(x, y, z, nx, ny, nz, u = 0, w = 0, cg = null, cn = null) {
    this.p.push(x, y, z);
    this.n.push(nx, ny, nz);
    if (this.conUv) this.t.push(u, w);
    if (this.conColori) {
      const g = cg ?? [255, 255, 255];
      const n = cn ?? g;
      this.c.push(g[0], g[1], g[2]);
      this.cn.push(n[0], n[1], n[2]);
    }
    return this.p.length / 3 - 1;
  }

  tri(a, b, c) {
    this.i.push(a, b, c);
  }

  /**
   * Un triangolo di punti `[x, y, z, u, v]`, girato in modo che la sua
   * normale geometrica vada come [n].
   */
  triPunti(a, b, c, n, cg, cn) {
    const ux = b[0] - a[0];
    const uy = b[1] - a[1];
    const uz = b[2] - a[2];
    const vx = c[0] - a[0];
    const vy = c[1] - a[1];
    const vz = c[2] - a[2];
    const gx = uy * vz - uz * vy;
    const gy = uz * vx - ux * vz;
    const gz = ux * vy - uy * vx;
    if (gx * n[0] + gy * n[1] + gz * n[2] < 0) [b, c] = [c, b];
    const ia = this.v(a[0], a[1], a[2], n[0], n[1], n[2], a[3] ?? 0, a[4] ?? 0, cg, cn);
    const ib = this.v(b[0], b[1], b[2], n[0], n[1], n[2], b[3] ?? 0, b[4] ?? 0, cg, cn);
    const ic = this.v(c[0], c[1], c[2], n[0], n[1], n[2], c[3] ?? 0, c[4] ?? 0, cg, cn);
    this.tri(ia, ib, ic);
  }

  /**
   * Un quadrilatero a-b-c-d (in giro), con quattro vertici e due triangoli.
   * [cg]/[cn]: un colore per tutti, o quattro (uno per vertice: le ombre
   * negli angoli del cemento).
   */
  quad(a, b, c, d, n, cg, cn) {
    const ux = b[0] - a[0];
    const uy = b[1] - a[1];
    const uz = b[2] - a[2];
    const vx = c[0] - a[0];
    const vy = c[1] - a[1];
    const vz = c[2] - a[2];
    const gx = uy * vz - uz * vy;
    const gy = uz * vx - ux * vz;
    const gz = ux * vy - uy * vx;
    const giro = gx * n[0] + gy * n[1] + gz * n[2] < 0;
    const uno = (c, i) => (c && Array.isArray(c[0]) ? c[i] : c);
    const q = [a, b, c, d].map((p, i) => this.v(p[0], p[1], p[2], n[0], n[1], n[2], p[3] ?? 0, p[4] ?? 0, uno(cg, i), uno(cn, i)));
    if (giro) {
      this.tri(q[0], q[2], q[1]);
      this.tri(q[0], q[3], q[2]);
    } else {
      this.tri(q[0], q[1], q[2]);
      this.tri(q[0], q[2], q[3]);
    }
  }

  /** I dati pronti da spedire: array tipizzati (e la lista da trasferire). */
  fatto() {
    const out = {
      posizioni: new Float32Array(this.p),
      normali: Int8Array.from(this.n, (v) => Math.round(Math.max(-1, Math.min(1, v)) * 127)),
      indici: this.vertici > 65535 ? new Uint32Array(this.i) : new Uint16Array(this.i),
    };
    if (this.conUv) out.uv = new Float32Array(this.t);
    if (this.conColori) {
      out.colori = new Uint8Array(this.c);
      out.coloriNotte = new Uint8Array(this.cn);
    }
    return out;
  }
}

/** I buffer di una geometria fatta, da trasferire al thread principale. */
export function daTrasferire(g, lista = []) {
  if (!g) return lista;
  for (const k of ['posizioni', 'normali', 'indici', 'uv', 'colori', 'coloriNotte', 'matrici']) {
    if (g[k]) lista.push(g[k].buffer);
  }
  return lista;
}

/** Una matrice 4x4 (colonne, come three.js) da posizione, rotazione attorno a z e scala. */
export function matrice(out, o, x, y, z, ang, sx, sy, sz) {
  const c = Math.cos(ang);
  const s = Math.sin(ang);
  out[o + 0] = c * sx;
  out[o + 1] = s * sx;
  out[o + 2] = 0;
  out[o + 3] = 0;
  out[o + 4] = -s * sy;
  out[o + 5] = c * sy;
  out[o + 6] = 0;
  out[o + 7] = 0;
  out[o + 8] = 0;
  out[o + 9] = 0;
  out[o + 10] = sz;
  out[o + 11] = 0;
  out[o + 12] = x;
  out[o + 13] = y;
  out[o + 14] = z;
  out[o + 15] = 1;
}
