import 'dart:math' as math;

import '../distributori/distributori.dart';
import '../motore/modello_consumo.dart';
import '../veicolo/profilo_veicolo.dart';

/// Il modello di consumo dell'auto, come lo vuole TomTom: con quello ogni
/// percorso torna col suo consumo stimato (`batteryConsumptionInkWh`, o
/// `fuelConsumptionInLiters` per la termica), salite e discese comprese, e la
/// strada «eco» si sceglie per quell'auto e non per una media.
///
/// Per l'elettrica si parte dallo stesso profilo con cui gdanav calcola le
/// soste: la curva del consumo a velocità costante (aria e rotolamento), i
/// consumi fissi come potenza a parte, il peso, e i rendimenti di trazione e
/// recupero per le salite e le discese. Per la termica una curva da auto
/// media, un po' più bassa col gasolio e più alta col GPL.
class ModelloConsumoTomTom {
  const ModelloConsumoTomTom._(this.parametri, {required this.elettrica, this.unita = 'kWh'});

  factory ModelloConsumoTomTom.elettrica(ProfiloVeicolo p, [Condizioni c = const Condizioni()]) {
    final curva = [
      for (final v in velocita) '$v,${consumoCostanteKwh100(v.toDouble(), p, c).toStringAsFixed(2)}',
    ].join(':');
    // TomTom vuole il prodotto dei due rendimenti non oltre uno.
    final avanti = p.rendimentoTrazione.clamp(0.3, 0.98).toDouble();
    final indietro = math.min(p.rendimentoRecupero.clamp(0.05, 0.95).toDouble(), 1 / avanti);
    String due(double x) => x.toStringAsFixed(2);
    return ModelloConsumoTomTom._({
      'vehicleEngineType': const ['electric'],
      'constantSpeedConsumptionInkWhPerHundredkm': [curva],
      'auxiliaryPowerInkW': [due((p.consumoFissoW + c.climaW) * c.fattoreConsumo / 1000)],
      'vehicleWeight': ['${p.massaKg.round()}'],
      'accelerationEfficiency': [due(avanti)],
      'decelerationEfficiency': [due(indietro)],
      'uphillEfficiency': [due(avanti)],
      'downhillEfficiency': [due(indietro)],
    }, elettrica: true);
  }

  factory ModelloConsumoTomTom.termica(Carburante carburante) {
    final k = fattoreCarburante(carburante);
    final curva = [
      for (final (v, l) in curvaTermica) '$v,${(l * k).toStringAsFixed(2)}',
    ].join(':');
    return ModelloConsumoTomTom._({
      'vehicleEngineType': const ['combustion'],
      'constantSpeedConsumptionInLitersPerHundredkm': [curva],
    }, elettrica: false, unita: carburante == Carburante.metano ? 'kg' : 'l');
  }

  /// Le velocità della curva per l'elettrica, in km/h.
  static const velocita = [10, 30, 50, 70, 90, 110, 130];

  /// Litri ogni 100 km di un'auto media a benzina, a velocità costante.
  static const curvaTermica = [(30, 7.2), (50, 6.1), (70, 5.5), (90, 5.8), (110, 6.8), (130, 8.3)];

  /// Il gasolio ne fa meno, il GPL di più; il metano si conta in kg.
  static double fattoreCarburante(Carburante c) => switch (c) {
        Carburante.benzina => 1.0,
        Carburante.diesel => 0.82,
        Carburante.gpl => 1.28,
        Carburante.metano => 0.68,
      };

  /// I parametri da aggiungere alla richiesta del percorso.
  final Map<String, List<String>> parametri;

  final bool elettrica;

  /// «kWh», «l» o «kg»: di cosa è il consumo.
  final String unita;

  /// Il consumo di un tratto con la curva della termica, in litri (o kg),
  /// per quando TomTom non l'ha detto.
  static double litriTratto(double lunghezzaM, double kmh, Carburante carburante) {
    final curva = curvaTermica;
    double l;
    if (kmh <= curva.first.$1) {
      l = curva.first.$2;
    } else {
      // Fra due punti della curva, o oltre l'ultimo sulla stessa pendenza.
      var i = 1;
      while (i < curva.length - 1 && curva[i].$1 < kmh) {
        i++;
      }
      final (v1, l1) = curva[i - 1];
      final (v2, l2) = curva[i];
      l = l1 + (kmh - v1) * (l2 - l1) / (v2 - v1);
    }
    return l * fattoreCarburante(carburante) * lunghezzaM / 100000;
  }
}
