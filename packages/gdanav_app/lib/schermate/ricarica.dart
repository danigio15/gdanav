import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/archivio.dart';
import '../stato/gestore_viaggio.dart';

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

  /// Gli operatori che ci sono intorno, dal più diffuso: è da questi che si
  /// sceglie chi non vedere. Vuoto finché l'archivio non è letto.
  List<String> _operatori = const [];

  @override
  void initState() {
    super.initState();
    widget.archivio.preferenze().then((p) => mounted ? setState(() => _p = p) : null);
    /* Non si scrive un nome a mano: si tocca quello che si incontra. Le
     * colonnine scaricate sono quelle dei posti dove si passa, ed è lì che un
     * operatore lo si conosce o lo si evita. */
    archivioColonnine().then((a) {
      if (mounted) setState(() => _operatori = operatoriFra(a.tutte).take(24).toList());
    });
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
                Text('Quali colonnine (kW)', style: t.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Vale per le soste del viaggio e per quelle che vedi intorno a te.',
                  style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
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
                const SizedBox(height: 16),
                _Operatori(
                  tutti: _operatori,
                  esclusi: p.operatoriEsclusi,
                  cambia: (esclusi) => _cambia(p.copia(operatoriEsclusi: esclusi)),
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

/// Gli operatori che non si vogliono vedere.
///
/// Si **esclude**, non si include: un elenco di quelli buoni farebbe sparire
/// in silenzio un operatore nuovo, e a chi guarda sembrerebbe che lì non c'è
/// niente. Toccato, l'operatore si spegne: le sue colonnine non si propongono
/// come sosta e non compaiono fra quelle intorno.
class _Operatori extends StatelessWidget {
  const _Operatori({required this.tutti, required this.esclusi, required this.cambia});

  final List<String> tutti;
  final Set<String> esclusi;
  final ValueChanged<Set<String>> cambia;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final colori = Theme.of(context).colorScheme;
    if (tutti.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Operatori', style: t.titleSmall),
        const SizedBox(height: 4),
        Text(
          esclusi.isEmpty
              ? 'Li vedi tutti. Tocca quelli che non vuoi vedere.'
              : '${esclusi.length} spenti: le loro colonnine non si propongono e non si vedono.',
          style: t.bodySmall?.copyWith(color: colori.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final nome in tutti)
              FilterChip(
                label: Text(nome),
                selected: !esclusi.contains(operatoreNormale(nome)),
                onSelected: (tienilo) {
                  final chiave = operatoreNormale(nome);
                  final nuovi = {...esclusi};
                  if (tienilo) {
                    nuovi.remove(chiave);
                  } else {
                    nuovi.add(chiave);
                  }
                  cambia(nuovi);
                },
              ),
          ],
        ),
      ],
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
