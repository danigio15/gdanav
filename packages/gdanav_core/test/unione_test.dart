import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

Colonnina col(String id, double lat, double lon, {int prese = 1, String? operatore, String fonte = 'x'}) => Colonnina(
      id: id,
      nome: 'Colonnina $id',
      posizione: Punto(lat, lon),
      connettori: [
        for (var i = 0; i < prese; i++) const Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150),
      ],
      operatore: operatore,
      fonte: fonte,
    );

/// Una fonte che risponde quello che le si dice, o non risponde affatto.
class _Finta implements FonteColonnine {
  _Finta(this.colonnine, {this.errore, this.ritardo = Duration.zero});

  final List<Colonnina> colonnine;
  final Object? errore;
  final Duration ritardo;
  int chiamate = 0;

  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async {
    chiamate++;
    if (ritardo > Duration.zero) await Future<void>.delayed(ritardo);
    if (errore != null) throw Exception(errore);
    return colonnine;
  }
}

void main() {
  const strada = [Punto(45, 9), Punto(45.1, 9.1)];

  group('fondere gli elenchi', () {
    /* Il difetto: con la catena a riserva bastava che Open Charge Map
     * rispondesse — 143 colonnine intorno a Napoli — perché tutto il resto
     * non venisse nemmeno chiesto. */
    test('quello che una fonte non ha, ce l\'ha l\'altra, e resta', () {
      final fuse = fondiColonnine([
        [col('ocm:1', 45.0000, 9.0000), col('ocm:2', 45.0100, 9.0100)],
        [col('osm:9', 45.0200, 9.0200), col('osm:8', 45.0300, 9.0300)],
      ]);
      expect(fuse.map((c) => c.id), ['ocm:1', 'ocm:2', 'osm:9', 'osm:8']);
    });

    test('la stessa colonnina vista da due fonti è una sola', () {
      // ~22 m: sotto i 60 del raggio.
      final fuse = fondiColonnine([
        [col('ocm:1', 45.0000, 9.0000, prese: 2)],
        [col('osm:1', 45.0002, 9.0000, prese: 1)],
      ]);
      expect(fuse, hasLength(1));
      expect(fuse.single.fonte, 'x');
    });

    test('di due, resta quella che conosce più prese', () {
      final fuse = fondiColonnine([
        [col('ocm:1', 45.0000, 9.0000, prese: 1, fonte: 'ocm')],
        [col('osm:1', 45.0002, 9.0000, prese: 6, operatore: 'Ionity', fonte: 'osm')],
      ]);
      expect(fuse.single.id, 'osm:1');
      expect(fuse.single.connettori, hasLength(6));
      expect(fuse.single.operatore, 'Ionity');
      expect(fuse.single.fonte, 'ocm+osm');
    });

    test('l\'operatore si prende da chi ce l\'ha', () {
      final fuse = fondiColonnine([
        [col('ocm:1', 45.0000, 9.0000, prese: 4, fonte: 'ocm')],
        [col('osm:1', 45.0002, 9.0000, prese: 1, operatore: 'Enel X', fonte: 'osm')],
      ]);
      expect(fuse.single.operatore, 'Enel X');
    });

    /* Il difetto che la CI ha trovato: fondendo, 717 colonnine dal relay
     * diventavano 606. Accorpavo anche dentro la stessa fonte — e al Centro
     * Direzionale di Napoli, dove le stazioni stanno a pochi metri, vuol dire
     * farle sparire. Una fonte è già in ordine con sé stessa. */
    test('dentro una fonte non si accorpa niente, per quanto vicine', () {
      // Quattro stazioni a venti metri l'una dall'altra, dalla stessa fonte.
      final vicine = [for (var i = 0; i < 4; i++) col('osm:$i', 45 + i * 0.0002, 9, fonte: 'osm')];
      expect(fondiColonnine([vicine]), hasLength(4));
      expect(fondiColonnine([vicine, []]), hasLength(4));
    });

    test('un posto visto come uno da una fonte e come tre dall\'altra resta tre', () {
      final tre = [for (var i = 0; i < 3; i++) col('osm:$i', 45 + i * 0.0002, 9, prese: 2, fonte: 'osm')];
      final uno = [col('ocm:1', 45.0002, 9, prese: 1, fonte: 'ocm')];
      final fuse = fondiColonnine([tre, uno]);
      expect(fuse, hasLength(3));
      // Una sola si accoppia: l'accoppiamento è uno a uno.
      expect(fuse.where((c) => c.fonte.contains('+')), hasLength(1));
    });

    test('due colonnine lontane restano due, anche se si somigliano', () {
      // ~330 m.
      final fuse = fondiColonnine([
        [col('a', 45.0000, 9.0000)],
        [col('b', 45.0030, 9.0000)],
      ]);
      expect(fuse, hasLength(2));
    });

    test('mille colonnine non fanno un milione di confronti', () {
      final tante = [for (var i = 0; i < 1000; i++) col('a$i', 45 + i * 0.002, 9)];
      final altre = [for (var i = 0; i < 1000; i++) col('b$i', 45 + i * 0.002, 9.5)];
      final orologio = Stopwatch()..start();
      final fuse = fondiColonnine([tante, altre]);
      expect(fuse, hasLength(2000));
      expect(orologio.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('la fonte unita', () {
    test('chiede a tutte, non si ferma alla prima', () async {
      final a = _Finta([col('ocm:1', 45.0000, 9.0000)]);
      final b = _Finta([col('osm:1', 45.0500, 9.0500)]);
      final fuse = await FonteColonnineUnite([a, b]).lungo(strada);
      expect(a.chiamate, 1);
      expect(b.chiamate, 1);
      expect(fuse, hasLength(2));
    });

    test('se una fonte cade, le altre bastano', () async {
      final rotta = _Finta(const [], errore: 'Open Charge Map 403');
      final buona = _Finta([col('osm:1', 45.0500, 9.0500)]);
      expect(await FonteColonnineUnite([rotta, buona]).lungo(strada), hasLength(1));
    });

    test('una fonte lenta non blocca il viaggio', () async {
      final lenta = _Finta([col('lenta', 45.02, 9.02)], ritardo: const Duration(seconds: 3));
      final svelta = _Finta([col('svelta', 45.05, 9.05)]);
      final fuse = await FonteColonnineUnite(
        [lenta, svelta],
        attesa: const Duration(milliseconds: 80),
      ).lungo(strada);
      expect(fuse.map((c) => c.id), ['svelta']);
    });

    test('la riserva si chiede solo se non ha risposto nessuno', () async {
      final riserva = _Finta([col('overpass:1', 45.05, 9.05)]);
      final buona = _Finta([col('ocm:1', 45.00, 9.00)]);

      expect(await FonteColonnineUnite([buona], riserva: riserva).lungo(strada), hasLength(1));
      expect(riserva.chiamate, 0, reason: 'Overpass è lento: non si disturba per niente');

      final vuota = _Finta(const []);
      expect(await FonteColonnineUnite([vuota], riserva: riserva).lungo(strada), hasLength(1));
      expect(riserva.chiamate, 1);
    });

    test('se non risponde nessuno e non c\'è riserva, lo dice', () {
      final rotta = _Finta(const [], errore: 'niente rete');
      expect(FonteColonnineUnite([rotta]).lungo(strada), throwsA(isA<Exception>()));
    });
  });
}
