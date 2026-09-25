import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'icona_manovra.dart';
import 'scena_svincolo.dart';

/// Le manovre che meritano la vista dello svincolo: uscite, rampe e bivi.
const tipiSvincolo = {18, 19, 20, 21, 23, 24};

bool haSvincolo(Manovra m) => tipiSvincolo.contains(m.tipo);

/// Costruisce la scena dentro il popup: quella vera, o altro nelle prove.
typedef CostruisciMappaSvincolo = Widget Function(Viaggio v, Manovra m);

/// Il popup sul telefono: lo svincolo in 3D (la strada vista da chi guida,
/// corsie giuste in blu con le frecce), sopra il
/// cartello (uscita e direzione), in basso le corsie giuste e i metri che
/// mancano con la barra che si accorcia, e la X per chiuderlo.
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
    return Padding(
      key: const Key('popup-svincolo'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              mappa?.call(viaggio, manovra) ?? CustomPaint(painter: ScenaSvincolo(manovra)),
              // In alto il cartello e la X.
              Positioned(
                left: 10,
                top: 10,
                right: 56,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: manovra.verso.isNotEmpty || manovra.uscita.isNotEmpty
                      ? CartelloSvincolo(manovra: manovra)
                      : const SizedBox.shrink(),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filled(
                  key: const Key('chiudi-svincolo'),
                  iconSize: 20,
                  constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(backgroundColor: const Color(0xCC202633)),
                  onPressed: onChiudi,
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              // In basso i metri che mancano e le corsie.
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                      decoration: BoxDecoration(
                        color: const Color(0xE6202633),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            distanzaBreve(metri),
                            style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          SizedBox(
                            width: 64,
                            child: LinearProgressIndicator(
                              value: (metri / daMetri).clamp(0.0, 1.0),
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ],
                      ),
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
