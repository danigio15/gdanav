import 'stato_auto.dart';

/// Come l'utente ha messo lo switch «Fonte dati auto».
sealed class ModalitaFonte {
  const ModalitaFonte();
}

/// Vince la sorgente più affidabile fra quelle con un dato fresco.
class Automatica extends ModalitaFonte {
  const Automatica();
}

/// Solo questa sorgente, anche se è vecchia: l'utente sa cosa vuole.
class Fissa extends ModalitaFonte {
  const Fissa(this.sorgente);
  final TipoSorgente sorgente;
}

/// Sceglie da quale sorgente prendere lo stato dell'auto, e quando nessuna
/// è fresca lo stima togliendo l'energia consumata dall'ultima lettura.
class ArbitroSorgenti {
  ArbitroSorgenti({
    required this.capacitaUtileKwh,
    this.modalita = const Automatica(),
    Map<TipoSorgente, Duration>? freschezza,
  }) : freschezza = freschezza ?? freschezzaPredefinita;

  /// Dall'alto in basso: la prima fresca vince.
  static const priorita = [
    TipoSorgente.automotive,
    TipoSorgente.androidAuto,
    TipoSorgente.obd,
    TipoSorgente.gdahome,
    TipoSorgente.homeAssistant,
    TipoSorgente.manuale,
  ];

  /// Oltre questa età una lettura non conta più come fresca. Home Assistant
  /// (anche quello che arriva da gdahome) ha più margine perché le
  /// integrazioni dei costruttori aggiornano piano;
  /// il manuale vale solo come punto di partenza della stima.
  static const freschezzaPredefinita = {
    TipoSorgente.automotive: Duration(seconds: 30),
    TipoSorgente.androidAuto: Duration(seconds: 30),
    TipoSorgente.obd: Duration(seconds: 30),
    TipoSorgente.gdahome: Duration(minutes: 5),
    TipoSorgente.homeAssistant: Duration(minutes: 5),
    TipoSorgente.manuale: Duration.zero,
  };

  /// Cambia quando si cambia auto.
  double capacitaUtileKwh;
  final Map<TipoSorgente, Duration> freschezza;
  ModalitaFonte modalita;

  final _ultime = <TipoSorgente, StatoAuto>{};

  /// Energia consumata (positiva) o recuperata (negativa) dopo ogni lettura,
  /// tenuta per sorgente perché ognuna ha la sua ora.
  final _consumoDopo = <TipoSorgente, double>{};

  void registra(StatoAuto lettura) {
    final precedente = _ultime[lettura.sorgente];
    if (precedente != null && lettura.letto.isBefore(precedente.letto)) return;
    _ultime[lettura.sorgente] = lettura;
    _consumoDopo[lettura.sorgente] = 0;
  }

  /// Il motore lo chiama man mano che l'auto consuma, in kWh.
  void registraConsumo(double kWh) {
    for (final k in _consumoDopo.keys) {
      _consumoDopo[k] = _consumoDopo[k]! + kWh;
    }
  }

  StatoAuto? statoAttuale(DateTime ora) {
    switch (modalita) {
      case Fissa(:final sorgente):
        final l = _ultime[sorgente];
        return l == null ? null : _aggiornata(l, ora);
      case Automatica():
        for (final tipo in priorita) {
          final l = _ultime[tipo];
          if (l != null && l.eta(ora) <= freschezza[tipo]!) return l;
        }
        final piuRecente = _piuRecente();
        return piuRecente == null ? null : _aggiornata(piuRecente, ora);
    }
  }

  /// La lettura tolto il consumo avvenuto dopo: se non è cambiato niente
  /// resta com'è, con la sua sorgente vera.
  StatoAuto _aggiornata(StatoAuto l, DateTime ora) {
    final consumo = _consumoDopo[l.sorgente] ?? 0;
    if (consumo == 0) return l;
    final batteria = l.batteria - consumo / capacitaUtileKwh * 100;
    return l.conBatteria(batteria, sorgente: TipoSorgente.stima);
  }

  StatoAuto? _piuRecente() {
    StatoAuto? migliore;
    for (final l in _ultime.values) {
      if (migliore == null || l.letto.isAfter(migliore.letto)) migliore = l;
    }
    return migliore;
  }
}
