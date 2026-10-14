import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/* ── «Sullo schermo piccolo della 500 non si vede nulla» ──────────────────
 *
 * CarPlay a 400×240 punti: la scheda della manovra con «Alla rotonda prendi
 * l'uscita seconda in Via Faentina/SP253» su tre righe copriva la mappa.
 * CarPlay e Android Auto scelgono la frase che ci sta, se gliene diamo più
 * d'una dalla più lunga: qui si controlla che le frasi ci siano, in ordine,
 * corte davvero e senza la sigla ripetuta. */
void main() {
  Manovra manovra(
    int tipo, {
    String istruzione = '',
    String strada = '',
    String uscita = '',
    String verso = '',
    int? rotonda,
    double lunghezzaM = 500,
  }) =>
      Manovra(
        istruzione: istruzione,
        lunghezzaM: lunghezzaM,
        secondi: 30,
        inizio: 0,
        tipo: tipo,
        strada: strada,
        uscita: uscita,
        verso: verso,
        uscitaRotonda: rotonda,
      );

  /// Ogni elenco va dalla più lunga alla più corta, senza doppioni.
  void inOrdine(List<String> f) {
    for (var i = 1; i < f.length; i++) {
      expect(f[i].length, lessThanOrEqualTo(f[i - 1].length), reason: '$f');
    }
    expect(f.toSet(), hasLength(f.length), reason: '$f');
    expect(f.every((s) => s.trim() == s && s.isNotEmpty), isTrue, reason: '$f');
  }

  group('la rotonda della foto', () {
    test("«l'uscita seconda in Via Faentina/SP253»: 2ª, senza la sigla, fino a «2ª uscita»", () {
      final f = frasiManovra(manovra(
        26,
        istruzione: "Alla rotonda prendi l'uscita seconda in Via Faentina/SP253",
      ));
      expect(f, [
        'Alla rotonda prendi la 2ª uscita in Via Faentina',
        'Rotonda, 2ª uscita · Via Faentina',
        'Rotonda, 2ª uscita',
        '2ª uscita',
      ]);
      inOrdine(f);
      expect(f.any((s) => s.contains('SP253')), isFalse);
      expect(f.any((s) => s.contains('seconda')), isFalse);
    });

    test("l'uscita data a parte vale più di quella scritta nella frase", () {
      final f =
          frasiManovra(manovra(26, istruzione: 'Prendi la prima uscita', strada: 'Via Faentina/SP253', rotonda: 3));
      expect(f.first, 'Alla rotonda prendi la 3ª uscita in Via Faentina');
      expect(f.last, '3ª uscita');
    });

    test('la strada data a parte, con la sigla davanti o dietro', () {
      expect(
          frasiManovra(manovra(26, strada: 'SP253/Via Faentina', rotonda: 2))[1], 'Rotonda, 2ª uscita · Via Faentina');
      expect(
          frasiManovra(manovra(26, strada: 'Via Faentina;SP253', rotonda: 2))[1], 'Rotonda, 2ª uscita · Via Faentina');
      expect(frasiManovra(manovra(26, strada: 'Via Faentina · SP253', rotonda: 2))[1],
          'Rotonda, 2ª uscita · Via Faentina');
    });

    test('solo la sigla: resta la sigla', () {
      expect(frasiManovra(manovra(26, strada: 'SS16', rotonda: 1)), [
        'Alla rotonda prendi la 1ª uscita in SS16',
        'Rotonda, 1ª uscita · SS16',
        'Rotonda, 1ª uscita',
        '1ª uscita',
      ]);
    });
  });

  group('rotonde', () {
    test("l'uscita scritta in tanti modi", () {
      expect(uscitaDallaFrase('Alla rotonda prendi la seconda uscita'), 2);
      expect(uscitaDallaFrase("Alla rotonda prendi l'uscita seconda in Via Faentina"), 2);
      expect(uscitaDallaFrase('Entra nella rotonda e prendi la 3a uscita in Via Emilia'), 3);
      expect(uscitaDallaFrase('Entra nella rotonda e prendi la 4ª uscita'), 4);
      expect(uscitaDallaFrase('Alla rotonda prendi la prima uscita verso Forlì'), 1);
      expect(uscitaDallaFrase('Alla rotonda prendi la decima uscita'), 10);
      expect(uscitaDallaFrase('Alla rotonda prendi uscita 5'), 5);
      // «Prima» in un nome di strada, lontano da «uscita», non conta.
      expect(uscitaDallaFrase('Alla rotonda prosegui in Via Prima Strada'), isNull);
      expect(uscitaDallaFrase('Gira a destra'), isNull);
    });

    test('senza uscita: «Rotonda»', () {
      final f = frasiManovra(manovra(26, strada: 'Viale Carducci'));
      expect(f, ['Alla rotonda prosegui in Viale Carducci', 'Rotonda · Viale Carducci', 'Rotonda']);
    });

    test('uscire dalla rotonda', () {
      final f = frasiManovra(manovra(27, strada: 'Via Emilia Levante/SS9'));
      expect(f, [
        'Esci dalla rotonda in Via Emilia Levante',
        'Esci dalla rotonda · Via Emilia Levante',
        'Esci dalla rotonda',
        'Esci',
      ]);
    });

    test('ordinale femminile', () {
      expect(ordinaleUscita(1), '1ª');
      expect(ordinaleUscita(12), '12ª');
    });
  });

  group('svolte', () {
    test('a destra e a sinistra, con la strada', () {
      expect(frasiManovra(manovra(10, strada: 'Via Roma')),
          ['Gira a destra in Via Roma', 'A destra · Via Roma', 'A destra']);
      expect(frasiManovra(manovra(15, strada: 'Corso Malta')),
          ['Gira a sinistra in Corso Malta', 'A sinistra · Corso Malta', 'A sinistra']);
    });

    test('leggere, strette, inversione', () {
      expect(frasiManovra(manovra(9, strada: 'Via Po')).last, 'Leggera destra');
      expect(frasiManovra(manovra(16)), ['Svolta leggermente a sinistra', 'Leggera sinistra']);
      expect(frasiManovra(manovra(11, strada: 'Via Po')).first, 'Svolta stretta a destra in Via Po');
      expect(frasiManovra(manovra(14)).first, 'Svolta stretta a sinistra');
      expect(frasiManovra(manovra(13, strada: 'Via Po')),
          ['Fai inversione a U in Via Po', 'Inversione · Via Po', 'Inversione']);
      expect(frasiManovra(manovra(12)).last, 'Inversione');
    });

    test('la strada presa dalla frase del motore, ma non «per 2 km»', () {
      expect(frasiManovra(manovra(10, istruzione: 'Gira a destra in Via Roma.'))[1], 'A destra · Via Roma');
      expect(frasiManovra(manovra(8, istruzione: 'Prosegui per 2 km')), ['Prosegui']);
      expect(frasiManovra(manovra(15, istruzione: 'Svolta a sinistra')), ['Gira a sinistra', 'A sinistra']);
    });

    test('dritto: la frase di mezzo è solo la strada', () {
      expect(frasiManovra(manovra(8, strada: 'Via Emilia/SS9')), ['Prosegui su Via Emilia', 'Via Emilia', 'Prosegui']);
      expect(frasiManovra(manovra(7, strada: 'Via Emilia')).last, 'Prosegui');
      expect(frasiManovra(manovra(0)), ['Prosegui']);
    });
  });

  group('autostrade e svincoli', () {
    test("l'uscita numerata col cartello: lunga col cartello intero, corta col primo nome", () {
      final f = frasiManovra(manovra(20, uscita: '43', verso: 'A14 · Bologna, Ravenna', strada: 'Raccordo'));
      expect(f, [
        "Prendi l'uscita 43 verso A14, Bologna, Ravenna",
        'Uscita 43 · Bologna',
        'Uscita 43',
      ]);
      inOrdine(f);
    });

    test("l'uscita senza numero", () {
      final f = frasiManovra(manovra(21, verso: 'E45/Cesena'));
      expect(f, ['Esci a sinistra verso E45, Cesena', 'Esci a sinistra · Cesena', 'Esci a sinistra', 'Esci']);
    });

    test("entrare in autostrada e i bivi", () {
      expect(frasiManovra(manovra(18, verso: 'A1 · Milano')),
          ['Prendi la rampa a destra verso A1, Milano', 'Rampa a destra · Milano', 'Rampa a destra', 'Rampa']);
      expect(frasiManovra(manovra(24, verso: 'A13 · Padova')),
          ['Al bivio tieni la sinistra verso A13, Padova', 'Tieni la sinistra · Padova', 'Tieni la sinistra']);
      expect(frasiManovra(manovra(23, verso: 'A14')),
          ['Al bivio tieni la destra verso A14', 'Tieni la destra · A14', 'Tieni la destra']);
      expect(frasiManovra(manovra(22)).last, 'Resta al centro');
    });

    test("al bivio senza cartello conta la strada", () {
      expect(frasiManovra(manovra(23, strada: 'Tangenziale Nord'))[1], 'Tieni la destra · Tangenziale Nord');
    });

    test('immissioni', () {
      expect(frasiManovra(manovra(25, strada: 'A14/E45')), ['Immettiti su A14', 'Immettiti · A14', 'Immettiti']);
      expect(frasiManovra(manovra(37)).last, 'Immettiti');
      expect(frasiManovra(manovra(38)).first, 'Immettiti a sinistra');
    });

    test('sigle', () {
      for (final s in ['SP253', 'A14', 'E45', 'SS16', 'SS9dir', 'RA 6', 'A1var', 'SR 11']) {
        expect(eSigla(s), isTrue, reason: s);
      }
      for (final s in ['Via Faentina', 'Corso Italia', 'Viale XX Settembre', 'Raccordo']) {
        expect(eSigla(s), isFalse, reason: s);
      }
      expect(stradaSenzaSigla('Via Faentina/SP253'), 'Via Faentina');
      expect(stradaSenzaSigla('A14/E45'), 'A14');
      expect(stradaSenzaSigla(''), '');
    });
  });

  group('arrivo, partenza, traghetto', () {
    test('arrivo', () {
      expect(frasiManovra(manovra(4)), ['Sei arrivato a destinazione', 'Arrivo']);
      expect(frasiManovra(manovra(5)).last, 'Arrivo');
      expect(frasiManovra(manovra(6)).first, 'La destinazione è sulla sinistra');
    });

    test('partenza e traghetto', () {
      expect(frasiManovra(manovra(1, strada: 'Via Roma')), ['Parti su Via Roma', 'Parti · Via Roma', 'Parti']);
      expect(frasiManovra(manovra(28, strada: 'Olbia')).first, 'Prendi il traghetto per Olbia');
      expect(frasiManovra(manovra(29)).last, 'Scendi');
    });
  });

  test('ogni tipo dà frasi in ordine, la più corta entro venti lettere', () {
    for (var tipo = 0; tipo <= 38; tipo++) {
      for (final m in [
        manovra(tipo),
        manovra(tipo, strada: 'Via Giuseppe Garibaldi/SP253', rotonda: 2, uscita: '12', verso: 'A14 · Bologna'),
        manovra(tipo, istruzione: 'Alla rotonda prendi la terza uscita in Viale della Repubblica'),
      ]) {
        final f = frasiManovra(m);
        expect(f, isNotEmpty);
        inOrdine(f);
        expect(f.last.length, lessThanOrEqualTo(20), reason: '$tipo: $f');
        inOrdine(frasiPoi(m));
      }
    }
  });

  group('il «poi»', () {
    test('solo se la manovra dopo arriva entro 150 m', () {
      final dopo = manovra(10, strada: 'Via Roma');
      expect(poiVicino(manovra(26, lunghezzaM: 80), dopo), isTrue);
      expect(poiVicino(manovra(26, lunghezzaM: 149), dopo), isTrue);
      expect(poiVicino(manovra(26, lunghezzaM: 150), dopo), isFalse);
      expect(poiVicino(manovra(26, lunghezzaM: 900), dopo), isFalse);
      expect(poiVicino(manovra(26, lunghezzaM: 50), null), isFalse);
    });

    test('le frasi del poi', () {
      expect(frasiPoi(manovra(10, strada: 'Via Roma/SP1')), ['Poi a destra · Via Roma', 'Poi a destra', 'Poi']);
      expect(frasiPoi(manovra(8, strada: 'Via Faentina/SP253')), ['Poi Via Faentina', 'Poi prosegui', 'Poi']);
      expect(frasiPoi(manovra(26, rotonda: 2)), ['Poi rotonda, 2ª uscita', 'Poi']);
      expect(
          frasiPoi(manovra(20, uscita: '43', verso: 'Bologna')), ['Poi uscita 43 · Bologna', 'Poi uscita 43', 'Poi']);
    });
  });
}
