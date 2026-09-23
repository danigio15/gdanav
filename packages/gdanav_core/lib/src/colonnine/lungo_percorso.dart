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
}) {
  final out = <ColonninaSulPercorso>[];
  for (final c in colonnine) {
    final potenza = c.potenzaPer(compatibili);
    if (potenza < potenzaMinimaKw) continue;
    final p = percorso.proietta(c.posizione);
    if (p.lontanoM > distanzaMassimaM) continue;
    out.add(ColonninaSulPercorso(
      id: c.id,
      nome: c.nome,
      distanzaM: p.lungoM,
      potenzaKw: potenza,
      // In linea d'aria è troppo ottimista: le strade girano.
      deviazioneM: p.lontanoM * fattoreDeviazione,
    ));
  }
  out.sort((a, b) => a.distanzaM.compareTo(b.distanzaM));
  return out;
}
