import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_luoghi.dart';

/// «Dove vuoi andare?»: si scrive, e sotto compaiono i posti. Toccarne uno
/// lo restituisce a chi ha aperto la schermata.
class CercaDestinazione extends StatefulWidget {
  const CercaDestinazione({super.key, required this.luoghi, this.vicinoA, this.salvati, this.titolo = 'Dove andiamo?'});

  final FonteLuoghi luoghi;
  final Punto? vicinoA;

  /// Casa, Lavoro e recenti, da mostrare finché non si scrive.
  final GestoreLuoghi? salvati;

  /// Il testo nel campo vuoto.
  final String titolo;

  @override
  State<CercaDestinazione> createState() => _CercaDestinazioneState();
}

class _CercaDestinazioneState extends State<CercaDestinazione> {
  Timer? _attesa;
  List<Luogo> _risultati = const [];
  var _cercato = false;
  String? _errore;
  var _cercando = false;
  var _ultima = 0;

  // Il campo ha il suo controller: così il testo non dipende da come è
  // costruita la barra sopra.
  final _testo = TextEditingController();

  void _scritto(String testo) {
    _attesa?.cancel();
    setState(() {}); // per la ✕

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
      if (questa == _ultima && mounted) {
        setState(() {
          _risultati = r;
          _cercato = true;
        });
      }
    } catch (_) {
      if (questa == _ultima && mounted) setState(() => _errore = 'La ricerca non risponde. Riprova tra poco.');
    } finally {
      if (questa == _ultima && mounted) setState(() => _cercando = false);
    }
  }

  @override
  void dispose() {
    _attesa?.cancel();
    _testo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _testo,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.titolo, border: InputBorder.none),
          textInputAction: TextInputAction.search,
          onChanged: _scritto,
          onSubmitted: _cerca,
        ),
        actions: [
          if (_testo.text.isNotEmpty)
            IconButton(
              tooltip: 'Cancella',
              icon: const Icon(Icons.close),
              onPressed: () {
                _attesa?.cancel();
                _ultima++;
                _testo.clear();
                setState(() {
                  _risultati = const [];
                  _cercando = false;
                });
              },
            ),
        ],
        // La barra di avanzamento c'è sempre, cambia solo se si vede: se
        // comparisse e sparisse, il campo verrebbe ricostruito e perderebbe
        // quello che si è scritto.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Opacity(
            opacity: _cercando ? 1 : 0,
            child: LinearProgressIndicator(minHeight: 2, value: _cercando ? null : 0),
          ),
        ),
      ),
      body: _errore != null
          ? Padding(padding: const EdgeInsets.all(16), child: Text(_errore!))
          : ListView(
              children: [
                if (_testo.text.trim().length < 3 && widget.salvati != null) ..._salvati(context),
                for (final l in _risultati)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(l.nome),
                    subtitle: l.descrizione.isEmpty ? null : Text(l.descrizione),
                    onTap: () => Navigator.of(context).pop(l),
                  ),
                if (!_cercando && _risultati.isEmpty && _testo.text.trim().length >= 3 && _cercato)
                  const Padding(padding: EdgeInsets.all(16), child: Text('Nessun posto trovato.')),
              ],
            ),
    );
  }

  Iterable<Widget> _salvati(BuildContext context) sync* {
    final g = widget.salvati!;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    for (final p in g.preferiti) {
      yield ListTile(
        leading: Icon(switch (p.tipo) {
          TipoPreferito.casa => Icons.home_rounded,
          TipoPreferito.lavoro => Icons.work_rounded,
          TipoPreferito.altro => Icons.star_rounded,
        }),
        title: Text(p.etichetta),
        subtitle: Text(p.luogo.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.of(context).pop(p.luogo),
      );
    }
    for (final l in g.recenti) {
      yield ListTile(
        leading: Icon(Icons.history, color: muto),
        title: Text(l.nome),
        subtitle: l.descrizione.isEmpty ? null : Text(l.descrizione, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.of(context).pop(l),
      );
    }
  }
}
