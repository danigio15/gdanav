import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/archivio.dart';

String riassuntoPreferenze(PreferenzeRicarica p) =>
    'Arrivo ≥ ${p.minimoArrivo.round()}% · fino all\'${p.massimoRicarica.round()}% · ≥ ${p.potenzaMinimaKw.round()} kW';

/// Come preferisci ricaricare: il pianificatore ne tiene conto. Si salva a
/// ogni tocco.
class PreferenzeRicaricaSchermata extends StatefulWidget {
  const PreferenzeRicaricaSchermata({super.key, required this.archivio});

  final Archivio archivio;

  @override
  State<PreferenzeRicaricaSchermata> createState() => _PreferenzeRicaricaSchermataState();
}

class _PreferenzeRicaricaSchermataState extends State<PreferenzeRicaricaSchermata> {
  PreferenzeRicarica? _p;

  @override
  void initState() {
    super.initState();
    widget.archivio.preferenze().then((p) => mounted ? setState(() => _p = p) : null);
  }

  void _cambia(PreferenzeRicarica p) {
    setState(() => _p = p);
    widget.archivio.salvaPreferenze(p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ricarica')),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _Cursore(
                  titolo: 'Arriva a destinazione con almeno',
                  valore: p.minimoArrivo,
                  min: 5,
                  max: 50,
                  onChanged: (v) => _cambia(p.copia(minimoArrivo: v)),
                ),
                _Cursore(
                  titolo: 'Arriva alle colonnine con almeno',
                  valore: p.minimoSosta,
                  min: 5,
                  max: 40,
                  onChanged: (v) => _cambia(p.copia(minimoSosta: v)),
                ),
                _Cursore(
                  titolo: 'Ricarica al massimo fino al',
                  sotto: 'Sopra l\'80% la ricarica rapida rallenta molto: meglio una sosta in più.',
                  valore: p.massimoRicarica,
                  min: 50,
                  max: 100,
                  onChanged: (v) => _cambia(p.copia(massimoRicarica: v)),
                ),
                const SizedBox(height: 12),
                Text('Colonnine da proporre (kW)', style: t.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 22, label: Text('Tutte')),
                    ButtonSegment(value: 50, label: Text('≥ 50')),
                    ButtonSegment(value: 100, label: Text('≥ 100')),
                    ButtonSegment(value: 150, label: Text('≥ 150')),
                  ],
                  selected: {p.potenzaMinimaKw},
                  onSelectionChanged: (s) => _cambia(p.copia(potenzaMinimaKw: s.first)),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Evita le colonnine piene'),
                  subtitle: const Text(
                    'Se adesso sono tutte occupate, conta 15 minuti di attesa e preferisce le libere.',
                  ),
                  value: p.evitaOccupate,
                  onChanged: (v) => _cambia(p.copia(evitaOccupate: v)),
                ),
              ],
            ),
    );
  }
}

class _Cursore extends StatelessWidget {
  const _Cursore({
    required this.titolo,
    required this.valore,
    required this.min,
    required this.max,
    required this.onChanged,
    this.sotto,
  });

  final String titolo;
  final String? sotto;
  final double valore;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(titolo, style: t.titleSmall)),
              Text('${valore.round()}%', style: t.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ],
          ),
          Slider(value: valore, min: min, max: max, divisions: ((max - min) / 5).round(), onChanged: onChanged),
          if (sotto != null)
            Text(sotto!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
