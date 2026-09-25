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
/// si passa dal distributore e poi si prosegue verso la meta.
Future<void> mostraDistributori(
  BuildContext context, {
  required Punto? qui,
  required ValueChanged<Luogo> onScegli,
  bool inGuida = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (contesto) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (contesto, scorrimento) => _Elenco(
        qui: qui,
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
  const _Elenco({required this.qui, required this.scorrimento, required this.inGuida, required this.onScegli});

  final Punto? qui;
  final ScrollController scorrimento;
  final bool inGuida;
  final ValueChanged<Luogo> onScegli;

  @override
  State<_Elenco> createState() => _ElencoState();
}

class _ElencoState extends State<_Elenco> {
  late Future<List<Distributore>>? _cerca = widget.qui == null ? null : distributoriVicini(widget.qui!);

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
        if (qui == null)
          messaggio('Non so dove sei: attiva la posizione per gdanav.')
        else
          FutureBuilder(
            future: _cerca,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (s.hasError) return messaggio('I distributori non sono arrivati. Riprova tra poco.', riprova: true);
              final elenco = s.data ?? const <Distributore>[];
              if (elenco.isEmpty) return messaggio('Nessun distributore entro 5 km.');
              return Column(
                children: [
                  for (final d in elenco)
                    ListTile(
                      key: Key('distributore-${d.id}'),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFDE7D2),
                        child: Icon(Icons.local_gas_station, color: Color(0xFFD9700F)),
                      ),
                      title: Text(d.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(descriviDistributore(d, qui), maxLines: 2),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onScegli(luogoDistributore(d, qui)),
                    ),
                ],
              );
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text('Dati: © OpenStreetMap contributors', style: t.bodySmall?.copyWith(color: muto)),
        ),
      ],
    );
  }
}
