import 'package:gdanav_core/gdanav_core.dart';

/// Dove si chiedono i distributori (in Italia coi prezzi del Ministero):
/// nelle prove se ne mette uno finto.
FonteDistributori clienteDistributori = DistributoriConPrezzi();

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

/// «1,799 €»
String euro(double e) => '${e.toStringAsFixed(3).replaceAll('.', ',')} €';

String distanza(Distributore d, Punto qui) {
  final km = distanzaM(qui, d.posizione) / 1000;
  return km < 1 ? '${(km * 1000 / 10).round() * 10} m' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Quando il gestore ha comunicato il prezzo: «oggi 07:12», «ieri», «20/9».
String? quandoAggiornato(DateTime? t, {DateTime? adesso}) {
  if (t == null) return null;
  final l = t.toLocal(), ora = adesso ?? DateTime.now();
  final giorni = DateTime(ora.year, ora.month, ora.day).difference(DateTime(l.year, l.month, l.day)).inDays;
  if (giorni <= 0) return 'oggi ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  if (giorni == 1) return 'ieri';
  return '${l.day}/${l.month}';
}

/// «1,2 km · Benzina 1,799 € self · Eni» coi prezzi; senza, i carburanti:
/// «1,2 km · Eni · Benzina, Diesel, GPL · 24 ore».
String descriviDistributore(Distributore d, Punto qui, {Carburante carburante = Carburante.benzina}) {
  final p = d.prezzoDi(carburante);
  return [
    distanza(d, qui),
    if (p != null) '${carburante.nome} ${euro(p.euro)}${p.self ? ' self' : ''}',
    if (d.marca case final m? when m.isNotEmpty && m != d.nome) m,
    if (p == null && d.carburanti.isNotEmpty)
      (d.carburanti.toList()..sort((a, b) => a.index - b.index)).map((c) => c.nome).join(', '),
    if (d.sempreAperto) '24 ore',
  ].join(' · ');
}

Luogo luogoDistributore(Distributore d, Punto qui, {Carburante carburante = Carburante.benzina}) => Luogo(
  nome: d.nome,
  posizione: d.posizione,
  descrizione: descriviDistributore(d, qui, carburante: carburante),
);
