import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/distributori.dart';

/// Il tasto dei distributori, sulla mappa: tondo e arancione.
class BottoneDistributori extends StatelessWidget {
  const BottoneDistributori({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Distributori vicini',
    child: Material(
      color: const Color(0xFFF08A24),
      elevation: 6,
      shadowColor: const Color(0x55000000),
      shape: const CircleBorder(),
      child: InkWell(
        key: const Key('distributori'),
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox.square(
          dimension: 60,
          child: Icon(Icons.local_gas_station, size: 32, color: Colors.white),
        ),
      ),
    ),
  );
}

/// L'elenco dei distributori vicini: tocchi e ci vai. In guida, [inGuida]:
/// si passa dal distributore e poi si prosegue verso la meta. In Italia coi
/// prezzi del Ministero, del [carburante] dell'auto.
Future<void> mostraDistributori(
  BuildContext context, {
  required Punto? qui,
  required ValueChanged<Luogo> onScegli,
  Carburante carburante = Carburante.benzina,
  bool inGuida = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (contesto) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      builder: (contesto, scorrimento) => _Elenco(
        qui: qui,
        carburante: carburante,
        scorrimento: scorrimento,
        inGuida: inGuida,
        onScegli: (l) {
          Navigator.of(contesto).pop();
          onScegli(l);
        },
      ),
    ),
  );
}

class _Elenco extends StatefulWidget {
  const _Elenco({
    required this.qui,
    required this.carburante,
    required this.scorrimento,
    required this.inGuida,
    required this.onScegli,
  });

  final Punto? qui;
  final Carburante carburante;
  final ScrollController scorrimento;
  final bool inGuida;
  final ValueChanged<Luogo> onScegli;

  @override
  State<_Elenco> createState() => _ElencoState();
}

class _ElencoState extends State<_Elenco> {
  late Future<List<Distributore>>? _cerca = widget.qui == null ? null : distributoriVicini(widget.qui!);
  late var _carburante = widget.carburante;
  var _economici = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    final qui = widget.qui;
    Widget messaggio(String testo, {bool riprova = false}) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(testo, textAlign: TextAlign.center),
          if (riprova)
            TextButton(
              onPressed: () => setState(() => _cerca = distributoriVicini(qui!)),
              child: const Text('Riprova'),
            ),
        ],
      ),
    );
    return FutureBuilder(
      future: _cerca,
      builder: (context, s) {
        final elenco = [...?s.data];
        final conPrezzi = elenco.any((d) => d.prezzi.isNotEmpty);
        if (_economici) {
          // I più economici del carburante scelto; chi non lo ha va in fondo.
          elenco.sort((a, b) {
            final pa = a.prezzoDi(_carburante)?.euro ?? 99, pb = b.prezzoDi(_carburante)?.euro ?? 99;
            return pa != pb ? pa.compareTo(pb) : distanzaM(qui!, a.posizione).compareTo(distanzaM(qui, b.posizione));
          });
        }
        final minimo = [
          for (final d in elenco)
            if (d.prezzoDi(_carburante) case final p?) p.euro,
        ].fold<double?>(null, (m, e) => m == null || e < m ? e : m);
        return ListView(
          controller: widget.scorrimento,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Distributori vicini', style: t.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                widget.inGuida ? 'Tocca per passarci e poi proseguire.' : 'Tocca per andarci.',
                style: t.bodyMedium?.copyWith(color: muto),
              ),
            ),
            if (conPrezzi) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (final c in Carburante.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          key: Key('carburante-${c.name}'),
                          label: Text(c.nome),
                          selected: c == _carburante,
                          onSelected: (_) => setState(() => _carburante = c),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: SegmentedButton<bool>(
                  key: const Key('ordine-distributori'),
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.near_me), label: Text('Più vicini')),
                    ButtonSegment(value: true, icon: Icon(Icons.euro), label: Text('Più economici')),
                  ],
                  selected: {_economici},
                  onSelectionChanged: (v) => setState(() => _economici = v.first),
                ),
              ),
            ],
            if (qui == null)
              messaggio('Non so dove sei: attiva la posizione per gdanav.')
            else if (s.connectionState != ConnectionState.done)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (s.hasError)
              messaggio('I distributori non sono arrivati. Riprova tra poco.', riprova: true)
            else if (elenco.isEmpty)
              messaggio('Nessun distributore entro 5 km.')
            else
              for (final d in elenco)
                _Riga(
                  distributore: d,
                  qui: qui,
                  carburante: _carburante,
                  piuEconomico: minimo != null && d.prezzoDi(_carburante)?.euro == minimo,
                  onTap: () => widget.onScegli(luogoDistributore(d, qui, carburante: _carburante)),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                conPrezzi
                    ? 'Prezzi: Osservaprezzi carburanti (MIMIT), comunicati dai gestori.'
                    : 'Dati: © OpenStreetMap contributors',
                style: t.bodySmall?.copyWith(color: muto),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Riga extends StatelessWidget {
  const _Riga({
    required this.distributore,
    required this.qui,
    required this.carburante,
    required this.piuEconomico,
    required this.onTap,
  });

  final Distributore distributore;
  final Punto qui;
  final Carburante carburante;
  final bool piuEconomico;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    final d = distributore;
    final p = d.prezzoDi(carburante);
    final sotto = p == null
        ? descriviDistributore(d, qui, carburante: carburante)
        : [
            distanza(d, qui),
            ?d.indirizzo,
            if (quandoAggiornato(d.aggiornato) case final q?) 'prezzo di $q',
          ].join(' · ');
    const verde = Color(0xFF16A34A);
    return ListTile(
      key: Key('distributore-${d.id}'),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFDE7D2),
        child: Icon(Icons.local_gas_station, color: Color(0xFFD9700F)),
      ),
      title: Text(d.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sotto, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: p == null
          ? const Icon(Icons.chevron_right)
          : Column(
              key: Key('prezzo-${d.id}'),
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  euro(p.euro),
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: piuEconomico ? verde : null),
                ),
                Text(p.self ? 'self' : 'servito', style: t.bodySmall?.copyWith(color: muto)),
              ],
            ),
      onTap: onTap,
    );
  }
}
