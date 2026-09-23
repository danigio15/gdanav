import 'dart:math' as math;

import '../veicolo/profilo_veicolo.dart';

const _g = 9.81;

/// Un pezzo di strada a velocità e pendenza costanti, come arriva da
/// Valhalla dopo averlo spezzato per limite di velocità e quota.
class Tratto {
  const Tratto({required this.lunghezzaM, required this.velocitaKmh, this.dislivelloM = 0});

  final double lunghezzaM;
  final double velocitaKmh;

  /// Positivo in salita, negativo in discesa.
  final double dislivelloM;

  double get secondi => lunghezzaM / (velocitaKmh / 3.6);
}

/// Quello che il meteo e l'abitacolo aggiungono.
class Condizioni {
  const Condizioni({this.temperaturaC = 20, this.ventoControMs = 0, this.climaW = 0});

  /// Il clima stimato dalla temperatura esterna: niente fra 18 e 26 gradi,
  /// poi riscaldamento o raffrescamento proporzionali, con un tetto.
  factory Condizioni.daMeteo({required double temperaturaC, double ventoControMs = 0}) {
    final caldo = math.min(3000.0, math.max(0.0, 18 - temperaturaC) * 150);
    final freddo = math.min(1500.0, math.max(0.0, temperaturaC - 26) * 100);
    return Condizioni(temperaturaC: temperaturaC, ventoControMs: ventoControMs, climaW: caldo + freddo);
  }

  final double temperaturaC;

  /// Vento contrario positivo, a favore negativo.
  final double ventoControMs;

  final double climaW;

  /// Densità dell'aria alla temperatura data, al livello del mare.
  double get densitaAria => 101325 / (287.05 * (temperaturaC + 273.15));
}

/// L'energia presa dalla batteria per percorrere il [tratto], in Wh.
/// Negativa quando in discesa si recupera più di quanto si spende.
double energiaTrattoWh(Tratto tratto, ProfiloVeicolo p, [Condizioni c = const Condizioni()]) {
  final v = tratto.velocitaKmh / 3.6;
  final d = tratto.lunghezzaM;
  final aria = v + c.ventoControMs;

  final aerodinamica = 0.5 * c.densitaAria * p.cdA * aria * aria.abs();
  final rotolamento = p.massaKg * _g * p.crr;
  final ruota = (aerodinamica + rotolamento) * d + p.massaKg * _g * tratto.dislivelloM;

  final batteria = ruota >= 0 ? ruota / p.rendimentoTrazione : ruota * p.rendimentoRecupero;
  final fissi = (p.consumoFissoW + c.climaW) * tratto.secondi;
  return (batteria + fissi) / 3600;
}

/// Consumo medio in Wh/km, il numero che si mostra all'utente.
double consumoMedioWhKm(List<Tratto> tratti, ProfiloVeicolo p, [Condizioni c = const Condizioni()]) {
  var wh = 0.0, m = 0.0;
  for (final t in tratti) {
    wh += energiaTrattoWh(t, p, c);
    m += t.lunghezzaM;
  }
  return m == 0 ? 0 : wh / (m / 1000);
}
