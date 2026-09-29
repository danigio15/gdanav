import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Un percorso finto lungo [punti], che dura [durata].
PercorsoCalcolato percorso(List<Punto> punti, Duration durata) {
  var metri = 0.0;
  for (var i = 1; i < punti.length; i++) {
    metri += distanzaM(punti[i - 1], punti[i]);
  }
  return PercorsoCalcolato(
    punti: punti,
    tratti: [Tratto(lunghezzaM: metri, velocitaKmh: metri / durata.inSeconds * 3.6)],
    manovre: const [],
  );
}

/// Da [da] ad [a] in linea retta, un punto ogni cento metri circa.
List<Punto> dritto(Punto da, Punto a) {
  final n = (distanzaM(da, a) / 100).ceil().clamp(2, 1000);
  return [for (var i = 0; i <= n; i++) Punto(da.lat + (a.lat - da.lat) * i / n, da.lon + (a.lon - da.lon) * i / n)];
}

void main() {
  // La ZTL: un quadrato di un chilometro intorno al centro di Napoli, attiva
  // nei giorni feriali dalle 7 alle 18.
  const centro = Punto(40.85, 14.25);
  final ztl = ZonaLimitata(
    id: 'r1',
    tipo: TipoZona.ztl,
    nome: 'Centro storico',
    citta: 'Napoli',
    orari: OrariZtl.leggi('Mo-Fr 07:00-18:00'),
    anelli: [
      [
        Punto(centro.lat - 0.005, centro.lon - 0.005),
        Punto(centro.lat - 0.005, centro.lon + 0.005),
        Punto(centro.lat + 0.005, centro.lon + 0.005),
        Punto(centro.lat + 0.005, centro.lon - 0.005),
      ],
    ],
  );
  final archivio = ArchivioZtl([ztl]);
  const sud = Punto(40.84, 14.25), nord = Punto(40.86, 14.25);
  // Martedì 29 settembre 2026, alle dieci.
  final martedi = DateTime(2026, 9, 29, 10);

  late List<(List<Punto>, List<Rettangolo>)> chieste;

  /// TomTom finto: senza rettangoli la strada dritta (11 minuti); coi
  /// rettangoli il giro largo a est (14 minuti).
  Future<PercorsoCalcolato> tomtom(List<Punto> tappe, List<Rettangolo> evita) async {
    chieste.add((tappe, evita));
    final da = tappe.first, a = tappe.last;
    if (evita.isEmpty) return percorso(dritto(da, a), const Duration(minutes: 11));
    const est = 14.262;
    return percorso([
      ...dritto(da, Punto(da.lat, est)),
      ...dritto(Punto(da.lat, est), Punto(a.lat, est)).skip(1),
      ...dritto(Punto(a.lat, est), a).skip(1),
    ], const Duration(minutes: 14));
  }

  PercorsiConZtl calcolo(Map<String, bool> permessi, {DateTime? quando, PercorsoEvitando? calcola}) => PercorsiConZtl(
        zone: () async => archivio,
        permessi: () async => permessi,
        calcola: calcola ?? tomtom,
        adesso: () => quando ?? martedi,
      );

  setUp(() => chieste = []);

  test('senza risposta: la gira al largo e chiede, coi minuti che si guadagnerebbero', () async {
    final p = await calcolo(const {}).percorso([sud, nord]);
    expect(p.durata, const Duration(minutes: 14));
    expect(archivio.ztlSulPercorso(p.punti), isEmpty, reason: 'il percorso sta fuori');
    final z = p.ztl!;
    expect(z.evitate.single.id, 'r1');
    expect(z.daChiedere?.id, 'r1');
    expect(z.durataPassandoci, const Duration(minutes: 11));
    expect(archivio.ztlSulPercorso(z.puntiPassandoci).single.zona.id, 'r1');
    // Due richieste: la strada com'è, e quella che gira al largo coi
    // rettangoli, che stanno dentro la ZTL.
    expect(chieste, hasLength(2));
    final rettangoli = chieste.last.$2;
    expect(rettangoli, isNotEmpty);
    expect(rettangoli.length, lessThanOrEqualTo(PercorsiConZtl.massimoRettangoli));
    for (final r in rettangoli) {
      expect(ztl.riquadro.tocca(r), isTrue);
      expect(r.sud, greaterThanOrEqualTo(ztl.riquadro.sud));
      expect(r.nord, lessThanOrEqualTo(ztl.riquadro.nord));
    }
  });

  test('col permesso ci passa, e non chiede niente a TomTom in più', () async {
    final p = await calcolo({ztl.chiave: true}).percorso([sud, nord]);
    expect(p.durata, const Duration(minutes: 11));
    expect(p.ztl!.attraversate.single.id, 'r1');
    expect(p.ztl!.daChiedere, isNull);
    expect(chieste, hasLength(1));
  });

  test('senza permesso la gira al largo e non chiede', () async {
    final p = await calcolo({ztl.chiave: false}).percorso([sud, nord]);
    expect(p.durata, const Duration(minutes: 14));
    expect(p.ztl!.evitate.single.id, 'r1');
    expect(p.ztl!.daChiedere, isNull);
    expect(p.ztl!.puntiPassandoci, isEmpty);
  });

  test('spenta non conta: la domenica, e la sera', () async {
    for (final quando in [DateTime(2026, 10, 4, 10), DateTime(2026, 9, 29, 19)]) {
      chieste.clear();
      final p = await calcolo(const {}, quando: quando).percorso([sud, nord]);
      expect(p.durata, const Duration(minutes: 11));
      expect(p.ztl!.evitate, isEmpty);
      expect(chieste, hasLength(1));
    }
  });

  test('conta quando ci si arriva, non quando si parte', () async {
    // Il finto dà sempre 11 minuti, e l'ingresso è a nove decimi della
    // strada: dieci minuti dopo la partenza.
    final p = await calcolo(const {}, quando: DateTime(2026, 9, 29, 6, 48)).percorso([
      const Punto(40.70, 14.25),
      nord,
    ]);
    expect(p.ztl!.evitate, isEmpty, reason: 'alle 6:58 è ancora spenta');
    final tardi = await calcolo(const {}, quando: DateTime(2026, 9, 29, 6, 55)).percorso([
      const Punto(40.70, 14.25),
      nord,
    ]);
    expect(tardi.ztl!.evitate.single.id, 'r1', reason: 'alle 7:05 è accesa');
  });

  test('la meta è dentro: si arriva al varco, fuori, sulla strada che ci entra', () async {
    final p = await calcolo({ztl.chiave: false}).percorso([sud, centro]);
    final z = p.ztl!;
    expect(z.metaDentro?.id, 'r1');
    expect(z.evitate, isEmpty);
    final varco = z.varco!;
    expect(ztl.contiene(varco), isFalse);
    expect(distanzaM(varco, Punto(ztl.riquadro.sud, 14.25)), lessThan(150));
    expect(chieste.last.$1.last, varco);
    expect(archivio.ztlSulPercorso(p.punti), isEmpty);
  });

  test('da dentro si esce e basta', () async {
    final p = await calcolo(const {}).percorso([centro, nord]);
    expect(p.durata, const Duration(minutes: 11));
    expect(p.ztl!.evitate, isEmpty);
    expect(chieste, hasLength(1));
  });

  test('se TomTom non ce la fa coi rettangoli, si resta com\'era e lo si dice', () async {
    Future<PercorsoCalcolato> capriccioso(List<Punto> tappe, List<Rettangolo> evita) async {
      if (evita.isNotEmpty) throw const ErrorePercorso('avoid area too large', stato: 400);
      return tomtom(tappe, evita);
    }

    final p = await calcolo({ztl.chiave: false}, calcola: capriccioso).percorso([sud, nord]);
    expect(p.durata, const Duration(minutes: 11));
    expect(p.ztl!.nonEvitate.single.id, 'r1');
    expect(p.ztl!.evitate, isEmpty);
  });

  test('le strade da scegliere: tutte fuori dalla ZTL', () async {
    final scelte = await PercorsiConZtl(
      zone: () async => archivio,
      permessi: () async => const {},
      calcola: tomtom,
      alternative: (da, a, evita) async => [
        await tomtom([da, a], evita),
        await tomtom([da, a], evita)
      ],
      adesso: () => martedi,
    ).scelte(sud, nord);
    expect(scelte, hasLength(2));
    for (final s in scelte) {
      expect(archivio.ztlSulPercorso(s.punti), isEmpty);
      expect(s.ztl!.daChiedere?.id, 'r1');
    }
  });

  test('due pezzi della stessa ZTL: un permesso solo li apre tutti e due', () async {
    // Un secondo pezzo, più a nord sulla stessa strada, con lo stesso nome.
    final pezzo = ZonaLimitata(
      id: 'w2',
      tipo: TipoZona.ztl,
      nome: 'Centro storico',
      citta: 'Napoli',
      anelli: [
        [
          const Punto(40.8555, 14.245),
          const Punto(40.8555, 14.255),
          const Punto(40.8585, 14.255),
          const Punto(40.8585, 14.245),
        ],
      ],
    );
    final dueArchivio = ArchivioZtl([ztl, pezzo]);
    PercorsiConZtl con(Map<String, bool> permessi) => PercorsiConZtl(
          zone: () async => dueArchivio,
          permessi: () async => permessi,
          calcola: tomtom,
          adesso: () => martedi,
        );
    final chiede = await con(const {}).percorso([sud, nord]);
    expect(chiede.ztl!.daChiedere?.chiave, ztl.chiave);
    expect(chiede.ztl!.evitate.map((z) => z.id), unorderedEquals(['r1', 'w2']));
    chieste.clear();
    final passa = await con({ztl.chiave: true}).percorso([sud, nord]);
    expect(passa.durata, const Duration(minutes: 11));
    expect(passa.ztl!.attraversate.map((z) => z.id), unorderedEquals(['r1', 'w2']));
    expect(chieste, hasLength(1));
  });

  test('il traffico rifatto non fa dimenticare le ZTL', () async {
    final p = await calcolo(const {}).percorso([sud, nord]);
    final conCode = p.conTraffico(const []);
    expect(conCode.ztl?.daChiedere?.id, 'r1');
    expect(conCode.base.ztl?.daChiedere?.id, 'r1');
  });
}
