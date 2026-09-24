import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/stato_colonnina.dart';
import '../stato/gestore_viaggio.dart';
import '../tema.dart';

Future<void> mostraColonnina(BuildContext context, GestoreViaggio gestore, String id) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DettaglioColonnina(gestore: gestore, id: id),
  );
}

String nomeConnettore(TipoConnettore t) => switch (t) {
  TipoConnettore.ccs2 => 'CCS',
  TipoConnettore.chademo => 'CHAdeMO',
  TipoConnettore.tipo2 => 'Tipo 2',
  TipoConnettore.tesla => 'Tesla',
  TipoConnettore.altro => 'Altra presa',
};

/// Tutto di una colonnina: prese, potenza, quante libere, e «fermati qui».
class DettaglioColonnina extends StatelessWidget {
  const DettaglioColonnina({super.key, required this.gestore, required this.id});

  final GestoreViaggio gestore;
  final String id;

  @override
  Widget build(BuildContext context) {
    final stato = gestore.stato;
    if (stato is! ViaggioPronto) return const SizedBox.shrink();
    final c = stato.viaggio.colonnine.where((c) => c.id == id).firstOrNull;
    if (c == null) return const SizedBox.shrink();
    final soste = stato.viaggio.piano?.soste ?? const <Sosta>[];
    final sosta = soste.where((s) => s.colonnina.id == id).firstOrNull;
    final numero = sosta == null ? null : soste.indexOf(sosta) + 1;
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    final prese = <(TipoConnettore, double), List<Connettore>>{};
    for (final p in c.dettaglio?.connettori ?? const <Connettore>[]) {
      prese.putIfAbsent((p.tipo, p.potenzaKw), () => []).add(p);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (numero != null)
              Text(
                c.obbligata ? 'SOSTA $numero · SCELTA DA TE' : 'SOSTA $numero DEL VIAGGIO',
                style: t.labelMedium?.copyWith(color: ColoriGdanav.di(context).libera, letterSpacing: 0.8),
              ),
            Text(c.nome, style: t.titleLarge),
            if (c.dettaglio?.operatore case final o?) Text(o, style: t.bodyMedium?.copyWith(color: muto)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [BadgePotenza(c.potenzaKw), BadgeDisponibilita(c.disponibilita)]),
            const SizedBox(height: 12),
            Text(
              'A ${(c.distanzaM / 1000).round()} km dalla partenza'
              '${c.deviazioneM >= 100 ? ' · ${(c.deviazioneM / 1000).toStringAsFixed(1)} km fuori strada' : ''}',
              style: t.bodyMedium,
            ),
            if (sosta != null)
              Text(
                'Ricarichi dal ${sosta.batteriaArrivo.round()}% al ${sosta.batteriaPartenza.round()}% '
                'in ${sosta.ricarica.inMinutes} min',
                style: t.bodyMedium,
              ),
            if (prese.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Prese', style: t.titleSmall),
              const SizedBox(height: 6),
              for (final MapEntry(key: (tipo, kw), value: lista) in prese.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 110, child: Text('${nomeConnettore(tipo)} · ${kw.round()} kW')),
                      for (final p in lista)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tooltip(
                            message: switch (p.stato) {
                              StatoPresa.disponibile => 'Libera',
                              StatoPresa.occupata => 'Occupata',
                              StatoPresa.fuoriServizio => 'Fuori servizio',
                              StatoPresa.sconosciuto => 'Stato non disponibile',
                            },
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(color: _colorePresa(context, p.stato), shape: BoxShape.circle),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 20),
            if (c.obbligata)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.remove_circle_outline),
                  label: const Text('Togli questa sosta'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    gestore.togliSosta(id);
                  },
                ),
              )
            else if (sosta == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.ev_station),
                  label: const Text('Fermati qui'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    gestore.fermatiA(id);
                  },
                ),
              )
            else
              Text('Il viaggio si ferma già qui.', style: t.bodyMedium?.copyWith(color: muto)),
            const SizedBox(height: 8),
            Text(
              'Stato delle prese: PUN e operatori, quando lo pubblicano.',
              style: t.bodySmall?.copyWith(color: muto),
            ),
          ],
        ),
      ),
    );
  }

  static Color _colorePresa(BuildContext context, StatoPresa s) {
    final c = ColoriGdanav.di(context);
    return switch (s) {
      StatoPresa.disponibile => c.libera,
      StatoPresa.occupata => c.piena,
      StatoPresa.fuoriServizio => c.guasta,
      StatoPresa.sconosciuto => c.ignota,
    };
  }
}
