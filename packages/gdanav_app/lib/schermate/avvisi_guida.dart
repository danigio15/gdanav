import 'package:flutter/material.dart';

import '../componenti/icone_segnalazioni.dart';
import '../stato/scelte_avvisi.dart';

/// Gli avvisi della guida, uno per uno: a voce, solo a schermo o spento.
///
/// Il tasto dell'audio in guida (Tutto, Avvisi, Muto) resta com'è e vale su
/// tutto; qui si sceglie quali avvisi si vogliono, e come.
class AvvisiGuidaSchermata extends StatelessWidget {
  const AvvisiGuidaSchermata({super.key, required this.scelte});

  final ScelteAvvisi scelte;

  static const _strada = [
    Avviso.autovelox,
    Avviso.tutor,
    Avviso.polizia,
    Avviso.incidente,
    Avviso.pericolo,
    Avviso.lavori,
    Avviso.chiusura,
    Avviso.traffico,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Avvisi in guida')),
      body: ListenableBuilder(
        listenable: scelte,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const _Nota(),
            _Gruppo(
              titolo: 'Sulla strada',
              voci: [for (final a in _strada) _RigaAvviso(avviso: a, scelte: scelte)],
            ),
            _Gruppo(
              titolo: 'Zone e limiti',
              voci: [
                _RigaAvviso(avviso: Avviso.ztl, scelte: scelte),
                _RigaAvviso(avviso: Avviso.limite, scelte: scelte),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Text(
                'Vale sul telefono, su CarPlay e su Android Auto. Il tasto dell\'audio in '
                'guida resta: con «Muto» tace tutto.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    Widget riga(IconData icona, String titolo, String testo) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icona, size: 18, color: tema.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$titolo  ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: testo),
                ],
              ),
              style: tema.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: tema.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          riga(Icons.record_voice_over_rounded, 'Voce', 'lo dice e lo mostra nel riquadro in guida.'),
          riga(Icons.notifications_active_rounded, 'Beep', 'un beep al posto delle parole, e il riquadro.'),
          riga(Icons.visibility_rounded, 'Schermo', 'solo il riquadro, senza voce.'),
          riga(
            Icons.notifications_off_rounded,
            'Spento',
            'niente voce, niente riquadro, e sparisce anche dalla mappa.',
          ),
        ],
      ),
    );
  }
}

class _Gruppo extends StatelessWidget {
  const _Gruppo({required this.titolo, required this.voci});

  final String titolo;
  final List<Widget> voci;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
          child: Text(
            titolo.toUpperCase(),
            style: tema.textTheme.labelMedium?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: tema.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, v) in voci.indexed) ...[
                if (i > 0)
                  Divider(height: 1, indent: 64, color: tema.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                v,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RigaAvviso extends StatelessWidget {
  const _RigaAvviso({required this.avviso, required this.scelte});

  final Avviso avviso;
  final ScelteAvvisi scelte;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final scelta = scelte.di(avviso);
    final spento = scelta == ComeAvvisare.spento;
    final opzioni = avviso.soloVoce
        ? const [ComeAvvisare.voce, ComeAvvisare.beep, ComeAvvisare.schermo]
        : ComeAvvisare.values;
    return Padding(
      key: Key('avviso-${avviso.name}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Opacity(opacity: spento ? 0.4 : 1, child: _Icona(avviso)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(avviso.nome, style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      avviso.soloVoce && scelta == ComeAvvisare.schermo ? 'Solo il tachimetro rosso' : avviso.sotto,
                      style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.zero,
            child: SegmentedButton<ComeAvvisare>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (final c in opzioni)
                  ButtonSegment(
                    value: c,
                    label: Text(c.etichetta, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              selected: {scelta},
              onSelectionChanged: (s) => scelte.scegli(avviso, s.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _Icona extends StatelessWidget {
  const _Icona(this.avviso);

  final Avviso avviso;

  @override
  Widget build(BuildContext context) {
    if (avviso == Avviso.limite) {
      // Il cartello del limite.
      return Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFDC2626), width: 4.5),
        ),
        child: const Text(
          '50',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 13, height: 1),
        ),
      );
    }
    final (colore, icona) = switch (avviso.segnalazione) {
      final t? => aspetto(t),
      null when avviso == Avviso.tutor => (const Color(0xFF7C3AED), Icons.av_timer_rounded),
      null => (const Color(0xFFDC2626), Icons.do_not_disturb_on_rounded),
    };
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: colore, borderRadius: BorderRadius.circular(11)),
      child: Icon(icona, color: Colors.white, size: 22),
    );
  }
}
