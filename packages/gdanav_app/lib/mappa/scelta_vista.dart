import 'package:flutter/material.dart';

import 'controllo_mappa.dart';

/// Il tasto della vista: dice quella di adesso, e al tocco apre la scelta fra
/// 2D, 3D, immersiva e 3D aumentato. Prima era un interruttore 2D/3D; con più
/// viste un interruttore che gira in tondo obbliga a passare da quella che
/// non si vuole, e non dice dove si arriva.
///
/// Il 3D aumentato, dove il telefono non ce la fa (o non c'è la WebView), si
/// vede lo stesso, spento, col perché; toccandolo si spiega, e si può
/// riprovare.
class SceltaVista extends StatelessWidget {
  const SceltaVista({super.key, required this.controllo, this.stile, this.forma});

  final ControlloMappa controllo;
  final TextStyle? stile;
  final ShapeBorder? forma;

  static String _spiega(VistaMappa v) => switch (v) {
    VistaMappa.piatta => 'Dall\'alto, il nord in su',
    VistaMappa.inclinata => 'Inclinata, con gli edifici',
    VistaMappa.immersiva => 'Da vicino, con le corsie sulla strada',
    VistaMappa.aumentata => 'In guida: viadotti, alberi ed edifici in 3D',
  };

  /// Perché il 3D aumentato non si può scegliere, sotto la voce.
  String get _perche =>
      controllo.aumentataPossibile ? spiegaAumentatoNonVa(controllo.aumentataNonVa) : 'Non c\'è su questo dispositivo';

  void _scegli(BuildContext context, VistaMappa v) {
    if (v == VistaMappa.aumentata && !controllo.aumentataDisponibile) {
      _nonDisponibile(context);
      return;
    }
    controllo.scegliVista(v);
  }

  /// Il 3D aumentato spento: perché, e «Riprova» (se qui si può provare).
  Future<void> _nonDisponibile(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('vista-aumentata-spiegazione'),
      icon: const IconaAumentata(dimensione: 30),
      title: const Text('3D aumentato non disponibile'),
      content: Text(
        controllo.aumentataPossibile
            ? '$_perche, così la mappa è tornata alla vista ${controllo.vistaPrima.inFrase}. '
                  'Puoi riprovare: se non va, torna da sola com\'era.'
            : '$_perche: serve un telefono Android o un iPhone.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Chiudi')),
        if (controllo.aumentataPossibile)
          FilledButton(
            key: const Key('vista-aumentata-riprova'),
            onPressed: () {
              Navigator.of(context).pop();
              controllo.riprovaAumentata();
            },
            child: const Text('Riprova'),
          ),
      ],
    ),
  );

  Widget _segno(VistaMappa v, TextStyle testo, double icona, {bool spenta = false}) => switch (v) {
    VistaMappa.immersiva => Icon(Icons.view_in_ar_rounded, size: icona),
    VistaMappa.aumentata => IconaAumentata(dimensione: icona, stile: testo, spenta: spenta),
    _ => Text(v.sigla, style: testo),
  };

  @override
  Widget build(BuildContext context) {
    final v = controllo.vista;
    final grigio = Theme.of(context).disabledColor;
    const testoVoce = TextStyle(fontSize: 17, fontWeight: FontWeight.w800);
    return PopupMenuButton<VistaMappa>(
      tooltip: 'Vista: ${v.nome}',
      initialValue: v,
      onSelected: (scelta) => _scegli(context, scelta),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      itemBuilder: (context) => [
        for (final scelta in VistaMappa.values)
          () {
            final spenta = scelta == VistaMappa.aumentata && !controllo.aumentataDisponibile;
            return PopupMenuItem(
              key: Key('vista-${scelta.name}'),
              value: scelta,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                iconColor: spenta ? grigio : null,
                textColor: spenta ? grigio : null,
                leading: SizedBox(
                  width: 34,
                  child: Center(
                    child: _segno(scelta, spenta ? testoVoce.copyWith(color: grigio) : testoVoce, 24, spenta: spenta),
                  ),
                ),
                title: Text(scelta.nome, style: TextStyle(fontWeight: scelta == v ? FontWeight.w800 : FontWeight.w600)),
                subtitle: Text(spenta ? _perche : _spiega(scelta)),
                trailing: scelta == v
                    ? const Icon(Icons.check_rounded)
                    : spenta
                    ? const Icon(Icons.info_outline_rounded)
                    : null,
              ),
            );
          }(),
      ],
      child: SizedBox.square(
        dimension: 56,
        child: Center(child: _segno(v, stile ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.w800), 26)),
      ),
    );
  }
}

/// Il 3D aumentato si è fermato: si torna alla vista di prima
/// ([ControlloMappa.lasciaAumentata]) e lo si dice, una volta, in fondo.
void lasciaAumentataConAvviso(BuildContext context, ControlloMappa controllo, String motivo, {required bool ricorda}) {
  if (controllo.vista != VistaMappa.aumentata) return;
  controllo.lasciaAumentata(motivo, ricorda: ricorda);
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const Key('aumentato-non-va'),
        content: Row(
          children: [
            const IconaAumentata(
              dimensione: 22,
              stile: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(avvisoAumentatoNonVa(controllo.vista, ricorda: ricorda))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
}

/// Il segno del 3D aumentato: «3D» con una scintilla in alto a destra.
class IconaAumentata extends StatelessWidget {
  const IconaAumentata({super.key, this.dimensione = 24, this.stile, this.spenta = false});

  final double dimensione;
  final TextStyle? stile;

  /// Grigia anche la scintilla (il 3D aumentato non si può scegliere).
  final bool spenta;

  @override
  Widget build(BuildContext context) {
    final testo = (stile ?? const TextStyle(fontWeight: FontWeight.w800)).copyWith(
      fontSize: dimensione * 0.7,
      height: 1,
    );
    return Semantics(
      label: '3D aumentato',
      excludeSemantics: true,
      child: SizedBox(
        width: dimensione * 1.3,
        height: dimensione,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Text('3D', style: testo),
            Positioned(
              right: -dimensione * 0.12,
              top: -dimensione * 0.12,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: dimensione * 0.5,
                color: spenta ? testo.color : const Color(0xFFF2B01E),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
