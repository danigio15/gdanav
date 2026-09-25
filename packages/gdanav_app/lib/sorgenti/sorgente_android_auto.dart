import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Batteria e autonomia chieste all'auto con la Car App Library
/// (`CarHardwareManager` → `CarInfo.addEnergyLevelListener`).
///
/// Il lato Kotlin sta nel `CarAppService` di Android Auto e manda qui ogni
/// lettura sul canale `gdanav/auto`. Molte auto non passano questi dati: in
/// quel caso il canale tace e l'arbitro usa un'altra sorgente. Su iPhone il
/// canale non esiste proprio: CarPlay non dà i dati dell'auto.
class SorgenteAndroidAuto implements SorgenteDatiAuto {
  SorgenteAndroidAuto({EventChannel? canale, this.onVelocita}) : _canale = canale ?? const EventChannel('gdanav/auto');

  final EventChannel _canale;

  /// La velocità del cruscotto, anche quando l'auto non dice la batteria.
  final void Function(double kmh)? onVelocita;
  final _letture = StreamController<StatoAuto>.broadcast();
  StreamSubscription<dynamic>? _iscrizione;

  @override
  TipoSorgente get tipo => TipoSorgente.androidAuto;

  @override
  Stream<StatoAuto> get letture => _letture.stream;

  @override
  Future<void> avvia() async {
    _iscrizione = _canale.receiveBroadcastStream().listen(
      (dato) {
        if (dato is Map && dato['velocita_kmh'] is num) onVelocita?.call((dato['velocita_kmh'] as num).toDouble());
        final stato = statoDaMappa(dato);
        if (stato != null) _letture.add(stato);
      },
      // Niente codice nativo (iPhone, prove) o auto che non risponde: si tace.
      onError: (Object _) {},
    );
  }

  @override
  Future<void> ferma() async => _iscrizione?.cancel();

  /// Il formato che manda Kotlin: `batteria` (0–100), `autonomia_km`,
  /// `velocita_kmh`, `odometro_km`, `letto_ms` (epoch in millisecondi).
  static StatoAuto? statoDaMappa(Object? dato) {
    if (dato is! Map) return null;
    final batteria = (dato['batteria'] as num?)?.toDouble();
    if (batteria == null) return null;
    final ms = dato['letto_ms'] as int?;
    return StatoAuto(
      sorgente: dato['automotive'] == true ? TipoSorgente.automotive : TipoSorgente.androidAuto,
      letto: ms == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(ms),
      batteria: batteria,
      autonomiaKm: (dato['autonomia_km'] as num?)?.toDouble(),
      velocitaKmh: (dato['velocita_kmh'] as num?)?.toDouble(),
      odometroKm: (dato['odometro_km'] as num?)?.toDouble(),
    );
  }
}
