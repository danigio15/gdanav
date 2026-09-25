import 'package:flutter/material.dart';

import '../tema.dart';

/// I riquadri che galleggiano sulla mappa: sfondo quasi opaco e un'ombra
/// morbida e larga, non il bordo netto dell'elevazione.
class Vetro extends StatelessWidget {
  const Vetro({super.key, required this.child, this.raggio = 20, this.onTap, this.forma});

  final Widget child;
  final double raggio;
  final VoidCallback? onTap;

  /// Per i bottoni tondi.
  final BoxShape? forma;

  @override
  Widget build(BuildContext context) {
    final tondo = forma == BoxShape.circle;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColoriGdanav.di(context).vetro,
        shape: forma ?? BoxShape.rectangle,
        borderRadius: tondo ? null : BorderRadius.circular(raggio),
        boxShadow: const [
          BoxShadow(color: Color(0x24000000), blurRadius: 18, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: tondo
              ? const CircleBorder()
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(raggio)),
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}
