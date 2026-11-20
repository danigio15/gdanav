import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:sensors_plus/sensors_plus.dart';

/* ─── L'accelerometro del telefono, in guida ──────────────────────────────────
 *
 * Le frenate e le ripartenze quando succedono, non un secondo dopo col GPS:
 * vedi [AccelerazioneDiMarcia]. Qui solo i sensori: l'accelerometro senza la
 * gravità (per l'accelerazione) e con (per la gravità: se cambia direzione il
 * telefono si è spostato nel supporto), cinquanta volte al secondo, solo
 * mentre si guida. La velocità del cruscotto, quando l'auto la dice, si
 * guarda a ogni campione ([velocitaAuto]): quella del GPS la porta la guida. */

/// Un campione dei sensori: [t], e i tre assi in m/s².
typedef CampioneSensore = ({DateTime t, double x, double y, double z});

/// Vedi sopra.
class SensoriDiMarcia {
  SensoriDiMarcia({
    Stream<CampioneSensore> Function()? senzaGravita,
    Stream<CampioneSensore> Function()? conGravita,
    this.velocitaAuto,
    AccelerazioneDiMarcia? stima,
  }) : _senzaGravita = senzaGravita ?? _utente,
       _conGravita = conGravita ?? _totale,
       stima = stima ?? AccelerazioneDiMarcia();

  /// Quelli dell'app, per la diagnosi.
  static SensoriDiMarcia? attuale;

  /// Quello che si impara e che si dice: l'accelerazione lungo la strada.
  final AccelerazioneDiMarcia stima;

  /// La velocità dell'auto dal cruscotto (m/s) e quando è stata letta, se
  /// c'è: insegna meglio del GPS, che è in ritardo.
  final ({double ms, DateTime alle})? Function()? velocitaAuto;

  final Stream<CampioneSensore> Function() _senzaGravita, _conGravita;
  StreamSubscription<CampioneSensore>? _a, _g;
  CampioneSensore? _ultimo;
  DateTime? _autoLetta;

  /// Se i sensori sono accesi.
  bool get accesi => _a != null;

  /// Se l'accelerometro ha parlato almeno una volta.
  bool get accelerometroSentito => _ultimo != null;

  /// Le velocità del cruscotto arrivate (per la diagnosi: arrivano? quanto
  /// spesso?): quante, la prima e l'ultima.
  int lettureCruscotto = 0;
  DateTime? primaCruscotto, ultimaCruscotto;

  static const _periodo = Duration(milliseconds: 20);

  static Stream<CampioneSensore> _utente() =>
      userAccelerometerEventStream(samplingPeriod: _periodo).map((e) => (t: e.timestamp, x: e.x, y: e.y, z: e.z));

  static Stream<CampioneSensore> _totale() =>
      accelerometerEventStream(samplingPeriod: _periodo).map((e) => (t: e.timestamp, x: e.x, y: e.y, z: e.z));

  /// Accende i sensori (in guida). Un telefono senza accelerometro non fa
  /// niente di male: si resta col GPS.
  void avvia() {
    if (_a != null) return;
    try {
      _a = _senzaGravita().listen(_campione, onError: (Object e) => debugPrint('accelerometro: $e'));
      _g = _conGravita().listen(_gravita, onError: (Object e) => debugPrint('accelerometro: $e'));
    } catch (e) {
      debugPrint('accelerometro non disponibile: $e');
    }
  }

  /// Spegne i sensori (fine guida): la taratura resta, il telefono nel
  /// supporto è lo stesso al prossimo viaggio (se no, si reimpara).
  Future<void> ferma() async {
    await _a?.cancel();
    await _g?.cancel();
    _a = null;
    _g = null;
  }

  void _campione(CampioneSensore c) {
    _ultimo = c;
    stima.campione(c.t, c.x, c.y, c.z);
    final v = velocitaAuto?.call();
    if (v != null && v.alle != _autoLetta) {
      _autoLetta = v.alle;
      stima.velocita(v.alle, v.ms, cruscotto: true);
      lettureCruscotto++;
      primaCruscotto ??= v.alle;
      ultimaCruscotto = v.alle;
    }
  }

  void _gravita(CampioneSensore c) {
    final u = _ultimo;
    // La gravità: l'accelerometro meno l'accelerazione dell'auto.
    if (u == null) return;
    stima.gravita(c.t, c.x - u.x, c.y - u.y, c.z - u.z);
  }

  /// La velocità del GPS ([ms] m/s), letta [alle]: per tarare.
  void velocitaGps(DateTime alle, double ms) => stima.velocita(alle, ms, cruscotto: false);
}
