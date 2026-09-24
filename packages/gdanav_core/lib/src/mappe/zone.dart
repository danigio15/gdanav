import 'dart:math' as math;

import '../geo/geo.dart';

/// Una zona da scaricare per usare la mappa senza rete.
class Zona {
  const Zona(this.id, this.nome, this.sud, this.ovest, this.nord, this.est);

  /// Un quadrato di [raggioKm] intorno a un punto.
  factory Zona.intorno(Punto centro, {double raggioKm = 30, String nome = 'Intorno a te'}) {
    final dLat = raggioKm / 111.0;
    final dLon = dLat / math.cos(centro.lat * math.pi / 180).abs().clamp(0.2, 1.0);
    return Zona(
      'intorno-${centro.lat.toStringAsFixed(2)}-${centro.lon.toStringAsFixed(2)}',
      nome,
      centro.lat - dLat,
      centro.lon - dLon,
      centro.lat + dLat,
      centro.lon + dLon,
    );
  }

  final String id;
  final String nome;
  final double sud, ovest, nord, est;

  /// I riquadri di mappa da scaricare fino a [zoomMassimo]: le mappe
  /// vettoriali arrivano a 14, oltre si ingrandiscono quelle.
  int riquadri({int zoomMinimo = 0, int zoomMassimo = 14}) {
    var totale = 0;
    for (var z = zoomMinimo; z <= zoomMassimo; z++) {
      final n = 1 << z;
      int x(double lon) => ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
      int y(double lat) {
        final r = lat * math.pi / 180;
        return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor().clamp(0, n - 1);
      }

      totale += (x(est) - x(ovest) + 1) * (y(sud) - y(nord) + 1);
    }
    return totale;
  }

  /// Quanto occupa, a spanne: una ventina di KB a riquadro in media fra città
  /// (di più) e campagna (molto meno).
  double megabyteStimati({int zoomMassimo = 14}) => riquadri(zoomMassimo: zoomMassimo) * 20 / 1024;
}

/// Le regioni d'Italia, per riquadro.
const regioniItalia = [
  Zona('abruzzo', 'Abruzzo', 41.68, 13.02, 42.90, 14.79),
  Zona('basilicata', 'Basilicata', 39.90, 15.33, 41.14, 16.87),
  Zona('calabria', 'Calabria', 37.91, 15.63, 40.15, 17.21),
  Zona('campania', 'Campania', 39.99, 13.76, 41.51, 15.81),
  Zona('emilia-romagna', 'Emilia-Romagna', 43.73, 9.20, 45.14, 12.76),
  Zona('friuli-venezia-giulia', 'Friuli-Venezia Giulia', 45.58, 12.32, 46.65, 13.92),
  Zona('lazio', 'Lazio', 40.78, 11.45, 42.84, 14.03),
  Zona('liguria', 'Liguria', 43.77, 7.49, 44.68, 10.07),
  Zona('lombardia', 'Lombardia', 44.68, 8.50, 46.64, 11.43),
  Zona('marche', 'Marche', 42.69, 12.19, 43.97, 13.92),
  Zona('molise', 'Molise', 41.36, 13.94, 42.07, 15.16),
  Zona('piemonte', 'Piemonte', 44.06, 6.63, 46.46, 9.21),
  Zona('puglia', 'Puglia', 39.79, 14.93, 42.23, 18.52),
  Zona('sardegna', 'Sardegna', 38.86, 8.13, 41.31, 9.83),
  Zona('sicilia', 'Sicilia', 36.64, 12.42, 38.81, 15.65),
  Zona('toscana', 'Toscana', 42.24, 9.69, 44.47, 12.37),
  Zona('trentino-alto-adige', 'Trentino-Alto Adige', 45.67, 10.38, 47.09, 12.48),
  Zona('umbria', 'Umbria', 42.36, 11.89, 43.62, 13.26),
  Zona('valle-d-aosta', "Valle d'Aosta", 45.47, 6.80, 45.99, 7.94),
  Zona('veneto', 'Veneto', 44.79, 10.62, 46.68, 13.10),
];
