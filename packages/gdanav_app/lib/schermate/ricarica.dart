import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/archivio.dart';
import '../stato/gestore_viaggio.dart';

String riassuntoPreferenze(PreferenzeRicarica p) =>
    'Arrivo ≥ ${p.minimoArrivo.round()}% · fino all\'${p.massimoRicarica.round()}% · ≥ ${p.potenzaMinimaKw.round()} kW';

/// Come preferisci ricaricare: il pianificatore ne tiene conto. Si salva a
/// ogni tocco.
class PreferenzeRicaricaSchermata extends StatefulWidget {
  const PreferenzeRicaricaSchermata({super.key, required this.archivio, this.operatori});

  final Archivio archivio;

  /// Gli operatori fra cui scegliere chi non vedere. Di serie, quelli delle
  /// colonnine già scaricate — che sono quelle dei posti dove si passa.
  ///
  /// Si può passare da fuori per guardare la pagina senza l'archivio addosso:
  /// è così che si fanno le fotografie (`test/foto/ricarica_foto.dart`).
  final Future<List<String>> Function()? operatori;

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
    (widget.operatori ?? _dallArchivio)().then((elenco) {
      if (mounted) setState(() => _operatori = elenco);
    });
  }

  static Future<List<String>> _dallArchivio() async =>
      operatoriFra((await archivioColonnine()).tutte).take(24).toList();

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
                Text('Soste del viaggio (kW)', style: t.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Il percorso ti fa fermare solo a colonnine da questa potenza in su. '
                  'Sulla mappa e fra quelle intorno a te le vedi sempre tutte, anche le lente.',
                  style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: PreferenzeRicarica.minimaSoste, label: Text('≥ 22')),
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
    /* Quelli spenti ci sono sempre, anche se non sono fra i più diffusi qui
     * intorno: spegnerne uno raro e non ritrovarlo più sarebbe una trappola —
     * resterebbe spento per sempre senza un modo di riaccenderlo. */
    final conosciuti = {for (final nome in tutti) operatoreNormale(nome)};
    final elenco = [...tutti, ...esclusi.where((o) => !conosciuti.contains(o))];
    if (elenco.isEmpty) return const SizedBox.shrink();
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
            for (final nome in elenco)
              _UnOperatore(
                nome: nome,
                spento: esclusi.contains(operatoreNormale(nome)),
                cambia: (spegnilo) {
                  final chiave = operatoreNormale(nome);
                  final nuovi = {...esclusi};
                  if (spegnilo) {
                    nuovi.add(chiave);
                  } else {
                    nuovi.remove(chiave);
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

/// Una pastiglia: acceso è lo stato normale, e lo stato normale non urla.
///
/// Acceso non porta nessun segno — sono decine, e decine di spunte blu sono
/// una pagina che sembra piena di scelte quando invece non si è scelto
/// niente. Spento invece si vede da lontano: il nome barrato e l'occhio
/// chiuso, che è quello che vuol dire.
class _UnOperatore extends StatelessWidget {
  const _UnOperatore({required this.nome, required this.spento, required this.cambia});

  final String nome;
  final bool spento;
  final ValueChanged<bool> cambia;

  @override
  Widget build(BuildContext context) {
    final colori = Theme.of(context).colorScheme;
    return FilterChip(
      showCheckmark: false,
      selected: spento,
      selectedColor: colori.surfaceContainerHighest,
      avatar: spento ? Icon(Icons.visibility_off_rounded, size: 18, color: colori.onSurfaceVariant) : null,
      label: Text(
        nome,
        style: spento ? TextStyle(decoration: TextDecoration.lineThrough, color: colori.onSurfaceVariant) : null,
      ),
      tooltip: spento ? 'Tocca per rivederlo' : 'Tocca per non vederlo più',
      onSelected: cambia,
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
