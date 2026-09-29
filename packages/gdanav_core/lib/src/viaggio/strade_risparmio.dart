/// Le strade che fanno risparmiare energia, come in ABRP: prima di partire
/// ogni alternativa ha il suo nome (più rapida, risparmia energia, tempo
/// simile), e durante la guida si propone la strada che consuma meno — o
/// quella che il traffico ha reso più rapida — se vale il disturbo.
library;

import '../geo/geo.dart';
import '../percorso/valhalla.dart';

/// Quando una strada vale la proposta.
class SoglieRisparmio {
  const SoglieRisparmio({
    this.proponi = true,
    this.minimoPercento = 5,
    this.massimoInPiu = const Duration(minutes: 10),
    this.ancheRapide = true,
    this.rapidaDi = const Duration(minutes: 3),
  });

  /// Proporle durante il viaggio.
  final bool proponi;

  /// Il risparmio minimo, in percento del consumo della strada che si fa.
  final double minimoPercento;

  /// Quanto si accetta di arrivare più tardi per risparmiare.
  final Duration massimoInPiu;

  /// Proporre anche le strade che il traffico ha reso più rapide.
  final bool ancheRapide;

  /// Più rapida vuol dire almeno tanto prima.
  final Duration rapidaDi;
}

/// Perché si propone una strada.
enum MotivoProposta { risparmio, rapida }

/// Una strada proposta durante la guida.
class PropostaStrada {
  const PropostaStrada({
    required this.percorso,
    required this.motivo,
    required this.consumo,
    required this.consumoAdesso,
    required this.differenza,
    required this.firma,
    this.via = '',
    this.senzaAutostrada = false,
  });

  /// Da dove si è alla meta, per la strada proposta.
  final PercorsoCalcolato percorso;
  final MotivoProposta motivo;

  /// Quanto consuma lei e quanto la strada che si fa (kWh o litri).
  final double consumo;
  final double consumoAdesso;

  /// Quanto si risparmia (positivo) o si spende in più (negativo).
  double get risparmio => consumoAdesso - consumo;

  /// Quanto dopo si arriva (negativa: prima).
  final Duration differenza;

  /// Dove si stacca dalla strada di adesso: per non riproporla se rifiutata.
  final Set<String> firma;

  /// La strada che la distingue («SS 18»), e se lascia l'autostrada.
  final String via;
  final bool senzaAutostrada;
}

/// Quanto consuma un percorso: da TomTom se l'ha detto, se no con [stima].
double consumoStrada(PercorsoCalcolato p, double Function(PercorsoCalcolato p) stima) => p.consumoTomTom ?? stima(p);

/// Il pezzo di [p] che resta da fare, da [daM] metri fino alla meta: il primo
/// punto è dove si è sul percorso. È quello che si rimanda a TomTom per
/// confrontarlo con le altre strade.
List<Punto> restoDelPercorso(PercorsoCalcolato p, double daM) {
  if (p.punti.length < 2) return p.punti;
  final l = Linea(p.punti);
  final m = daM.clamp(0.0, l.lunghezzaM);
  var i = 1;
  while (i < p.punti.length - 1 && l.cumulate[i] <= m) {
    i++;
  }
  final a = p.punti[i - 1], b = p.punti[i];
  final tratto = l.cumulate[i] - l.cumulate[i - 1];
  final t = tratto <= 0 ? 0.0 : ((m - l.cumulate[i - 1]) / tratto).clamp(0.0, 1.0);
  final qui = Punto(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t);
  return [qui, ...p.punti.sublist(t >= 1 ? i + 1 : i)];
}

/// La proposta, se ce n'è una che vale. [adesso] è la strada che si fa, da
/// dove si è alla meta; [eco] le strade che consumano meno, [rapide] quelle
/// che arrivano prima. Si sceglie la più risparmiosa fra quelle che
/// risparmiano almeno la soglia senza costare più dei minuti scelti; se non
/// ce n'è, con [SoglieRisparmio.ancheRapide] la più rapida che fa arrivare
/// prima di almeno [SoglieRisparmio.rapidaDi]. Mai una strada già
/// [rifiutate].
PropostaStrada? scegliProposta({
  required PercorsoCalcolato adesso,
  List<PercorsoCalcolato> eco = const [],
  List<PercorsoCalcolato> rapide = const [],
  required SoglieRisparmio soglie,
  required double Function(PercorsoCalcolato p) consumo,
  List<Set<String>> rifiutate = const [],
}) {
  if (!soglie.proponi || adesso.punti.length < 2) return null;
  final base = consumo(adesso);
  PropostaStrada? proposta(PercorsoCalcolato p, MotivoProposta motivo) {
    final firma = firmaDeviazione(p, adesso);
    if (firma.isEmpty || rifiutate.any((r) => somiglia(r, firma))) return null;
    return PropostaStrada(
      percorso: p,
      motivo: motivo,
      consumo: consumo(p),
      consumoAdesso: base,
      differenza: p.durata - adesso.durata,
      firma: firma,
      via: p.stradaDistintiva([adesso]),
      senzaAutostrada: adesso.conAutostrade && !p.conAutostrade,
    );
  }

  PropostaStrada? migliore;
  if (base > 0) {
    for (final p in eco) {
      final c = consumo(p);
      if (base - c < base * soglie.minimoPercento / 100) continue;
      if (p.durata - adesso.durata > soglie.massimoInPiu) continue;
      final pr = proposta(p, MotivoProposta.risparmio);
      if (pr != null && (migliore == null || pr.consumo < migliore.consumo)) migliore = pr;
    }
  }
  if (migliore != null || !soglie.ancheRapide) return migliore;
  for (final p in rapide) {
    if (adesso.durata - p.durata < soglie.rapidaDi) continue;
    final pr = proposta(p, MotivoProposta.rapida);
    if (pr != null && (migliore == null || pr.percorso.durata < migliore.percorso.durata)) migliore = pr;
  }
  return migliore;
}

/// Le celle (di circa un chilometro) dove [p] passa lontano da [da]: il pezzo
/// in cui è un'altra strada. Vuota se è la stessa.
Set<String> firmaDeviazione(PercorsoCalcolato p, PercorsoCalcolato da, {double lontanoM = 150}) {
  if (p.punti.length < 2 || da.punti.length < 2) return const {};
  final linea = Linea(da.punti);
  final celle = <String>{};
  // Anche i tratti lunghi, un punto ogni duecento metri.
  for (var i = 1; i < p.punti.length; i++) {
    final a = p.punti[i - 1], b = p.punti[i];
    final passi = (distanzaM(a, b) / 200).ceil().clamp(1, 1000);
    for (var k = 0; k < passi; k++) {
      final q = Punto(a.lat + (b.lat - a.lat) * k / passi, a.lon + (b.lon - a.lon) * k / passi);
      if (linea.proietta(q).lontanoM > lontanoM) celle.add('${(q.lat * 100).round()},${(q.lon * 100).round()}');
    }
  }
  return celle;
}

/// Se due firme sono la stessa strada: metà delle celle in comune, contando
/// sulla più corta (andando avanti la deviazione si accorcia).
bool somiglia(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return false;
  final comuni = a.intersection(b).length;
  return comuni >= (a.length < b.length ? a.length : b.length) * 0.5;
}

/// Il nome di un'alternativa, come in ABRP.
enum EtichettaStrada { piuRapida, risparmia, tempoSimile, piuLenta }

/// Il nome di ogni strada fra le [scelte]: la più rapida; quella che consuma
/// di meno, se risparmia almeno [minimoPercento] sulla più rapida; le altre
/// «tempo simile» fino a [simile] in più, «più lenta» oltre.
List<EtichettaStrada> etichetteStrade(
  List<PercorsoCalcolato> scelte,
  double Function(PercorsoCalcolato p) consumo, {
  double minimoPercento = 5,
  Duration simile = const Duration(minutes: 5),
}) {
  if (scelte.isEmpty) return const [];
  var rapida = 0;
  for (var i = 1; i < scelte.length; i++) {
    if (scelte[i].durata < scelte[rapida].durata) rapida = i;
  }
  final consumi = [for (final s in scelte) consumo(s)];
  int? risparmia;
  for (var i = 0; i < scelte.length; i++) {
    if (i == rapida) continue;
    if (consumi[rapida] - consumi[i] < consumi[rapida] * minimoPercento / 100) continue;
    if (risparmia == null || consumi[i] < consumi[risparmia]) risparmia = i;
  }
  return [
    for (var i = 0; i < scelte.length; i++)
      if (i == rapida)
        EtichettaStrada.piuRapida
      else if (i == risparmia)
        EtichettaStrada.risparmia
      else if (scelte[i].durata - scelte[rapida].durata <= simile)
        EtichettaStrada.tempoSimile
      else
        EtichettaStrada.piuLenta,
  ];
}

/// [scelte] con in più [eco], se è davvero un'altra strada: se per quasi
/// tutta la sua lunghezza sta su una di quelle che ci sono già, non serve.
List<PercorsoCalcolato> conStradaEco(List<PercorsoCalcolato> scelte, PercorsoCalcolato eco, {double lontanoM = 60}) {
  if (eco.punti.length < 2) return scelte;
  for (final s in scelte) {
    if (s.punti.length < 2) continue;
    final linea = Linea(s.punti);
    final passo = (eco.punti.length / 80).ceil().clamp(1, 1 << 20);
    var fuori = 0, tutti = 0;
    for (var i = 0; i < eco.punti.length; i += passo) {
      tutti++;
      if (linea.proietta(eco.punti[i]).lontanoM > lontanoM) fuori++;
    }
    if (fuori <= tutti * 0.1) return scelte;
  }
  return [...scelte, eco];
}
