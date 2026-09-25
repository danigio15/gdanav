import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Come calcolare il percorso: più veloce o più risparmio, e cosa evitare.
/// Si cambia a ogni tocco.
class PannelloOpzioniPercorso extends StatelessWidget {
  const PannelloOpzioniPercorso({super.key, required this.opzioni, required this.onCambia});

  final OpzioniPercorso opzioni;
  final ValueChanged<OpzioniPercorso> onCambia;

  static String spiega(ModoGuida m) => switch (m) {
    ModoGuida.veloce => 'Alle velocità della strada: si arriva prima, si consuma di più.',
    ModoGuida.equilibrato => 'Al massimo 120 km/h: poco più lento, meno soste.',
    ModoGuida.risparmio => 'Al massimo 100 km/h: si consuma molto meno, a volte una sosta in meno.',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = opzioni;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Guida', style: t.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ModoGuida>(
          showSelectedIcon: false,
          segments: [
            for (final m in ModoGuida.values)
              ButtonSegment(
                value: m,
                label: Text(m.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                icon: Icon(switch (m) {
                  ModoGuida.veloce => Icons.speed,
                  ModoGuida.equilibrato => Icons.balance,
                  ModoGuida.risparmio => Icons.eco,
                }),
              ),
          ],
          selected: {o.modo},
          onSelectionChanged: (s) => onCambia(o.copia(modo: s.first)),
        ),
        const SizedBox(height: 6),
        Text(spiega(o.modo), style: t.bodySmall),
        const SizedBox(height: 16),
        Text('Evita', style: t.titleSmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.toll_outlined),
          title: const Text('Pedaggi'),
          value: o.evitaPedaggi,
          onChanged: (v) => onCambia(o.copia(evitaPedaggi: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.add_road),
          title: const Text('Autostrade'),
          value: o.evitaAutostrade,
          onChanged: (v) => onCambia(o.copia(evitaAutostrade: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.directions_boat_outlined),
          title: const Text('Traghetti'),
          value: o.evitaTraghetti,
          onChanged: (v) => onCambia(o.copia(evitaTraghetti: v)),
        ),
        const SizedBox(height: 16),
        Text('In viaggio', style: t.titleSmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.autorenew),
          title: const Text('Ricalcolo automatico'),
          subtitle: const Text(
            'Se il consumo vero si allontana dal previsto, le soste si ricalcolano da sole. '
            'Spento, te lo chiede. Se esci dal percorso si ricalcola sempre.',
          ),
          value: o.ricalcoloAutomatico,
          onChanged: (v) => onCambia(o.copia(ricalcoloAutomatico: v)),
        ),
      ],
    );
  }
}

/// Dal menu: le opzioni valgono per i prossimi viaggi (e per quello in corso).
class OpzioniPercorsoSchermata extends StatefulWidget {
  const OpzioniPercorsoSchermata({super.key, required this.iniziali, required this.onCambia});

  final OpzioniPercorso iniziali;
  final ValueChanged<OpzioniPercorso> onCambia;

  @override
  State<OpzioniPercorsoSchermata> createState() => _OpzioniPercorsoSchermataState();
}

class _OpzioniPercorsoSchermataState extends State<OpzioniPercorsoSchermata> {
  late var _o = widget.iniziali;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Percorso')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        PannelloOpzioniPercorso(
          opzioni: _o,
          onCambia: (o) {
            setState(() => _o = o);
            widget.onCambia(o);
          },
        ),
      ],
    ),
  );
}

/// Dalla scheda del viaggio: si sceglie e si ricalcola subito.
Future<void> mostraOpzioniPercorso(
  BuildContext context,
  OpzioniPercorso iniziali,
  ValueChanged<OpzioniPercorso> onCambia,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    var o = iniziali;
    return StatefulBuilder(
      builder: (context, aggiorna) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Opzioni del percorso', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              PannelloOpzioniPercorso(
                opzioni: o,
                onCambia: (n) {
                  aggiorna(() => o = n);
                  onCambia(n);
                },
              ),
            ],
          ),
        ),
      ),
    );
  },
);
