import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/segnaposto.dart';
import '../stato/gestore_auto.dart';
import '../stato/gestore_consumo.dart';
import '../stato/gestore_posizione.dart';
import '../tema.dart';

String schedaBreve(ProfiloVeicolo v) {
  final prese = v.connettori.contains(TipoConnettore.ccs2) ? 'CCS' : 'CHAdeMO';
  return '${_n(v.capacitaUtileKwh)} kWh · fino a ${v.piccoDcKw.round()} kW · $prese';
}

String _n(double x) => x == x.roundToDouble() ? '${x.round()}' : x.toStringAsFixed(1).replaceAll('.', ',');

/// La scelta dell'auto: da lei dipendono consumi, tempi di ricarica e prese.
class LaTuaAuto extends StatefulWidget {
  const LaTuaAuto({super.key, required this.auto, required this.posizione, this.consumo});

  final GestoreAuto auto;
  final GestorePosizione posizione;
  final GestoreConsumo? consumo;

  @override
  State<LaTuaAuto> createState() => _LaTuaAutoState();
}

class _LaTuaAutoState extends State<LaTuaAuto> {
  // Con l'auto d'esempio e Home Assistant collegato, si parte dal nome che
  // arriva da lì («Leapmotor B10»): basta scegliere la batteria.
  late var _filtro = widget.auto.veicolo.id == ProfiloVeicolo.esempio.id
      ? _parolePrincipali(widget.auto.abbinamento?.nomeAuto ?? '')
      : '';
  late final _campo = TextEditingController(text: _filtro);

  /// Le parole del nome che stanno nel catalogo: «La mia Leapmotor B10» → «Leapmotor B10».
  static String _parolePrincipali(String nome) {
    final parole = semplice(nome).split(' ').where((p) => p.isNotEmpty);
    final buone = [
      for (final p in parole)
        if (catalogoVeicoli.any((v) => semplice(v.nome).split(' ').contains(p))) p,
    ];
    final filtro = buone.join(' ');
    return catalogoVeicoli.any((v) => corrisponde(v, filtro)) ? filtro : '';
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scelta = widget.auto.veicolo;
    final elettrica = widget.auto.elettrica;
    final elenco = catalogoVeicoli.where((v) => corrisponde(v, _filtro)).toList()
      ..sort((a, b) => semplice(a.nome).compareTo(semplice(b.nome)));
    // Le righe della lista: l'intestazione della marca, poi le sue auto.
    final righe = <Object>[];
    for (final v in elenco) {
      if (righe.isEmpty || (righe.last is ProfiloVeicolo && (righe.last as ProfiloVeicolo).marca != v.marca)) {
        righe.add(v.marca);
      }
      righe.add(v);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('La tua auto')),
      body: CustomScrollView(
        slivers: [
          SliverList.list(
            children: [
              // Prima di tutto: elettrica o termica.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: SegmentedButton<bool>(
                  key: const Key('tipo-auto'),
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.electric_car), label: Text('Elettrica')),
                    ButtonSegment(value: false, icon: Icon(Icons.local_gas_station), label: Text('Termica')),
                  ],
                  selected: {elettrica},
                  onSelectionChanged: (v) async {
                    await widget.auto.impostaElettrica(v.first);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              if (!elettrica)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: Text(
                    'Benzina, diesel, GPL o ibrida: gdanav fa il navigatore normale, senza soste di ricarica, '
                    'batteria e colonnine. Restano percorso, traffico, autovelox, segnalazioni, meteo e Android Auto.',
                    key: const Key('spiega-termica'),
                    style: t.bodyMedium,
                  ),
                ),
              if (elettrica)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            child: Icon(Icons.electric_car, color: Theme.of(context).colorScheme.onPrimary, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(scelta.nome, style: t.titleMedium),
                                Text(schedaBreve(scelta), style: t.bodyMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.consumo case final c? when elettrica) _ConsumoImparato(consumo: c),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Come ti vedi sulla mappa', style: t.titleSmall),
              ),
              SizedBox(
                height: 112,
                child: ListenableBuilder(
                  listenable: widget.posizione,
                  builder: (context, _) => ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final s in Segnaposto.values)
                        _Scelta(
                          segnaposto: s,
                          scelto: widget.posizione.segnaposto == s,
                          onTap: () => widget.posizione.scegli(s),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (elettrica)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _campo,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Cerca fra ${catalogoVeicoli.length} auto: marca o modello',
                    ),
                    onChanged: (s) => setState(() => _filtro = s),
                  ),
                ),
            ],
          ),
          // 400 e passa auto: si costruiscono solo quelle che si vedono.
          SliverList.builder(
            itemCount: elettrica ? righe.length : 0,
            itemBuilder: (context, i) => switch (righe[i]) {
              final String marca => Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(marca.toUpperCase(), style: t.labelMedium?.copyWith(letterSpacing: 1.1)),
              ),
              final ProfiloVeicolo v => ListTile(
                title: Text(v.modello),
                subtitle: Text(schedaBreve(v)),
                trailing: v.id == scelta.id
                    ? Icon(Icons.check_circle, color: ColoriGdanav.di(context).libera)
                    : const Icon(Icons.chevron_right),
                selected: v.id == scelta.id,
                onTap: () async {
                  await widget.auto.scegliVeicolo(v);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              _ => const SizedBox.shrink(),
            },
          ),
          if (elettrica && elenco.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(20), child: Text('Nessuna auto con questo nome.')),
            ),
          SliverList.list(
            children: [
              if (elettrica)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    'Valori indicativi dalle schede tecniche. I dati veri della tua auto (Home Assistant, OBD) '
                    'correggono le stime col tempo.',
                    style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ],
      ),
    );
  }
}

class _Scelta extends StatelessWidget {
  const _Scelta({required this.segnaposto, required this.scelto, required this.onTap});

  final Segnaposto segnaposto;
  final bool scelto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        selected: scelto,
        button: true,
        label: segnaposto.etichetta,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: 84,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scelto ? s.primaryContainer : s.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scelto ? s.primary : Colors.transparent, width: 2),
            ),
            child: Column(
              children: [
                Expanded(child: Image.asset(segnaposto.asset, fit: BoxFit.contain)),
                const SizedBox(height: 4),
                Text(
                  segnaposto.etichetta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Minuscole, senza accenti né trattini: «Škoda Elroq» e «skoda elroq»,
/// «ë-C4» ed «e-c4» sono la stessa cosa.
String semplice(String s) {
  const accenti = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', //
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', //
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', //
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', //
    'š': 's', 'ž': 'z', 'č': 'c', 'ç': 'c', 'ñ': 'n', //
  };
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final d = accenti[c] ?? c;
    b.write(RegExp(r'[a-z0-9 ]').hasMatch(d) ? d : ' ');
  }
  return b.toString().replaceAll(RegExp(r' +'), ' ').trim();
}

/// Tutte le parole cercate devono esserci, anche attaccate: «id3», «id 3» e
/// «ID.3» trovano la stessa auto.
bool corrisponde(ProfiloVeicolo v, String filtro) {
  final nome = semplice(v.nome);
  final compatto = nome.replaceAll(' ', '');
  for (final parola in semplice(filtro).split(' ')) {
    if (parola.isNotEmpty && !nome.contains(parola) && !compatto.contains(parola)) return false;
  }
  return true;
}

/// Quanto la tua auto consuma davvero rispetto alla scheda, imparato
/// guidando con i dati dell'auto.
class _ConsumoImparato extends StatelessWidget {
  const _ConsumoImparato({required this.consumo});
  final GestoreConsumo consumo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: consumo,
      builder: (context, _) {
        final c = consumo.imparato;
        final km = c.kmOsservati.round();
        final scarto = c.scartoPercento;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const Icon(Icons.insights_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Consumo imparato', style: t.titleSmall),
                        Text(
                          km == 0
                              ? 'Ancora nessun dato: guida con Home Assistant o Android Auto collegati e gdanav '
                                    'impara quanto consuma davvero la tua auto.'
                              : '${scarto == 0 ? 'Come la scheda' : '${scarto > 0 ? '+' : ''}$scarto% rispetto '
                                          'alla scheda'} · misurato su $km km',
                          key: const Key('consumo-imparato'),
                          style: t.bodySmall?.copyWith(color: muto),
                        ),
                      ],
                    ),
                  ),
                  if (km > 0) TextButton(onPressed: consumo.azzera, child: const Text('Azzera')),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
