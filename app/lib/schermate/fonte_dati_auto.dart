import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_auto.dart';
import '../componenti/indicatore_batteria.dart';
import 'esplora_auto.dart';
import 'scegli_dongle.dart';

/// Lo switch «Fonte dati auto»: Automatica, oppure una sorgente fissa.
Future<void> mostraFonteDatiAuto(BuildContext context, GestoreAuto gestore) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => FonteDatiAuto(gestore: gestore),
  );
}

class FonteDatiAuto extends StatelessWidget {
  const FonteDatiAuto({super.key, required this.gestore});

  final GestoreAuto gestore;

  static const _scelte = [TipoSorgente.androidAuto, TipoSorgente.obd, TipoSorgente.homeAssistant, TipoSorgente.manuale];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: gestore,
      builder: (context, _) {
        final m = gestore.modalita;
        final scelta = switch (m) {
          Automatica() => null,
          Fissa(:final sorgente) => sorgente,
        };
        return SafeArea(
          child: RadioGroup<TipoSorgente?>(
            groupValue: scelta,
            onChanged: (t) => gestore.cambiaModalita(t == null ? const Automatica() : Fissa(t)),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('Fonte dati auto', style: Theme.of(context).textTheme.titleLarge),
                ),
                const RadioListTile<TipoSorgente?>(
                  value: null,
                  title: Text('Automatica'),
                  subtitle: Text('Auto, poi OBD, poi Home Assistant se recente, poi stima'),
                ),
                for (final t in _scelte)
                  RadioListTile<TipoSorgente?>(
                    value: t,
                    title: Text(nomeSorgente(t)),
                    subtitle: gestore.disponibili.contains(t) ? null : const Text('Non collegata'),
                  ),
                const Divider(),
                _Dongle(gestore: gestore),
                const Divider(),
                _BatteriaManuale(gestore: gestore),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BatteriaManuale extends StatefulWidget {
  const _BatteriaManuale({required this.gestore});

  final GestoreAuto gestore;

  @override
  State<_BatteriaManuale> createState() => _BatteriaManualeState();
}

class _BatteriaManualeState extends State<_BatteriaManuale> {
  late double _valore = widget.gestore.stato?.batteria.roundToDouble() ?? 80;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: _valore,
              max: 100,
              divisions: 100,
              label: '${_valore.round()}%',
              onChanged: (v) => setState(() => _valore = v),
            ),
          ),
          FilledButton.tonal(
            onPressed: () => widget.gestore.manuale.imposta(_valore),
            child: Text('Batteria ${_valore.round()}%'),
          ),
        ],
      ),
    );
  }
}

/// Il dongle OBD: quale, se dà dati, e come cambiarlo.
class _Dongle extends StatelessWidget {
  const _Dongle({required this.gestore});

  final GestoreAuto gestore;

  @override
  Widget build(BuildContext context) {
    final d = gestore.dongle;
    void scegli() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScegliDongle(auto: gestore)));
    if (d == null) {
      return ListTile(
        leading: const Icon(Icons.cable),
        title: const Text('Dongle OBD Bluetooth'),
        subtitle: const Text('Batteria, velocità e temperatura dalla presa OBD, come ABRP'),
        trailing: const Icon(Icons.chevron_right),
        onTap: scegli,
      );
    }
    final dati = gestore.stato?.sorgente == TipoSorgente.obd;
    return ListTile(
      leading: const Icon(Icons.cable),
      title: Text(d.nome.isEmpty ? 'Dongle OBD' : d.nome),
      subtitle: Text(dati ? 'Dà i dati dell\'auto' : (gestore.erroreObd ?? 'In attesa dell\'auto accesa')),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => switch (v) {
          'esplora' => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EsploraAuto(auto: gestore))),
          'cambia' => scegli(),
          _ => gestore.togliDongle(),
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'esplora', child: Text("Esplora l'auto")),
          PopupMenuItem(value: 'cambia', child: Text('Cambia dongle')),
          PopupMenuItem(value: 'togli', child: Text('Togli')),
        ],
      ),
    );
  }
}
