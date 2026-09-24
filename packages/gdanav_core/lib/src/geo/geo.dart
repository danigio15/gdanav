import 'dart:math' as math;

/// Un punto sulla Terra, in gradi.
class Punto {
  const Punto(this.lat, this.lon);

  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) => other is Punto && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => '($lat, $lon)';
}

const _raggioTerraM = 6371008.8;

double _rad(double gradi) => gradi * math.pi / 180;

/// Distanza sul cerchio massimo, in metri.
double distanzaM(Punto a, Punto b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h =
      math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _raggioTerraM * math.asin(math.min(1, math.sqrt(h)));
}

/// La direzione da [a] a [b], in gradi da nord in senso orario (0–360).
double rottaGradi(Punto a, Punto b) {
  final f1 = _rad(a.lat), f2 = _rad(b.lat), dl = _rad(b.lon - a.lon);
  final y = math.sin(dl) * math.cos(f2);
  final x = math.cos(f1) * math.sin(f2) - math.sin(f1) * math.cos(f2) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Decodifica una polyline codificata: precisione 6 per Valhalla, 5 per
/// Google e Open Charge Map.
List<Punto> decodificaPolyline(String codificata, {int precisione = 6}) {
  final fattore = math.pow(10, precisione).toDouble();
  final punti = <Punto>[];
  var indice = 0, lat = 0, lon = 0;
  int prossimo() {
    var risultato = 0, spostamento = 0, b = 0;
    do {
      b = codificata.codeUnitAt(indice++) - 63;
      risultato |= (b & 0x1f) << spostamento;
      spostamento += 5;
    } while (b >= 0x20);
    return (risultato & 1) != 0 ? ~(risultato >> 1) : risultato >> 1;
  }

  while (indice < codificata.length) {
    lat += prossimo();
    lon += prossimo();
    punti.add(Punto(lat / fattore, lon / fattore));
  }
  return punti;
}

String codificaPolyline(List<Punto> punti, {int precisione = 5}) {
  final fattore = math.pow(10, precisione).toDouble();
  final out = StringBuffer();
  var latPrima = 0, lonPrima = 0;
  void scrivi(int valore) {
    var v = valore < 0 ? ~(valore << 1) : valore << 1;
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    out.writeCharCode(v + 63);
  }

  for (final p in punti) {
    final lat = (p.lat * fattore).round(), lon = (p.lon * fattore).round();
    scrivi(lat - latPrima);
    scrivi(lon - lonPrima);
    latPrima = lat;
    lonPrima = lon;
  }
  return out.toString();
}

/// Tiene un punto ogni [passoM] metri circa (più primo e ultimo): per
/// mandare un percorso lungo in un URL senza superarne la lunghezza.
List<Punto> semplifica(List<Punto> punti, double passoM) {
  if (punti.length <= 2) return punti;
  final out = [punti.first];
  var accumulato = 0.0;
  for (var i = 1; i < punti.length - 1; i++) {
    accumulato += distanzaM(punti[i - 1], punti[i]);
    if (accumulato >= passoM) {
      out.add(punti[i]);
      accumulato = 0;
    }
  }
  out.add(punti.last);
  return out;
}

/// Dove cade un punto rispetto a una linea: quanto lungo la linea (dalla
/// partenza) e quanto lontano da essa.
class Proiezione {
  const Proiezione({required this.lungoM, required this.lontanoM, this.segmento = 0, this.t = 0});
  final double lungoM;
  final double lontanoM;

  /// Il segmento più vicino (dal punto `segmento` al successivo) e dove ci
  /// si trova, da 0 a 1.
  final int segmento;
  final double t;
}

/// Una linea con le distanze cumulate già calcolate, per proiettarci sopra
/// tanti punti (le colonnine) senza ricalcolare tutto ogni volta.
class Linea {
  Linea(this.punti) : cumulate = _cumulate(punti);

  final List<Punto> punti;
  final List<double> cumulate;

  double get lunghezzaM => cumulate.last;

  static List<double> _cumulate(List<Punto> p) {
    final c = <double>[0];
    for (var i = 1; i < p.length; i++) {
      c.add(c.last + distanzaM(p[i - 1], p[i]));
    }
    return c;
  }

  /// Proiezione su ogni segmento, in un piano locale attorno al punto:
  /// alle distanze di qualche chilometro l'errore è trascurabile.
  Proiezione proietta(Punto q) => proiettaTra(q, 0, punti.length - 1);

  /// Come [proietta], ma solo sui segmenti da [da] ad [a] (esclusi i punti
  /// oltre): chi guida non salta dall'altra parte di un anello.
  Proiezione proiettaTra(Punto q, int da, int a) {
    final kx = math.cos(_rad(q.lat)) * _raggioTerraM * math.pi / 180;
    const ky = _raggioTerraM * math.pi / 180;
    var migliore = const Proiezione(lungoM: 0, lontanoM: double.infinity);
    for (var i = math.max(1, da + 1); i <= math.min(a, punti.length - 1); i++) {
      final a = punti[i - 1], b = punti[i];
      final ax = (a.lon - q.lon) * kx, ay = (a.lat - q.lat) * ky;
      final bx = (b.lon - q.lon) * kx, by = (b.lat - q.lat) * ky;
      final dx = bx - ax, dy = by - ay;
      final l2 = dx * dx + dy * dy;
      final t = l2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / l2).clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      final d = math.sqrt(px * px + py * py);
      if (d < migliore.lontanoM) {
        migliore = Proiezione(
          lungoM: cumulate[i - 1] + t * (cumulate[i] - cumulate[i - 1]),
          lontanoM: d,
          segmento: i - 1,
          t: t,
        );
      }
    }
    return migliore;
  }
}
