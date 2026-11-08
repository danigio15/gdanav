import 'package:flutter/material.dart';

import '../tema.dart';

/// Come si colora un pezzo della riga del viaggio.
enum TonoPezzo { normale, rosso, verde, ambra }

/// Un pezzo della riga: il testo, il colore, e la chiave per le prove.
/// [prima] è la parte che non si colora («arrivo » prima della percentuale).
typedef PezzoViaggio = ({String chiave, String prima, String testo, TonoPezzo tono});

/// Lo spazio che non va a capo: dentro un pezzo («arrivo 46%», «☀ 12°») non
/// si va a capo, solo fra un pezzo e l'altro.
const _nbsp = '\u00A0';

/// La pila davanti alla batteria, come la scrive l'auto.
const _pila = '🔋$_nbsp';

/// La riga del viaggio, la stessa della scheda dell'arrivo di Android Auto
/// (`GuidaAuto.testoDelViaggio`): «🔋 51% · 200 km · arrivo 46% · ☀ 12°».
///
/// «Dati auto e km all'arrivo sul telefono devono essere uguali ad Android
/// Auto»: le regole stanno qui, una volta sola. La batteria «~51%» se è una
/// stima fra due letture dell'auto, rossa sotto il 20%; i km e l'arrivo solo
/// con la batteria (l'auto termica non ne ha); l'arrivo verde, rosso sotto il
/// 10%; il meteo all'arrivo (o qui); il pedaggio in ambra, se c'è.
List<PezzoViaggio> pezziDelViaggio({
  double? batteria,
  bool stimata = false,
  double? autonomiaKm,
  double? arrivo,
  String? meteoEmoji,
  double? temperaturaC,
  String? pedaggio,
}) {
  final circa = stimata ? '~' : '';
  return [
    if (batteria != null) ...[
      (
        chiave: 'batteria-ora',
        prima: '',
        testo: '$_pila$circa${batteria.round()}%',
        tono: batteria < 20 ? TonoPezzo.rosso : TonoPezzo.normale,
      ),
      if (autonomiaKm != null)
        (chiave: 'autonomia', prima: '', testo: '$circa${autonomiaKm.round()}${_nbsp}km', tono: TonoPezzo.normale),
      if (arrivo != null)
        (
          chiave: 'batteria-arrivo',
          prima: 'arrivo$_nbsp',
          testo: '${arrivo.round()}%',
          tono: arrivo < 10 ? TonoPezzo.rosso : TonoPezzo.verde,
        ),
    ],
    if (temperaturaC != null)
      (
        chiave: 'meteo',
        prima: '',
        testo: '${meteoEmoji == null ? '' : '$meteoEmoji$_nbsp'}${temperaturaC.round()}°',
        tono: TonoPezzo.normale,
      ),
    if (pedaggio != null && pedaggio.isNotEmpty)
      (chiave: 'pedaggio-viaggio', prima: '', testo: pedaggio, tono: TonoPezzo.ambra),
  ];
}

/// La riga del viaggio sul telefono: i pezzi uno dopo l'altro, col «·» in
/// mezzo; se non ci stanno si va a capo fra un pezzo e l'altro.
class RigaDelViaggio extends StatelessWidget {
  const RigaDelViaggio({super.key, required this.pezzi, this.stile});

  final List<PezzoViaggio> pezzi;
  final TextStyle? stile;

  @override
  Widget build(BuildContext context) {
    final c = ColoriGdanav.di(context);
    final base = stile ?? Theme.of(context).textTheme.titleSmall;
    Color? colore(TonoPezzo t) => switch (t) {
      TonoPezzo.normale => null,
      TonoPezzo.rosso => c.guasta,
      TonoPezzo.verde => c.libera,
      TonoPezzo.ambra => c.piena,
    };
    return Wrap(
      key: const Key('riga-del-viaggio'),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, p) in pezzi.indexed)
          Text.rich(
            TextSpan(
              children: [
                if (i > 0) const TextSpan(text: ' · '),
                if (p.prima.isNotEmpty) TextSpan(text: p.prima),
                // Sul telefono la pila è l'icona dell'app, non l'emoji
                // (che l'auto disegna da sé): uguale su ogni telefono.
                if (p.testo.startsWith(_pila)) ...[
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(
                      Icons.battery_std_rounded,
                      size: (base?.fontSize ?? 16) * 1.15,
                      color: colore(p.tono) ?? base?.color,
                    ),
                  ),
                  TextSpan(
                    text: p.testo.substring(_pila.length),
                    style: TextStyle(color: colore(p.tono), fontWeight: FontWeight.w800),
                  ),
                ] else
                  TextSpan(
                    text: p.testo,
                    style: TextStyle(color: colore(p.tono), fontWeight: FontWeight.w800),
                  ),
              ],
            ),
            key: Key(p.chiave),
            style: base,
          ),
      ],
    );
  }
}
