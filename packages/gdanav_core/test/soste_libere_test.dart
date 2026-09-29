import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// «Nel calcolo del percorso devi vedere quelle libere e in servizio.» Con
/// lo stato di tutta Italia il pianificatore lo sa per ogni colonnina: salta
/// le guaste, conta l'attesa alle piene, e fra due vicine prende quella che
/// si sa libera.
void main() {
  ColonninaSulPercorso sosta(String id, double km, Disponibilita d, {double kw = 150}) =>
      ColonninaSulPercorso(id: id, nome: id, distanzaM: km * 1000, potenzaKw: kw, disponibilita: d);

  test('fra due colonnine vicine vince quella che si sa libera, anche se più lenta', () {
    final ignota = sosta('ignota', 100, Disponibilita.sconosciuta, kw: 300);
    final libera = sosta('libera', 100.4, const Disponibilita(libere: 2, occupate: 1, totali: 4));
    expect(PianificatoreSoste.candidate([ignota, libera]).map((c) => c.id), ['libera']);
    final piena = sosta('piena', 100.2, const Disponibilita(occupate: 4, totali: 4), kw: 350);
    expect(PianificatoreSoste.candidate([piena, ignota]).map((c) => c.id), ['ignota']);
    final guasta = sosta('guasta', 100.1, const Disponibilita(guaste: 2, totali: 2), kw: 350);
    expect(PianificatoreSoste.candidate([guasta, piena]).map((c) => c.id), ['piena']);
    // Lontane più di un chilometro restano tutte e due: le sceglie il viaggio.
    expect(PianificatoreSoste.candidate([ignota, sosta('altra', 110, Disponibilita.sconosciuta)]), hasLength(2));
  });
}
