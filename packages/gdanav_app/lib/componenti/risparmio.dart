import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_risparmio.dart';
import '../tema.dart';

/// Il verde delle strade a risparmio: la scheda, la strada sulla mappa, il
/// fumetto.
const verdeRisparmio = Color(0xFF16A34A);

/// In guida, sopra la barra in basso: «C'è una strada che risparmia
/// energia», quanto si risparmia e quanto ci si mette in più, la batteria
/// all'arrivo e da dove passa; «Resto qui» e «Prendila». La barra sotto si
/// svuota: se non si tocca niente la proposta si chiude da sola.
class PropostaRisparmio extends StatelessWidget {
  const PropostaRisparmio({
    super.key,
    required this.proposta,
    required this.unita,
    required this.elettrica,
    required this.rimasto,
    required this.onPrendi,
    required this.onResta,
    this.arrivo,
    this.arrivoCon,
    this.arrivoAlle,
  });

  final PropostaStrada proposta;

  /// «kWh», «l» o «kg».
  final String unita;
  final bool elettrica;

  /// Quanto resta prima che si chiuda da sola, da 1 a 0.
  final double rimasto;
  final VoidCallback onPrendi;
  final VoidCallback onResta;

  /// La batteria all'arrivo adesso, e prendendo la strada proposta.
  final double? arrivo;
  final double? arrivoCon;

  /// L'ora d'arrivo adesso: per quella più rapida, «arrivi alle…».
  final DateTime? arrivoAlle;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final muto = tema.colorScheme.onSurfaceVariant;
    final scuro = tema.brightness == Brightness.dark;
    final verde = scuro ? const Color(0xFF4ADE80) : verdeRisparmio;
    final p = proposta;
    final rapida = p.motivo == MotivoProposta.rapida;
    final grande = rapida ? minutiConSegno(p.differenza) : quantitaConSegno(-p.risparmio, unita);
    final piccolo = rapida
        ? (p.risparmio.abs() < 0.05 ? null : quantitaConSegno(-p.risparmio, unita))
        : minutiConSegno(p.differenza);
    String ora(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final dettaglio = [
      if (!rapida && arrivo != null && arrivoCon != null)
        'Arrivi con il ${arrivoCon!.round()}% invece del ${arrivo!.round()}%'
      else if (rapida && arrivoAlle != null)
        'Arrivi alle ${ora(arrivoAlle!.add(p.differenza))} invece che alle ${ora(arrivoAlle!)}',
      ?doveProposta(p),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Material(
        key: const Key('proposta-strada'),
        color: tema.colorScheme.surface,
        elevation: 6,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: verde.withValues(alpha: 0.45), width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(rapida ? Icons.bolt_rounded : Icons.eco_rounded, color: verde, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titoloProposta(p, elettrica: elettrica),
                      maxLines: 2,
                      style: t.titleSmall?.copyWith(color: verde, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Sul telefono stretto il secondo numero va a capo, non esce.
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Text(
                    grande,
                    key: const Key('proposta-quanto'),
                    style: t.headlineMedium?.copyWith(color: verde, fontWeight: FontWeight.w900),
                  ),
                  if (piccolo != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        piccolo,
                        key: const Key('proposta-anche'),
                        style: t.titleLarge?.copyWith(color: muto, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              if (dettaglio.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  dettaglio,
                  key: const Key('proposta-dettaglio'),
                  style: t.bodyMedium?.copyWith(color: muto, height: 1.35),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      key: const Key('resta-strada'),
                      onPressed: onResta,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      child: const Text('Resto qui'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('prendi-strada'),
                      onPressed: onPrendi,
                      style: FilledButton.styleFrom(
                        backgroundColor: verdeRisparmio,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: const Text('Prendila', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  key: const Key('proposta-tempo'),
                  value: rimasto.clamp(0.0, 1.0),
                  minHeight: 5,
                  color: verde.withValues(alpha: 0.7),
                  backgroundColor: ColoriGdanav.di(context).ignota.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
