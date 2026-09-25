import 'package:gdanav_core/gdanav_core.dart';

/// Dove si chiedono i distributori: nelle prove se ne mette uno finto.
ClienteDistributori clienteDistributori = ClienteDistributori();

({Punto qui, DateTime quando, List<Distributore> elenco})? _ultimi;

/// I distributori intorno a [qui], dal più vicino. Per qualche minuto, e se
/// non ci si è spostati molto, si riusano quelli già trovati.
Future<List<Distributore>> distributoriVicini(Punto qui, {DateTime Function() ora = DateTime.now}) async {
  final u = _ultimi;
  if (u != null && ora().difference(u.quando) < const Duration(minutes: 10) && distanzaM(u.qui, qui) < 800) {
    return [...u.elenco]..sort((a, b) => distanzaM(qui, a.posizione).compareTo(distanzaM(qui, b.posizione)));
  }
  final elenco = await clienteDistributori.vicino(qui);
  _ultimi = (qui: qui, quando: ora(), elenco: elenco);
  return elenco;
}

/// Si dimenticano quelli trovati (nelle prove).
void dimenticaDistributori() => _ultimi = null;

/// «1,2 km · Eni · Benzina, Diesel, GPL · 24 ore»
String descriviDistributore(Distributore d, Punto qui) {
  final km = distanzaM(qui, d.posizione) / 1000;
  return [
    km < 1 ? '${(km * 1000 / 10).round() * 10} m' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km',
    if (d.marca case final m? when m.isNotEmpty && m != d.nome) m,
    if (d.carburanti.isNotEmpty)
      (d.carburanti.toList()..sort((a, b) => a.index - b.index)).map((c) => c.nome).join(', '),
    if (d.sempreAperto) '24 ore',
  ].join(' · ');
}

Luogo luogoDistributore(Distributore d, Punto qui) =>
    Luogo(nome: d.nome, posizione: d.posizione, descrizione: descriviDistributore(d, qui));
