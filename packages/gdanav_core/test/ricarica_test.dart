import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  const p = ProfiloVeicolo.esempio;
  final lungo = List.generate(450, (_) => const Tratto(lunghezzaM: 1000, velocitaKmh: 120));
  final corto = List.generate(80, (_) => const Tratto(lunghezzaM: 1000, velocitaKmh: 120));

  ColonninaSulPercorso c(
    int km, {
    double kw = 150,
    Disponibilita d = Disponibilita.sconosciuta,
    bool obbligata = false,
    String? id,
  }) =>
      ColonninaSulPercorso(
        id: id ?? 'c$km',
        nome: 'Area $km',
        distanzaM: km * 1000.0,
        potenzaKw: kw,
        disponibilita: d,
        obbligata: obbligata,
      );

  group('soste scelte dall\'utente', () {
    final pianificatore = PianificatoreSoste(profilo: p);

    test('ci si ferma anche se non servirebbe', () {
      final piano = pianificatore.pianifica(
        percorso: corto,
        batteriaPartenza: 90,
        colonnine: [c(40, obbligata: true)],
      )!;
      expect(piano.soste.single.colonnina.id, 'c40');
    });

    test('non si salta una sosta obbligata, anche se ce n\'è una migliore dopo', () {
      final piano = pianificatore.pianifica(
        percorso: lungo,
        batteriaPartenza: 90,
        colonnine: [c(100, obbligata: true), for (var km = 150; km < 450; km += 50) c(km)],
      )!;
      expect(piano.soste.first.colonnina.id, 'c100');
      expect(piano.batteriaArrivo, greaterThanOrEqualTo(15));
    });
  });

  group('colonnine piene', () {
    test('a parità di posizione si preferisce quella libera', () {
      final pianificatore = PianificatoreSoste(profilo: p);
      final piano = pianificatore.pianifica(
        percorso: lungo,
        batteriaPartenza: 90,
        colonnine: [
          for (var km = 50; km < 450; km += 50) ...[
            c(km, id: 'piena$km', d: const Disponibilita(occupate: 4, totali: 4)),
            c(km + 1, id: 'libera$km', d: const Disponibilita(libere: 2, occupate: 2, totali: 4)),
          ],
        ],
      )!;
      expect(piano.soste, isNotEmpty);
      expect(piano.soste.every((s) => s.colonnina.id.startsWith('libera')), isTrue);
    });

    test("senza l'attesa in conto, una piena vale come le altre", () {
      final pianificatore = PianificatoreSoste(profilo: p, attesaSeOccupata: Duration.zero);
      final piano = pianificatore.pianifica(
        percorso: lungo,
        batteriaPartenza: 90,
        colonnine: [for (var km = 50; km < 450; km += 50) c(km, d: const Disponibilita(occupate: 4, totali: 4))],
      )!;
      expect(piano.soste, isNotEmpty);
    });

    test('la disponibilità si conta sulle prese adatte all\'auto', () {
      const col = Colonnina(
        id: 'x',
        nome: 'x',
        posizione: Punto(45, 9),
        connettori: [
          Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150, stato: StatoPresa.occupata),
          Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150, stato: StatoPresa.fuoriServizio),
          Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150),
          Connettore(tipo: TipoConnettore.chademo, potenzaKw: 50, stato: StatoPresa.disponibile),
        ],
      );
      final d = col.disponibilitaPer({TipoConnettore.ccs2});
      expect((d.libere, d.occupate, d.guaste, d.totali), (0, 1, 1, 3));
      expect(d.piena, isTrue);
      expect(d.nota, isTrue);
      expect(Disponibilita.sconosciuta.nota, isFalse);
    });
  });

  group('grafico della batteria', () {
    final piano = PianificatoreSoste(profilo: p).pianifica(
      percorso: lungo,
      batteriaPartenza: 90,
      colonnine: [for (var km = 50; km < 450; km += 50) c(km)],
    )!;
    final g = piano.profiloBatteria;

    test('parte dalla partenza e finisce all\'arrivo', () {
      expect(g.first.km, 0);
      expect(g.first.batteria, 90);
      expect(g.last.km, closeTo(450, 1e-6));
      expect(g.last.batteria, piano.batteriaArrivo);
    });

    test('scende guidando e sale solo alle soste', () {
      final kmSoste = piano.soste.map((s) => s.colonnina.distanzaM / 1000).toSet();
      for (var i = 1; i < g.length; i++) {
        if (g[i].batteria > g[i - 1].batteria + 1e-9) {
          expect(kmSoste, contains(g[i].km));
          expect(g[i].km, g[i - 1].km);
        }
      }
    });

    test('energia e ricarica totali', () {
      expect(piano.energiaKwh, closeTo(consumoMedioWhKm(lungo, p) * 450 / 1000, 1e-6));
      expect(piano.ricarica, piano.soste.fold(Duration.zero, (t, s) => t + s.ricarica));
    });
  });

  group('catalogo', () {
    test('id unici, valori sensati', () {
      final id = catalogoVeicoli.map((v) => v.id).toSet();
      expect(id, hasLength(catalogoVeicoli.length));
      for (final v in catalogoVeicoli) {
        expect(v.capacitaUtileKwh, inInclusiveRange(20, 120), reason: v.nome);
        expect(v.massaKg, inInclusiveRange(900, 3000), reason: v.nome);
        expect(v.piccoDcKw, inInclusiveRange(20, 400), reason: v.nome);
        expect(v.nome, '${v.marca} ${v.modello}');
      }
    });

    test('si ritrova per id', () {
      expect(veicoloPerId('tesla-model-3-lr')!.capacitaUtileKwh, 75);
      expect(veicoloPerId('esempio'), same(ProfiloVeicolo.esempio));
      expect(veicoloPerId('non-esiste'), isNull);
    });

    test('ogni auto del catalogo fa Milano–Bologna (215 km) con al più una sosta', () {
      final tratta = List.generate(215, (_) => const Tratto(lunghezzaM: 1000, velocitaKmh: 120));
      for (final v in catalogoVeicoli.where((v) => v.capacitaUtileKwh >= 40)) {
        final piano = PianificatoreSoste(profilo: v).pianifica(
          percorso: tratta,
          batteriaPartenza: 90,
          colonnine: [for (var km = 30; km < 215; km += 30) c(km)],
        );
        expect(piano, isNotNull, reason: v.nome);
        expect(piano!.soste.length, lessThanOrEqualTo(1), reason: v.nome);
      }
    });
  });

  test('le preferenze si salvano e si rileggono', () {
    const p = PreferenzeRicarica(minimoArrivo: 20, massimoRicarica: 85, potenzaMinimaKw: 100, evitaOccupate: false);
    final letto = PreferenzeRicarica.daJson(p.toJson());
    expect(letto.toJson(), p.toJson());
    expect(PreferenzeRicarica.daJson(const {}).toJson(), const PreferenzeRicarica().toJson());
  });
}
