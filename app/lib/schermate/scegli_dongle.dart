import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../sorgenti/canale_ble.dart';
import '../stato/gestore_auto.dart';

/// Si cercano i dongle OBD Bluetooth intorno e se ne sceglie uno. Quelli che
/// sembrano OBD (Vgate, OBDLink, Veepeak…) vanno in cima.
class ScegliDongle extends StatefulWidget {
  const ScegliDongle({super.key, required this.auto});

  final GestoreAuto auto;

  @override
  State<ScegliDongle> createState() => _ScegliDongleState();
}

class _ScegliDongleState extends State<ScegliDongle> {
  final _trovati = <String, DiscoveredDevice>{};
  StreamSubscription<DiscoveredDevice>? _ricerca;
  Timer? _fine;
  String? _errore;
  var _cercando = false;

  @override
  void initState() {
    super.initState();
    _cerca();
  }

  Future<void> _cerca() async {
    if (!await CanaleBle.permessi()) {
      if (mounted) setState(() => _errore = 'Serve il permesso Bluetooth per trovare il dongle.');
      return;
    }
    await _ricerca?.cancel();
    setState(() {
      _cercando = true;
      _errore = null;
    });
    _ricerca = CanaleBle.cerca().listen(
      (d) => setState(() => _trovati[d.id] = d),
      onError: (Object e) => setState(() {
        _errore = 'Bluetooth: accendilo e riprova.';
        _cercando = false;
      }),
    );
    _fine?.cancel();
    _fine = Timer(const Duration(seconds: 12), () async {
      await _ricerca?.cancel();
      if (mounted) setState(() => _cercando = false);
    });
  }

  @override
  void dispose() {
    _fine?.cancel();
    _ricerca?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elenco = _trovati.values.toList()
      ..sort((a, b) {
        final oa = CanaleBle.sembraObd(a.name) ? 0 : 1, ob = CanaleBle.sembraObd(b.name) ? 0 : 1;
        return oa != ob ? oa.compareTo(ob) : b.rssi.compareTo(a.rssi);
      });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dongle OBD'),
        actions: [
          if (!_cercando) IconButton(tooltip: 'Cerca di nuovo', onPressed: _cerca, icon: const Icon(Icons.refresh)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Opacity(opacity: _cercando ? 1 : 0, child: const LinearProgressIndicator(minHeight: 2)),
        ),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Inserisci il dongle nella presa OBD (sotto il volante) e accendi l\'auto. '
              'Servono dongle Bluetooth LE con chip ELM327: Vgate iCar Pro, OBDLink CX, Veepeak BLE…',
            ),
          ),
          if (_errore case final e?) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(e)),
          for (final d in elenco)
            ListTile(
              leading: Icon(CanaleBle.sembraObd(d.name) ? Icons.cable : Icons.bluetooth),
              title: Text(d.name),
              subtitle: Text(CanaleBle.sembraObd(d.name) ? 'Sembra un dongle OBD' : d.id),
              onTap: () async {
                await _ricerca?.cancel();
                await widget.auto.usaDongle(d.id, d.name);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          if (!_cercando && elenco.isEmpty && _errore == null)
            const Padding(padding: EdgeInsets.all(16), child: Text('Nessun dispositivo trovato.')),
        ],
      ),
    );
  }
}
