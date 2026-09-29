import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Un quadrato di circa un chilometro intorno a [centro].
List<Punto> quadrato(Punto centro, {double lato = 0.01}) => [
      Punto(centro.lat - lato / 2, centro.lon - lato / 2),
      Punto(centro.lat - lato / 2, centro.lon + lato / 2),
      Punto(centro.lat + lato / 2, centro.lon + lato / 2),
      Punto(centro.lat + lato / 2, centro.lon - lato / 2),
    ];

void main() {
  group('gli orari di OpenStreetMap', () {
    // Lunedì 28 settembre 2026.
    final lunedi = DateTime(2026, 9, 28);

    test('giorni feriali, dalle 7:30 alle 19:30', () {
      final o = OrariZtl.leggi('Mo-Fr 07:30-19:30')!;
      expect(o.attivaAlle(lunedi.add(const Duration(hours: 10))), isTrue);
      expect(o.attivaAlle(lunedi.add(const Duration(hours: 7, minutes: 29))), isFalse);
      expect(o.attivaAlle(lunedi.add(const Duration(hours: 19, minutes: 30))), isFalse);
      // Sabato no.
      expect(o.attivaAlle(DateTime(2026, 10, 3, 10)), isFalse);
      expect(o.finoAlle(DateTime(2026, 9, 28, 10)), DateTime(2026, 9, 28, 19, 30));
      expect(o.dalle(DateTime(2026, 9, 28, 20)), DateTime(2026, 9, 29, 7, 30));
      // Venerdì sera: la prossima volta è lunedì.
      expect(o.dalle(DateTime(2026, 10, 2, 20)), DateTime(2026, 10, 5, 7, 30));
    });

    test('la notte, a cavallo della mezzanotte', () {
      final o = OrariZtl.leggi('Fr-Sa 21:00-03:00')!;
      expect(o.attivaAlle(DateTime(2026, 10, 2, 23)), isTrue); // venerdì sera
      expect(o.attivaAlle(DateTime(2026, 10, 3, 2)), isTrue); // sabato notte, da venerdì
      expect(o.attivaAlle(DateTime(2026, 10, 3, 4)), isFalse);
      expect(o.attivaAlle(DateTime(2026, 10, 4, 2)), isTrue); // domenica notte, da sabato
      expect(o.attivaAlle(DateTime(2026, 10, 5, 2)), isFalse); // lunedì notte no
      expect(o.finoAlle(DateTime(2026, 10, 2, 23)), DateTime(2026, 10, 3, 3));
    });

    test('più fasce, e una regola dopo che prende il posto di quella prima', () {
      final o = OrariZtl.leggi('Mo-Sa 08:00-13:00,15:00-20:00; Sa 08:00-13:00')!;
      expect(o.attivaAlle(DateTime(2026, 9, 29, 16)), isTrue); // martedì pomeriggio
      expect(o.attivaAlle(DateTime(2026, 10, 3, 16)), isFalse); // sabato pomeriggio no
      expect(o.attivaAlle(DateTime(2026, 10, 3, 9)), isTrue);
      expect(o.attivaAlle(DateTime(2026, 9, 29, 14)), isFalse); // la pausa
    });

    test('i festivi: Natale, Pasquetta e le domeniche spente', () {
      final o = OrariZtl.leggi('Mo-Sa 07:00-20:00; Su,PH off')!;
      expect(o.attivaAlle(DateTime(2026, 12, 25, 10)), isFalse); // Natale, venerdì
      expect(o.attivaAlle(DateTime(2026, 4, 6, 10)), isFalse); // Pasquetta 2026
      expect(o.attivaAlle(DateTime(2026, 4, 7, 10)), isTrue);
      expect(o.attivaAlle(DateTime(2026, 10, 4, 10)), isFalse); // domenica
    });

    test('solo d\'estate', () {
      final o = OrariZtl.leggi('Jun-Sep 20:00-02:00')!;
      expect(o.attivaAlle(DateTime(2026, 7, 10, 22)), isTrue);
      expect(o.attivaAlle(DateTime(2026, 11, 10, 22)), isFalse);
      final natale = OrariZtl.leggi('Dec 08-Jan 06 10:00-20:00')!;
      expect(natale.attivaAlle(DateTime(2026, 12, 20, 12)), isTrue);
      expect(natale.attivaAlle(DateTime(2027, 1, 3, 12)), isTrue);
      expect(natale.attivaAlle(DateTime(2026, 11, 20, 12)), isFalse);
    });

    test('il divieto a tempo, e le condizioni che si sommano', () {
      final o = OrariZtl.daCondizione('no @ (Mo-Fr 07:30-10:00); destination @ (Sa 08:00-12:00)')!;
      expect(o.attivaAlle(DateTime(2026, 9, 28, 9)), isTrue);
      expect(o.attivaAlle(DateTime(2026, 9, 28, 11)), isFalse);
      expect(o.attivaAlle(DateTime(2026, 10, 3, 9)), isTrue);
      final daiTag =
          OrariZtl.daiTag({'motor_vehicle:conditional': 'no @ (Mo-Su 00:00-24:00)', 'opening_hours': 'Mo 10:00-11:00'});
      expect(daiTag!.attivaAlle(DateTime(2026, 10, 4, 3)), isTrue, reason: 'vince il divieto');
    });

    test('«yes @»: le ore in cui si passa, e la ZTL è attiva nelle altre', () {
      // Torino, ZTL Centrale: si passa sempre, tranne i feriali 7:30-10:30.
      final torino = OrariZtl.daCondizione('yes @ (Mo-Fr 00:00-07:30,10:30-24:00; Sa-Su,PH 00:00-24:00)')!;
      expect(torino.attivaAlle(DateTime(2026, 9, 29, 9)), isTrue); // martedì
      expect(torino.attivaAlle(DateTime(2026, 9, 29, 11)), isFalse);
      expect(torino.attivaAlle(DateTime(2026, 9, 29, 7, 29)), isFalse);
      expect(torino.attivaAlle(DateTime(2026, 10, 3, 9)), isFalse); // sabato
      expect(torino.attivaAlle(DateTime(2026, 4, 6, 9)), isFalse); // Pasquetta, lunedì
      expect(torino.finoAlle(DateTime(2026, 9, 29, 9)), DateTime(2026, 9, 29, 10, 30));
      expect(torino.dalle(DateTime(2026, 9, 29, 11)), DateTime(2026, 9, 30, 7, 30));
      expect(torino.dalle(DateTime(2026, 10, 2, 11)), DateTime(2026, 10, 5, 7, 30));

      // Bologna: si passa dalle 20 alle 7, attiva di giorno tutti i giorni.
      final bologna = OrariZtl.daCondizione('yes @ 20:00-07:00')!;
      expect(bologna.attivaAlle(DateTime(2026, 10, 4, 12)), isTrue);
      expect(bologna.attivaAlle(DateTime(2026, 10, 4, 22)), isFalse);
      expect(bologna.attivaAlle(DateTime(2026, 10, 4, 6, 59)), isFalse);
      expect(bologna.attivaAlle(DateTime(2026, 10, 4, 7)), isTrue);
      expect(bologna.finoAlle(DateTime(2026, 10, 4, 12)), DateTime(2026, 10, 4, 20));

      // Aperta sempre: mai attiva.
      expect(OrariZtl.daCondizione('yes @ (24/7)')!.attivaAlle(DateTime(2026, 9, 29, 9)), isFalse);
    });

    test('i giorni all\'italiana, e i due punti dopo le date', () {
      // Si passa Lu-Ve dalle 6 alle 9: attiva il resto.
      final o = OrariZtl.daCondizione('yes @ (Lu-Fr 06:00-09:00)')!;
      expect(o.attivaAlle(DateTime(2026, 9, 28, 7)), isFalse); // lunedì
      expect(o.attivaAlle(DateTime(2026, 9, 28, 10)), isTrue);
      expect(o.attivaAlle(DateTime(2026, 10, 3, 7)), isTrue); // sabato
      final erice = OrariZtl.daCondizione('permit @ (Jul 15-Sep 15: Mo-Su 02:00-11:00)')!;
      expect(erice.attivaAlle(DateTime(2026, 8, 1, 3)), isTrue);
      expect(erice.attivaAlle(DateTime(2026, 8, 1, 12)), isFalse);
      expect(erice.attivaAlle(DateTime(2026, 10, 1, 3)), isFalse);
      expect(OrariZtl.leggi('Jun 20:00-23:00')!.attivaAlle(DateTime(2026, 6, 5, 21)), isTrue);
    });

    test('«sempre» scritto apposta', () {
      expect(OrariZtl.sempre('permit @ (24/7)'), isTrue);
      expect(OrariZtl.sempre('permit'), isTrue);
      expect(OrariZtl.sempre('24/7'), isTrue);
      expect(OrariZtl.sempre('no @ (Mo 10:00-11:00)'), isFalse);
      expect(OrariZtl.sempre('sunrise-sunset'), isFalse);
      expect(OrariZtl.daCondizione('permit @ (24/7)'), isNull);
    });

    test('quello che non si capisce vale come sempre', () {
      expect(OrariZtl.leggi('24/7'), isNull);
      expect(OrariZtl.leggi('sunrise-sunset'), isNull);
      expect(OrariZtl.leggi('Mo-Fr 07:30-19:30; SH off'), isNull);
      expect(OrariZtl.leggi('week 1-20 Mo-Fr 08:00-18:00'), isNull);
      expect(OrariZtl.daCondizione('no @ (weight>7.5)'), isNull);
      expect(OrariZtl.daiTag(const {}), isNull);
      // Un commento fra virgolette non cambia gli orari.
      expect(OrariZtl.leggi('Mo-Fr 07:30-19:30 "varchi attivi"')!.attivaAlle(DateTime(2026, 9, 28, 8)), isTrue);
    });

    test('il giorno del cambio dell\'ora le fasce restano all\'ora giusta', () {
      final o = OrariZtl.leggi('Mo-Su 08:00-18:00')!;
      // 29 marzo 2026: si passa all'ora legale.
      expect(o.dalle(DateTime(2026, 3, 29, 1)), DateTime(2026, 3, 29, 8));
      expect(o.finoAlle(DateTime(2026, 3, 29, 9)), DateTime(2026, 3, 29, 18));
    });
  });

  group('le zone', () {
    const centro = Punto(40.85, 14.25);
    final ztl = ZonaLimitata(
      id: 'r1',
      tipo: TipoZona.ztl,
      nome: 'Centro storico',
      citta: 'Napoli',
      orari: OrariZtl.leggi('Mo-Fr 07:00-18:00'),
      orariTesto: 'Mo-Fr 07:00-18:00',
      anelli: [quadrato(centro)],
    );

    test('dentro e fuori, e l\'etichetta', () {
      expect(ztl.contiene(centro), isTrue);
      expect(ztl.contiene(const Punto(40.86, 14.25)), isFalse);
      expect(ztl.etichetta, 'Napoli · Centro storico');
      expect(ztl.titolo, 'ZTL Centro storico');
      final senzaNome = ZonaLimitata(id: 'w9', tipo: TipoZona.ztl, nome: '', citta: 'Brescia', anelli: [
        quadrato(centro),
      ]);
      expect(senzaNome.etichetta, 'Brescia');
      expect(senzaNome.titolo, 'ZTL di Brescia');
      // Due pezzi con lo stesso nome nello stesso comune: un permesso solo.
      final altroPezzo = ZonaLimitata(id: 'w10', tipo: TipoZona.ztl, nome: '', citta: 'Brescia', anelli: [
        quadrato(const Punto(40.9, 14.3)),
      ]);
      expect(altroPezzo.chiave, senzaNome.chiave);
      expect(ztl.chiave, isNot(senzaNome.chiave));
      expect(ZonaLimitata(id: 'w11', tipo: TipoZona.ztl, nome: '', anelli: [quadrato(centro)]).chiave, 'w11');
      expect(ztl.attivaAlle(DateTime(2026, 9, 28, 10)), isTrue);
      expect(ztl.attivaAlle(DateTime(2026, 10, 4, 10)), isFalse);
    });

    test('il percorso che la attraversa: dove entra; da dentro non conta', () {
      final archivio = ArchivioZtl([ztl]);
      final attraverso = [for (var i = 0; i <= 20; i++) Punto(40.84 + i * 0.001, 14.25)];
      final ingressi = archivio.ztlSulPercorso(attraverso);
      expect(ingressi.single.zona.id, 'r1');
      expect(attraverso[ingressi.single.indice].lat, closeTo(40.846, 0.0011));
      final intorno = [for (var i = 0; i <= 20; i++) Punto(40.84 + i * 0.001, 14.26)];
      expect(archivio.ztlSulPercorso(intorno), isEmpty);
      final daDentro = [for (var i = 0; i <= 10; i++) Punto(40.85 + i * 0.001, 14.25)];
      expect(archivio.ztlSulPercorso(daDentro), isEmpty);
    });

    test('anche coi punti radi che scavalcano un angolo', () {
      final archivio = ArchivioZtl([ztl]);
      // Due punti fuori, il tratto fra loro taglia la zona.
      final radi = [const Punto(40.84, 14.25), const Punto(40.86, 14.25)];
      expect(archivio.ztlSulPercorso(radi).single.zona.id, 'r1');
    });

    test('la copertura: tutta la zona dentro i rettangoli, e al massimo quanti se ne chiede', () {
      // Una «L»: il rettangolo solo prenderebbe dentro l'angolo vuoto.
      final elle = ZonaLimitata(
        id: 'w2',
        tipo: TipoZona.ztl,
        nome: 'L',
        anelli: [
          [
            const Punto(0, 0),
            const Punto(0, 0.02),
            const Punto(0.01, 0.02),
            const Punto(0.01, 0.01),
            const Punto(0.02, 0.01),
            const Punto(0.02, 0),
          ],
        ],
      );
      final rettangoli = elle.copertura(quanti: 4, margineM: 0);
      expect(rettangoli.length, lessThanOrEqualTo(4));
      for (var la = 0.0005; la < 0.02; la += 0.001) {
        for (var lo = 0.0005; lo < 0.02; lo += 0.001) {
          final p = Punto(la, lo);
          if (elle.contiene(p)) {
            expect(rettangoli.any((r) => r.contiene(p)), isTrue, reason: 'scoperto: $p');
          }
        }
      }
      // L'angolo vuoto in alto a destra resta fuori.
      expect(rettangoli.any((r) => r.contiene(const Punto(0.018, 0.018))), isFalse);
      // Col margine le strade sul bordo restano libere.
      final stretti = elle.copertura(quanti: 4, margineM: 10);
      expect(stretti.any((r) => r.contiene(const Punto(0.0000449, 0.005))), isFalse);
    });

    test('l\'archivio va e torna, e trova le zone vicine', () {
      final pedonale = ZonaLimitata(
        id: 'w3',
        tipo: TipoZona.pedonale,
        nome: 'Piazza del Plebiscito',
        anelli: [quadrato(const Punto(40.8359, 14.2488), lato: 0.002)],
      );
      final testo = ArchivioZtl.scrivi([ztl, pedonale], generato: DateTime.utc(2026, 9, 29));
      final a = ArchivioZtl.leggi(testo);
      expect(a.quanteZtl, 1);
      expect(a.quantePedonali, 1);
      expect(a.generato, DateTime.utc(2026, 9, 29));
      final letta = a.perId('r1')!;
      expect(letta.etichetta, 'Napoli · Centro storico');
      expect(letta.orari, isNotNull);
      expect(letta.contiene(centro), isTrue);
      expect(letta.anelli.single.first.lat, closeTo(40.845, 0.00001));
      expect(a.vicine(const Punto(40.8359, 14.2488), 300).map((z) => z.id), contains('w3'));
      expect(a.vicine(const Punto(41.9, 12.5), 5000), isEmpty);
      // Le aree pedonali non hanno orari: in auto mai.
      expect(a.perId('w3')!.attivaAlle(DateTime(2026, 10, 4, 3)), isTrue);
    });

    test('le aree pedonali che il percorso gira intorno', () {
      final pedonale = ZonaLimitata(
        id: 'w3',
        tipo: TipoZona.pedonale,
        nome: 'Piazza',
        anelli: [quadrato(const Punto(40.8, 14.3), lato: 0.001)],
      );
      final a = ArchivioZtl([pedonale]);
      // Lungo il bordo ovest, a una decina di metri.
      final lungo = [const Punto(40.799, 14.29940), const Punto(40.801, 14.29940)];
      expect(a.pedonaliLungo(lungo).single.id, 'w3');
      final lontano = [const Punto(40.799, 14.29), const Punto(40.801, 14.29)];
      expect(a.pedonaliLungo(lontano), isEmpty);
    });
  });
}
