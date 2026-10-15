import 'dart:math' as math;

import '../geo/geo.dart';
import '../ztl/ztl.dart' show Rettangolo;
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
  ///
  /// Nell'ordine: i pedaggi veri casello per casello
  /// ([PercorsoCalcolato.pagamentiPedaggio], da HERE); se no il prezzo vero
  /// del motore ([PercorsoCalcolato.prezzoPedaggio]); se no la stima, dove
  /// le strade a prezzo fisso ([stradeAPrezzoFisso]) hanno il loro prezzo
  /// vero e il resto va a km.
  CostoPedaggio stima(PercorsoCalcolato percorso, {double daM = 0}) {
    final tratti = [
      for (final t in percorso.pedaggi)
        if (t.aM > daM) t,
    ];
    final vignetta = tratti.any((t) => t.vignetta);
    final kmTutti = tratti.fold(0.0, (s, t) => s + (t.vignetta ? 0 : t.lunghezzaM)) / 1000;

    // I pedaggi veri, casello per casello: quelli che restano da pagare.
    if (percorso.pagamentiPedaggio case final pagamenti?) {
      final restano = [
        for (final p in pagamenti)
          if (p.aM >= daM) p,
      ];
      return CostoPedaggio(
        euro: restano.fold(0.0, (s, p) => s + p.euro),
        km: kmTutti,
        stimato: false,
        vignetta: vignetta,
        // Si paga ma HERE non ha dato prezzi (un tratto che non conosce): si
        // sa solo che c'è.
        sconosciuto: restano.isEmpty && kmTutti > 0 && pagamenti.isEmpty,
        classe: classe,
        caselli: [for (final p in restano) p.nome].where((n) => n.isNotEmpty).toList(),
      );
    }

    final nomi = _NomiDelleStrade(percorso);
    var km = 0.0, kmFuori = 0.0, euroKm = 0.0, euroFissi = 0.0;
    var fissiStimati = false;
    TrattoPedaggio? aperto;
    var metriAperto = 0.0;
    StradaAPrezzoFisso? fissa;
    var fineFissa = double.negativeInfinity;
    void chiudi() {
      if (aperto == null) return;
      euroKm += math.max(minimoPerTratta, metriAperto / 1000 * euroAlKm);
      aperto = null;
      metriAperto = 0;
    }

    for (final t in tratti) {
      if (t.vignetta) continue;
      if (t.paese != null && !paesiStimati.contains(t.paese)) {
        kmFuori += t.lunghezzaM / 1000;
        continue;
      }
      km += t.lunghezzaM / 1000;
      // Una strada a prezzo fisso: si paga una volta a passaggio, quanto
      // dice il suo listino, e non a km. Due pezzi attaccati della stessa
      // strada sono lo stesso passaggio.
      if (nomi.prezzoFisso(t) case final f?) {
        chiudi();
        if (!(identical(f, fissa) && t.daM - fineFissa <= _giunzioneM)) {
          final prezzo = f.prezzo(classe);
          euroFissi += prezzo.euro;
          fissiStimati = fissiStimati || prezzo.stimato;
        }
        fissa = f;
        fineFissa = t.aM;
        continue;
      }
      fissa = null;
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
      // La stima a km si arrotonda ai dieci centesimi; i prezzi fissi no:
      // la Tangenziale di Napoli costa 1,05 €, non 1,10.
      euro: arrotondaPedaggio(euroKm) + euroFissi,
      km: km,
      kmNonStimati: kmFuori,
      vignetta: vignetta,
      // Il motore dice che si paga, ma non dove (Valhalla con `has_toll`
      // e nessuna manovra segnata): si sa solo che c'è.
      sconosciuto: daM <= 0 && percorso.conPedaggi && percorso.pedaggi.isEmpty,
      // Esatto solo se tutto quello che si paga è a prezzo fisso, col
      // listino della classe.
      stimato: euroKm > 0 || fissiStimati || (euroFissi <= 0),
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
    this.caselli = const [],
  });

  /// Dove si paga, quando i pedaggi sono quelli veri: i nomi dei caselli
  /// (o delle barriere), nell'ordine.
  final List<String> caselli;

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

/// Un pedaggio vero: quanto, e dove lungo il percorso si paga (in metri
/// sulla geometria dei punti). In Italia si paga all'uscita: un pagamento
/// oltre la posizione di adesso è ancora da fare.
class PagamentoPedaggio {
  const PagamentoPedaggio({required this.euro, required this.aM, this.nome = ''});

  final double euro;
  final double aM;

  /// Il casello o la barriera, come lo chiama chi ha dato il prezzo.
  final String nome;

  @override
  String toString() => 'PagamentoPedaggio(${euroItaliani(euro)} a ${aM.round()} m${nome.isEmpty ? '' : ', $nome'})';
}

/// Il prezzo di un passaggio su una strada a prezzo fisso, per una classe.
class PrezzoFisso {
  const PrezzoFisso(this.euro, {this.stimato = false});
  final double euro;

  /// `true` se il listino di questa classe non si sa e si è fatto in
  /// proporzione alla classe A.
  final bool stimato;
}

/// Una strada a sistema aperto: si paga lo stesso prezzo a ogni passaggio,
/// comunque si entri e si esca. Si riconosce dai nomi e dai numeri delle
/// strade delle manovre (TomTom: `street` e `roadNumbers`).
class StradaAPrezzoFisso {
  const StradaAPrezzoFisso({
    required this.nome,
    required this.schema,
    required this.listino,
    required this.dal,
    this.zona,
    this.nellaZona,
    this.cortaNellaZonaM = 0,
  });

  final String nome;

  /// Come la chiamano le manovre: «A56», «Tangenziale di Napoli».
  final String schema;

  /// Il prezzo vero per classe, IVA compresa. Le classi che mancano si fanno
  /// in proporzione alla A ([ClassePedaggio.fattore]) e restano stimate.
  final Map<ClassePedaggio, double> listino;

  /// Da quando vale il listino: per ricordarsi di aggiornarlo.
  final String dal;

  /// Dove sta la strada, se la si conosce: dentro, basta un nome piu'
  /// largo ([nellaZona]) — «Tangenziale» e basta — e un tratto a pagamento
  /// lungo fino a [cortaNellaZonaM], tutto li' dentro, e' lei.
  final Rettangolo? zona;
  final String? nellaZona;
  final double cortaNellaZonaM;

  bool riconosce(String testo, [Punto? dove]) {
    if (RegExp(schema, caseSensitive: false).hasMatch(testo)) return true;
    final z = zona, largo = nellaZona;
    return z != null &&
        largo != null &&
        dove != null &&
        z.contiene(dove) &&
        RegExp(largo, caseSensitive: false).hasMatch(testo);
  }

  PrezzoFisso prezzo(ClassePedaggio c) {
    if (listino[c] case final e?) return PrezzoFisso(e);
    final a = listino[ClassePedaggio.a] ?? 0;
    return PrezzoFisso((a * c.fattore * 20).round() / 20, stimato: true);
  }
}

/// Le strade italiane a prezzo fisso che si conoscono. Si aggiungono qui,
/// col listino ufficiale e la data da cui vale.
const stradeAPrezzoFisso = [
  // A56: 1,05 € a passaggio in classe A dal 1° gennaio 2026 (prima 1,00 €).
  // «Di nuovo pedaggio 1,00»: TomTom la chiama anche solo «Tangenziale», o
  // il chilometro della barriera sta sotto la manovra di un'altra strada.
  // Dentro questo riquadro di Napoli l'unica strada a pagamento e' la
  // Tangenziale (le barriere dell'A1 e dell'A3 stanno fuori): un tratto a
  // pagamento tutto li' dentro e' lei.
  StradaAPrezzoFisso(
    nome: 'Tangenziale di Napoli',
    schema: r'\bA\s?56\b|tangenziale di napoli',
    listino: {ClassePedaggio.a: 1.05},
    dal: '2026-01-01',
    zona: Rettangolo(40.82, 14.12, 40.91, 14.285),
    nellaZona: r'\btangenziale\b|\btang\.',
    cortaNellaZonaM: 25000,
  ),
];

/// I nomi delle strade lungo il percorso, dalle manovre: ogni manovra vale
/// dal suo punto a quello della manovra dopo.
class _NomiDelleStrade {
  _NomiDelleStrade(PercorsoCalcolato p) : _punti = p.punti {
    if (p.punti.length < 2) return;
    final cumulate = _cumulate = Linea(p.punti).cumulate;
    if (p.manovre.isEmpty) return;
    final n = cumulate.length - 1;
    for (var i = 0; i < p.manovre.length; i++) {
      final m = p.manovre[i];
      final da = cumulate[m.inizio.clamp(0, n)];
      final a = i + 1 < p.manovre.length ? cumulate[p.manovre[i + 1].inizio.clamp(0, n)] : cumulate[n];
      // Una rampa senza nome porta alla strada della manovra dopo: la
      // barriera della Tangenziale sta proprio sulla rampa d'ingresso.
      final dopo = i + 1 < p.manovre.length ? p.manovre[i + 1] : null;
      final testo = m.strada.trim().isEmpty && dopo != null ? '${dopo.strada} ${dopo.verso}' : '${m.strada} ${m.verso}';
      if (a > da) _pezzi.add((da: da, a: a, testo: testo));
    }
  }

  final _pezzi = <({double da, double a, String testo})>[];
  final List<Punto> _punti;
  List<double> _cumulate = const [];

  /// Il punto del percorso a [m] metri dalla partenza.
  Punto? _a(double m) {
    if (_cumulate.isEmpty) return null;
    for (var i = 0; i < _cumulate.length; i++) {
      if (_cumulate[i] >= m) return _punti[i];
    }
    return _punti.last;
  }

  /// La strada a prezzo fisso su cui sta [t]: quella delle manovre che ne
  /// coprono almeno metà.
  StradaAPrezzoFisso? prezzoFisso(TrattoPedaggio t) {
    if (t.lunghezzaM <= 0) return null;
    for (final f in stradeAPrezzoFisso) {
      var coperti = 0.0;
      for (final p in _pezzi) {
        if (!f.riconosce(p.testo, _a((p.da + p.a) / 2))) continue;
        coperti += math.max(0, math.min(p.a, t.aM) - math.max(p.da, t.daM));
      }
      if (coperti >= t.lunghezzaM / 2) return f;
      // Un tratto tutto nella zona della strada, comunque lo chiamino le
      // manovre.
      final z = f.zona, inizio = _a(t.daM), fine = _a(t.aM);
      if (z != null &&
          t.lunghezzaM <= f.cortaNellaZonaM &&
          inizio != null &&
          fine != null &&
          z.contiene(inizio) &&
          z.contiene(fine)) {
        return f;
      }
    }
    return null;
  }
}
