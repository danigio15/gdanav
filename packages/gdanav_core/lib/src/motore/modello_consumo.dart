import 'dart:math' as math;

import '../veicolo/profilo_veicolo.dart';
import '../veicolo/stato_auto.dart';
import 'consumo_imparato.dart';

/* ─── Il modello, in breve ──────────────────────────────────────────────────
 *
 * L'energia di un tratto, presa dalla batteria, è la somma di:
 *
 *  - **ruota**: aria (½·ρ·CdA·v², con ρ dalla temperatura e il vento
 *    contro), rotolamento (m·g·Crr) e quota (m·g·Δh), diviso il rendimento
 *    della trazione; in discesa la quota torna indietro col rendimento del
 *    recupero;
 *  - **partenze e frenate** ([fermatePerKm]): la strada vera non si fa a
 *    velocità costante. A ogni rallentamento l'energia cinetica ½·m·v² si
 *    spende per riprendere velocità e se ne recupera solo una parte, quindi
 *    ogni «fermata» costa ½·m·v²·(1/ηtrazione − ηrecupero). In città se ne
 *    fa una ogni centinaio di metri, in autostrada quasi mai. Senza questo
 *    termine un giro in città a 50 km/h usciva a 7-8 kWh/100 km, che nessuna
 *    elettrica fa, e il correttivo imparato lo compensava gonfiando anche
 *    le autostrade;
 *  - **consumi fissi** (elettronica, pompe) e **clima**, in watt per il tempo
 *    del tratto. Il clima solo se la temperatura si sa (dall'auto o dal
 *    meteo): senza, nessun riscaldamento inventato ([Condizioni.daMeteo]).
 *    Se l'auto dice quanto consuma il suo riscaldatore, conta anche quello
 *    ([Condizioni.conAuto]);
 *  - tutto per il **correttivo** dell'auto ([Condizioni.fattorePer]): quello
 *    imparato guidando ([ConsumoImparato]) o, prima, quello del «consumo di
 *    riferimento» scritto dall'utente (per esempio quello calibrato di ABRP,
 *    [fattoreDaRiferimento]).
 *
 * Le velocità sono quelle dei tratti di Valhalla o TomTom (limiti, tempi
 * col traffico), le quote quelle di Valhalla dove ci sono.
 */

const _g = 9.81;

/// Quante volte per chilometro si rallenta fino a fermarsi (o l'equivalente
/// in rallentamenti parziali) su una strada percorsa in media a [kmh]:
/// semafori, rotonde, precedenze, code.
///
/// Valori tipici da cicli di guida misurati (WLTP, Artemis): in città una
/// ogni 300-500 metri, su una statale una ogni qualche chilometro, in
/// autostrada quasi nessuna.
double fermatePerKm(double kmh) {
  const tabella = [(0.0, 3.0), (20.0, 3.0), (30.0, 2.0), (50.0, 1.0), (70.0, 0.4), (90.0, 0.15), (110.0, 0.05)];
  if (kmh >= tabella.last.$1) return tabella.last.$2;
  for (var i = 1; i < tabella.length; i++) {
    final (v1, f1) = tabella[i];
    if (kmh <= v1) {
      final (v0, f0) = tabella[i - 1];
      return f0 + (f1 - f0) * (kmh - v0) / (v1 - v0);
    }
  }
  return tabella.last.$2;
}

/// Un pezzo di strada a velocità e pendenza costanti, come arriva da
/// Valhalla dopo averlo spezzato per limite di velocità e quota.
class Tratto {
  const Tratto({required this.lunghezzaM, required this.velocitaKmh, this.dislivelloM = 0});

  final double lunghezzaM;
  final double velocitaKmh;

  /// Positivo in salita, negativo in discesa.
  final double dislivelloM;

  double get secondi => lunghezzaM / (velocitaKmh / 3.6);
}

/// Quello che il meteo e l'abitacolo aggiungono.
class Condizioni {
  const Condizioni({
    this.temperaturaC = 20,
    this.ventoControMs = 0,
    this.climaW = 0,
    this.fattoreConsumo = 1,
    this.fattoriStrada = const {},
    this.riscaldamentoBatteriaKwh = 0,
    this.temperaturaBatteriaC,
  });

  /// Il clima stimato dalla temperatura esterna: niente fra 18 e 26 gradi,
  /// poi riscaldamento o raffrescamento proporzionali, con un tetto.
  factory Condizioni.daMeteo({
    required double temperaturaC,
    double ventoControMs = 0,
    double fattoreConsumo = 1,
    Map<TipoStrada, double> fattoriStrada = const {},
  }) =>
      Condizioni(
        temperaturaC: temperaturaC,
        ventoControMs: ventoControMs,
        climaW: climaStimatoW(temperaturaC),
        fattoreConsumo: fattoreConsumo,
        fattoriStrada: fattoriStrada,
      );

  /// Il clima che serve a [temperaturaC] fuori, in W: vedi [Condizioni.daMeteo].
  static double climaStimatoW(double temperaturaC) =>
      math.min(3000.0, math.max(0.0, 18 - temperaturaC) * 150) +
      math.min(1500.0, math.max(0.0, temperaturaC - 26) * 100);

  /// Quanto dura, di solito, il riscaldamento della batteria fredda, e con
  /// che potenza quando l'auto non la dice: una resistenza o la pompa di
  /// calore da qualche kW per un quarto d'ora, venti minuti.
  static const durataRiscaldamentoBatteria = Duration(minutes: 20);
  static const potenzaRiscaldamentoBatteriaW = 3000.0;

  /// Queste condizioni col clima e la batteria come li dice l'auto adesso.
  ///
  /// - La **temperatura** dell'auto, se la dice, vale più di questa (che è
  ///   del meteo, della zona e di un'ora fa); il clima stimato si rifà da lei.
  /// - **Batteria in riscaldamento**: costa una volta sola, alla partenza
  ///   ([riscaldamentoBatteriaKwh]), la potenza del riscaldatore (o quella
  ///   tipica) per [durataRiscaldamentoBatteria]. Non per tutto il viaggio:
  ///   scaldata la batteria, si spegne. Intanto il riscaldatore scalda lei,
  ///   e il clima resta quello stimato.
  /// - **Clima acceso** con la potenza del riscaldatore misurata: metà la
  ///   misura e metà la stima. La misura è di adesso, e appena accesa
  ///   l'auto il riscaldatore va al massimo per scaldare l'abitacolo; la
  ///   stima è quella di quando l'abitacolo è caldo. Una potenza 0 non dice
  ///   niente (il raffrescamento e la pompa di calore non sono il
  ///   riscaldatore), e resta la stima.
  ///
  /// Senza dati, le condizioni restano queste: niente si inventa.
  Condizioni conAuto(StatoAuto? s) {
    if (s == null) return this;
    final t = s.temperaturaEsternaC ?? temperaturaC;
    var clima = s.temperaturaEsternaC == null ? climaW : climaStimatoW(t);
    var batteria = 0.0;
    final misurata = s.potenzaClimaW;
    if (s.batteriaInRiscaldamento == true) {
      final w = misurata != null && misurata > 0 ? misurata : potenzaRiscaldamentoBatteriaW;
      batteria = w * durataRiscaldamentoBatteria.inSeconds / 3.6e6;
    } else if (s.climaAcceso == true && misurata != null && misurata > 0) {
      clima = (climaStimatoW(t) + misurata) / 2;
    }
    return Condizioni(
      temperaturaC: t,
      ventoControMs: ventoControMs,
      climaW: clima,
      fattoreConsumo: fattoreConsumo,
      fattoriStrada: fattoriStrada,
      riscaldamentoBatteriaKwh: batteria,
      temperaturaBatteriaC: s.temperaturaBatteriaC ?? temperaturaBatteriaC,
    );
  }

  final double temperaturaC;

  /// Vento contrario positivo, a favore negativo.
  final double ventoControMs;

  final double climaW;

  /// L'energia per scaldare la batteria, presa una volta alla partenza:
  /// vedi [conAuto].
  final double riscaldamentoBatteriaKwh;

  /// La batteria fredda carica piano in continua: vedi
  /// [PianificatoreSoste]. `null` se non si sa.
  final double? temperaturaBatteriaC;

  /// Quanto la tua auto consuma rispetto al modello: lo impara
  /// [ConsumoImparato] guidando (1,1 = il 10% in più).
  final double fattoreConsumo;

  /// Il correttivo per tipo di strada, dove misurato; altrove [fattoreConsumo].
  final Map<TipoStrada, double> fattoriStrada;

  /// Le stesse condizioni (temperatura, vento, clima) senza il correttivo
  /// dell'auto: quello che il misuratore confronta con la batteria vera,
  /// perché il correttivo lo si vuole misurare, non presupporre. Il clima
  /// resta: se no il riscaldamento finiva dentro il correttivo e il piano,
  /// che il clima lo conta già dal meteo, lo contava due volte.
  Condizioni get senzaCorrettivo => Condizioni(
        temperaturaC: temperaturaC,
        ventoControMs: ventoControMs,
        climaW: climaW,
        riscaldamentoBatteriaKwh: riscaldamentoBatteriaKwh,
        temperaturaBatteriaC: temperaturaBatteriaC,
      );

  double fattorePer(double kmh) => fattoriStrada[TipoStrada.daVelocita(kmh)] ?? fattoreConsumo;

  /// Densità dell'aria alla temperatura data, al livello del mare.
  double get densitaAria => 101325 / (287.05 * (temperaturaC + 273.15));
}

/// L'energia presa dalla batteria per percorrere il [tratto], in Wh.
/// Negativa quando in discesa si recupera più di quanto si spende.
double energiaTrattoWh(Tratto tratto, ProfiloVeicolo p, [Condizioni c = const Condizioni()]) {
  final v = tratto.velocitaKmh / 3.6;
  final d = tratto.lunghezzaM;
  final aria = v + c.ventoControMs;

  final aerodinamica = 0.5 * c.densitaAria * p.cdA * aria * aria.abs();
  final rotolamento = p.massaKg * _g * p.crr;
  final ruota = (aerodinamica + rotolamento) * d + p.massaKg * _g * tratto.dislivelloM;

  final batteria = ruota >= 0 ? ruota / p.rendimentoTrazione : ruota * p.rendimentoRecupero;
  // Partenze e frenate: l'energia cinetica spesa e recuperata solo in parte.
  final fermate = fermatePerKm(tratto.velocitaKmh) * d / 1000;
  final dinamica = fermate * 0.5 * p.massaKg * v * v * (1 / p.rendimentoTrazione - p.rendimentoRecupero);
  final fissi = (p.consumoFissoW + c.climaW) * tratto.secondi;
  final wh = (batteria + dinamica + fissi) / 3600;
  // Il correttivo vale per quello che si spende, non per il recupero.
  return wh > 0 ? wh * c.fattorePer(tratto.velocitaKmh) : wh;
}

/// Quanto si consuma a velocità costante in piano, in kWh ogni 100 km,
/// senza i consumi fissi (clima, elettronica): chi li vuole li conta a parte,
/// come TomTom che li chiede come potenza.
double consumoCostanteKwh100(double kmh, ProfiloVeicolo p, [Condizioni c = const Condizioni()]) {
  final v = kmh / 3.6;
  final aria = v + c.ventoControMs;
  final forza = 0.5 * c.densitaAria * p.cdA * aria * aria.abs() + p.massaKg * _g * p.crr;
  return forza * 100000 / p.rendimentoTrazione / 3.6e6 * c.fattorePer(kmh);
}

/// L'energia per tutto il percorso fatto di [tratti], in kWh.
double energiaPercorsoKwh(List<Tratto> tratti, ProfiloVeicolo p, [Condizioni c = const Condizioni()]) =>
    tratti.fold(0.0, (s, t) => s + energiaTrattoWh(t, p, c)) / 1000;

/// Consumo medio in Wh/km, il numero che si mostra all'utente.
double consumoMedioWhKm(List<Tratto> tratti, ProfiloVeicolo p, [Condizioni c = const Condizioni()]) {
  var wh = 0.0, m = 0.0;
  for (final t in tratti) {
    wh += energiaTrattoWh(t, p, c);
    m += t.lunghezzaM;
  }
  return m == 0 ? 0 : wh / (m / 1000);
}

/// Il correttivo che porta il modello al «consumo di riferimento» scritto
/// dall'utente: [whKm] a [kmh] costanti, in piano, senza clima. È il numero
/// che ABRP chiama «consumo di riferimento» (calibrato guidando, alla sua
/// «velocità di riferimento», di solito 110 km/h).
///
/// Si confronta con quello che il modello dice alla stessa velocità, con
/// le stesse partenze e frenate e i consumi fissi: il rapporto è quanto la
/// tua auto si discosta dalla scheda tecnica. Tenuto fra 0,6 e 1,8 come il
/// correttivo imparato.
double fattoreDaRiferimento({required double whKm, required double kmh, required ProfiloVeicolo profilo}) {
  final modello = consumoMedioWhKm([Tratto(lunghezzaM: 1000, velocitaKmh: kmh)], profilo);
  if (whKm <= 0 || modello <= 0) return 1;
  return (whKm / modello).clamp(ConsumoImparato.minimo, ConsumoImparato.massimo).toDouble();
}

/// Il correttivo che viene dal consumo medio misurato dall'auto, [kwh100]
/// kWh ogni 100 km (quello del computer di bordo, delle ultime settimane).
///
/// Non è un consumo a velocità costante come il riferimento di ABRP
/// ([fattoreDaRiferimento]): è guida vera, mista. Si confronta quindi con
/// quello che il modello dice per una guida mista, un terzo in città a 40
/// km/h, un terzo fuori a 80 e un terzo in autostrada a 120, con le partenze
/// e frenate di ciascuna, i consumi fissi e il clima delle [condizioni]
/// (quelle della temperatura di adesso, che è più o meno quella delle
/// ultime settimane), senza correttivo. Tenuto fra 0,6 e 1,8 come il
/// correttivo imparato; quanto conti lo decide [ConsumoImparato.fattoreCon].
double fattoreDaConsumoMedio({
  required double kwh100,
  required ProfiloVeicolo profilo,
  Condizioni condizioni = const Condizioni(),
}) {
  const misto = [
    Tratto(lunghezzaM: 10000, velocitaKmh: 40),
    Tratto(lunghezzaM: 10000, velocitaKmh: 80),
    Tratto(lunghezzaM: 10000, velocitaKmh: 120),
  ];
  final modello = consumoMedioWhKm(misto, profilo, condizioni.senzaCorrettivo) / 10;
  if (!kwh100.isFinite || kwh100 <= 0 || modello <= 0) return 1;
  return (kwh100 / modello).clamp(ConsumoImparato.minimo, ConsumoImparato.massimo).toDouble();
}
