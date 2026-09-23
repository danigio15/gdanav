import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// «Dove vuoi andare?»: si scrive, e sotto compaiono i posti. Toccarne uno
/// lo restituisce a chi ha aperto la schermata.
class CercaDestinazione extends StatefulWidget {
  const CercaDestinazione({super.key, required this.luoghi, this.vicinoA});

  final FonteLuoghi luoghi;
  final Punto? vicinoA;

  @override
  State<CercaDestinazione> createState() => _CercaDestinazioneState();
}

class _CercaDestinazioneState extends State<CercaDestinazione> {
  Timer? _attesa;
  List<Luogo> _risultati = const [];
  String? _errore;
  var _cercando = false;
  var _ultima = 0;

  void _scritto(String testo) {
    _attesa?.cancel();
    // Si aspetta che si smetta di scrivere: una richiesta per parola, non
    // per lettera.
    _attesa = Timer(const Duration(milliseconds: 400), () => _cerca(testo));
  }

  Future<void> _cerca(String testo) async {
    final questa = ++_ultima;
    setState(() {
      _cercando = true;
      _errore = null;
    });
    try {
      final r = await widget.luoghi.cerca(testo, vicinoA: widget.vicinoA);
      if (questa == _ultima && mounted) setState(() => _risultati = r);
    } catch (_) {
      if (questa == _ultima && mounted) setState(() => _errore = 'La ricerca non risponde. Riprova tra poco.');
    } finally {
      if (questa == _ultima && mounted) setState(() => _cercando = false);
    }
  }

  @override
  void dispose() {
    _attesa?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Dove vuoi andare?', border: InputBorder.none),
          textInputAction: TextInputAction.search,
          onChanged: _scritto,
          onSubmitted: _cerca,
        ),
        bottom: _cercando
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: _errore != null
          ? Padding(padding: const EdgeInsets.all(16), child: Text(_errore!))
          : ListView(
              children: [
                for (final l in _risultati)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(l.nome),
                    subtitle: l.descrizione.isEmpty ? null : Text(l.descrizione),
                    onTap: () => Navigator.of(context).pop(l),
                  ),
              ],
            ),
    );
  }
}
