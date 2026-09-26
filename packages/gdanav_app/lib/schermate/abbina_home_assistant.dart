import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../servizi.dart';
import '../stato/gestore_auto.dart';

/// Il collegamento con l'integrazione gdanav in Home Assistant: si scrive
/// il codice (pulsante «Nuovo codice di abbinamento» nel dispositivo gdanav)
/// oppure si inquadra il QR. Se Home Assistant è aperto sullo stesso
/// telefono, il codice è l'unico modo.
class AbbinaHomeAssistant extends StatefulWidget {
  const AbbinaHomeAssistant({super.key, required this.gestore, this.daCodice, this.fotocamera = true});

  final GestoreAuto gestore;

  /// Dal codice all'abbinamento: sul relay di gdanav, se non si dice altro.
  final Future<Abbinamento> Function(String codice)? daCodice;

  /// Nelle prove non c'è una fotocamera.
  final bool fotocamera;

  @override
  State<AbbinaHomeAssistant> createState() => _AbbinaHomeAssistantState();
}

class _AbbinaHomeAssistantState extends State<AbbinaHomeAssistant> {
  final _codice = TextEditingController();
  String? _errore;
  var _fatto = false;
  var _attesa = false;

  @override
  void dispose() {
    _codice.dispose();
    super.dispose();
  }

  Future<void> _abbina(Abbinamento a) async {
    _fatto = true;
    await widget.gestore.abbina(a);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _letto(BarcodeCapture cattura) async {
    if (_fatto) return;
    for (final codice in cattura.barcodes) {
      final testo = codice.rawValue;
      if (testo == null) continue;
      try {
        return await _abbina(Abbinamento.daUri(testo));
      } on FormatException catch (e) {
        setState(() => _errore = e.message);
      }
    }
  }

  /// Il codice di dieci caratteri, o il link intero incollato.
  Future<void> _scritto() async {
    final testo = _codice.text.trim();
    if (testo.isEmpty || _attesa) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _attesa = true;
      _errore = null;
    });
    try {
      final a = testo.startsWith('gdanav:')
          ? Abbinamento.daUri(testo)
          : await (widget.daCodice ?? (c) => CodiceAbbinamento.recupera(Uri.parse(Servizi.segnalazioni), c))(testo);
      await _abbina(a);
    } on FormatException catch (e) {
      if (mounted) setState(() => _errore = e.message);
    } catch (e) {
      if (mounted) setState(() => _errore = 'Il relay di gdanav non risponde. Controlla la connessione e riprova.');
    } finally {
      if (mounted) setState(() => _attesa = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final abbinata = widget.gestore.abbinamento;
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Home Assistant')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (abbinata != null)
            Card(
              child: ListTile(
                leading: Icon(Icons.check_circle, color: s.primary),
                title: Text('Collegata a ${abbinata.nomeAuto.isEmpty ? 'Home Assistant' : abbinata.nomeAuto}'),
                subtitle: const Text('Per cambiarla, scrivi un altro codice o inquadra un altro QR.'),
              ),
            ),
          const SizedBox(height: 8),
          Text('Scrivi il codice', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'In Home Assistant apri il dispositivo gdanav della tua auto e premi «Nuovo codice di abbinamento». '
            'Il codice compare nelle notifiche e vale dieci minuti.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('codice-abbinamento'),
            controller: _codice,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _scritto(),
            inputFormatters: [LengthLimitingTextInputFormatter(400)],
            style: t.headlineSmall?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '7KQ2M-9XAPD',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: 'Incolla',
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final dati = await Clipboard.getData(Clipboard.kTextPlain);
                  if (dati?.text case final testo?) _codice.text = testo.trim();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _attesa ? null : _scritto,
            icon: _attesa
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link),
            label: const Text('Collega'),
          ),
          if (_errore != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _errore!,
                key: const Key('errore-abbinamento'),
                style: TextStyle(color: s.error),
              ),
            ),
          const SizedBox(height: 28),
          Text('Oppure inquadra il QR', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Se Home Assistant è aperto su un altro schermo: il «QR di abbinamento» nel dispositivo gdanav.'),
          const SizedBox(height: 12),
          if (widget.fotocamera)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(height: 300, child: MobileScanner(onDetect: _letto)),
            ),
          if (abbinata != null) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () async {
                await widget.gestore.scollega();
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Scollega Home Assistant'),
            ),
          ],
        ],
      ),
    );
  }
}
