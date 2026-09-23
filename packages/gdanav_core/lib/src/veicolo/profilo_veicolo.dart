import '../colonnine/colonnina.dart';

/// Un punto della curva di ricarica: con la batteria a [batteria]% l'auto
/// accetta al massimo [potenzaKw].
class PuntoCurva {
  const PuntoCurva(this.batteria, this.potenzaKw);
  final double batteria;
  final double potenzaKw;
}

/// Tutto quello che serve sapere di un modello di auto per stimarne i
/// consumi e i tempi di ricarica.
class ProfiloVeicolo {
  const ProfiloVeicolo({
    required this.nome,
    required this.massaKg,
    required this.cdA,
    required this.crr,
    required this.capacitaUtileKwh,
    required this.curvaRicarica,
    this.connettori = const {TipoConnettore.ccs2, TipoConnettore.tipo2},
    this.rendimentoTrazione = 0.90,
    this.rendimentoRecupero = 0.65,
    this.consumoFissoW = 300,
  });

  final String nome;

  /// Massa in ordine di marcia più il conducente.
  final double massaKg;

  /// Coefficiente aerodinamico per area frontale, in m².
  final double cdA;

  /// Coefficiente di resistenza al rotolamento.
  final double crr;

  final double capacitaUtileKwh;

  /// Punti ordinati per batteria crescente.
  final List<PuntoCurva> curvaRicarica;

  /// Le prese che l'auto accetta.
  final Set<TipoConnettore> connettori;

  /// Dalla batteria alla ruota.
  final double rendimentoTrazione;

  /// Dalla ruota alla batteria, in frenata e in discesa.
  final double rendimentoRecupero;

  /// Elettronica, luci, pompe: quello che si consuma anche da fermi, senza
  /// clima.
  final double consumoFissoW;

  /// La potenza massima accettata alla [batteria] data, interpolando la
  /// curva.
  double potenzaRicaricaKw(double batteria) {
    final c = curvaRicarica;
    if (batteria <= c.first.batteria) return c.first.potenzaKw;
    if (batteria >= c.last.batteria) return c.last.potenzaKw;
    for (var i = 1; i < c.length; i++) {
      if (batteria <= c[i].batteria) {
        final a = c[i - 1], b = c[i];
        final t = (batteria - a.batteria) / (b.batteria - a.batteria);
        return a.potenzaKw + t * (b.potenzaKw - a.potenzaKw);
      }
    }
    return c.last.potenzaKw;
  }

  /// Un'auto media di segmento C, per le prove e per chi non ha ancora
  /// scelto il suo modello.
  static const esempio = ProfiloVeicolo(
    nome: 'Esempio segmento C (60 kWh)',
    massaKg: 1900,
    cdA: 0.62,
    crr: 0.009,
    capacitaUtileKwh: 60,
    curvaRicarica: [
      PuntoCurva(0, 110),
      PuntoCurva(10, 130),
      PuntoCurva(50, 120),
      PuntoCurva(70, 80),
      PuntoCurva(80, 55),
      PuntoCurva(90, 30),
      PuntoCurva(100, 8),
    ],
  );
}
