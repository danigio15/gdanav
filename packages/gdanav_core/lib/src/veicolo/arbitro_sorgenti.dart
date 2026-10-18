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
  /// (anche quello che arriva da GdAHome) ha più margine perché le
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

  /// Da quando ogni lettura vale come «adesso»: di solito la sua ora
  /// ([StatoAuto.letto]), ma vedi [registra].
  final _quando = <TipoSorgente, DateTime>{};

  /// Energia consumata (positiva) o recuperata (negativa) dopo ogni lettura,
  /// tenuta per sorgente perché ognuna ha la sua ora.
  final _consumoDopo = <TipoSorgente, double>{};

  /// Una lettura da una sorgente. [ricevuto] è quando è arrivata al telefono.
  ///
  /// Dal campo: l'auto diceva 23% e 95 km, gdanav 21% e 88 km. I dati di Home
  /// Assistant erano giusti, ma datati col loro ultimo cambio (e
  /// l'integrazione dell'auto, o l'orologio della casa, li data come vuole):
  /// una lettura **nuova**, appena arrivata, sembrava vecchia di un quarto
  /// d'ora, e al suo posto si mostrava la stima. Adesso una lettura che dice
  /// qualcosa di diverso dalla precedente della stessa sorgente vale da
  /// quando è arrivata: Home Assistant manda un cambio quando c'è, non una
  /// fotografia di ore fa. La prima lettura di una sorgente, che può essere
  /// quella rimasta da ieri, vale invece dalla sua ora. E una lettura uguale
  /// alla precedente, rimandata (una sorgente che si riaccende), non cambia
  /// niente: né l'ora, né la stima già fatta dopo di lei.
  ///
  /// L'energia che resta conta come la batteria: è la stessa lettura, a un
  /// decimo di kWh invece che a punti. E una lettura con la stessa batteria
  /// e la stessa ora ma altri dati nuovi (la temperatura, il clima: Home
  /// Assistant la data con la batteria) li porta dentro, senza toccare l'ora
  /// né la stima: prima si buttava via tutta.
  void registra(StatoAuto lettura, {DateTime? ricevuto}) {
    final tipo = lettura.sorgente;
    final precedente = _ultime[tipo];
    if (precedente != null && lettura.letto.isBefore(precedente.letto)) return;
    final diversa = precedente != null &&
        (precedente.batteria != lettura.batteria ||
            precedente.autonomiaKm != lettura.autonomiaKm ||
            precedente.energiaKwh != lettura.energiaKwh);
    if (precedente != null && !diversa && !lettura.letto.isAfter(precedente.letto)) {
      _ultime[tipo] = lettura;
      return;
    }
    _ultime[tipo] = lettura;
    _quando[tipo] = diversa && ricevuto != null && ricevuto.isAfter(lettura.letto) ? ricevuto : lettura.letto;
    _consumoDopo[tipo] = 0;
  }

  /// Il motore (la guida) lo chiama man mano che l'auto consuma, in kWh.
  ///
  /// Con [ora] il consumo non si conta per le letture ancora fresche: quelle
  /// si mostrano come le ha dette l'auto, e la stima comincia quando smettono
  /// di esserlo. Così il numero non salta, né quando la lettura arriva né
  /// quando invecchia, e la stima vale solo **fra** due letture.
  void registraConsumo(double kWh, {DateTime? ora}) {
    for (final k in _consumoDopo.keys) {
      if (ora != null && _fresca(k, ora)) continue;
      _consumoDopo[k] = _consumoDopo[k]! + kWh;
    }
  }

  bool _fresca(TipoSorgente tipo, DateTime ora) {
    final da = _quando[tipo];
    return da != null && ora.difference(da) <= freschezza[tipo]!;
  }

  StatoAuto? statoAttuale(DateTime ora) {
    switch (modalita) {
      case Fissa(:final sorgente):
        final l = _ultime[sorgente];
        return l == null ? null : _aggiornata(l, ora);
      case Automatica():
        for (final tipo in priorita) {
          final l = _ultime[tipo];
          if (l != null && _fresca(tipo, ora)) return l;
        }
        final piuRecente = _piuRecente();
        return piuRecente == null ? null : _aggiornata(piuRecente, ora);
    }
  }

  /// La lettura tolto il consumo avvenuto dopo: se non è cambiato niente
  /// resta com'è, con la sua sorgente vera. L'autonomia dell'auto scende con
  /// lei, coi chilometri per punto che dice l'auto, e così l'energia che
  /// resta. I punti si contano con la capacità vera, se l'auto la dice
  /// ([StatoAuto.capacitaVeraKwh]).
  StatoAuto _aggiornata(StatoAuto l, DateTime ora) {
    final consumo = _consumoDopo[l.sorgente] ?? 0;
    if (consumo == 0) return l;
    final capacita = l.capacitaVeraKwh ?? capacitaUtileKwh;
    final batteria = (l.batteria - consumo / capacita * 100).clamp(0, 100).toDouble();
    final km = l.autonomiaKm, kWh = l.energiaKwh;
    return l.conBatteria(
      batteria,
      sorgente: TipoSorgente.stima,
      autonomiaKm: km != null && l.batteria > 0 ? km * batteria / l.batteria : null,
      energiaKwh: kWh == null ? null : (kWh - consumo).clamp(0, double.infinity).toDouble(),
      stimataDa: l.sorgente,
    );
  }

  StatoAuto? _piuRecente() {
    StatoAuto? migliore;
    DateTime? quando;
    for (final MapEntry(key: tipo, value: l) in _ultime.entries) {
      final q = _quando[tipo] ?? l.letto;
      if (quando == null || q.isAfter(quando)) {
        migliore = l;
        quando = q;
      }
    }
    return migliore;
  }
}
