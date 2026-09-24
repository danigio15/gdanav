import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/segnaposto.dart';
import '../stato/gestore_auto.dart';
import '../stato/gestore_posizione.dart';
import '../tema.dart';

String schedaBreve(ProfiloVeicolo v) {
  final prese = v.connettori.contains(TipoConnettore.ccs2) ? 'CCS' : 'CHAdeMO';
  return '${_n(v.capacitaUtileKwh)} kWh · fino a ${v.piccoDcKw.round()} kW · $prese';
}

String _n(double x) => x == x.roundToDouble() ? '${x.round()}' : x.toStringAsFixed(1).replaceAll('.', ',');

/// La scelta dell'auto: da lei dipendono consumi, tempi di ricarica e prese.
class LaTuaAuto extends StatefulWidget {
  const LaTuaAuto({super.key, required this.auto, required this.posizione});

  final GestoreAuto auto;
  final GestorePosizione posizione;

  @override
  State<LaTuaAuto> createState() => _LaTuaAutoState();
}

class _LaTuaAutoState extends State<LaTuaAuto> {
  var _filtro = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scelta = widget.auto.veicolo;
    final f = _filtro.toLowerCase();
    final elenco = catalogoVeicoli.where((v) => f.isEmpty || v.nome.toLowerCase().contains(f)).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));
    final marche = <String, List<ProfiloVeicolo>>{};
    for (final v in elenco) {
      marche.putIfAbsent(v.marca, () => []).add(v);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('La tua auto')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Icon(Icons.electric_car, color: Theme.of(context).colorScheme.onPrimary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(scelta.nome, style: t.titleMedium),
                          Text(schedaBreve(scelta), style: t.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Come ti vedi sulla mappa', style: t.titleSmall),
          ),
          SizedBox(
            height: 112,
            child: ListenableBuilder(
              listenable: widget.posizione,
              builder: (context, _) => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final s in Segnaposto.values)
                    _Scelta(
                      segnaposto: s,
                      scelto: widget.posizione.segnaposto == s,
                      onTap: () => widget.posizione.scegli(s),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cerca marca o modello'),
              onChanged: (s) => setState(() => _filtro = s),
            ),
          ),
          for (final MapEntry(key: marca, value: auto) in marche.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(marca.toUpperCase(), style: t.labelMedium?.copyWith(letterSpacing: 1.1)),
            ),
            for (final v in auto)
              ListTile(
                title: Text(v.modello),
                subtitle: Text(schedaBreve(v)),
                trailing: v.id == scelta.id
                    ? Icon(Icons.check_circle, color: ColoriGdanav.di(context).libera)
                    : const Icon(Icons.chevron_right),
                selected: v.id == scelta.id,
                onTap: () async {
                  await widget.auto.scegliVeicolo(v);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'Valori indicativi dalle schede tecniche. I dati veri della tua auto (Home Assistant, OBD) '
              'correggono le stime col tempo.',
              style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Scelta extends StatelessWidget {
  const _Scelta({required this.segnaposto, required this.scelto, required this.onTap});

  final Segnaposto segnaposto;
  final bool scelto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Semantics(
        selected: scelto,
        button: true,
        label: segnaposto.etichetta,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: 84,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scelto ? s.primaryContainer : s.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scelto ? s.primary : Colors.transparent, width: 2),
            ),
            child: Column(
              children: [
                Expanded(child: Image.asset(segnaposto.asset, fit: BoxFit.contain)),
                const SizedBox(height: 4),
                Text(
                  segnaposto.etichetta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
