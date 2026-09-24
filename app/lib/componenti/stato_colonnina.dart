import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/dati_viaggio.dart';
import '../tema.dart';

Color coloreStato(BuildContext context, StatoColonnina s) {
  final c = ColoriGdanav.di(context);
  return switch (s) {
    StatoColonnina.libera => c.libera,
    StatoColonnina.piena => c.piena,
    StatoColonnina.guasta => c.guasta,
    StatoColonnina.ignota => c.ignota,
  };
}

/// «2 libere su 4», «Piena», «Guasta», «Stato non disponibile».
String testoDisponibilita(Disponibilita d) {
  final funzionanti = d.totali - d.guaste;
  return switch (statoDi(d)) {
    StatoColonnina.libera => d.libere == 1 && funzionanti == 1 ? 'Libera' : '${d.libere} libere su $funzionanti',
    StatoColonnina.piena => funzionanti == 1 ? 'Occupata' : 'Piena · $funzionanti occupate',
    StatoColonnina.guasta => 'Fuori servizio',
    StatoColonnina.ignota => 'Stato non disponibile',
  };
}

/// La pastiglia colorata con lo stato delle prese.
class BadgeDisponibilita extends StatelessWidget {
  const BadgeDisponibilita(this.disponibilita, {super.key});

  final Disponibilita disponibilita;

  @override
  Widget build(BuildContext context) {
    final colore = coloreStato(context, statoDi(disponibilita));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: colore.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: colore, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            testoDisponibilita(disponibilita),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colore, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// «150 kW», in un riquadro.
class BadgePotenza extends StatelessWidget {
  const BadgePotenza(this.kw, {super.key});

  final double kw;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: s.primaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 14, color: s.onPrimaryContainer),
          Text(
            '${kw.round()} kW',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: s.onPrimaryContainer, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
