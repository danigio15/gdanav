import 'package:flutter/material.dart';

import 'controllo_mappa.dart';

/// Il tasto della vista: dice quella di adesso, e al tocco apre la scelta fra
/// 2D, 3D e immersiva. Prima era un interruttore 2D/3D; con tre viste un
/// interruttore che gira in tondo obbliga a passare da quella che non si
/// vuole, e non dice dove si arriva.
class SceltaVista extends StatelessWidget {
  const SceltaVista({super.key, required this.controllo, this.stile, this.forma});

  final ControlloMappa controllo;
  final TextStyle? stile;
  final ShapeBorder? forma;

  static String _spiega(VistaMappa v) => switch (v) {
    VistaMappa.piatta => 'Dall\'alto, il nord in su',
    VistaMappa.inclinata => 'Inclinata, con gli edifici',
    VistaMappa.immersiva => 'Da vicino, con le corsie sulla strada',
  };

  @override
  Widget build(BuildContext context) {
    final v = controllo.vista;
    return PopupMenuButton<VistaMappa>(
      tooltip: 'Vista: ${v.nome}',
      initialValue: v,
      onSelected: controllo.scegliVista,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      itemBuilder: (context) => [
        for (final scelta in VistaMappa.values)
          PopupMenuItem(
            key: Key('vista-${scelta.name}'),
            value: scelta,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 34,
                child: scelta == VistaMappa.immersiva
                    ? const Icon(Icons.view_in_ar_rounded)
                    : Text(scelta.sigla, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              title: Text(scelta.nome, style: TextStyle(fontWeight: scelta == v ? FontWeight.w800 : FontWeight.w600)),
              subtitle: Text(_spiega(scelta)),
              trailing: scelta == v ? const Icon(Icons.check_rounded) : null,
            ),
          ),
      ],
      child: SizedBox.square(
        dimension: 56,
        child: Center(
          child: v == VistaMappa.immersiva
              ? const Icon(Icons.view_in_ar_rounded, size: 26)
              : Text(v.sigla, style: stile ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}
