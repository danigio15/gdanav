/* Quanto è costata l'energia di un viaggio in elettrico, per davvero.
 *
 * Dal campo: «per il costo del viaggio, soprattutto se elettrico, devi
 * considerare se si parte da casa al 100%, e verificare l'ultima ricarica a
 * casa per portare a quella percentuale come è stata caricata; e capire, o
 * chiedere, quanto si è speso per la ricarica se ci si ferma in autostrada o
 * per strada, e da lì fare il conto preciso».
 *
 * Il conto è questo. L'energia consumata viene prima dalla batteria con cui
 * si è partiti, poi da quella presa per strada (come si svuota davvero un
 * serbatoio: quello che resta all'arrivo è il pieno dell'ultima sosta, e non
 * è di questo viaggio). Il kWh di casa costa quanto è costata l'ultima
 * ricarica a casa — il sole niente, la rete il suo prezzo —, quello delle
 * soste quanto si è pagato lì.
 *
 * «Verifica i costi perché non mi trovo: 1 € di energia per 3,5 kWh». Erano
 * 0,30 €/kWh, il numero di serie delle opzioni, scritto come «Casa 3,5 kWh»:
 * la ricarica di casa c'era, ma la batteria alla partenza era 18 punti sotto
 * a dove l'aveva lasciata, e la si scartava ([RicaricaDiCasa.valePer]). Ora
 * vale finché l'energia in batteria è la sua; se non c'è, il prezzo è la
 * tariffa di casa ([EnergiaDiCasa.euroAlKwh]); e quello delle opzioni resta
 * l'ultima riserva, detta per quello che è: una stima, con cosa manca
 * ([SenzaPrezzoVero]).
 */

/// L'ultima ricarica a casa, come la racconta la casa (GdAHome).
class RicaricaDiCasa {
  const RicaricaDiCasa({required this.finitaIl, required this.kwh, this.socA, this.kwhSole, this.euroRete});

  /// Da `ponte/auto/ricariche-di-casa`: `{finitaIl, socA, kwh, kwhSole, euroRete}`.
  static RicaricaDiCasa? daJson(Object? j) {
    if (j is! Map) return null;
    final quando = DateTime.tryParse('${j['finitaIl'] ?? ''}');
    final kwh = (j['kwh'] as num?)?.toDouble();
    if (quando == null || kwh == null || kwh <= 0) return null;
    return RicaricaDiCasa(
      finitaIl: quando,
      kwh: kwh,
      socA: (j['socA'] as num?)?.toDouble(),
      kwhSole: (j['kwhSole'] as num?)?.toDouble(),
      euroRete: (j['euroRete'] as num?)?.toDouble(),
    );
  }

  final DateTime finitaIl;
  final double kwh;

  /// Fino a che percentuale.
  final double? socA;

  /// Quanti kWh col sole, e quanto è costata la rete.
  final double? kwhSole, euroRete;

  /// Il prezzo di un kWh di quella ricarica: il sole gratis, la rete il suo.
  /// `null` se la casa il prezzo della rete non lo sa.
  double? get euroAlKwh => euroRete == null ? null : euroRete! / kwh;

  /// La parte dal sole, da 0 a 1.
  double? get quotaSole => kwhSole == null ? null : (kwhSole! / kwh).clamp(0.0, 1.0);

  /// Per quanto tempo l'energia in batteria si dice ancora «di questa
  /// ricarica», quando la batteria alla partenza lo conferma.
  static const quantoVale = Duration(days: 14);

  /// Senza sapere la batteria (alla partenza, o a fine ricarica) ci si fida
  /// di meno: tre giorni.
  static const quantoValeAlBuio = Duration(days: 3);

  /// Di quanti punti la batteria alla partenza può stare sopra a dove la
  /// ricarica l'ha lasciata: la casa legge la fine della ricarica quando
  /// l'auto gliela dice, anche un po' prima dell'ultimo punto.
  static const puntiInPiu = 15.0;

  /// Se l'energia con cui si parte è ancora quella di questa ricarica.
  ///
  /// Dal campo: «non è vero che non c'era una ricarica a casa: per portarla
  /// al 100% ho ricaricato a casa». Era partito all'82%, dopo altri viaggi:
  /// qui si voleva la batteria «vicina» (entro 15 punti) a dove la ricarica
  /// l'aveva lasciata, e 100 − 82 = 18 la faceva scartare; il conto andava
  /// al prezzo delle opzioni. Ma una batteria più **giù** è la stessa
  /// energia, meno quella dei viaggi già fatti: la casa ricorda sempre
  /// l'ultima ricarica, e finché non ne arriva un'altra quella in batteria è
  /// sua. Non vale solo se la batteria è più **su** di come la ricarica
  /// l'aveva lasciata (si è caricato altrove, e la casa non l'ha visto), o se
  /// è passato troppo tempo.
  bool valePer({required DateTime partenza, double? batteriaPartenza}) {
    final da = partenza.difference(finitaIl);
    // Un orologio un po' avanti (la casa, il telefono) non è una ricarica
    // nel futuro.
    if (da < const Duration(minutes: -10)) return false;
    if (socA == null || batteriaPartenza == null) return da <= quantoValeAlBuio;
    if (superataDa(batteriaPartenza)) return false;
    return da <= quantoVale;
  }

  /// Vero se la batteria alla partenza è più carica di come questa ricarica
  /// l'aveva lasciata: dopo, si è caricato da un'altra parte (una colonnina,
  /// un'altra casa), e quell'energia non ha il prezzo di casa.
  bool superataDa(double? batteriaPartenza) {
    final a = socA;
    return a != null && batteriaPartenza != null && batteriaPartenza > a + puntiInPiu;
  }
}

/// Quello che la casa (GdAHome) sa dell'energia con cui l'auto parte:
/// l'ultima ricarica a casa, il prezzo della sua rete, e se l'auto la segue.
/// È la risposta di `ponte/auto/ricariche-di-casa`.
class EnergiaDiCasa {
  const EnergiaDiCasa({this.ricarica, this.euroAlKwh, this.conTariffa, this.autoSeguita});

  /// Dalla risposta della casa: `{ricariche: [{nome, finitaIl, socA, kwh,
  /// kwhSole, euroRete}], prezzo: {euroAlKwh} | null, auto: [nomi]}`.
  /// [nomi]: come si chiama l'auto in uso nella plancia. Una casa di prima
  /// manda solo `ricariche`: il resto resta `null`, «non lo dice».
  static EnergiaDiCasa daRisposta(Object? r, {Iterable<String?> nomi = const []}) {
    if (r is! Map) return const EnergiaDiCasa();
    final suoi = {
      for (final n in nomi)
        if (n != null && n.isNotEmpty) n,
    };
    final elenco = r['ricariche'];
    final voci = elenco is List ? elenco.whereType<Map>().toList() : const <Map>[];
    final sua = voci.where((v) => suoi.contains(v['nome'])).firstOrNull ?? (voci.length == 1 ? voci.single : null);
    final prezzo = r['prezzo'];
    final euro = prezzo is Map ? (prezzo['euroAlKwh'] as num?)?.toDouble() : null;
    final seguite = r['auto'];
    return EnergiaDiCasa(
      ricarica: RicaricaDiCasa.daJson(sua),
      euroAlKwh: euro != null && euro > 0 ? euro : null,
      conTariffa: r.containsKey('prezzo') ? euro != null && euro > 0 : null,
      autoSeguita:
          seguite is List ? seguite.length == 1 || seguite.any((n) => suoi.contains(n is Map ? n['nome'] : n)) : null,
    );
  }

  /// L'ultima ricarica a casa dell'auto, valga o no per questo viaggio
  /// ([RicaricaDiCasa.valePer]).
  final RicaricaDiCasa? ricarica;

  /// Il prezzo di un kWh preso dalla rete di casa, come lo sa la casa (la
  /// tariffa della plancia: unica, a fasce o da un'entità). `null` se non
  /// l'ha.
  final double? euroAlKwh;

  /// Se la casa ha un prezzo dell'energia; `null`: non lo dice.
  final bool? conTariffa;

  /// Se la casa segue la ricarica di quest'auto; `null`: non lo dice.
  final bool? autoSeguita;
}

/// Perché il kWh della batteria non ha il prezzo vero della sua ricarica:
/// lo si dice a chi guida, con dove si rimedia ([RiepilogoViaggio.note]).
enum SenzaPrezzoVero {
  /// La casa non ha risposto (non collegata alla partenza né all'arrivo).
  casaMuta,

  /// La casa non ha il prezzo dell'energia: lo mette chi la configura.
  senzaTariffa,

  /// La casa non segue la ricarica di quest'auto: mancano i suoi sensori.
  autoNonSeguita,

  /// La casa segue l'auto ma una ricarica non l'ha ancora vista.
  senzaRicarica,

  /// L'ultima ricarica a casa è troppo vecchia per dire che l'energia in
  /// batteria sia ancora la sua.
  ricaricaNonVale,

  /// Dopo l'ultima ricarica a casa si è caricato altrove: la batteria alla
  /// partenza era più carica di come l'aveva lasciata.
  ricaricaAltrove,
}

/// Da dove viene il prezzo del kWh con cui si è partiti.
enum PrezzoDiPartenza {
  /// Dall'ultima ricarica a casa: il sole niente, la rete quanto è costata.
  ricarica,

  /// Dalla tariffa di casa: il prezzo della rete, come lo sa la casa.
  tariffa,

  /// Dalle opzioni del percorso: una stima, non si sa da dove viene l'energia.
  opzioni,
}

/// Una ricarica fatta durante il viaggio.
class RicaricaInViaggio {
  const RicaricaInViaggio({required this.dove, required this.kwh, this.euroStimati, this.euroPagati});

  /// Dove: il nome della colonnina, o «per strada».
  final String dove;
  final double kwh;

  /// Dalla tariffa della colonnina, se il gestore la dice.
  final double? euroStimati;

  /// Quanto si è pagato davvero, se chi guida l'ha detto.
  final double? euroPagati;

  double? get euro => euroPagati ?? euroStimati;
  bool get stimata => euroPagati == null;

  RicaricaInViaggio pagata(double euro) =>
      RicaricaInViaggio(dove: dove, kwh: kwh, euroStimati: euroStimati, euroPagati: euro);
}

/// Il costo dell'energia del viaggio, diviso fra casa e soste.
class CostoDellEnergia {
  const CostoDellEnergia({
    required this.kwhDaCasa,
    required this.euroCasa,
    required this.origine,
    required this.kwhDalleSoste,
    required this.euroSoste,
    required this.sosteStimate,
    this.euroAlKwhCasa,
    this.quotaSole,
  });

  /// I kWh della batteria con cui si è partiti, e quanto sono costati. «Da
  /// casa» solo se il prezzo viene dalla casa ([origine]): col prezzo delle
  /// opzioni non si sa da dove venissero.
  final double kwhDaCasa, euroCasa;

  /// Da dove viene il prezzo di quei kWh.
  final PrezzoDiPartenza origine;

  /// Vero se il prezzo di casa viene dall'ultima ricarica.
  bool get prezzoCasaVero => origine == PrezzoDiPartenza.ricarica;

  /// Il prezzo di un kWh preso dalla rete (la tariffa di casa) o stimato (le
  /// opzioni), da scrivere accanto al conto; `null` con l'ultima ricarica,
  /// che ha il suo.
  final double? euroAlKwhCasa;

  /// La parte dal sole dell'energia di casa, se si sa.
  final double? quotaSole;

  final double kwhDalleSoste, euroSoste;

  /// Vero se almeno una sosta non è stata detta da chi guida.
  final bool sosteStimate;

  double get totale => euroCasa + euroSoste;
}

/// Il conto: [consumatiKwh] in tutto, partiti con [partenzaKwh] nella
/// batteria; [casa] l'ultima ricarica a casa (`null` se non vale), [soste]
/// quelle fatte per strada.
///
/// Il prezzo del kWh con cui si è partiti, nell'ordine:
///  1. quello dell'ultima ricarica a casa ([RicaricaDiCasa.euroAlKwh]): il
///     sole niente, la rete quanto è costata;
///  2. [euroAlKwhDiCasa], la tariffa che la casa ha per la sua rete — «a casa
///     pago meno»: se la ricarica non c'è o non ha il suo prezzo, è comunque
///     più vero di un numero scritto nelle opzioni. Con una ricarica che vale
///     e sa quanta parte veniva dal sole, quella parte non si paga;
///  3. [euroAlKwhDiRiserva], il prezzo delle opzioni: una stima, e lo si dice.
CostoDellEnergia? costoDellEnergia({
  required double consumatiKwh,
  double? partenzaKwh,
  RicaricaDiCasa? casa,
  double? euroAlKwhDiCasa,
  List<RicaricaInViaggio> soste = const [],
  double? euroAlKwhDiRiserva,
}) {
  if (!(consumatiKwh > 0)) return null;
  final presiPerStrada = soste.fold(0.0, (s, r) => s + r.kwh);
  final daCasa = partenzaKwh == null
      ? (consumatiKwh - presiPerStrada).clamp(0.0, consumatiKwh)
      : consumatiKwh.clamp(0.0, partenzaKwh);
  final dalleSoste = consumatiKwh - daCasa;
  final tariffa = euroAlKwhDiCasa != null && euroAlKwhDiCasa > 0 ? euroAlKwhDiCasa : null;
  final sole = casa?.quotaSole;
  final (double? prezzoCasa, PrezzoDiPartenza origine) = switch (casa?.euroAlKwh) {
    final vero? => (vero, PrezzoDiPartenza.ricarica),
    _ when tariffa != null => (tariffa * (1 - (sole ?? 0)), PrezzoDiPartenza.tariffa),
    _ => (euroAlKwhDiRiserva, PrezzoDiPartenza.opzioni),
  };
  if (prezzoCasa == null && daCasa > 0) return null;
  // Il prezzo medio delle soste: quelle con un prezzo; le altre al prezzo di
  // riserva.
  final conPrezzo = soste.where((r) => r.euro != null);
  final kwhConPrezzo = conPrezzo.fold(0.0, (s, r) => s + r.kwh);
  final double? prezzoSoste =
      kwhConPrezzo > 0 ? conPrezzo.fold(0.0, (s, r) => s + r.euro!) / kwhConPrezzo : euroAlKwhDiRiserva;
  if (prezzoSoste == null && dalleSoste > 0) return null;
  return CostoDellEnergia(
    kwhDaCasa: daCasa,
    euroCasa: daCasa * (prezzoCasa ?? 0),
    origine: origine,
    euroAlKwhCasa: switch (origine) {
      PrezzoDiPartenza.ricarica => null,
      PrezzoDiPartenza.tariffa => tariffa,
      PrezzoDiPartenza.opzioni => euroAlKwhDiRiserva,
    },
    quotaSole: origine == PrezzoDiPartenza.opzioni ? null : sole,
    kwhDalleSoste: dalleSoste,
    euroSoste: dalleSoste * (prezzoSoste ?? 0),
    sosteStimate: soste.any((r) => r.stimata),
  );
}
