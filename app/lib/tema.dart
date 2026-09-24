import 'package:flutter/material.dart';

/// I colori che hanno un significato, uguali in chiaro e in scuro dove
/// possibile: chi guida li riconosce a colpo d'occhio.
@immutable
class ColoriGdanav extends ThemeExtension<ColoriGdanav> {
  const ColoriGdanav({
    required this.percorso,
    required this.libera,
    required this.piena,
    required this.guasta,
    required this.ignota,
    required this.arrivo,
    required this.vetro,
  });

  final Color percorso;
  final Color libera;
  final Color piena;
  final Color guasta;
  final Color ignota;
  final Color arrivo;

  /// Lo sfondo dei riquadri che galleggiano sulla mappa.
  final Color vetro;

  static const chiari = ColoriGdanav(
    percorso: Color(0xFF2563EB),
    libera: Color(0xFF16A34A),
    piena: Color(0xFFD97706),
    guasta: Color(0xFFDC2626),
    ignota: Color(0xFF64748B),
    arrivo: Color(0xFFDC2626),
    vetro: Color(0xF2FFFFFF),
  );

  static const scuri = ColoriGdanav(
    percorso: Color(0xFF60A5FA),
    libera: Color(0xFF4ADE80),
    piena: Color(0xFFFBBF24),
    guasta: Color(0xFFF87171),
    ignota: Color(0xFF94A3B8),
    arrivo: Color(0xFFF87171),
    vetro: Color(0xF2141B26),
  );

  static ColoriGdanav di(BuildContext context) => Theme.of(context).extension<ColoriGdanav>()!;

  @override
  ColoriGdanav copyWith() => this;

  @override
  ColoriGdanav lerp(ColoriGdanav? other, double t) => t < 0.5 ? this : (other ?? this);
}

const _seme = Color(0xFF2563EB);

ThemeData temaGdanav(Brightness luce) {
  final scuro = luce == Brightness.dark;
  final schema = ColorScheme.fromSeed(
    seedColor: _seme,
    brightness: luce,
    primary: scuro ? const Color(0xFF7FB2FF) : const Color(0xFF1D4ED8),
    surface: scuro ? const Color(0xFF111821) : const Color(0xFFFFFFFF),
  );
  final base = ThemeData(colorScheme: schema, useMaterial3: true, brightness: luce);
  final testo = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: schema.surface,
    extensions: [scuro ? ColoriGdanav.scuri : ColoriGdanav.chiari],
    textTheme: testo.copyWith(
      headlineSmall: testo.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: testo.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: testo.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: testo.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scuro ? const Color(0xFF18212C) : const Color(0xFFF4F6F9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: schema.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: testo.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scuro ? const Color(0xFF18212C) : const Color(0xFFF4F6F9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 20)),
    sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.onDrag),
  );
}
