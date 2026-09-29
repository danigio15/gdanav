import 'dart:math' as math;

import '../geo/geo.dart';
import '../percorso/valhalla.dart';
import 'ztl.dart';

/// Un percorso fra le tappe, lontano dai rettangoli.
typedef PercorsoEvitando = Future<PercorsoCalcolato> Function(List<Punto> tappe, List<Rettangolo> evita);

/// Più percorsi fra due punti, lontani dai rettangoli.
typedef AlternativeEvitando = Future<List<PercorsoCalcolato>> Function(Punto da, Punto a, List<Rettangolo> evita);

/// I percorsi che sanno delle ZTL.
///
/// TomTom le ZTL non le conosce. Allora si fa così: il percorso si chiede
/// com'è, e si guarda in quali ZTL entra. Quelle attive quando ci si
/// arriverebbe, senza il permesso — o di cui ancora non si sa, che è la
/// scelta che non costa una multa — si girano al largo: si richiede il
/// percorso con le «aree da evitare», i rettangoli che le coprono (dieci al
/// massimo per richiesta). Il nuovo percorso si riguarda, perché girando al
/// largo si può finire in un'altra; al terzo giro ci si ferma.
///
/// Se la meta è dentro una ZTL senza permesso non la si può girare al
/// largo: il percorso arriva al varco, l'ultimo punto fuori sulla strada
/// che ci entra, e lo dice.
///
/// Da dove si parte non conta: chi è già dentro esce e basta.
class PercorsiConZtl {
  PercorsiConZtl({
    required this.zone,
    required this.permessi,
    required this.calcola,
    this.alternative,
    DateTime Function()? adesso,
  }) : _adesso = adesso ?? DateTime.now;

  /// L'archivio delle ZTL (si legge una volta, dall'app).
  final Future<ArchivioZtl> Function() zone;

  /// I permessi risposti: [ZonaLimitata.chiave] → `true` ce l'ho, `false`
  /// no. Chi manca non ha ancora risposto.
  final Future<Map<String, bool>> Function() permessi;

  final PercorsoEvitando calcola;
  final AlternativeEvitando? alternative;
  final DateTime Function() _adesso;

  /// TomTom non ne vuole più di tanti in una richiesta.
  static const massimoRettangoli = 10;

  /// Quante volte si riguarda il percorso nuovo.
  static const giri = 3;

  /// Quanto prima della ZTL si ferma il varco: abbastanza da non finire,
  /// agganciandosi alla strada, già dentro.
  static const primaDelVarcoM = 40.0;

  /// Il percorso fra le [tappe].
  Future<PercorsoCalcolato> percorso(List<Punto> tappe) async {
    final libero = await calcola(tappe, const []);
    final fuori = await _rispetta(tappe, [libero], (t, r) async => [await calcola(t, r)]);
    return fuori.first;
  }

  /// Le strade fra cui scegliere da [da] ad [a], la migliore per prima.
  Future<List<PercorsoCalcolato>> scelte(Punto da, Punto a) async {
    final altre = alternative;
    if (altre == null) {
      return [
        await percorso([da, a]),
      ];
    }
    final liberi = await altre(da, a, const []);
    if (liberi.isEmpty) return liberi;
    return _rispetta(
        [da, a], liberi, (t, r) => t.length == 2 ? altre(t.first, t.last, r) : calcola(t, r).then((p) => [p]));
  }

  Future<List<PercorsoCalcolato>> _rispetta(
    List<Punto> tappe,
    List<PercorsoCalcolato> liberi,
    Future<List<PercorsoCalcolato>> Function(List<Punto> tappe, List<Rettangolo> evita) rifai,
  ) async {
    final ArchivioZtl archivio;
    try {
      archivio = await zone();
    } catch (_) {
      return liberi;
    }
    if (archivio.zone.isEmpty) return liberi;
    final permesso = await permessi();
    final ora = _adesso();
    final libero = liberi.first;

    final daEvitare = <String, ZonaLimitata>{};
    ZonaLimitata? daChiedere;
    ZonaLimitata? metaDentro;
    Punto? varco;
    var tappeOra = tappe;
    var risultato = liberi;
    var giro = libero;
    for (var n = 0; n < giri; n++) {
      final nuove = _daEvitare(archivio, giro, ora, permesso).where((i) => !daEvitare.containsKey(i.zona.id)).toList();
      if (nuove.isEmpty) break;
      for (final i in nuove) {
        daEvitare[i.zona.id] = i.zona;
        if (n == 0 && daChiedere == null && !permesso.containsKey(i.zona.chiave)) daChiedere = i.zona;
        if (metaDentro == null && i.zona.contiene(tappeOra.last)) {
          metaDentro = i.zona;
          varco = _varco(giro, i.indice);
          tappeOra = [...tappeOra.take(tappeOra.length - 1), varco];
        }
      }
      final rettangoli = _copertura([
        for (final z in daEvitare.values)
          if (z != metaDentro) z,
      ], tappeOra);
      try {
        final rifatti = await rifai(tappeOra, rettangoli);
        if (rifatti.isEmpty) break;
        risultato = rifatti;
        giro = rifatti.first;
      } on ErrorePercorso {
        // TomTom non ci è riuscito con quei rettangoli: si resta col
        // percorso di prima, e si dice da quali ZTL passa.
        break;
      }
    }

    // Cosa fa davvero il percorso finale.
    final attraversate = <ZonaLimitata>[];
    final nonEvitate = <ZonaLimitata>[];
    for (final i in archivio.ztlSulPercorso(giro.punti)) {
      if (!i.zona.attivaAlle(_quando(giro, i.indice, ora))) continue;
      if (permesso[i.zona.chiave] == true) {
        attraversate.add(i.zona);
      } else if (i.zona != metaDentro) {
        nonEvitate.add(i.zona);
      }
    }
    final info = ZtlDelViaggio(
      evitate: [
        for (final z in daEvitare.values)
          if (z != metaDentro && !nonEvitate.contains(z)) z,
      ],
      attraversate: attraversate,
      daChiedere: daChiedere,
      puntiPassandoci: daChiedere == null ? const [] : libero.punti,
      durataPassandoci: daChiedere == null ? null : libero.durata,
      metaDentro: metaDentro,
      varco: varco,
      nonEvitate: nonEvitate,
      pedonali: archivio.pedonaliLungo(giro.punti),
    );
    return [for (final p in risultato) p.conZtl(info)];
  }

  /// Le ZTL in cui [p] entra, attive quando ci arriva e senza permesso: per
  /// scartare una strada proposta in guida che ci passerebbe. Quella dove
  /// arriva non conta: lì si ferma al varco.
  static List<ZonaLimitata> vietate(
    ArchivioZtl archivio,
    PercorsoCalcolato p,
    DateTime ora,
    Map<String, bool> permesso,
  ) =>
      [
        for (final i in _daEvitare(archivio, p, ora, permesso))
          if (p.punti.isEmpty || !i.zona.contiene(p.punti.last)) i.zona,
      ];

  /// I rettangoli da evitare per [zone], come per il percorso: per chiedere
  /// a TomTom le strade migliori senza che ci rientrino.
  static List<Rettangolo> rettangoli(List<ZonaLimitata> zone, List<Punto> tappe) => _copertura(zone, tappe);

  /// Le ZTL in cui entra [p], attive quando ci si arriva e senza permesso.
  static List<IngressoZtl> _daEvitare(
          ArchivioZtl archivio, PercorsoCalcolato p, DateTime ora, Map<String, bool> permesso) =>
      [
        for (final i in archivio.ztlSulPercorso(p.punti))
          if (permesso[i.zona.chiave] != true && i.zona.attivaAlle(_quando(p, i.indice, ora))) i,
      ];

  /// Quando si arriva al punto [indice] di [p], partendo a [ora]: la ZTL deve
  /// essere attiva allora, non adesso.
  static DateTime _quando(PercorsoCalcolato p, int indice, DateTime ora) {
    if (p.punti.length < 2) return ora;
    final linea = Linea(p.punti);
    final parte = linea.lunghezzaM > 0 ? linea.cumulate[indice.clamp(0, p.punti.length - 1)] / linea.lunghezzaM : 0.0;
    return ora.add(Duration(seconds: (p.durata.inSeconds * parte).round()));
  }

  /// Il varco: sul percorso che entra nella ZTL, [primaDelVarcoM] metri
  /// prima del primo punto dentro.
  static Punto _varco(PercorsoCalcolato p, int indice) {
    final linea = Linea(p.punti);
    final dentro = indice.clamp(1, p.punti.length - 1);
    final metri = math.max(0.0, linea.cumulate[dentro] - primaDelVarcoM);
    var i = dentro;
    while (i > 0 && linea.cumulate[i] > metri) {
      i--;
    }
    return p.punti[i];
  }

  /// I rettangoli per [zone], al massimo [massimoRettangoli] in tutto:
  /// divisi fra le zone, più strisce a chi ne ha di più da dare. Quelli che
  /// prenderebbero dentro una tappa si lasciano: da una tappa si deve poter
  /// partire e arrivare, e il percorso rifatto dice se è bastato.
  static List<Rettangolo> _copertura(List<ZonaLimitata> zone, List<Punto> tappe) {
    if (zone.isEmpty) return const [];
    final prese = zone.take(massimoRettangoli).toList();
    final ognuna = (massimoRettangoli ~/ prese.length).clamp(1, 4);
    return [
      for (final z in prese)
        for (final r in z.copertura(quanti: ognuna))
          if (!tappe.any(r.contiene)) r,
    ].take(massimoRettangoli).toList();
  }
}
