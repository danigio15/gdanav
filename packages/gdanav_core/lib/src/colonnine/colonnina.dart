import '../geo/geo.dart';

enum TipoConnettore { ccs2, chademo, tipo2, tesla, altro }

enum StatoPresa { disponibile, occupata, fuoriServizio, sconosciuto }

class Connettore {
  const Connettore({required this.tipo, required this.potenzaKw, this.stato = StatoPresa.sconosciuto});

  final TipoConnettore tipo;
  final double potenzaKw;
  final StatoPresa stato;

  Connettore conStato(StatoPresa s) => Connettore(tipo: tipo, potenzaKw: potenzaKw, stato: s);
}

/// Quante prese adatte a un'auto sono libere adesso.
class Disponibilita {
  const Disponibilita({this.libere = 0, this.occupate = 0, this.guaste = 0, this.totali = 0});

  final int libere;
  final int occupate;
  final int guaste;

  /// Le prese compatibili, comprese quelle di cui non si sa lo stato.
  final int totali;

  /// `true` se almeno una presa dice come sta.
  bool get nota => libere + occupate + guaste > 0;

  /// Tutte le prese funzionanti sono occupate: si rischia di aspettare.
  bool get piena => libere == 0 && occupate > 0;

  /// Tutte le prese sono guaste: non ci si ricarica.
  bool get guasta => totali > 0 && guaste == totali;

  static const sconosciuta = Disponibilita();
}

/// Un punto di ricarica, da qualunque fonte arrivi.
class Colonnina {
  const Colonnina({
    required this.id,
    required this.nome,
    required this.posizione,
    required this.connettori,
    this.operatore,
    this.fonte = '',
  });

  final String id;
  final String nome;
  final Punto posizione;
  final List<Connettore> connettori;
  final String? operatore;

  /// `ocm`, `ocpi`…: per citare la fonte, come chiedono le licenze.
  final String fonte;

  /// La potenza massima fra le prese che l'auto può usare, anche guaste:
  /// quella di targa.
  double potenzaNominalePer(Set<TipoConnettore> compatibili) {
    var massima = 0.0;
    for (final c in connettori) {
      if (compatibili.contains(c.tipo) && c.potenzaKw > massima) massima = c.potenzaKw;
    }
    return massima;
  }

  /// La potenza massima fra le prese che l'auto può usare e che non sono
  /// guaste. 0 se nessuna va bene.
  double potenzaPer(Set<TipoConnettore> compatibili) {
    var massima = 0.0;
    for (final c in connettori) {
      if (compatibili.contains(c.tipo) && c.stato != StatoPresa.fuoriServizio && c.potenzaKw > massima) {
        massima = c.potenzaKw;
      }
    }
    return massima;
  }

  /// Contando solo le prese adatte all'auto e, con [minimaKw], solo quelle
  /// abbastanza potenti: una Tipo 2 libera non fa libera una colonnina rapida
  /// con tutte le CCS occupate.
  Disponibilita disponibilitaPer(Set<TipoConnettore> compatibili, {double minimaKw = 0}) {
    var libere = 0, occupate = 0, guaste = 0, totali = 0;
    for (final c in connettori.where((c) => compatibili.contains(c.tipo) && c.potenzaKw >= minimaKw)) {
      totali++;
      switch (c.stato) {
        case StatoPresa.disponibile:
          libere++;
        case StatoPresa.occupata:
          occupate++;
        case StatoPresa.fuoriServizio:
          guaste++;
        case StatoPresa.sconosciuto:
          break;
      }
    }
    return Disponibilita(libere: libere, occupate: occupate, guaste: guaste, totali: totali);
  }

  /// `true` se tutte le prese compatibili sono occupate adesso.
  bool tuttaOccupata(Set<TipoConnettore> compatibili) {
    final utili = connettori.where((c) => compatibili.contains(c.tipo) && c.stato != StatoPresa.fuoriServizio);
    return utili.isNotEmpty && utili.every((c) => c.stato == StatoPresa.occupata);
  }
}

/// Da dove si prendono le colonnine.
abstract interface class FonteColonnine {
  /// Le colonnine entro [distanzaKm] dal percorso.
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3});
}
