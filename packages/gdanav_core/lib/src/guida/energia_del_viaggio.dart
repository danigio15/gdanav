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

  /// Se si è partiti con questa carica: finita da poco (tre giorni) e la
  /// batteria alla partenza vicina a dove la ricarica l'ha lasciata.
  bool valePer({required DateTime partenza, double? batteriaPartenza}) {
    final da = partenza.difference(finitaIl);
    if (da.isNegative || da > const Duration(days: 3)) return false;
    final a = socA;
    if (a == null || batteriaPartenza == null) return true;
    return (a - batteriaPartenza).abs() <= 15;
  }
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
    required this.prezzoCasaVero,
    required this.kwhDalleSoste,
    required this.euroSoste,
    required this.sosteStimate,
    this.quotaSole,
  });

  final double kwhDaCasa, euroCasa;

  /// Vero se il prezzo di casa viene dall'ultima ricarica, e non dalle opzioni.
  final bool prezzoCasaVero;

  /// La parte dal sole dell'energia di casa, se si sa.
  final double? quotaSole;

  final double kwhDalleSoste, euroSoste;

  /// Vero se almeno una sosta non è stata detta da chi guida.
  final bool sosteStimate;

  double get totale => euroCasa + euroSoste;
}

/// Il conto: [consumatiKwh] in tutto, partiti con [partenzaKwh] nella
/// batteria; [casa] l'ultima ricarica a casa (`null` se non vale), [soste]
/// quelle fatte per strada. [euroAlKwhDiRiserva]: il prezzo delle opzioni,
/// per quello che non si sa.
CostoDellEnergia? costoDellEnergia({
  required double consumatiKwh,
  double? partenzaKwh,
  RicaricaDiCasa? casa,
  List<RicaricaInViaggio> soste = const [],
  double? euroAlKwhDiRiserva,
}) {
  if (!(consumatiKwh > 0)) return null;
  final presiPerStrada = soste.fold(0.0, (s, r) => s + r.kwh);
  final daCasa = partenzaKwh == null
      ? (consumatiKwh - presiPerStrada).clamp(0.0, consumatiKwh)
      : consumatiKwh.clamp(0.0, partenzaKwh);
  final dalleSoste = consumatiKwh - daCasa;
  final prezzoCasa = casa?.euroAlKwh ?? euroAlKwhDiRiserva;
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
    prezzoCasaVero: casa?.euroAlKwh != null,
    quotaSole: casa?.euroAlKwh != null ? casa!.quotaSole : null,
    kwhDalleSoste: dalleSoste,
    euroSoste: dalleSoste * (prezzoSoste ?? 0),
    sosteStimate: soste.any((r) => r.stimata),
  );
}
