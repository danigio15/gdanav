import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/anello_batteria.dart';
import '../componenti/grafico_batteria.dart';
import '../componenti/stato_colonnina.dart';
import '../mappa/dati_viaggio.dart';
import '../stato/gestore_viaggio.dart';
import '../tema.dart';
import 'dettaglio_colonnina.dart';

String durata(Duration d) {
  final ore = d.inHours, minuti = d.inMinutes % 60;
  if (ore == 0) return '$minuti min';
  return '$ore h ${minuti.toString().padLeft(2, '0')}';
}

String orario(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Il riquadro in basso: sta calcolando, il viaggio con le sue soste, o
/// cosa non va.
class SchedaViaggio extends StatelessWidget {
  const SchedaViaggio({super.key, required this.gestore, required this.onAvvia, this.soglia = 15});

  final GestoreViaggio gestore;
  final VoidCallback onAvvia;
  final double soglia;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: gestore,
      builder: (context, _) => switch (gestore.stato) {
        NessunViaggio() => const SizedBox.shrink(),
        Calcolo(:final destinazione, :final fase) => _Piccola(
          titolo: destinazione.nome,
          onChiudi: gestore.annulla,
          children: [
            Text(switch (fase) {
              FaseViaggio.percorso => 'Calcolo il percorso…',
              FaseViaggio.colonnine => 'Cerco le colonnine lungo la strada…',
              FaseViaggio.soste => 'Scelgo le soste…',
            }, key: const Key('fase-calcolo')),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: null, minHeight: 6),
            ),
            const SizedBox(height: 6),
            Text(
              'Passo ${fase.index + 1} di ${FaseViaggio.values.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        ErroreViaggio(:final messaggio, :final destinazione) => _Piccola(
          titolo: destinazione?.nome ?? 'Viaggio',
          onChiudi: gestore.annulla,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: ColoriGdanav.di(context).piena),
                const SizedBox(width: 12),
                Expanded(child: Text(messaggio)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (destinazione != null)
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => gestore.pianifica(destinazione),
                      child: const Text('Riprova'),
                    ),
                  ),
              ],
            ),
          ],
        ),
        final ViaggioPronto pronto => _Pronta(pronto: pronto, gestore: gestore, soglia: soglia, onAvvia: onAvvia),
      },
    );
  }
}

class _Piccola extends StatelessWidget {
  const _Piccola({required this.titolo, required this.onChiudi, required this.children});

  final String titolo;
  final VoidCallback onChiudi;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 8,
            shadowColor: Colors.black38,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 10, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(titolo, style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(onPressed: onChiudi, icon: const Icon(Icons.close), tooltip: 'Chiudi'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
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

class _Pronta extends StatelessWidget {
  const _Pronta({required this.pronto, required this.gestore, required this.soglia, required this.onAvvia});

  final ViaggioPronto pronto;
  final GestoreViaggio gestore;
  final double soglia;
  final VoidCallback onAvvia;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final muto = tema.colorScheme.onSurfaceVariant;
    final v = pronto.viaggio;
    final piano = v.piano;
    final km = v.percorso.lunghezzaM / 1000;
    final soste = piano?.soste ?? const <Sosta>[];
    final idSoste = {for (final s in soste) s.colonnina.id};
    final altre = v.colonnine.where((c) => !idSoste.contains(c.id)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.46,
      minChildSize: 0.2,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.2, 0.46, 0.92],
      builder: (context, scorrimento) => Material(
        color: tema.colorScheme.surface,
        elevation: 12,
        shadowColor: Colors.black45,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ListView(
          controller: scorrimento,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tema.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pronto.destinazione.nome, style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (pronto.destinazione.descrizione.isNotEmpty)
                        Text(pronto.destinazione.descrizione, style: t.bodyMedium?.copyWith(color: muto), maxLines: 1),
                    ],
                  ),
                ),
                IconButton.filledTonal(onPressed: gestore.annulla, icon: const Icon(Icons.close), tooltip: 'Chiudi'),
              ],
            ),
            const SizedBox(height: 14),
            if (piano == null) ...[
              Text('${km.round()} km', style: t.headlineSmall),
              const SizedBox(height: 6),
              const Text(
                'Con questa batteria non ci si arriva, e lungo la strada non ci sono colonnine adatte abbastanza vicine. '
                'Prova ad abbassare la potenza minima nelle preferenze di ricarica.',
              ),
            ] else ...[
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Arrivo ',
                      style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w400),
                    ),
                    TextSpan(text: orario(pronto.arrivoAlle!), style: t.headlineSmall),
                  ],
                ),
              ),
              Text('${durata(piano.durata)} · ${km.round()} km', style: t.titleMedium?.copyWith(color: muto)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onAvvia,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Avvia'),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _Dato(
                      icona: AnelloBatteria(batteria: piano.batteriaArrivo, dimensione: 30, spessore: 4),
                      valore: '${piano.batteriaArrivo.round()}%',
                      etichetta: "all'arrivo",
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Dato(
                      icona: Icon(Icons.ev_station, color: ColoriGdanav.di(context).libera),
                      valore: soste.isEmpty ? 'Nessuna' : durata(piano.ricarica),
                      etichetta: switch (soste.length) {
                        0 => 'sosta',
                        1 => '1 sosta',
                        final n => '$n soste',
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Dato(
                      icona: Icon(Icons.bolt, color: tema.colorScheme.primary),
                      valore: '${piano.energiaKwh.toStringAsFixed(piano.energiaKwh < 10 ? 1 : 0)} kWh',
                      etichetta: 'consumo',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Batteria lungo il viaggio', style: t.titleSmall),
              const SizedBox(height: 8),
              GraficoBatteria(piano: piano, soglia: soglia),
              const SizedBox(height: 20),
              Text(soste.isEmpty ? 'Soste' : 'Le soste', style: t.titleSmall),
              const SizedBox(height: 8),
              if (soste.isEmpty)
                _Riga(
                  icona: Icon(Icons.check_circle, color: ColoriGdanav.di(context).libera),
                  testo: 'Ci arrivi senza fermarti.',
                )
              else
                for (final (i, s) in soste.indexed)
                  _SchedaSosta(numero: i + 1, sosta: s, onTap: () => mostraColonnina(context, gestore, s.colonnina.id)),
            ],
            if (altre.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Colonnine lungo la strada', style: t.titleSmall),
              Text('Toccane una per fermarti lì.', style: t.bodySmall?.copyWith(color: muto)),
              const SizedBox(height: 4),
              for (final c in altre.take(12))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: coloreStato(context, statoDi(c.disponibilita)),
                      shape: BoxShape.circle,
                    ),
                  ),
                  minLeadingWidth: 12,
                  title: Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${(c.distanzaM / 1000).round()} km · ${c.potenzaKw.round()} kW · ${testoDisponibilita(c.disponibilita)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => mostraColonnina(context, gestore, c.id),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              'Colonnine: © Open Charge Map contributors, PUN · Mappa: © OpenFreeMap © OpenStreetMap contributors',
              style: t.bodySmall?.copyWith(color: muto),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({required this.icona, required this.valore, required this.etichetta});

  final Widget icona;
  final String valore;
  final String etichetta;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 30,
              child: Align(alignment: Alignment.centerLeft, child: icona),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valore, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text(etichetta, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Riga extends StatelessWidget {
  const _Riga({required this.icona, required this.testo});
  final Widget icona;
  final String testo;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          icona,
          const SizedBox(width: 12),
          Expanded(child: Text(testo)),
        ],
      ),
    ),
  );
}

class _SchedaSosta extends StatelessWidget {
  const _SchedaSosta({required this.numero, required this.sosta, required this.onTap});

  final int numero;
  final Sosta sosta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = sosta.colonnina;
    final colore = coloreStato(context, statoDi(c.disponibilita));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colore,
                  child: Text(
                    '$numero',
                    style: t.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.nome, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        'Al km ${(c.distanzaM / 1000).round()} · ricarichi dal ${sosta.batteriaArrivo.round()}% '
                        'al ${sosta.batteriaPartenza.round()}% in ${durata(sosta.ricarica)}',
                        style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          BadgePotenza(c.potenzaKw),
                          BadgeDisponibilita(c.disponibilita),
                          if (c.obbligata)
                            Chip(
                              label: const Text('Scelta da te'),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelStyle: t.labelMedium,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
