import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  const p = ProfiloVeicolo.esempio;
  // 100 km di autostrada in piano.
  final autostrada = List.generate(100, (_) => const Tratto(lunghezzaM: 1000, velocitaKmh: 120));

  group('consumo', () {
    test('in autostrada a 120 km/h sta fra 160 e 230 Wh/km', () {
      expect(consumoMedioWhKm(autostrada, p), inInclusiveRange(160, 230));
    });

    test('più piano si va, meno si consuma', () {
      final lento = consumoMedioWhKm([const Tratto(lunghezzaM: 1000, velocitaKmh: 90)], p);
      final veloce = consumoMedioWhKm([const Tratto(lunghezzaM: 1000, velocitaKmh: 130)], p);
      expect(lento, lessThan(veloce));
    });

    test('in discesa ripida si recupera energia', () {
      const discesa = Tratto(lunghezzaM: 1000, velocitaKmh: 60, dislivelloM: -80);
      expect(energiaTrattoWh(discesa, p), isNegative);
    });

    test('salire e riscendere costa più che stare in piano', () {
      final piano = energiaTrattoWh(const Tratto(lunghezzaM: 2000, velocitaKmh: 80), p);
      final suEGiu =
          energiaTrattoWh(const Tratto(lunghezzaM: 1000, velocitaKmh: 80, dislivelloM: 50), p) +
          energiaTrattoWh(const Tratto(lunghezzaM: 1000, velocitaKmh: 80, dislivelloM: -50), p);
      expect(suEGiu, greaterThan(piano));
    });

    test('col freddo il clima pesa', () {
      final mite = consumoMedioWhKm(autostrada, p, Condizioni.daMeteo(temperaturaC: 20));
      final freddo = consumoMedioWhKm(autostrada, p, Condizioni.daMeteo(temperaturaC: -5));
      expect(freddo, greaterThan(mite));
    });

    test('la curva di ricarica si interpola', () {
      expect(p.potenzaRicaricaKw(10), 130);
      expect(p.potenzaRicaricaKw(75), closeTo(67.5, 1e-9));
      expect(p.potenzaRicaricaKw(100), 8);
    });
  });

  group('soste', () {
    final pianificatore = PianificatoreSoste(profilo: p);
    // 450 km: con 60 kWh non si fanno senza fermarsi.
    final lungo = List.generate(450, (_) => const Tratto(lunghezzaM: 1000, velocitaKmh: 120));
    final colonnine = [
      for (var km = 50; km < 450; km += 50)
        ColonninaSulPercorso(id: 'c$km', nome: 'Area $km', distanzaM: km * 1000.0, potenzaKw: 150, deviazioneM: 300),
    ];

    test('un viaggio corto non ha soste', () {
      final piano = pianificatore.pianifica(percorso: autostrada, batteriaPartenza: 90, colonnine: colonnine)!;
      expect(piano.soste, isEmpty);
      expect(piano.batteriaArrivo, greaterThanOrEqualTo(15));
    });

    test('un viaggio lungo si ferma e arriva sopra la soglia', () {
      final piano = pianificatore.pianifica(percorso: lungo, batteriaPartenza: 90, colonnine: colonnine)!;
      expect(piano.soste, isNotEmpty);
      expect(piano.batteriaArrivo, greaterThanOrEqualTo(15));
      for (final s in piano.soste) {
        expect(s.batteriaArrivo, greaterThanOrEqualTo(10));
        expect(s.batteriaPartenza, lessThanOrEqualTo(90));
        expect(s.batteriaPartenza, greaterThan(s.batteriaArrivo));
      }
      // Le soste vanno avanti, mai indietro.
      final km = piano.soste.map((s) => s.colonnina.distanzaM).toList();
      expect(km, orderedEquals([...km]..sort()));
    });

    test('senza colonnine un viaggio lungo non si fa', () {
      expect(pianificatore.pianifica(percorso: lungo, batteriaPartenza: 90, colonnine: const []), isNull);
    });

    test('una colonnina lenta allunga il viaggio', () {
      final veloci = pianificatore.pianifica(percorso: lungo, batteriaPartenza: 90, colonnine: colonnine)!;
      final lente = pianificatore.pianifica(
        percorso: lungo,
        batteriaPartenza: 90,
        colonnine: [
          for (final c in colonnine)
            ColonninaSulPercorso(
              id: c.id,
              nome: c.nome,
              distanzaM: c.distanzaM,
              potenzaKw: 50,
              deviazioneM: c.deviazioneM,
            ),
        ],
      )!;
      expect(lente.durata, greaterThan(veloci.durata));
    });
  });
}
