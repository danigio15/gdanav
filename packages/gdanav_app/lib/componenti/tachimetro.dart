import 'package:flutter/material.dart';

/// Il tachimetro di Waze in basso a sinistra: la velocità in un cerchio
/// bianco, rosso se si supera il limite; accanto il cartello del limite.
class Tachimetro extends StatelessWidget {
  const Tachimetro({super.key, required this.velocitaKmh, this.limiteKmh});

  final double velocitaKmh;
  final int? limiteKmh;

  /// Qualche km/h di tolleranza, come fa l'autovelox.
  bool get oltre => limiteKmh != null && velocitaKmh > limiteKmh! + 3;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scuro = Theme.of(context).brightness == Brightness.dark;
    final fondo = oltre ? const Color(0xFFE5484D) : (scuro ? const Color(0xFF232A38) : Colors.white);
    final testo = oltre ? Colors.white : (scuro ? Colors.white : const Color(0xFF1F2328));
    return SizedBox(
      width: limiteKmh == null ? 84 : 128,
      height: 84,
      child: Stack(
        children: [
          Container(
            key: const Key('tachimetro'),
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: fondo,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${velocitaKmh.round()}',
                  style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: testo, height: 1),
                ),
                Text('km/h', style: t.labelSmall?.copyWith(color: testo.withValues(alpha: 0.75))),
              ],
            ),
          ),
          if (limiteKmh case final l?) Positioned(right: 0, top: 0, child: CartelloLimite(limiteKmh: l)),
        ],
      ),
    );
  }
}

/// Il cartello italiano: cerchio bianco col bordo rosso e il numero nero.
class CartelloLimite extends StatelessWidget {
  const CartelloLimite({super.key, required this.limiteKmh, this.lato = 52});

  final int limiteKmh;
  final double lato;

  @override
  Widget build(BuildContext context) => Container(
    width: lato,
    height: lato,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFD62C2C), width: lato * 0.12),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 3))],
    ),
    alignment: Alignment.center,
    child: Text(
      '$limiteKmh',
      style: TextStyle(
        fontSize: lato * (limiteKmh >= 100 ? 0.32 : 0.4),
        fontWeight: FontWeight.w900,
        color: const Color(0xFF111111),
        height: 1,
      ),
    ),
  );
}
