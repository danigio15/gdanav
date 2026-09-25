import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_auto.dart';
import 'vetro.dart';
import 'anello_batteria.dart';

String nomeSorgente(TipoSorgente t) => switch (t) {
  TipoSorgente.automotive => 'Auto',
  TipoSorgente.androidAuto => 'Android Auto',
  TipoSorgente.obd => 'OBD',
  TipoSorgente.gdahome => 'gdahome',
  TipoSorgente.homeAssistant => 'Home Assistant',
  TipoSorgente.manuale => 'Manuale',
  TipoSorgente.stima => 'Stima',
};

String eta(Duration d) {
  if (d.inSeconds < 60) return 'adesso';
  if (d.inMinutes < 60) return '${d.inMinutes} min fa';
  return '${d.inHours} h fa';
}

/// La batteria in alto: anello con la percentuale, i chilometri che restano,
/// l'auto e da dove arriva il dato. Toccandola si apre lo switch della fonte.
class IndicatoreBatteria extends StatelessWidget {
  const IndicatoreBatteria({super.key, required this.auto, required this.onTap});

  final GestoreAuto auto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = auto.stato;
    final km = auto.autonomiaKm();
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 330),
      child: Vetro(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnelloBatteria(
                batteria: s?.batteria,
                child: Text(
                  s == null ? '?' : '${s.batteria.round()}',
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s == null ? 'Batteria sconosciuta' : '${s.batteria.round()}% · ≈ ${km!.round()} km',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      s == null
                          ? 'Tocca per scriverla'
                          : '${auto.veicolo.modello} · ${nomeSorgente(s.sorgente)} · '
                                '${eta(DateTime.now().difference(s.letto))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: muto),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
