/// Da dove arriva un dato dell'auto. L'ordine non conta: la priorità la
/// decide l'[ArbitroSorgenti].
enum TipoSorgente {
  /// Android Automotive: l'app gira dentro l'auto.
  automotive,

  /// Android Auto: il telefono chiede i dati all'auto con `CarInfo`.
  androidAuto,

  /// Dongle OBD-II via Bluetooth LE.
  obd,

  /// GdAHome: l'auto della sezione Auto della sua plancia, quando GdANav gira
  /// dentro l'app GdAHome. Senza abbinamento: la casa è già collegata lì.
  gdahome,

  /// Home Assistant, attraverso l'integrazione GdANav.
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
    this.energiaKwh,
    this.capacitaKwh,
    this.consumoMedioKwh100,
    this.potenzaClimaW,
    this.climaAcceso,
    this.batteriaInRiscaldamento,
    this.temperaturaInternaC,
    this.stimataDa,
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

  /// L'energia che resta nella batteria, in kWh: un decimo di kWh invece
  /// dell'1%, così il consumo vero si misura dopo pochi km
  /// ([MisuratoreConsumo]).
  final double? energiaKwh;

  /// La capacità utile della batteria come la dice l'auto, al posto di
  /// quella del catalogo: vedi [capacitaVeraKwh].
  final double? capacitaKwh;

  /// Il consumo medio che l'auto ha misurato nelle ultime settimane, in kWh
  /// ogni 100 km.
  final double? consumoMedioKwh100;

  /// La potenza del riscaldatore (abitacolo e batteria), in W.
  final double? potenzaClimaW;

  final bool? climaAcceso;

  /// La batteria si sta scaldando: costa qualche kWh, e poi si ricarica più
  /// in fretta.
  final bool? batteriaInRiscaldamento;

  final double? temperaturaInternaC;

  /// Per una [TipoSorgente.stima]: la sorgente della lettura vera da cui la
  /// stima parte (la batteria di Home Assistant, meno quello che si è
  /// consumato dopo). `null` per una lettura vera.
  final TipoSorgente? stimataDa;

  Duration eta(DateTime ora) => ora.difference(letto);

  /// La capacità utile vera della batteria, in kWh, se l'auto la fa sapere:
  /// quella che dice, oppure l'energia che resta divisa per la percentuale
  /// (sopra il 10%, perché sotto un punto di batteria pesa troppo). `null`
  /// se non la si sa o se il numero non è una batteria d'auto: allora vale
  /// quella del catalogo.
  double? get capacitaVeraKwh {
    bool buona(double? kwh) => kwh != null && kwh.isFinite && kwh >= 10 && kwh <= 250;
    if (buona(capacitaKwh)) return capacitaKwh;
    final e = energiaKwh;
    if (e == null || batteria < 10) return null;
    final dallEnergia = e / batteria * 100;
    return buona(dallEnergia) ? dallEnergia : null;
  }

  /// La stessa lettura con un'altra batteria (la stima dell'arbitro):
  /// [energiaKwh] scende con lei, se l'auto la dice.
  StatoAuto conBatteria(
    double batteria, {
    TipoSorgente? sorgente,
    DateTime? letto,
    double? autonomiaKm,
    double? energiaKwh,
    TipoSorgente? stimataDa,
  }) =>
      StatoAuto(
        sorgente: sorgente ?? this.sorgente,
        letto: letto ?? this.letto,
        batteria: batteria.clamp(0, 100).toDouble(),
        autonomiaKm: autonomiaKm ?? this.autonomiaKm,
        inCarica: inCarica,
        potenzaCaricaKw: potenzaCaricaKw,
        temperaturaBatteriaC: temperaturaBatteriaC,
        latitudine: latitudine,
        longitudine: longitudine,
        temperaturaEsternaC: temperaturaEsternaC,
        velocitaKmh: velocitaKmh,
        potenzaKw: potenzaKw,
        odometroKm: odometroKm,
        energiaKwh: energiaKwh ?? this.energiaKwh,
        capacitaKwh: capacitaKwh,
        consumoMedioKwh100: consumoMedioKwh100,
        potenzaClimaW: potenzaClimaW,
        climaAcceso: climaAcceso,
        batteriaInRiscaldamento: batteriaInRiscaldamento,
        temperaturaInternaC: temperaturaInternaC,
        stimataDa: stimataDa ?? this.stimataDa,
      );

  @override
  String toString() => 'StatoAuto(${sorgente.name}, ${batteria.toStringAsFixed(1)}%, $letto)';
}

/// Quanti dati, al massimo, un'auto puo' mandare: i dieci di [StatoAuto].
///
/// La batteria non si conta fra questi: senza quella non c'e' nemmeno uno
/// stato. Sono i dieci che la schermata «Dati che arrivano dall'auto» elenca,
/// e li conta anche l'auto: cosi' «tre su dieci» vuol dire la stessa cosa sul
/// telefono, su Android Auto e su CarPlay.
const int datiPossibili = 10;

/// Quanti di quei dieci stanno arrivando adesso.
///
/// Serve a dire in una riga sola se l'auto sta parlando o sta tacendo, senza
/// aprire l'elenco: un dongle appena collegato ne da' due o tre, gdahome col
/// sensore giusto ne da' molti di piu'.
int quantiDatiArrivano(StatoAuto s) {
  var quanti = 1; // la batteria, che c'e' sempre
  if (s.autonomiaKm != null) quanti++;
  if (s.inCarica != null) quanti++;
  if (s.potenzaCaricaKw != null) quanti++;
  if (s.temperaturaEsternaC != null) quanti++;
  if (s.temperaturaBatteriaC != null) quanti++;
  if (s.velocitaKmh != null) quanti++;
  if (s.potenzaKw != null) quanti++;
  if (s.odometroKm != null) quanti++;
  if (s.latitudine != null && s.longitudine != null) quanti++;
  return quanti;
}
