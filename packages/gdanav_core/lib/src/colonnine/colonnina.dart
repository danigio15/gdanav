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
