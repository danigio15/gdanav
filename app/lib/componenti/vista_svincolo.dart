import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'icona_manovra.dart';
import 'scena_svincolo.dart';

/// Le manovre che meritano la vista dello svincolo: uscite, rampe e bivi.
const tipiSvincolo = {18, 19, 20, 21, 23, 24};

bool haSvincolo(Manovra m) => tipiSvincolo.contains(m.tipo);

/// Costruisce la scena dentro il popup: quella vera, o altro nelle prove.
typedef CostruisciMappaSvincolo = Widget Function(Viaggio v, Manovra m);

/// Il popup sul telefono, in alto al posto del riquadro della manovra: la
/// freccia, i metri che mancano e il cartello (uscita e direzione), sotto lo
/// svincolo in 3D (la strada vista da chi guida, corsie giuste in blu con le
/// frecce) con la barra che si accorcia e la X per chiuderlo. Sotto la
/// mappa continua come sempre.
class PopupSvincolo extends StatelessWidget {
  const PopupSvincolo({
    super.key,
    required this.viaggio,
    required this.manovra,
    required this.metri,
    required this.onChiudi,
    this.mappa,
  });

  final Viaggio viaggio;
  final Manovra manovra;
  final double metri;
  final VoidCallback onChiudi;
  final CostruisciMappaSvincolo? mappa;

  static const daMetri = 800.0;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const scuro = Color(0xFF2A3140);
    final strada = manovra.strada.isNotEmpty ? manovra.strada : manovra.istruzione;
    return Padding(
      key: const Key('popup-svincolo'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: ColoredBox(
            color: scuro,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // La manovra: freccia, metri, cartello o strada.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A4458),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(iconaManovra(manovra.tipo), color: Colors.white, size: 42),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              distanzaBreve(metri),
                              style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            if (manovra.verso.isNotEmpty || manovra.uscita.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: CartelloSvincolo(manovra: manovra),
                              )
                            else if (strada.isNotEmpty)
                              Text(
                                strada,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleSmall?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('chiudi-svincolo'),
                        iconSize: 22,
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF3A4458)),
                        onPressed: onChiudi,
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                // Lo svincolo in 3D, con la barra dei metri che si accorcia.
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      mappa?.call(viaggio, manovra) ?? CustomPaint(painter: ScenaSvincolo(manovra)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: (metri / daMetri).clamp(0.0, 1.0),
                          minHeight: 5,
                          color: Colors.white,
                          backgroundColor: const Color(0x55202633),
                        ),
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
