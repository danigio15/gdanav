import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../risorse.dart';
import '../stato/gestore_aggiornamento.dart';

/// Questa versione di gdanav non va più: si può solo aggiornarla. Prende
/// tutto lo schermo al posto del navigatore di gdanav (`GdanavApp`): sotto
/// non c'è niente da riaprire.
class SchermataAggiorna extends StatelessWidget {
  const SchermataAggiorna({super.key, this.apri = _apri});

  /// Apre il primo indirizzo che si apre (nelle prove: finto).
  final Future<void> Function(List<Uri> indirizzi) apri;

  static const titolo = 'C\'è una versione nuova di gdanav: aggiornala per continuare';

  static Future<void> _apri(List<Uri> indirizzi) async {
    for (final u in indirizzi) {
      try {
        if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(logoGdanav, width: 96, height: 96),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    titolo,
                    key: const Key('aggiorna-titolo'),
                    textAlign: TextAlign.center,
                    style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Questa versione non è più attiva. Scarica l\'ultima: le tue auto, i luoghi e le '
                    'impostazioni restano dove sono.',
                    textAlign: TextAlign.center,
                    style: t.bodyLarge?.copyWith(color: s.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    key: const Key('aggiorna-negozio'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () => apri(indirizziNegozio(defaultTargetPlatform)),
                    icon: const Icon(Icons.system_update),
                    label: Text(ios ? 'Aggiorna dall\'App Store' : 'Aggiorna dal Play Store'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
