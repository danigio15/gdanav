import 'dart:isolate';

import '../colonnine/colonnina.dart';
import '../colonnine/disponibilita_tomtom.dart';
import '../colonnine/lungo_percorso.dart';
import '../geo/geo.dart';
import '../motore/modello_consumo.dart';
import '../motore/pianificatore_soste.dart';
import '../percorso/valhalla.dart';
import '../veicolo/profilo_veicolo.dart';

/// Il viaggio completo: percorso, colonnine lungo la strada, soste.
class Viaggio {
  const Viaggio({required this.percorso, required this.colonnine, required this.piano});

  final PercorsoCalcolato percorso;

  /// Tutte quelle utili, per mostrarle sulla mappa.
  final List<ColonninaSulPercorso> colonnine;

  /// `null` se non si arriva nemmeno fermandosi.
  final PianoViaggio? piano;
}

/// Come si preferisce ricaricare. Si sceglie nelle impostazioni.
class PreferenzeRicarica {
  const PreferenzeRicarica({
    this.minimoArrivo = 15,
    this.minimoSosta = 10,
    this.massimoRicarica = 80,
    this.potenzaMinimaKw = 50,
    this.evitaOccupate = true,
  });

  factory PreferenzeRicarica.daJson(Map<String, Object?> j) {
    const d = PreferenzeRicarica();
    double n(String k, double v) => (j[k] as num?)?.toDouble() ?? v;
    return PreferenzeRicarica(
      minimoArrivo: n('minimo_arrivo', d.minimoArrivo),
      minimoSosta: n('minimo_sosta', d.minimoSosta),
      massimoRicarica: n('massimo_ricarica', d.massimoRicarica),
      potenzaMinimaKw: n('potenza_minima_kw', d.potenzaMinimaKw),
      evitaOccupate: j['evita_occupate'] as bool? ?? d.evitaOccupate,
    );
  }

  /// Batteria con cui arrivare a destinazione.
  final double minimoArrivo;

  /// Batteria con cui arrivare a una colonnina.
  final double minimoSosta;

  /// Fin dove ricaricare alle soste: oltre, la ricarica rapida rallenta.
  final double massimoRicarica;

  /// Le colonnine più lente non si propongono come soste.
  final double potenzaMinimaKw;

  /// Mette in conto un'attesa alle colonnine tutte occupate adesso, così si
  /// preferiscono quelle libere.
  final bool evitaOccupate;

  PreferenzeRicarica copia({
    double? minimoArrivo,
    double? minimoSosta,
    double? massimoRicarica,
    double? potenzaMinimaKw,
    bool? evitaOccupate,
  }) => PreferenzeRicarica(
    minimoArrivo: minimoArrivo ?? this.minimoArrivo,
    minimoSosta: minimoSosta ?? this.minimoSosta,
    massimoRicarica: massimoRicarica ?? this.massimoRicarica,
    potenzaMinimaKw: potenzaMinimaKw ?? this.potenzaMinimaKw,
    evitaOccupate: evitaOccupate ?? this.evitaOccupate,
  );

  Map<String, Object?> toJson() => {
    'minimo_arrivo': minimoArrivo,
    'minimo_sosta': minimoSosta,
    'massimo_ricarica': massimoRicarica,
    'potenza_minima_kw': potenzaMinimaKw,
    'evita_occupate': evitaOccupate,
  };
}

/// A che punto è il calcolo, per dirlo a chi aspetta.
enum FaseViaggio { percorso, colonnine, soste }

/// Mette insieme Valhalla, le colonnine e il pianificatore delle soste.
class PianificatoreViaggio {
  PianificatoreViaggio({
    required this.percorsi,
    required this.colonnine,
    required this.profilo,
    this.preferenze = const PreferenzeRicarica(),
    this.disponibilita,
    this.traffico,
    this.alternative,
    this.seguendo,
  });

  final Future<PercorsoCalcolato> Function(List<Punto> tappe) percorsi;
  final FonteColonnine colonnine;
  final ProfiloVeicolo profilo;
  final PreferenzeRicarica preferenze;

  /// Lo stato delle prese in tempo reale, per controllare le soste.
  final FonteDisponibilita? disponibilita;

  /// Il traffico di adesso sul percorso (Premium): tempi e consumi con le
  /// code. Se non risponde si pianifica senza.
  final Future<PercorsoCalcolato> Function(PercorsoCalcolato percorso)? traffico;

  /// Più percorsi fra due punti, per scegliere (senza corsie né limiti).
  final Future<List<PercorsoCalcolato>> Function(Punto da, Punto a)? alternative;

  /// Quello scelto fra le [alternative], rifatto con corsie e limiti.
  final Future<PercorsoCalcolato> Function(PercorsoCalcolato scelto)? seguendo;

  /// I percorsi fra cui scegliere, ognuno col traffico se c'è: il primo è
  /// il migliore. Senza [alternative], quello solo.
  Future<List<PercorsoCalcolato>> scelte({required Punto partenza, required Punto arrivo}) async {
    final a = alternative;
    final trovati = a == null
        ? [
            await percorsi([partenza, arrivo]),
          ]
        : await a(partenza, arrivo);
    final t = traffico;
    if (t == null) return trovati;
    final conTraffico = await Future.wait([
      for (final p in trovati) t(p).timeout(const Duration(seconds: 25)).catchError((Object _) => p),
    ]);
    // Col traffico il migliore può cambiare.
    return conTraffico..sort((x, y) => x.durata.compareTo(y.durata));
  }

  /// Il percorso da [partenza] ad [arrivo] passando dalle [tappe], col
  /// traffico se c'è. [scelto]: un percorso già calcolato da usare (una
  /// delle alternative), senza richiederlo.
  Future<PercorsoCalcolato> percorso({
    required Punto partenza,
    required Punto arrivo,
    List<Punto> tappe = const [],
    PercorsoCalcolato? scelto,
  }) async {
    var p = scelto ?? await percorsi([partenza, ...tappe, arrivo]);
    // Uno scelto fra le alternative si rifà con corsie e limiti; il
    // traffico già letto resta.
    if (scelto != null && seguendo != null) {
      try {
        final rifatto = await seguendo!(scelto);
        p = scelto.trafficoVero ? rifatto.conTraffico(_riporta(scelto, rifatto)) : rifatto;
      } catch (_) {}
    }
    final t = traffico;
    if (t == null || p.trafficoVero) return p;
    try {
      return await t(p).timeout(const Duration(seconds: 25));
    } catch (_) {
      return p;
    }
  }

  /// Le code di [da] sui metri di [a] (lo stesso percorso rifatto).
  static List<Coda> _riporta(PercorsoCalcolato da, PercorsoCalcolato a) {
    final k = Linea(da.punti).lunghezzaM;
    final l = Linea(a.punti).lunghezzaM;
    final f = k > 0 ? l / k : 1.0;
    return [
      for (final c in da.code)
        Coda(
          daM: c.daM * f,
          aM: c.aM * f,
          ritardo: c.ritardo,
          livello: c.livello,
          velocitaKmh: c.velocitaKmh,
          tipo: c.tipo,
        ),
    ];
  }

  /// [obbligate]: gli id delle colonnine dove l'utente vuole fermarsi.
  /// [tappe]: dove passare prima dell'[arrivo], in ordine; le soste si
  /// pianificano sul viaggio intero.
  Future<Viaggio> pianifica({
    required Punto partenza,
    required Punto arrivo,
    required double batteria,
    List<Punto> tappe = const [],
    PercorsoCalcolato? scelto,
    Condizioni condizioni = const Condizioni(),
    Set<String> obbligate = const {},
    void Function(FaseViaggio fase)? avanzamento,
  }) async {
    avanzamento?.call(FaseViaggio.percorso);
    final percorso = await this.percorso(partenza: partenza, arrivo: arrivo, tappe: tappe, scelto: scelto);
    final p = preferenze;
    final pianificatore = PianificatoreSoste(
      profilo: profilo,
      condizioni: condizioni,
      minimoArrivo: p.minimoArrivo,
      minimoSosta: p.minimoSosta,
      massimoRicarica: p.massimoRicarica,
      attesaSeOccupata: p.evitaOccupate ? const Duration(minutes: 15) : Duration.zero,
    );
    final senzaSoste = obbligate.isEmpty
        ? pianificatore.pianifica(percorso: percorso.tratti, batteriaPartenza: batteria, colonnine: const [])
        : null;

    // Le colonnine si chiedono sempre, anche quando non servono: sulla mappa
    // si vedono lungo la strada, e se ne può scegliere una. Ma se il servizio
    // non risponde e la batteria basta, il viaggio si fa lo stesso.
    avanzamento?.call(FaseViaggio.colonnine);
    List<Colonnina> trovate;
    try {
      trovate = await colonnine.lungo(percorso.punti);
    } catch (_) {
      if (senzaSoste == null) rethrow;
      trovate = const [];
    }
    // Proiettare migliaia di colonnine e cercare le soste è lavoro pesante:
    // si fa su un altro filo, così l'interfaccia non si blocca.
    avanzamento?.call(FaseViaggio.soste);
    final prese = profilo.connettori;
    Future<(List<ColonninaSulPercorso>, PianoViaggio?)> calcola(List<Colonnina> tutte) => Isolate.run(() {
      final vicine = colonnineSulPercorso(
        Linea(percorso.punti),
        tutte,
        compatibili: prese,
        potenzaMinimaKw: p.potenzaMinimaKw,
        obbligate: obbligate,
      );
      return (
        vicine,
        senzaSoste ?? pianificatore.pianifica(percorso: percorso.tratti, batteriaPartenza: batteria, colonnine: vicine),
      );
    });
    var (vicine, piano) = await calcola(trovate);

    // Come ABRP: le soste scelte si controllano adesso (libere, occupate,
    // guaste); se una è piena o guasta si ripianifica, e si ricontrollano
    // le nuove. Due giri al massimo.
    final fonte = disponibilita;
    if (fonte != null) {
      final controllate = <String>{};
      for (var giro = 0; giro < 2 && piano != null; giro++) {
        final daControllare = [
          for (final s in piano.soste)
            if (s.colonnina.dettaglio case final c? when controllate.add(c.id)) c,
        ];
        if (daControllare.isEmpty) break;
        final aggiornate = await Future.wait([
          for (final c in daControllare) fonte.aggiorna(c).timeout(const Duration(seconds: 15)).catchError((_) => c),
        ]);
        final perId = {for (final c in aggiornate) c.id: c};
        trovate = [for (final c in trovate) perId[c.id] ?? c];
        final cambiata = aggiornate.any((c) {
          final d = c.disponibilitaPer(prese, minimaKw: p.potenzaMinimaKw);
          return d.piena || d.guasta;
        });
        (vicine, piano) = await calcola(trovate);
        if (!cambiata) break;
      }
    }
    return Viaggio(percorso: percorso, colonnine: vicine, piano: piano);
  }
}
