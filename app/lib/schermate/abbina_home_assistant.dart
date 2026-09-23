import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../stato/gestore_auto.dart';

/// Si inquadra il QR che mostra l'integrazione gdanav in Home Assistant
/// (il dispositivo dell'auto → «QR di abbinamento»).
class AbbinaHomeAssistant extends StatefulWidget {
  const AbbinaHomeAssistant({super.key, required this.gestore});

  final GestoreAuto gestore;

  @override
  State<AbbinaHomeAssistant> createState() => _AbbinaHomeAssistantState();
}

class _AbbinaHomeAssistantState extends State<AbbinaHomeAssistant> {
  String? _errore;
  var _fatto = false;

  Future<void> _letto(BarcodeCapture cattura) async {
    if (_fatto) return;
    for (final codice in cattura.barcodes) {
      final testo = codice.rawValue;
      if (testo == null) continue;
      try {
        final a = Abbinamento.daUri(testo);
        _fatto = true;
        await widget.gestore.abbina(a);
        if (mounted) Navigator.of(context).pop();
        return;
      } on FormatException catch (e) {
        setState(() => _errore = e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final abbinata = widget.gestore.abbinamento;
    return Scaffold(
      appBar: AppBar(title: const Text('Home Assistant')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              abbinata == null
                  ? 'In Home Assistant apri il dispositivo gdanav della tua auto e inquadra il «QR di abbinamento».'
                  : 'Collegata a ${abbinata.nomeAuto.isEmpty ? 'Home Assistant' : abbinata.nomeAuto}. '
                        'Inquadra un altro QR per cambiarla.',
            ),
          ),
          if (_errore != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_errore!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(child: MobileScanner(onDetect: _letto)),
          if (abbinata != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () async {
                  await widget.gestore.scollega();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Scollega Home Assistant'),
              ),
            ),
        ],
      ),
    );
  }
}
