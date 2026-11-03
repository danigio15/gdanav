import 'dart:async';

import 'package:gdanav_core/gdanav_core.dart';

import '../servizi.dart';
import 'gestore_auto.dart';
import 'gestore_guida.dart';
import 'gestore_viaggio.dart';
import 'prova_di_guida.dart';

/// La dimostrazione per le foto dello schermo dell'auto (Android Auto e
/// CarPlay) fatte dalla CI: un viaggio finto di 40 km con le code, la guida
/// che parte da sola e una posizione finta che va avanti piano.
///
/// Si accende solo alla compilazione, con
/// `--dart-define=GDANAV_DIMOSTRAZIONE=traffico7` (una coda, +7 min) o
/// `traffico18` (due code, +18 min). Senza, [Dimostrazione.daCompilazione] è
/// `null` e l'app è quella di sempre: niente di questo file entra in gioco.
enum Dimostrazione {
  /// Una coda fra il km 5 e il 12: +7 minuti.
  traffico7,

  /// Due code: fra il km 4 e il 9 (+8 minuti, ferma) e fra il 20 e il 26
  /// (+10): +18 minuti.
  traffico18;

  /// Quella chiesta alla compilazione, o `null`.
  static Dimostrazione? get daCompilazione => daNome(Servizi.dimostrazione);

  static Dimostrazione? daNome(String nome) => values.where((d) => d.name == nome.trim()).firstOrNull;

  /// Dove comincia la strada (la A1 verso nord, da Orte).
  static const partenza = Punto(42.46, 12.39);

  /// Lunga [lunghezzaKm], dritta verso nord.
  static const lunghezzaKm = 40;

  /// La meta, in fondo alla strada.
  Luogo get meta =>
      Luogo(nome: 'Orvieto', descrizione: 'Umbria', posizione: Punto(partenza.lat + lunghezzaKm * 0.009, partenza.lon));

  /// Le code di questa dimostrazione, in metri dall'inizio.
  List<Coda> get code => switch (this) {
    traffico7 => const [Coda(daM: 5000, aM: 12000, ritardo: Duration(minutes: 7), livello: 2)],
    traffico18 => const [
      Coda(daM: 4000, aM: 9000, ritardo: Duration(minutes: 8), livello: 3),
      Coda(daM: 20000, aM: 26000, ritardo: Duration(minutes: 10), livello: 2),
    ],
  };

  /// La strada senza traffico: un punto ogni chilometro, a 120 km/h, con
  /// una manovra all'inizio, l'uscita al km 34 e l'arrivo.
  static PercorsoCalcolato strada() {
    final punti = [for (var i = 0; i <= lunghezzaKm; i++) Punto(partenza.lat + i * 0.009, partenza.lon)];
    final linea = Linea(punti);
    final tratti = [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 120),
    ];
    double metri(int da, int a) => linea.cumulate[a] - linea.cumulate[da];
    double secondi(int da, int a) => metri(da, a) / (120 / 3.6);
    const uscita = 34;
    return PercorsoCalcolato(
      punti: punti,
      tratti: tratti,
      manovre: [
        Manovra(
          istruzione: 'Continua sulla A1 verso Firenze',
          tipo: 8,
          strada: 'A1',
          verso: 'A1 · Firenze',
          lunghezzaM: metri(0, uscita),
          secondi: secondi(0, uscita),
          inizio: 0,
        ),
        Manovra(
          istruzione: 'Prendi l\'uscita Orvieto',
          tipo: 20,
          verso: 'Orvieto',
          lunghezzaM: metri(uscita, lunghezzaKm),
          secondi: secondi(uscita, lunghezzaKm),
          inizio: uscita,
        ),
        Manovra(istruzione: 'Sei arrivato', tipo: 4, lunghezzaM: 0, secondi: 0, inizio: lunghezzaKm),
      ],
      limiti: [for (var i = 0; i < lunghezzaKm; i++) 130],
      conAutostrade: true,
    );
  }

  /// La strada con le code di questa dimostrazione.
  PercorsoCalcolato percorso() => strada().conTraffico(code);

  /// Il pianificatore finto: torna sempre [percorso], senza chiedere niente
  /// a nessuno.
  CostruisciPianificatore get pianificatore =>
      (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (_) async => percorso(),
        colonnine: const _NessunaColonnina(),
        profilo: profilo,
        preferenze: preferenze,
      );

  /// Dove si è all'inizio: due chilometri dopo la partenza, prima delle code.
  Future<Punto?> posizione() async => ProvaDiGuida.puntoA(Linea(strada().punti), 2000).$1;

  /// Quanto più lenta del vero va la posizione finta: a 120 km/h fa 6 km/h,
  /// così le foto trovano le code dove devono essere.
  static const acceleratore = 0.05;

  /// Parte: auto termica (niente soste da chiedere), il viaggio verso
  /// [meta], la guida e la posizione finta sulla strada.
  Future<void> avvia({
    required GestoreAuto auto,
    required GestoreViaggio viaggio,
    required GestoreGuida guida,
    required ProvaDiGuida prova,
  }) async {
    // Solo in memoria: l'archivio del telefono resta com'era.
    auto.elettrica = false;
    viaggio.trafficoFinto = (_) async => percorso();
    await viaggio.vaiA(meta);
    if (viaggio.stato is! ViaggioPronto) return;
    guida.avvia();
    prova.percorri(percorso(), daM: 2000);
  }
}

class _NessunaColonnina implements FonteColonnine {
  const _NessunaColonnina();

  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async => const [];
}
