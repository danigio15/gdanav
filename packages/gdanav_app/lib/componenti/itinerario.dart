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

/// Le strade fra cui scegliere, una sotto l'altra, ognuna col suo nome come
/// in ABRP — più rapida, risparmia energia, tempo simile, più lenta — la
/// durata col traffico, da dove passa, la batteria all'arrivo e quanto
/// consuma. Quella scelta è evidenziata.
class ScelteStrada extends StatelessWidget {
  const ScelteStrada({
    super.key,
    required this.scelte,
    required this.scelta,
    required this.onScegli,
    this.consumo,
    this.unita = 'kWh',
    this.arrivo,
    this.capacitaKwh,
    this.minimoPercento = 5,
  });

  final List<PercorsoCalcolato> scelte;
  final int scelta;
  final ValueChanged<int> onScegli;

  /// Quanto consuma ogni strada (kWh, o litri con la termica); senza, niente
  /// consumi e nessuna «risparmia energia».
  final double Function(PercorsoCalcolato p)? consumo;
  final String unita;

  /// La batteria all'arrivo con la strada scelta (il piano), e la capacità:
  /// per le altre si sposta di quello che consumano in meno o in più.
  /// `null` con le soste, dove si risparmia ricarica e non batteria.
  final double? arrivo;
  final double? capacitaKwh;

  /// Da quanto in su una strada «risparmia energia».
  final double minimoPercento;

  @override
  Widget build(BuildContext context) {
    final f = consumo;
    final consumi = [for (final s in scelte) f?.call(s)];
    final etichette = etichetteStrade(scelte, (p) => f?.call(p) ?? 0, minimoPercento: minimoPercento);
    final rapida = etichette.indexOf(EtichettaStrada.piuRapida);
    return Column(
      children: [
        for (final (i, s) in scelte.indexed) ...[
          if (i > 0) const SizedBox(height: 8),
          _carta(context, i, s, etichette[i], consumi[i], rapida < 0 ? null : consumi[rapida], consumi[scelta]),
        ],
      ],
    );
  }

  Widget _carta(
    BuildContext context,
    int i,
    PercorsoCalcolato s,
    EtichettaStrada etichetta,
    double? consumoQui,
    double? consumoRapida,
    double? consumoScelta,
  ) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final c = ColoriGdanav.di(context);
    final muto = tema.colorScheme.onSurfaceVariant;
    final verde = tema.brightness == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    final attiva = i == scelta;
    final risparmia = etichetta == EtichettaStrada.risparmia;
    final via = s.stradaDistintiva([
      for (final (j, a) in scelte.indexed)
        if (j != i) a,
    ]);
    // La batteria all'arrivo: quella del piano per la scelta, spostata per le
    // altre di quello che consumano in meno o in più.
    final a = arrivo, cap = capacitaKwh;
    final conArrivo = a == null || cap == null || cap <= 0 || consumoQui == null || consumoScelta == null
        ? null
        : (a + (consumoScelta - consumoQui) / cap * 100).clamp(0.0, 100.0);
    final (nome, colore) = switch (etichetta) {
      EtichettaStrada.piuRapida => ('PIÙ RAPIDA', tema.colorScheme.primary),
      EtichettaStrada.risparmia => (unita == 'kWh' ? 'RISPARMIA ENERGIA' : 'RISPARMIA CARBURANTE', verde),
      EtichettaStrada.tempoSimile => ('TEMPO SIMILE', muto),
      EtichettaStrada.piuLenta => ('PIÙ LENTA', muto),
    };
    String numero(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    final traffico = !s.trafficoVero
        ? null
        : s.ritardoTraffico.inMinutes >= 1
        ? '+${durataBreve(s.ritardoTraffico)} traffico'
        : 'scorrevole';
    return Material(
      color: attiva ? tema.colorScheme.primaryContainer.withValues(alpha: 0.55) : tema.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: attiva ? tema.colorScheme.primary : tema.colorScheme.outlineVariant,
          width: attiva ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('strada-$i'),
        onTap: () => onScegli(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 14, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (risparmia) ...[Icon(Icons.eco_rounded, size: 14, color: verde), const SizedBox(width: 4)],
                        Flexible(
                          child: Text(
                            nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelSmall?.copyWith(color: colore, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(durataBreve(s.durata), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 1),
                    Text(
                      [
                        if (via.isNotEmpty) via,
                        '${(s.lunghezzaM / 1000).round()} km',
                        if (conArrivo != null) 'arrivi con il ${conArrivo.round()}%',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: muto),
                    ),
                    if (s.conPedaggi || traffico != null)
                      Text(
                        [if (s.conPedaggi) 'pedaggi', ?traffico].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelSmall?.copyWith(
                          color: !s.trafficoVero || s.ritardoTraffico.inMinutes < 1
                              ? muto
                              : s.ritardoTraffico.inMinutes >= 10
                              ? c.guasta
                              : c.piena,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              if (consumoQui != null)
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${numero(consumoQui)} $unita',
                        style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: risparmia ? verde : null),
                      ),
                      if (risparmia && consumoRapida != null)
                        Text(
                          '−${numero(consumoRapida - consumoQui)} $unita',
                          style: t.labelSmall?.copyWith(color: muto, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
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
