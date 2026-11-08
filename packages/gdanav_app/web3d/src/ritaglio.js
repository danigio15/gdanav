// Ritagli di linee e poligoni su un rettangolo, aree, punti dentro.

/** Una linea tagliata sul rettangolo: i pezzi che ci stanno dentro (Liang-Barsky). */
export function ritagliaLinea(punti, minx, miny, maxx, maxy) {
  const fuori = [];
  let cur = null;
  for (let i = 0; i < punti.length - 1; i++) {
    const [x0, y0] = punti[i];
    const [x1, y1] = punti[i + 1];
    let t0 = 0;
    let t1 = 1;
    const dx = x1 - x0;
    const dy = y1 - y0;
    let ok = true;
    for (const [p, q] of [
      [-dx, x0 - minx],
      [dx, maxx - x0],
      [-dy, y0 - miny],
      [dy, maxy - y0],
    ]) {
      if (p === 0) {
        if (q < 0) {
          ok = false;
          break;
        }
      } else {
        const r = q / p;
        if (p < 0) {
          if (r > t1) {
            ok = false;
            break;
          }
          if (r > t0) t0 = r;
        } else {
          if (r < t0) {
            ok = false;
            break;
          }
          if (r < t1) t1 = r;
        }
      }
    }
    if (!ok) {
      if (cur) {
        fuori.push(cur);
        cur = null;
      }
      continue;
    }
    // Gli altri valori del punto (l'altezza) si interpolano anche loro.
    const a = punti[i].map((v, k) => v + (punti[i + 1][k] - v) * t0);
    const b = punti[i].map((v, k) => v + (punti[i + 1][k] - v) * t1);
    if (!cur) cur = [a];
    cur.push(b);
    if (t1 < 1) {
      fuori.push(cur);
      cur = null;
    }
  }
  if (cur) fuori.push(cur);
  return fuori.filter((l) => l.length > 1);
}

/** Un anello tagliato sul rettangolo (Sutherland-Hodgman); null se sparisce. */
export function ritagliaAnello(anello, minx, miny, maxx, maxy) {
  let pts = anello;
  const lati = [
    [(p) => p[0] >= minx, (a, b) => [minx, a[1] + ((minx - a[0]) / (b[0] - a[0])) * (b[1] - a[1])]],
    [(p) => p[0] <= maxx, (a, b) => [maxx, a[1] + ((maxx - a[0]) / (b[0] - a[0])) * (b[1] - a[1])]],
    [(p) => p[1] >= miny, (a, b) => [a[0] + ((miny - a[1]) / (b[1] - a[1])) * (b[0] - a[0]), miny]],
    [(p) => p[1] <= maxy, (a, b) => [a[0] + ((maxy - a[1]) / (b[1] - a[1])) * (b[0] - a[0]), maxy]],
  ];
  for (const [dentro, incrocio] of lati) {
    const res = [];
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i];
      const b = pts[(i + 1) % pts.length];
      const ia = dentro(a);
      const ib = dentro(b);
      if (ia) {
        res.push(a);
        if (!ib) res.push(incrocio(a, b));
      } else if (ib) res.push(incrocio(a, b));
    }
    pts = res;
    if (pts.length < 3) return null;
  }
  return pts;
}

/** Area con segno (shoelace, metà). */
export function area(anello) {
  let a = 0;
  for (let i = 0, j = anello.length - 1; i < anello.length; j = i++) {
    a += (anello[j][0] - anello[i][0]) * (anello[j][1] + anello[i][1]);
  }
  return a / 2;
}

/**
 * Gli anelli di un poligono MVT raggruppati: il primo di ogni gruppo è il
 * contorno, gli altri i buchi. In MVT (y in giù) il contorno ha area positiva.
 */
export function anelliPoligoni(geometria) {
  const poligoni = [];
  let cur = null;
  for (const anello of geometria) {
    const r = anello.map((p) => [p.x, p.y]);
    if (r.length > 1 && r[0][0] === r[r.length - 1][0] && r[0][1] === r[r.length - 1][1]) r.pop();
    if (r.length < 3) continue;
    const a = area(r);
    if (a === 0) continue;
    if (a > 0 || !cur) {
      cur = [r];
      poligoni.push(cur);
    } else cur.push(r);
  }
  return poligoni;
}

export function puntoDentroAnello(x, y, anello) {
  let dentro = false;
  for (let i = 0, j = anello.length - 1; i < anello.length; j = i++) {
    const [xi, yi] = anello[i];
    const [xj, yj] = anello[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) dentro = !dentro;
  }
  return dentro;
}

export const puntoDentroPoligono = (x, y, anelli) =>
  puntoDentroAnello(x, y, anelli[0]) && !anelli.slice(1).some((r) => puntoDentroAnello(x, y, r));

/** La distanza del punto dal segmento. */
export function distanzaSegmento(px, py, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  const l = dx * dx + dy * dy;
  let t = l ? ((px - ax) * dx + (py - ay) * dy) / l : 0;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - ax - t * dx, py - ay - t * dy);
}
