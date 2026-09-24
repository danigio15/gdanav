import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../stato/gestore_auto.dart';

/// «Esplora l'auto»: un giro di sola lettura col dongle OBD, e un rapporto da
/// mandare per avere il profilo del proprio modello.
class EsploraAuto extends StatefulWidget {
  const EsploraAuto({super.key, required this.auto});

  final GestoreAuto auto;

  @override
  State<EsploraAuto> createState() => _EsploraAutoState();
}

class _EsploraAutoState extends State<EsploraAuto> {
  final _righe = <String>[];
  String? _rapporto;
  String? _errore;
  var _inCorso = false;

  Future<void> _esplora() async {
    setState(() {
      _inCorso = true;
      _righe.clear();
      _rapporto = null;
      _errore = null;
    });
    try {
      final r = await widget.auto.esploraObd(onRiga: (riga) => mounted ? setState(() => _righe.add(riga)) : null);
      if (mounted) setState(() => _rapporto = r);
    } catch (e) {
      if (mounted) setState(() => _errore = '$e');
    } finally {
      if (mounted) setState(() => _inCorso = false);
    }
  }

  Future<void> _copia() async {
    await Clipboard.setData(ClipboardData(text: _rapporto ?? _righe.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Rapporto copiato: incollalo nella chat')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Esplora l'auto"),
        actions: [
          if (_righe.isNotEmpty && !_inCorso)
            IconButton(tooltip: 'Copia', onPressed: _copia, icon: const Icon(Icons.copy)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Opacity(opacity: _inCorso ? 1 : 0, child: const LinearProgressIndicator(minHeight: 2)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Auto accesa, dongle inserito. gdanav chiede all'auto cosa sa dire: solo letture, non cambia niente "
            "nelle centraline. Ci vuole circa un minuto. Poi copia il rapporto e mandalo: servirà a scrivere il "
            'profilo del tuo modello (batteria, potenza, temperature).',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _inCorso ? null : _esplora,
            icon: const Icon(Icons.search),
            label: Text(_righe.isEmpty ? 'Esplora' : 'Esplora di nuovo'),
          ),
          if (_errore case final e?) ...[
            const SizedBox(height: 12),
            Text(e, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
          ],
          if (_righe.isNotEmpty) ...[
            const SizedBox(height: 16),
            if (!_inCorso)
              FilledButton.tonalIcon(
                onPressed: _copia,
                icon: const Icon(Icons.copy),
                label: const Text('Copia il rapporto'),
              ),
            const SizedBox(height: 8),
            SelectableText(_righe.join('\n'), style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
          ],
        ],
      ),
    );
  }
}
