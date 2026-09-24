import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_mappe_offline.dart';
import '../tema.dart';

/// «Mappe offline»: si scaricano le regioni (o la zona intorno a sé) e la
/// mappa si vede anche senza rete.
class MappeOffline extends StatefulWidget {
  const MappeOffline({super.key, required this.gestore, this.qui});

  final GestoreMappeOffline gestore;
  final Punto? qui;

  @override
  State<MappeOffline> createState() => _MappeOfflineState();
}

class _MappeOfflineState extends State<MappeOffline> {
  @override
  void initState() {
    super.initState();
    widget.gestore.carica();
  }

  String _mb(double mb) =>
      mb >= 1000 ? '${(mb / 1024).toStringAsFixed(1).replaceAll('.', ',')} GB' : '${mb.round()} MB';

  Future<void> _conferma(Zona z) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Scaricare ${z.nome}?'),
        content: Text(
          'Circa ${_mb(z.megabyteStimati())}. Meglio col Wi-Fi. Si può continuare a usare l\'app mentre scarica.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Scarica')),
        ],
      ),
    );
    if (ok == true) await widget.gestore.scarica(z);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    final g = widget.gestore;
    return Scaffold(
      appBar: AppBar(title: const Text('Mappe offline')),
      body: ListenableBuilder(
        listenable: g,
        builder: (context, _) {
          final scaricate = g.zone;
          final daScaricare = [
            if (widget.qui case final qui?) Zona.intorno(qui),
            ...regioniItalia,
          ].where((z) => !g.scaricata(z)).toList();
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Con le mappe scaricate vedi strade, nomi ed edifici anche senza rete, sul telefono e in auto. '
                  'Il calcolo del percorso, la ricerca e le colonnine chiedono comunque la rete.',
                  style: t.bodyMedium?.copyWith(color: muto),
                ),
              ),
              if (g.errore case final e?)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(e, style: t.bodyMedium?.copyWith(color: ColoriGdanav.di(context).guasta)),
                ),
              if (g.inCorso case final z?)
                ListTile(
                  leading: const Icon(Icons.downloading),
                  title: Text('Scarico ${z.nome}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: g.progresso),
                      const SizedBox(height: 4),
                      Text('${(g.progresso * 100).round()}% · ${_mb(g.megabyte)}'),
                    ],
                  ),
                ),
              if (scaricate.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Scaricate', style: t.titleSmall),
                ),
                for (final s in scaricate)
                  ListTile(
                    leading: Icon(
                      s.completa ? Icons.offline_pin : Icons.pending,
                      color: s.completa ? ColoriGdanav.di(context).libera : muto,
                    ),
                    title: Text(s.zona.nome),
                    subtitle: Text(s.completa ? _mb(s.megabyte) : 'Incompleta · ${_mb(s.megabyte)}'),
                    trailing: IconButton(
                      tooltip: 'Cancella ${s.zona.nome}',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => g.cancella(s),
                    ),
                  ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Da scaricare', style: t.titleSmall),
              ),
              for (final z in daScaricare)
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: Text(z.nome),
                  subtitle: Text('circa ${_mb(z.megabyteStimati())}'),
                  trailing: const Icon(Icons.download),
                  enabled: g.inCorso == null,
                  onTap: () => _conferma(z),
                ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}
