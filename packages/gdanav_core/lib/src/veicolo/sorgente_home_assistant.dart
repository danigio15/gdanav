import 'dart:async';

import '../protocollo/cliente_relay.dart';
import '../protocollo/messaggio.dart';
import 'sorgente_dati_auto.dart';
import 'stato_auto.dart';

/// Lo stato dell'auto come lo vede Home Assistant, attraverso l'integrazione
/// gdanav e il relay.
class SorgenteHomeAssistant implements SorgenteDatiAuto {
  SorgenteHomeAssistant(this.relay);

  final ClienteRelay relay;
  StreamSubscription<Messaggio>? _iscrizione;
  final _letture = StreamController<StatoAuto>.broadcast();

  @override
  TipoSorgente get tipo => TipoSorgente.homeAssistant;

  @override
  Stream<StatoAuto> get letture => _letture.stream;

  @override
  Future<void> avvia() async {
    _iscrizione = relay.messaggi.where((m) => m.tipo == TipoMessaggio.statoAuto).listen((m) {
      final stato = statoDaMessaggio(m);
      if (stato != null) _letture.add(stato);
    });
    await relay.avvia();
  }

  @override
  Future<void> ferma() async {
    await _iscrizione?.cancel();
    await relay.ferma();
  }

  /// `null` se Home Assistant non conosce la batteria (entità non
  /// disponibile): meglio nessun dato che un dato inventato.
  static StatoAuto? statoDaMessaggio(Messaggio m) {
    final d = m.dati;
    final batteria = (d['batteria'] as num?)?.toDouble();
    if (batteria == null) return null;
    return StatoAuto(
      sorgente: TipoSorgente.homeAssistant,
      letto: DateTime.tryParse(d['letto'] as String? ?? '') ?? m.ts,
      batteria: batteria,
      autonomiaKm: (d['autonomia_km'] as num?)?.toDouble(),
      inCarica: d['in_carica'] as bool?,
      potenzaCaricaKw: (d['potenza_carica_kw'] as num?)?.toDouble(),
      temperaturaBatteriaC: (d['temperatura_batteria_c'] as num?)?.toDouble(),
      latitudine: (d['latitudine'] as num?)?.toDouble(),
      longitudine: (d['longitudine'] as num?)?.toDouble(),
      temperaturaEsternaC: (d['temperatura_esterna_c'] as num?)?.toDouble(),
      velocitaKmh: (d['velocita_kmh'] as num?)?.toDouble(),
      potenzaKw: (d['potenza_kw'] as num?)?.toDouble(),
      odometroKm: (d['odometro_km'] as num?)?.toDouble(),
    );
  }
}
