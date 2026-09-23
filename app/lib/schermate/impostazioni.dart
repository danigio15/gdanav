import 'package:flutter/material.dart';

import '../stato/archivio.dart';

/// Dove stanno i servizi: il server dei percorsi e la chiave delle
/// colonnine. Finché i servizi di gdanav non sono pubblici, si scrivono qui.
class SchermataImpostazioni extends StatefulWidget {
  const SchermataImpostazioni({super.key, required this.archivio});

  final Archivio archivio;

  @override
  State<SchermataImpostazioni> createState() => _SchermataImpostazioniState();
}

class _SchermataImpostazioniState extends State<SchermataImpostazioni> {
  final _valhalla = TextEditingController();
  final _chiaveValhalla = TextEditingController();
  final _chiaveOcm = TextEditingController();
  var _pronta = false;

  @override
  void initState() {
    super.initState();
    widget.archivio.impostazioni().then((i) {
      if (!mounted) return;
      _valhalla.text = i.valhalla;
      _chiaveValhalla.text = i.chiaveValhalla;
      _chiaveOcm.text = i.chiaveOcm;
      setState(() => _pronta = true);
    });
  }

  @override
  void dispose() {
    _valhalla.dispose();
    _chiaveValhalla.dispose();
    _chiaveOcm.dispose();
    super.dispose();
  }

  Future<void> _salva() async {
    await widget.archivio.salvaImpostazioni(
      Impostazioni(
        valhalla: _valhalla.text.trim(),
        chiaveValhalla: _chiaveValhalla.text.trim(),
        chiaveOcm: _chiaveOcm.text.trim(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impostazioni salvate')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: !_pronta
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  key: const Key('valhalla'),
                  controller: _valhalla,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server dei percorsi',
                    hintText: 'https://1-2-3-4.sslip.io/',
                    helperText: 'Il tuo Valhalla (vedi valhalla/README.md)',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('chiave_valhalla'),
                  controller: _chiaveValhalla,
                  decoration: const InputDecoration(labelText: 'Chiave del server dei percorsi'),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('chiave_ocm'),
                  controller: _chiaveOcm,
                  decoration: const InputDecoration(
                    labelText: 'Chiave di Open Charge Map',
                    helperText: 'Gratis su openchargemap.org, da My Profile, poi My Apps',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _salva, child: const Text('Salva')),
              ],
            ),
    );
  }
}
