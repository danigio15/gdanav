import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_meteo.dart';

/// «Meteo lungo la strada»: qualche punto dalla partenza all'arrivo, ognuno
/// all'ora in cui ci si passa, e con cosa si è calcolato il consumo.
class MeteoLungoLaStrada extends StatelessWidget {
  const MeteoLungoLaStrada({super.key, required this.meteo, this.condizioni});

  final GestoreMeteo meteo;

  /// Con cosa si è calcolato il viaggio.
  final Condizioni? condizioni;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: meteo,
      builder: (context, _) {
        final m = meteo.delViaggio;
        if (m == null || m.vuoto) return const SizedBox.shrink();
        final t = Theme.of(context).textTheme;
        final muto = Theme.of(context).colorScheme.onSurfaceVariant;
        final c = condizioni;
        return Column(
          key: const Key('meteo-viaggio'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text('Meteo lungo la strada', style: t.titleSmall),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                child: Row(
                  children: [
                    for (final (i, tappa) in m.tappe.indexed)
                      Expanded(
                        child: _Tappa(
                          tappa: tappa,
                          dove: i == 0
                              ? 'Partenza'
                              : i == m.tappe.length - 1
                              ? 'Arrivo'
                              : '${tappa.km.round()} km',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (c != null && (c.temperaturaC != 20 || c.ventoControMs.abs() >= 1))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Consumo calcolato con ${c.temperaturaC.round()} °C'
                  '${c.ventoControMs.abs() >= 1 ? ' e vento ${c.ventoControMs > 0 ? 'contro' : 'a favore'} '
                            '${(c.ventoControMs.abs() * 3.6).round()} km/h' : ''}'
                  '${c.climaW >= 300 ? ', col clima acceso' : ''}.',
                  style: t.bodySmall?.copyWith(color: muto),
                ),
              ),
            Text(MeteoMetNorway.citazione, style: t.bodySmall?.copyWith(color: muto)),
          ],
        );
      },
    );
  }
}

class _Tappa extends StatelessWidget {
  const _Tappa({required this.tappa, required this.dove});

  final MeteoTappa tappa;
  final String dove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = tappa.previsione;
    final ora = tappa.quando.toLocal();
    return Column(
      children: [
        Text(dove, style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('${ora.hour.toString().padLeft(2, '0')}:${ora.minute.toString().padLeft(2, '0')}', style: t.labelSmall),
        const SizedBox(height: 4),
        Text(p.cielo.emoji, style: const TextStyle(fontSize: 24)),
        Text('${p.temperaturaC.round()}°', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        if (p.pioggiaMm >= 0.3) Text('${p.pioggiaMm.toStringAsFixed(1)} mm', style: t.labelSmall),
      ],
    );
  }
}
