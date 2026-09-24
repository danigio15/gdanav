import '../geo/geo.dart';
import '../motore/pianificatore_soste.dart';
import 'colonnina.dart';

/// Porta le colonnine sul percorso: dove si esce, quanto si devia, quanta
/// potenza dà a questa auto. Tiene solo quelle utili.
List<ColonninaSulPercorso> colonnineSulPercorso(
  Linea percorso,
  List<Colonnina> colonnine, {
  required Set<TipoConnettore> compatibili,
  double potenzaMinimaKw = 40,
  double distanzaMassimaM = 3000,
  double fattoreDeviazione = 1.4,
  Set<String> obbligate = const {},
}) {
  final out = <ColonninaSulPercorso>[];
  for (final c in colonnine) {
    final obbligata = obbligate.contains(c.id);
    final potenza = c.potenzaPer(compatibili);
    // Una sosta scelta dall'utente resta anche se lenta o lontana: l'ha
    // voluta lui. Senza nessuna presa adatta però non serve a niente.
    if (potenza <= 0 || (!obbligata && potenza < potenzaMinimaKw)) continue;
    final p = percorso.proietta(c.posizione);
    if (!obbligata && p.lontanoM > distanzaMassimaM) continue;
    out.add(ColonninaSulPercorso(
      id: c.id,
      nome: c.nome,
      distanzaM: p.lungoM,
      potenzaKw: potenza,
      // In linea d'aria è troppo ottimista: le strade girano.
      deviazioneM: p.lontanoM * fattoreDeviazione,
      disponibilita: c.disponibilitaPer(compatibili),
      obbligata: obbligata,
      dettaglio: c,
    ));
  }
  out.sort((a, b) => a.distanzaM.compareTo(b.distanzaM));
  return out;
}
