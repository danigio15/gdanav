/// Da dove arriva un dato dell'auto. L'ordine non conta: la priorità la
/// decide l'[ArbitroSorgenti].
enum TipoSorgente {
  /// Android Automotive: l'app gira dentro l'auto.
  automotive,

  /// Android Auto: il telefono chiede i dati all'auto con `CarInfo`.
  androidAuto,

  /// Dongle OBD-II via Bluetooth LE.
  obd,

  /// gdahome: l'auto della sezione Auto della sua plancia, quando gdanav gira
  /// dentro l'app gdahome. Senza abbinamento: la casa è già collegata lì.
  gdahome,

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
    this.temperaturaEsternaC,
    this.velocitaKmh,
    this.potenzaKw,
    this.odometroKm,
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

  /// Per il clima nel modello di consumo.
  final double? temperaturaEsternaC;

  /// La velocità vista dall'auto: più precisa del GPS, per il tachimetro.
  final double? velocitaKmh;

  /// La potenza presa dalla batteria adesso, positiva quando consuma e
  /// negativa quando recupera o si carica.
  final double? potenzaKw;

  /// Il contachilometri: i chilometri veri fra due letture.
  final double? odometroKm;

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
    temperaturaEsternaC: temperaturaEsternaC,
    velocitaKmh: velocitaKmh,
    potenzaKw: potenzaKw,
    odometroKm: odometroKm,
  );

  @override
  String toString() => 'StatoAuto(${sorgente.name}, ${batteria.toStringAsFixed(1)}%, $letto)';
}
