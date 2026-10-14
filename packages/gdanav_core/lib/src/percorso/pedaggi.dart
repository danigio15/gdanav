import 'dart:math' as math;

import '../geo/geo.dart';
import 'valhalla.dart';

/// Quanto costa il pedaggio di un percorso, come lo mostra Waze: «Pedaggio
/// ~12,40 €», o «Senza pedaggi».
///
/// Da dove viene il prezzo, e quanto ci si può fidare.
///
/// Né TomTom né Valhalla danno il prezzo: dicono solo **dove** si paga.
/// TomTom con le sezioni `TOLL_ROAD` (e `TOLL_VIGNETTE` per i paesi a
/// bollino), Valhalla con `toll` su ogni manovra e `has_toll` nel sommario.
/// Il prezzo vero lo sanno servizi a pagamento (HERE Routing v8 con
/// `return=tolls`, TollGuru): se un giorno ci sarà una chiave, il motore che
/// lo sa lo mette in [PercorsoCalcolato.prezzoPedaggio] e qui vince lui.
///
/// Senza, si **stima**: i km fatti sui tratti a pagamento per una tariffa al
/// km della classe del veicolo. In Italia è un'approssimazione onesta del
/// sistema chiuso (si paga in base ai km fra entrata e uscita), ma:
///  * ogni concessionaria ha la sua tariffa: sulle autostrade «normali» si
///    sta intorno agli 8 centesimi al km in classe A, ma alcune (le
///    autostrade di montagna, quelle nuove in project financing) costano il
///    doppio o più, e lì la stima viene bassa;
///  * i trafori (Monte Bianco, Frejus) e i tratti a sistema aperto
///    (barriere a prezzo fisso, tangenziali) non vanno a km: per questi c'è
///    un [TariffaPedaggio.minimoPerTratta], che evita il «0,30 €» per una
///    barriera che ne costa due, ma resta una stima;
///  * fuori dall'Italia non si stima: i km a pagamento si contano a parte
///    ([CostoPedaggio.kmNonStimati]), e i paesi a vignetta non hanno un
///    prezzo per viaggio ([CostoPedaggio.vignetta]).
///
/// Per questo si scrive sempre «~» davanti e «stimato» dove c'è spazio.

/// Le classi dei pedaggi italiani: dipendono da assi e altezza, non dal
/// motore. Il [fattore] è quanto costa la classe rispetto alla A: sono
/// rapporti tipici delle tariffe italiane, arrotondati, non quelli di una
/// concessionaria in particolare.
enum ClassePedaggio {
  a('A', 'Auto e moto (2 assi, alte fino a 1,30 m all\'asse anteriore)', 1.0),
  b('B', '2 assi più alti di 1,30 m all\'asse anteriore: furgoni, camper', 1.03),
  tre('3', '3 assi: auto con rimorchio, camion leggeri', 1.30),
  quattro('4', '4 assi', 1.95),
  cinque('5', '5 assi o più', 2.30);

  const ClassePedaggio(this.sigla, this.descrizione, this.fattore);

  /// «A», «B», «3»…: come sul biglietto.
  final String sigla;
  final String descrizione;
  final double fattore;

  String get nome => 'Classe $sigla';

  static ClassePedaggio da(Object? nome) => values.where((c) => c.name == nome).firstOrNull ?? a;
}

/// Un tratto a pagamento del percorso, in metri dall'inizio (sulla
/// geometria dei punti, come le code).
class TrattoPedaggio {
  const TrattoPedaggio({required this.daM, required this.aM, this.vignetta = false, this.paese});

  final double daM;
  final double aM;

  /// Si paga col bollino (Svizzera, Austria, Slovenia…), non a km.
  final bool vignetta;

  /// Il paese (ISO a tre lettere, «ITA», «FRA»), se il motore lo dice.
  /// `null`: non si sa, e si stima come in Italia.
  final String? paese;

  double get lunghezzaM => math.max(0, aM - daM);

  @override
  String toString() => 'TrattoPedaggio(${daM.round()}–${aM.round()} m${vignetta ? ', vignetta' : ''}'
      '${paese == null ? '' : ', $paese'})';
}

/// Come si stima il pedaggio: la classe del veicolo e la tariffa al km.
class TariffaPedaggio {
  const TariffaPedaggio({
    this.classe = ClassePedaggio.a,
    this.euroAlKmClasseA = euroAlKmPredefinito,
    this.minimoPerTratta = minimoPredefinito,
    this.paesiStimati = const {'ITA'},
  });

  /// La tariffa media in classe A, IVA compresa: le autostrade italiane più
  /// trafficate stanno fra 7 e 9 centesimi al km. È un punto di partenza,
  /// non il listino di nessuno: si cambia dalle opzioni.
  static const euroAlKmPredefinito = 0.08;

  /// Un tratto a pagamento non costa quasi mai meno di così: barriere,
  /// tangenziali e tratti brevi hanno un prezzo fisso, che a km uscirebbe
  /// troppo basso.
  static const minimoPredefinito = 1.0;

  final ClassePedaggio classe;

  /// La tariffa della classe A; le altre la moltiplicano per il loro fattore.
  final double euroAlKmClasseA;
  final double minimoPerTratta;

  /// Dove la tariffa al km ha senso. Altrove i km a pagamento si contano ma
  /// non si stimano.
  final Set<String> paesiStimati;

  /// Quanto si paga al km con questa [classe].
  double get euroAlKm => euroAlKmClasseA * classe.fattore;

  /// Due tratti più vicini di così sono lo stesso: TomTom spezza la stessa
  /// autostrada a ogni svincolo, e il minimo non va contato due volte.
  static const _giunzioneM = 300.0;

  /// Il pedaggio del [percorso]. Con [daM] solo quello ancora da pagare,
  /// in guida: in Italia si paga all'uscita, quindi un tratto in cui si è
  /// dentro conta tutto.
  CostoPedaggio stima(PercorsoCalcolato percorso, {double daM = 0}) {
    final tratti = [
      for (final t in percorso.pedaggi)
        if (t.aM > daM) t,
    ];
    var km = 0.0, kmFuori = 0.0, euro = 0.0;
    var vignetta = false;
    TrattoPedaggio? aperto;
    var metriAperto = 0.0;
    void chiudi() {
      if (aperto == null) return;
      euro += math.max(minimoPerTratta, metriAperto / 1000 * euroAlKm);
      aperto = null;
      metriAperto = 0;
    }

    for (final t in tratti) {
      if (t.vignetta) {
        vignetta = true;
        continue;
      }
      if (t.paese != null && !paesiStimati.contains(t.paese)) {
        kmFuori += t.lunghezzaM / 1000;
        continue;
      }
      km += t.lunghezzaM / 1000;
      if (aperto case final a? when t.daM - a.aM <= _giunzioneM) {
        aperto = t;
        metriAperto += t.lunghezzaM;
        continue;
      }
      chiudi();
      aperto = t;
      metriAperto = t.lunghezzaM;
    }
    chiudi();

    // Il prezzo vero, se il motore lo sa: per quello che resta, in
    // proporzione ai km a pagamento che restano.
    if (percorso.prezzoPedaggio case final vero?) {
      final tutti = percorso.pedaggi.fold(0.0, (s, t) => s + (t.vignetta ? 0 : t.lunghezzaM)) / 1000;
      final quota = daM <= 0 || tutti <= 0 ? 1.0 : ((km + kmFuori) / tutti).clamp(0.0, 1.0);
      return CostoPedaggio(
        euro: vero * quota,
        km: km + kmFuori,
        stimato: false,
        vignetta: vignetta,
        classe: classe,
      );
    }
    return CostoPedaggio(
      euro: arrotondaPedaggio(euro),
      km: km,
      kmNonStimati: kmFuori,
      vignetta: vignetta,
      // Il motore dice che si paga, ma non dove (Valhalla con `has_toll`
      // e nessuna manovra segnata): si sa solo che c'è.
      sconosciuto: daM <= 0 && percorso.conPedaggi && percorso.pedaggi.isEmpty,
      classe: classe,
    );
  }

  TariffaPedaggio copia({ClassePedaggio? classe, double? euroAlKmClasseA, double? minimoPerTratta}) => TariffaPedaggio(
        classe: classe ?? this.classe,
        euroAlKmClasseA: euroAlKmClasseA ?? this.euroAlKmClasseA,
        minimoPerTratta: minimoPerTratta ?? this.minimoPerTratta,
        paesiStimati: paesiStimati,
      );
}

/// I pedaggi italiani si arrotondano ai dieci centesimi: anche la stima.
double arrotondaPedaggio(double euro) => (euro * 10).round() / 10;

/// Il pedaggio di un percorso, stimato o vero.
class CostoPedaggio {
  const CostoPedaggio({
    this.euro = 0,
    this.km = 0,
    this.kmNonStimati = 0,
    this.vignetta = false,
    this.sconosciuto = false,
    this.stimato = true,
    this.classe = ClassePedaggio.a,
  });

  /// Quanto si paga (in euro) sui tratti che si sanno stimare.
  final double euro;

  /// I km a pagamento stimati.
  final double km;

  /// I km a pagamento dove la tariffa non vale (all'estero).
  final double kmNonStimati;

  /// Passa da strade col bollino.
  final bool vignetta;

  /// Si paga, ma non si sa dove né quanto.
  final bool sconosciuto;

  /// `false` solo se il prezzo l'ha dato il motore dei percorsi.
  final bool stimato;
  final ClassePedaggio classe;

  /// Niente da pagare: «Senza pedaggi».
  bool get senzaPedaggi => euro <= 0 && km <= 0 && kmNonStimati <= 0 && !vignetta && !sconosciuto;

  /// C'è un prezzo da scrivere.
  bool get conPrezzo => euro > 0;

  /// «12,40 €», «~12,40 €» se stimato.
  String get prezzo => '${stimato ? '~' : ''}${euroItaliani(euro)}';

  /// Per la riga di un percorso: «~12,40 €», «~12,40 € + estero»,
  /// «Vignetta», «Pedaggio», o «Senza pedaggi».
  String get breve {
    if (senzaPedaggi) return 'Senza pedaggi';
    final primo = conPrezzo
        ? prezzo
        : kmNonStimati > 0
            ? 'Pedaggio estero'
            : vignetta
                ? 'Vignetta'
                : 'Pedaggio';
    return [
      primo,
      if (conPrezzo && kmNonStimati > 0) '+ estero',
      if (vignetta && primo != 'Vignetta') '+ vignetta',
    ].join(' ');
  }

  /// Per Android Auto e CarPlay: «Pedaggio ~12,40 €», «Senza pedaggi».
  String get riga => switch (breve) {
        _ when conPrezzo => 'Pedaggio $breve',
        'Pedaggio' => 'Con pedaggio',
        'Vignetta' => 'Con vignetta',
        final b => b,
      };

  /// Accanto ai km che restano, nella scheda dell'arrivo dell'auto:
  /// «~12,40 € pedaggio»; senza prezzo come [riga] («Con vignetta»).
  String get perStima => conPrezzo && kmNonStimati <= 0 && !vignetta ? '$prezzo pedaggio' : riga;

  @override
  String toString() => 'CostoPedaggio($riga, ${km.toStringAsFixed(1)} km)';
}

/// «12,40 €», con la virgola.
String euroItaliani(double euro) => '${euro.toStringAsFixed(2).replaceAll('.', ',')} €';

/// I tratti a pagamento da intervalli di indici sui [punti] (inizio, fine,
/// vignetta, paese): quelli attaccati diventano uno.
List<TrattoPedaggio> trattiDaIndici(
  List<Punto> punti,
  Iterable<({int da, int a, bool vignetta, String? paese})> intervalli,
) {
  if (punti.length < 2) return const [];
  final cumulate = Linea(punti).cumulate;
  final n = cumulate.length - 1;
  final ordinati = intervalli.where((i) => i.a > i.da).toList()..sort((x, y) => x.da.compareTo(y.da));
  final tratti = <TrattoPedaggio>[];
  for (final i in ordinati) {
    final t = TrattoPedaggio(
      daM: cumulate[i.da.clamp(0, n)],
      aM: cumulate[i.a.clamp(0, n)],
      vignetta: i.vignetta,
      paese: i.paese,
    );
    if (t.lunghezzaM <= 0) continue;
    final ultimo = tratti.lastOrNull;
    if (ultimo != null && ultimo.vignetta == t.vignetta && ultimo.paese == t.paese && t.daM <= ultimo.aM + 1) {
      tratti[tratti.length - 1] = TrattoPedaggio(
        daM: ultimo.daM,
        aM: math.max(ultimo.aM, t.aM),
        vignetta: t.vignetta,
        paese: t.paese,
      );
    } else {
      tratti.add(t);
    }
  }
  return tratti;
}
