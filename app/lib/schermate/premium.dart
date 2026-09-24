import 'package:flutter/material.dart';

import '../stato/gestore_premium.dart';

/// Cosa sblocca Premium, il prezzo e il bottone per comprarlo. Si usa da
/// solo (dal menu) e al posto delle funzioni bloccate.
class PannelloPremium extends StatelessWidget {
  const PannelloPremium({super.key, required this.premium, this.perche});

  final GestorePremium premium;

  /// Cosa si stava cercando di aprire: «Android Auto», «Home Assistant».
  final String? perche;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: premium,
      builder: (context, _) {
        final p = premium;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium, color: s.primary, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('gdanav Premium', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p.sbloccato
                  ? 'Premium è attivo: grazie!'
                  : perche == null
                  ? 'Un acquisto solo, per sempre, legato al tuo account Google.'
                  : '$perche fa parte di Premium: un acquisto solo, per sempre, legato al tuo account Google.',
              style: t.bodyLarge,
            ),
            const SizedBox(height: 16),
            const _Voce(
              icona: Icons.directions_car_filled,
              titolo: 'Android Auto',
              testo: 'La mappa, la guida e le soste sullo schermo dell\'auto.',
            ),
            const _Voce(
              icona: Icons.home_outlined,
              titolo: 'Home Assistant',
              testo: 'La batteria vera della tua auto, soste ricalcolate sul consumo reale, i viaggi a casa.',
            ),
            const SizedBox(height: 16),
            if (!p.sbloccato) ...[
              FilledButton.icon(
                key: const Key('compra-premium'),
                onPressed: p.inCorso || p.prezzo == null ? null : p.compra,
                icon: p.inCorso
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.lock_open),
                label: Text(p.prezzo == null ? 'Sblocca' : 'Sblocca a ${p.prezzo}'),
              ),
              TextButton(onPressed: p.inCorso ? null : p.ripristina, child: const Text('Ripristina acquisti')),
              if (p.prezzo == null && !p.inCorso)
                Text(
                  'Premium si compra dall\'app scaricata dal Play Store.',
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: s.onSurfaceVariant),
                ),
              if (p.errore case final e?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    e,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: s.error),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _Voce extends StatelessWidget {
  const _Voce({required this.icona, required this.titolo, required this.testo});

  final IconData icona;
  final String titolo;
  final String testo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icona),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titolo, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(testo, style: t.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dal menu, o toccando una funzione bloccata.
class SchermataPremium extends StatelessWidget {
  const SchermataPremium({super.key, required this.premium, this.perche});

  final GestorePremium premium;
  final String? perche;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Premium')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [PannelloPremium(premium: premium, perche: perche)],
    ),
  );
}
