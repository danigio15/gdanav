import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/dati_viaggio.dart';
import '../stato/gestore_premium.dart';
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

/// «2 libere su 4», «Piena», «Guasta»; e quando libere e occupate non si
/// sanno, quello che si sa davvero.
///
/// Prima diceva «Stato non comunicato» su ogni colonnina che non risponde in
/// tempo reale — e sono quasi tutte. Su una mappa piena, venti pastiglie che
/// dicono di non sapere sembrano un guasto dell'app, e non aggiungono niente:
/// meglio dire quante prese ci sono, che è un fatto, e lasciare il colore a
/// fare la sua parte. Senza Premium la pastiglia resta quella di prima,
/// perché lì la frase serve: lo stato di adesso c'è, ma non è acceso.
String testoDisponibilita(Disponibilita d) {
  final funzionanti = d.totali - d.guaste;
  return switch (statoDi(d)) {
    StatoColonnina.libera =>
      funzionanti == 1 ? 'Libera' : '${d.libere} ${d.libere == 1 ? 'libera' : 'libere'} su $funzionanti',
    StatoColonnina.piena => funzionanti == 1 ? 'Occupata' : 'Piena · $funzionanti occupate',
    StatoColonnina.guasta => 'Fuori servizio',
    StatoColonnina.ignota when !GestorePremium.attivo.value => 'Libere/occupate con Premium',
    StatoColonnina.ignota =>
      d.totali > 0 ? '${d.totali} ${d.totali == 1 ? 'presa' : 'prese'}' : 'Stato non comunicato',
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
