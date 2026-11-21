import 'package:gdanav_core/gdanav_core.dart';

/* Il percorso per l'assistenza.
 *
 * «Linea a zig zag e inversione a U alla rotonda», con le foto: la rotonda si
 * ritrova sulla mappa, ma la linea che TomTom ha mandato no — e i difetti
 * della fascia nascono proprio da quella. «Copia il percorso per
 * l'assistenza», nel menu, la mette negli appunti: la si incolla a chi
 * assiste, e il caso si rifà uguale. Resta sul telefono finche' chi lo usa non
 * la incolla da qualche parte: nessun server la riceve da qui. */

/// Il testo da incollare: la linea in polyline a sei decimali e i pezzi
/// rifatti sulle strade vere (`suStrada`), in metri.
String percorsoPerLAssistenza(PercorsoCalcolato p) {
  final su = [for (final (a, b, r) in p.suStrada) '${a.round()}-${b.round()}-${r.round()}'].join(',');
  return ['GdANav percorso 1', codificaPolyline(p.punti, precisione: 6), if (su.isNotEmpty) 'suStrada $su'].join('\n');
}
