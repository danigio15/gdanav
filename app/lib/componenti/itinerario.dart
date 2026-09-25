import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/dati_viaggio.dart' show durataBreve;
import '../tema.dart';

/// Il riepilogo del traffico sul percorso: «Traffico scorrevole» in verde,
/// o «+12 min di traffico · 2 code» in arancio; niente se il traffico di
/// adesso non si conosce.
class RigaTraffico extends StatelessWidget {
  const RigaTraffico({super.key, required this.percorso});

  final PercorsoCalcolato percorso;

  @override
  Widget build(BuildContext context) {
    if (!percorso.trafficoVero) return const SizedBox.shrink();
    final c = ColoriGdanav.di(context);
    final ritardo = percorso.ritardoTraffico;
    final code = percorso.code.length;
    final lento = ritardo.inMinutes >= 1;
    final colore = !lento ? c.libera : (ritardo.inMinutes >= 10 ? c.guasta : c.piena);
    final chiuse = percorso.code.where((x) => x.livello >= 4).length;
    final testo = !lento
        ? (code == 0 ? 'Traffico scorrevole' : 'Traffico scorrevole · qualche rallentamento')
        : [
            '+${durataBreve(ritardo)} di traffico',
            if (code == 1) '1 coda' else if (code > 1) '$code code',
            if (chiuse > 0) chiuse == 1 ? '1 strada chiusa' : '$chiuse strade chiuse',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.traffic_rounded, size: 18, color: colore),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              testo,
              key: const Key('traffico'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colore, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Le strade fra cui scegliere, affiancate: durata (col traffico), km, da
/// dove passa, pedaggi, traffico. Quella scelta è evidenziata.
class ScelteStrada extends StatelessWidget {
  const ScelteStrada({super.key, required this.scelte, required this.scelta, required this.onScegli});

  final List<PercorsoCalcolato> scelte;
  final int scelta;
  final ValueChanged<int> onScegli;

  @override
  Widget build(BuildContext context) {
    final migliore = scelte.map((s) => s.durata).reduce((a, b) => a < b ? a : b);
    // Una riga che scorre (non una ListView: dentro la scheda che scorre in
    // verticale).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, s) in scelte.indexed) ...[
            if (i > 0) const SizedBox(width: 10),
            _carta(context, i, s, migliore),
          ],
        ],
      ),
    );
  }

  Widget _carta(BuildContext context, int i, PercorsoCalcolato s, Duration migliore) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final c = ColoriGdanav.di(context);
    final muto = tema.colorScheme.onSurfaceVariant;
    final attiva = i == scelta;
    final piu = Duration(minutes: ((s.durata.inSeconds - migliore.inSeconds) / 60).round());
    final via = s.stradaDistintiva([
      for (final (j, a) in scelte.indexed)
        if (j != i) a,
    ]);
    return Material(
      color: attiva ? tema.colorScheme.primaryContainer : tema.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: attiva ? tema.colorScheme.primary : Colors.transparent, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('strada-$i'),
        onTap: () => onScegli(i),
        child: Container(
          width: 168,
          height: 118,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(durataBreve(s.durata), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (attiva) Icon(Icons.check_circle, size: 20, color: tema.colorScheme.primary),
                ],
              ),
              Text(
                piu.inMinutes == 0 ? 'La più veloce' : '+${durataBreve(piu)}',
                style: t.labelMedium?.copyWith(color: piu.inMinutes == 0 ? c.libera : muto),
              ),
              const Spacer(),
              Text(
                ['${(s.lunghezzaM / 1000).round()} km', if (via.isNotEmpty) 'via $via'].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (s.conPedaggi) ...[
                    Icon(Icons.toll_rounded, size: 15, color: muto),
                    const SizedBox(width: 3),
                    Text('Pedaggi', style: t.labelSmall?.copyWith(color: muto)),
                    const SizedBox(width: 8),
                  ],
                  if (s.trafficoVero)
                    Flexible(
                      child: Text(
                        s.ritardoTraffico.inMinutes >= 1 ? '+${durataBreve(s.ritardoTraffico)} traffico' : 'Scorrevole',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: s.ritardoTraffico.inMinutes >= 10
                              ? c.guasta
                              : s.ritardoTraffico.inMinutes >= 1
                              ? c.piena
                              : c.libera,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Da dove a dove, con le tappe in mezzo: si aggiungono, si tolgono, si
/// riordinano trascinandole. Le soste di ricarica si ricalcolano sul viaggio
/// intero.
class Itinerario extends StatelessWidget {
  const Itinerario({
    super.key,
    required this.destinazione,
    required this.tappe,
    this.onAggiungi,
    this.onTogli,
    this.onSposta,
  });

  final Luogo destinazione;
  final List<Luogo> tappe;
  final VoidCallback? onAggiungi;
  final ValueChanged<int>? onTogli;
  final void Function(int da, int a)? onSposta;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final muto = tema.colorScheme.onSurfaceVariant;
    final blu = ColoriGdanav.di(context).percorso;

    Widget riga({
      required Widget segno,
      required String testo,
      String? sotto,
      Widget? fine,
      Key? key,
      bool linea = true,
    }) => IntrinsicHeight(
      key: key,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                const SizedBox(height: 10),
                segno,
                if (linea)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: tema.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(testo, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyLarge),
                  if (sotto != null && sotto.isNotEmpty)
                    Text(
                      sotto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: muto),
                    ),
                ],
              ),
            ),
          ),
          ?fine,
        ],
      ),
    );

    Widget numero(int n) => Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tema.colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: blu, width: 2.5),
      ),
      child: Text(
        '$n',
        style: t.labelSmall?.copyWith(color: blu, fontWeight: FontWeight.w800),
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: tema.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Column(
          children: [
            riga(
              segno: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: blu,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                ),
              ),
              testo: 'La tua posizione',
            ),
            if (tappe.isNotEmpty)
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (da, a) => onSposta?.call(da, a),
                children: [
                  for (final (i, l) in tappe.indexed)
                    riga(
                      key: ValueKey('tappa-$i-${l.nome}'),
                      segno: numero(i + 1),
                      testo: l.nome,
                      sotto: l.descrizione,
                      fine: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: Key('togli-tappa-$i'),
                            tooltip: 'Togli la tappa',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: onTogli == null ? null : () => onTogli!(i),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.drag_handle_rounded, color: muto),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            riga(
              segno: Icon(Icons.location_on_rounded, color: ColoriGdanav.di(context).arrivo, size: 22),
              testo: destinazione.nome,
              sotto: destinazione.descrizione,
              linea: false,
            ),
            if (onAggiungi != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('aggiungi-tappa'),
                  onPressed: onAggiungi,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Aggiungi una tappa'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
