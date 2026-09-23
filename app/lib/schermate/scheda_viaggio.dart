import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_viaggio.dart';

/// Il riquadro in basso: sta calcolando, il viaggio con le sue soste, o
/// cosa non va.
class SchedaViaggio extends StatelessWidget {
  const SchedaViaggio({super.key, required this.gestore, required this.apriImpostazioni});

  final GestoreViaggio gestore;
  final VoidCallback apriImpostazioni;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: gestore,
      builder: (context, _) => switch (gestore.stato) {
        NessunViaggio() => const SizedBox.shrink(),
        Calcolo(:final destinazione) => _Riquadro(
          titolo: destinazione.nome,
          onChiudi: gestore.annulla,
          children: const [
            Row(
              children: [
                SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Calcolo percorso e soste…'),
              ],
            ),
          ],
        ),
        ErroreViaggio(:final messaggio, :final destinazione) => _Riquadro(
          titolo: destinazione?.nome ?? 'Viaggio',
          onChiudi: gestore.annulla,
          children: [
            Text(messaggio),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (destinazione != null)
                  FilledButton.tonal(onPressed: () => gestore.pianifica(destinazione), child: const Text('Riprova')),
                if (messaggio.contains('impostazioni'))
                  OutlinedButton(onPressed: apriImpostazioni, child: const Text('Impostazioni')),
              ],
            ),
          ],
        ),
        ViaggioPronto(:final destinazione, :final viaggio) => _Pronto(
          destinazione: destinazione,
          viaggio: viaggio,
          onChiudi: gestore.annulla,
        ),
      },
    );
  }
}

class _Pronto extends StatelessWidget {
  const _Pronto({required this.destinazione, required this.viaggio, required this.onChiudi});

  final Luogo destinazione;
  final Viaggio viaggio;
  final VoidCallback onChiudi;

  @override
  Widget build(BuildContext context) {
    final piano = viaggio.piano;
    final testo = Theme.of(context).textTheme;
    final km = viaggio.percorso.lunghezzaM / 1000;
    if (piano == null) {
      return _Riquadro(
        titolo: destinazione.nome,
        onChiudi: onChiudi,
        children: [
          Text('${km.round()} km'),
          const SizedBox(height: 4),
          const Text(
            'Con questa batteria non ci si arriva, e lungo la strada non ci sono colonnine adatte abbastanza vicine.',
          ),
        ],
      );
    }
    return _Riquadro(
      titolo: destinazione.nome,
      onChiudi: onChiudi,
      children: [
        Text(
          '${durata(piano.durata)} · ${km.round()} km · arrivi con il ${piano.batteriaArrivo.round()}%',
          style: testo.titleMedium,
        ),
        const SizedBox(height: 8),
        if (piano.soste.isEmpty)
          const Text('Nessuna sosta: ci arrivi con una carica.')
        else
          for (final s in piano.soste)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.ev_station_outlined),
              title: Text(s.colonnina.nome),
              subtitle: Text(
                '${(s.colonnina.distanzaM / 1000).round()} km · ${s.colonnina.potenzaKw.round()} kW · '
                '${s.batteriaArrivo.round()}% → ${s.batteriaPartenza.round()}% in ${durata(s.ricarica)}',
              ),
            ),
        const SizedBox(height: 4),
        Text(
          'Colonnine: © Open Charge Map contributors · Mappa: © OpenStreetMap contributors',
          style: testo.bodySmall,
        ),
      ],
    );
  }
}

String durata(Duration d) {
  final ore = d.inHours, minuti = d.inMinutes % 60;
  if (ore == 0) return '$minuti min';
  return '$ore h ${minuti.toString().padLeft(2, '0')}';
}

class _Riquadro extends StatelessWidget {
  const _Riquadro({required this.titolo, required this.onChiudi, required this.children});

  final String titolo;
  final VoidCallback onChiudi;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(titolo, style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(onPressed: onChiudi, icon: const Icon(Icons.close), tooltip: 'Chiudi'),
                ],
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
