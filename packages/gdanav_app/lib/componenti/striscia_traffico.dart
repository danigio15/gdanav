import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../tema.dart';

/// La striscia del traffico di lato, in guida.
///
/// «Mostra lateralmente la striscia del traffico con i minuti di ritardo e
/// man mano a che punto è il traffico.» Una barra sottile: in basso l'auto,
/// in cima la meta (o, in un viaggio lungo, i prossimi 100 km, con «…»). Le
/// code sono tratti colorati al loro posto — arancio, rosso la coda ferma,
/// scuro la strada chiusa — e accanto a ognuna quanti minuti fa ancora
/// perdere e fra quanto comincia. Andando avanti la parte fatta sparisce e
/// le code scendono verso l'auto ([strisciaTraffico]).
///
/// Prende l'altezza che le danno: in guida è lo spazio libero fra gli avvisi
/// in alto e il tachimetro in basso.
class StrisciaTrafficoLaterale extends StatelessWidget {
  const StrisciaTrafficoLaterale({super.key, required this.striscia});

  final StrisciaTraffico striscia;

  /// Sotto quest'altezza la striscia non dice niente: non si mette.
  static const altezzaMinima = 140.0;

  static const _larghezzaBarra = 10.0;
  static const _altezzaEtichetta = 38.0;

  /// Il colore di una coda: arancio, rosso la coda ferma, scuro la chiusa.
  static Color coloreDi(BuildContext context, int livello) {
    final c = ColoriGdanav.di(context);
    return switch (livello) {
      >= 4 => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF9CA3AF) : const Color(0xFF374151),
      3 => c.guasta,
      _ => c.piena,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = ColoriGdanav.di(context);
    final scuro = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, vincoli) {
        final alto = vincoli.maxHeight;
        if (!alto.isFinite || alto < altezzaMinima) return const SizedBox.shrink();
        // La barra fra la cima (meta o «…») e l'auto in basso.
        const sopra = 26.0, sotto = 26.0;
        final barra = alto - sopra - sotto;
        double y(double frazione) => sopra + barra * (1 - frazione);

        // Le etichette, dal basso: ognuna a metà della sua coda, spinta su se
        // tocca quella sotto; quelle che non ci stanno più si lasciano.
        final etichette = <(CodaInStriscia, double)>[];
        var libero = alto;
        for (final coda in striscia.code) {
          if (coda.minuti < 1) continue;
          final centro = y((coda.da + coda.a) / 2);
          final cima = math.min(centro - _altezzaEtichetta / 2, libero - _altezzaEtichetta - 4);
          if (cima < 0) break;
          etichette.add((coda, cima));
          libero = cima;
        }

        return SizedBox(
          key: const Key('striscia-traffico'),
          width: 96,
          height: alto,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // La strada che resta.
              Positioned(
                right: 6,
                top: sopra,
                height: barra,
                width: _larghezzaBarra,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.percorso.withValues(alpha: scuro ? 0.85 : 0.9),
                    borderRadius: BorderRadius.circular(_larghezzaBarra / 2),
                    border: Border.all(color: c.vetro, width: 1.5),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                ),
              ),
              // Le code, al loro posto.
              for (final coda in striscia.code)
                Positioned(
                  right: 6,
                  top: y(coda.a),
                  height: math.max(5.0, (coda.a - coda.da) * barra),
                  width: _larghezzaBarra,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: coloreDi(context, coda.livello),
                      borderRadius: BorderRadius.circular(_larghezzaBarra / 2),
                      border: Border.all(color: c.vetro, width: 1.5),
                    ),
                  ),
                ),
              // In cima: la meta, o «…» se la strada va oltre.
              Positioned(
                right: 0,
                top: 0,
                width: _larghezzaBarra + 12,
                height: sopra - 2,
                child: Center(
                  child: striscia.tagliata
                      ? Text(
                          '…',
                          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: c.percorso),
                        )
                      : Icon(Icons.sports_score, size: 20, color: c.arrivo),
                ),
              ),
              // In basso: l'auto.
              Positioned(
                right: 0,
                bottom: 0,
                width: _larghezzaBarra + 12,
                height: sotto,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.percorso,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.vetro, width: 2),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.navigation, size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ),
              for (final (coda, cima) in etichette)
                Positioned(
                  right: _larghezzaBarra + 12,
                  top: cima,
                  height: _altezzaEtichetta,
                  child: _Etichetta(coda: coda, colore: coloreDi(context, coda.livello)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Etichetta extends StatelessWidget {
  const _Etichetta({required this.coda, required this.colore});

  final CodaInStriscia coda;
  final Color colore;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = ColoriGdanav.di(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.vetro,
        borderRadius: BorderRadius.circular(10),
        border: Border(right: BorderSide(color: colore, width: 3)),
        boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(7, 3, 6, 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '+${coda.minuti} min',
              maxLines: 1,
              style: t.labelLarge?.copyWith(color: colore, fontWeight: FontWeight.w900, height: 1.1),
            ),
            Text(
              coda.dentro ? 'ci sei' : distanzaBreve(coda.distanzaM),
              maxLines: 1,
              style: t.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
