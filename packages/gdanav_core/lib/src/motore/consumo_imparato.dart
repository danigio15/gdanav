import 'dart:math' as math;

import '../percorso/valhalla.dart';
import 'modello_consumo.dart';

/// Quanto consuma davvero la tua auto rispetto al modello, imparato
/// guidando, come fa ABRP: si confronta l'energia prevista per un tratto con
/// quella tolta alla batteria (calo di percentuale per la capacità).
///
/// È una media pesata sui chilometri, con la memoria degli ultimi 300 km:
/// un viaggio d'inverno o in autostrada sposta il fattore, poi si riassesta.
class ConsumoImparato {
  const ConsumoImparato({this.fattore = 1, this.kmOsservati = 0});

  factory ConsumoImparato.daJson(Map<String, Object?> j) => ConsumoImparato(
        fattore: ((j['fattore'] as num?)?.toDouble() ?? 1).clamp(minimo, massimo).toDouble(),
        kmOsservati: (j['km'] as num?)?.toDouble() ?? 0,
      );

  final double fattore;
  final double kmOsservati;

  static const minimo = 0.6, massimo = 1.8;
  static const memoriaKm = 300.0;

  /// Un tratto misurato: [previstoWh] dal modello (senza correttivo),
  /// [realeWh] dalla batteria, lungo [km].
  ConsumoImparato con({required double previstoWh, required double realeWh, required double km}) {
    if (previstoWh <= 0 || realeWh <= 0 || km <= 0) return this;
    final rapporto = (realeWh / previstoWh).clamp(minimo, massimo);
    final peso = km / (math.min(kmOsservati, memoriaKm) + km);
    return ConsumoImparato(fattore: fattore + (rapporto - fattore) * peso, kmOsservati: kmOsservati + km);
  }

  /// In percentuale, per dirlo all'utente: «+8%».
  int get scartoPercento => ((fattore - 1) * 100).round();

  Map<String, Object?> toJson() => {'fattore': fattore, 'km': kmOsservati};
}

/// Una misura del consumo su un tratto guidato.
class MisuraConsumo {
  const MisuraConsumo({required this.previstoWh, required this.realeWh, required this.km});
  final double previstoWh;
  final double realeWh;
  final double km;

  double get realeWhKm => realeWh / km;
}

/// Segue il viaggio con i dati veri della batteria: a ogni lettura dice se
/// c'è una misura nuova del consumo (almeno 2 punti di batteria e un
/// chilometro dall'ultima), confrontata con quello che il modello prevedeva
/// per le stesse strade.
class MisuratoreConsumo {
  MisuratoreConsumo({
    required PercorsoCalcolato percorso,
    required this.capacitaKwh,
    required ProfiloConsumo profilo,
    this.passoPercento = 2,
  }) {
    // Energia prevista cumulata lungo i tratti, senza correttivo: il fattore
    // lo si vuole misurare, non presupporre.
    var m = 0.0, wh = 0.0;
    _metri.add(0);
    _wh.add(0);
    for (final t in percorso.tratti) {
      m += t.lunghezzaM;
      wh += profilo(t);
      _metri.add(m);
      _wh.add(wh);
    }
  }

  final double capacitaKwh;

  /// Quanti punti di batteria servono per una misura: la batteria si legge
  /// all'1%, sotto i 2 punti l'errore è troppo grande.
  final double passoPercento;

  final _metri = <double>[];
  final _wh = <double>[];
  ({double batteria, double metri})? _da;

  /// L'energia prevista dall'inizio fino a [metri] lungo il percorso.
  double previstaFinoA(double metri) {
    if (metri <= 0) return 0;
    if (metri >= _metri.last) return _wh.last;
    var lo = 0, hi = _metri.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_metri[mid] <= metri) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (metri - _metri[lo]) / (_metri[hi] - _metri[lo]);
    return _wh[lo] + t * (_wh[hi] - _wh[lo]);
  }

  /// Una lettura della batteria vera a [metri] dall'inizio del percorso.
  /// Durante una ricarica non si misura: si riparte da dopo.
  MisuraConsumo? registra({required double batteria, required double metri, bool inCarica = false}) {
    final da = _da;
    if (da == null || inCarica || batteria > da.batteria || metri < da.metri) {
      _da = (batteria: batteria, metri: metri);
      return null;
    }
    final calo = da.batteria - batteria;
    final percorsi = metri - da.metri;
    if (calo < passoPercento || percorsi < 1000) return null;
    _da = (batteria: batteria, metri: metri);
    final previsto = previstaFinoA(metri) - previstaFinoA(da.metri);
    return MisuraConsumo(previstoWh: previsto, realeWh: calo / 100 * capacitaKwh * 1000, km: percorsi / 1000);
  }
}

/// L'energia di un tratto, in Wh: di solito [energiaTrattoWh] con il profilo
/// dell'auto e le condizioni del momento.
typedef ProfiloConsumo = double Function(Tratto t);
