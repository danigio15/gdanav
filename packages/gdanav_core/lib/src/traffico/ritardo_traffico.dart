import 'dart:math' as math;

import '../percorso/valhalla.dart';

/// Il ritardo per il traffico: quanto se ne dichiara, quanto ne resta davanti
/// e come lo si dice a chi guida.
///
/// «Nel navigatore devi correggere il tempo di percorrenza in funzione del
/// traffico: devi calcolare il ritardo dovuto al traffico, e l'ora di arrivo
/// va allungata.» I tempi dei tratti hanno già dentro il traffico
/// ([PercorsoCalcolato.conTraffico], o i tempi di TomTom): qui ci sono i
/// conti puri che servono a dirlo bene.

/// Quanto si perde in tutto per il traffico, dal sommario di una rotta di
/// TomTom (`routes[0].summary`): la differenza col tempo senza traffico
/// (il rallentamento normale, fuori dalle code), o il ritardo degli eventi
/// segnalati se è di più. Mai negativo, e mai più di [tetto] — un numero
/// sballato non deve allungare un viaggio di ore.
Duration ritardoDalSommario(Map<String, Object?> sommario, {Duration tetto = const Duration(hours: 3)}) {
  double n(Object? x) => x is num ? x.toDouble() : 0;
  final conTraffico = n(sommario['travelTimeInSeconds']);
  final senza = n(sommario['noTrafficTravelTimeInSeconds']);
  final differenza = conTraffico > 0 && senza > 0 ? conTraffico - senza : 0.0;
  final dichiarato = n(sommario['trafficDelayInSeconds']);
  final secondi = math.max(0.0, math.max(differenza, dichiarato));
  return Duration(seconds: math.min(secondi, tetto.inSeconds.toDouble()).round());
}

/// Quanto ritardo per il traffico resta davanti, su un percorso di cui non
/// si ha la versione senza traffico (TomTom dà i tempi col traffico già
/// dentro): le code ancora davanti per la loro parte non fatta, più il
/// rallentamento sparso (il ritardo che non sta nelle code) in proporzione
/// al tempo che resta ([quotaTempoRestante], da 0 a 1).
Duration ritardoTrafficoAvanti(
  PercorsoCalcolato percorso, {
  required double percorsiM,
  required double quotaTempoRestante,
}) {
  if (!percorso.trafficoVero) return Duration.zero;
  var nelleCode = 0.0, davanti = 0.0;
  for (final c in percorso.code) {
    final secondi = c.ritardo.inMilliseconds / 1000;
    nelleCode += secondi;
    if (c.aM <= percorsiM || secondi <= 0) continue;
    final lunga = c.lunghezzaM;
    final restaDentro = lunga <= 0 ? 1.0 : ((c.aM - math.max(c.daM, percorsiM)) / lunga).clamp(0.0, 1.0);
    davanti += secondi * restaDentro;
  }
  final sparso = math.max(0.0, percorso.ritardoTraffico.inMilliseconds / 1000 - nelleCode);
  davanti += sparso * quotaTempoRestante.clamp(0.0, 1.0);
  return Duration(seconds: davanti.round());
}

/// Quanto è grave un ritardo, per il colore: 0 niente (sotto il minuto non
/// si dice), 1 arancio, 2 rosso (da [rossoDaMinuti] in su).
int gravitaRitardo(int minuti, {int rossoDaMinuti = 10}) => minuti < 1 ? 0 : (minuti >= rossoDaMinuti ? 2 : 1);

/// «+7 min di traffico», «+1 h 05 di traffico»; vuota sotto il minuto.
String testoRitardoTraffico(int minuti) {
  if (minuti < 1) return '';
  if (minuti < 60) return '+$minuti min di traffico';
  final ore = minuti ~/ 60, resto = minuti % 60;
  return resto == 0 ? '+$ore h di traffico' : '+$ore h ${resto.toString().padLeft(2, '0')} di traffico';
}

/// Il ritardo da mostrare, in minuti interi, senza farlo ballare.
///
/// Il conto cambia a ogni lettura del GPS (le code si avvicinano, si
/// attraversano) e a ogni traffico riletto: scritto così com'è, il «+7»
/// diventerebbe «+6», «+7», «+6» a ogni secondo. Si cambia il numero solo
/// quando quello nuovo se ne scosta di almeno [scarto] minuti, o quando si
/// scende sotto il minuto (finita la coda, la scritta se ne va).
class RitardoMostrato {
  RitardoMostrato({this.scarto = 1.5});

  final double scarto;
  int _minuti = 0;
  bool _visto = false;

  int get minuti => _minuti;

  /// Con il ritardo che resta adesso, i minuti da scrivere.
  int aggiorna(Duration ritardo) {
    final esatti = ritardo.inMilliseconds / 60000;
    if (esatti < 1) {
      _minuti = 0;
      _visto = true;
      return 0;
    }
    if (!_visto || _minuti == 0 || (esatti - _minuti).abs() >= scarto) _minuti = esatti.round();
    _visto = true;
    return _minuti;
  }

  /// Un'altra strada: si riparte da capo.
  void azzera() {
    _minuti = 0;
    _visto = false;
  }
}
