import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// L'icona di una manovra di Valhalla (il suo campo `type`).
IconData iconaManovra(int tipo) => switch (tipo) {
  4 || 5 || 6 => Icons.sports_score,
  9 => Icons.turn_slight_right,
  23 => Icons.fork_right,
  10 || 2 => Icons.turn_right,
  11 => Icons.turn_sharp_right,
  12 => Icons.u_turn_right,
  13 => Icons.u_turn_left,
  14 => Icons.turn_sharp_left,
  15 || 3 => Icons.turn_left,
  16 => Icons.turn_slight_left,
  24 => Icons.fork_left,
  18 || 20 => Icons.ramp_right,
  19 || 21 => Icons.ramp_left,
  25 || 37 || 38 => Icons.merge,
  26 || 27 => Icons.roundabout_right,
  28 || 29 => Icons.directions_boat,
  _ => Icons.straight,
};

/// La freccia dipinta su una corsia.
IconData iconaCorsia(DirezioneCorsia d) => switch (d) {
  DirezioneCorsia.inversioneSinistra => Icons.u_turn_left,
  DirezioneCorsia.sinistraStretta => Icons.turn_sharp_left,
  DirezioneCorsia.sinistra => Icons.turn_left,
  DirezioneCorsia.leggeraSinistra => Icons.turn_slight_left,
  DirezioneCorsia.dritto => Icons.straight,
  DirezioneCorsia.leggeraDestra => Icons.turn_slight_right,
  DirezioneCorsia.destra => Icons.turn_right,
  DirezioneCorsia.destraStretta => Icons.turn_sharp_right,
  DirezioneCorsia.inversioneDestra => Icons.u_turn_right,
};

/// Le corsie prima dello svincolo, come sul cartello: quelle giuste bianche
/// su blu, le altre spente. Ogni corsia mostra le sue frecce; quella da
/// seguire è accesa.
class CorsieSvincolo extends StatelessWidget {
  const CorsieSvincolo({super.key, required this.corsie, this.lato = 34});

  final List<Corsia> corsie;
  final double lato;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('corsie'),
      decoration: BoxDecoration(color: const Color(0xFF1B2130), borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, c) in corsie.indexed) ...[
              if (i > 0)
                Container(
                  width: 2,
                  height: lato * 0.9,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: Colors.white24,
                ),
              Container(
                width: lato + 12,
                height: lato + 12,
                decoration: BoxDecoration(
                  color: c.giusta ? const Color(0xFF2F6FE4) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    for (final d in c.direzioni.isEmpty ? const [DirezioneCorsia.dritto] : c.direzioni)
                      Icon(
                        iconaCorsia(d),
                        size: lato,
                        color: !c.giusta
                            ? Colors.white30
                            : (c.consigliata == null || c.consigliata == d)
                            ? Colors.white
                            : Colors.white38,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Il cartello dello svincolo: numero d'uscita e direzione. Verde se porta in
/// autostrada, blu altrimenti, come in Italia.
class CartelloSvincolo extends StatelessWidget {
  const CartelloSvincolo({super.key, required this.manovra});

  final Manovra manovra;

  @override
  Widget build(BuildContext context) {
    final autostrada = RegExp(r'\bA\s?\d').hasMatch(manovra.verso) || RegExp(r'\bA\s?\d').hasMatch(manovra.strada);
    final t = Theme.of(context).textTheme;
    return Container(
      key: const Key('cartello'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: autostrada ? const Color(0xFF0B7A3E) : const Color(0xFF1558B0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (manovra.uscita.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
              child: Text(
                'Uscita ${manovra.uscita}',
                style: t.labelMedium?.copyWith(fontWeight: FontWeight.w800, color: Colors.black),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              manovra.verso,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
