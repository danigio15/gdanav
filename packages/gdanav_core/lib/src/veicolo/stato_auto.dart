/// Da dove arriva un dato dell'auto. L'ordine non conta: la priorità la
/// decide l'[ArbitroSorgenti].
enum TipoSorgente {
  /// Android Automotive: l'app gira dentro l'auto.
  automotive,

  /// Android Auto: il telefono chiede i dati all'auto con `CarInfo`.
  androidAuto,

  /// Dongle OBD-II via Bluetooth LE.
  obd,

  /// Home Assistant, attraverso l'integrazione gdanav.
  homeAssistant,

  /// L'utente ha scritto la batteria a mano.
  manuale,

  /// Nessun dato fresco: la batteria è stimata dal modello di consumo.
  stima,
}

/// Una fotografia dell'auto, sempre con la sua sorgente e la sua ora.
///
/// Ogni campo tranne [batteria] può mancare: le sorgenti non sanno tutte le
/// stesse cose (Android Auto non conosce il clima, il manuale conosce solo la
/// batteria).
class StatoAuto {
  const StatoAuto({
    required this.sorgente,
    required this.letto,
    required this.batteria,
    this.autonomiaKm,
    this.inCarica,
    this.potenzaCaricaKw,
    this.temperaturaBatteriaC,
    this.latitudine,
    this.longitudine,
  });

  final TipoSorgente sorgente;

  /// Quando l'auto ha misurato il dato, non quando è arrivato al telefono.
  final DateTime letto;

  /// Stato di carica, da 0 a 100.
  final double batteria;

  final double? autonomiaKm;
  final bool? inCarica;
  final double? potenzaCaricaKw;
  final double? temperaturaBatteriaC;
  final double? latitudine;
  final double? longitudine;

  Duration eta(DateTime ora) => ora.difference(letto);

  StatoAuto conBatteria(double batteria, {TipoSorgente? sorgente, DateTime? letto}) => StatoAuto(
        sorgente: sorgente ?? this.sorgente,
        letto: letto ?? this.letto,
        batteria: batteria.clamp(0, 100).toDouble(),
        autonomiaKm: autonomiaKm,
        inCarica: inCarica,
        potenzaCaricaKw: potenzaCaricaKw,
        temperaturaBatteriaC: temperaturaBatteriaC,
        latitudine: latitudine,
        longitudine: longitudine,
      );

  @override
  String toString() => 'StatoAuto(${sorgente.name}, ${batteria.toStringAsFixed(1)}%, $letto)';
}
