import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/dati_viaggio.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/gestore_vicini.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

Colonnina posto(String id, String operatore, TipoConnettore tipo, double kw, {double lat = 40.85}) => Colonnina(
  id: id,
  nome: 'Posto $id',
  operatore: operatore,
  posizione: Punto(lat, 14.28),
  connettori: [Connettore(tipo: tipo, potenzaKw: kw)],
  fonte: 'pun',
);

/// Una lenta sotto casa, una Plenitude da 22 kW del Centro Direzionale e una
/// rapida a Milano: tre posti che la mappa di tutta Italia deve saper
/// mostrare o nascondere secondo le scelte di «Ricarica».
final archivioProva = ArchivioColonnine([
  posto('lenta', 'Enel X', TipoConnettore.tipo2, 11),
  posto('plenitude', 'Plenitude (Be Charge)', TipoConnettore.tipo2, 22.1),
  posto('rapida', 'Ionity', TipoConnettore.ccs2, 350, lat: 45.5),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sulla mappa di tutta Italia valgono le scelte di «Ricarica»', () async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final archivio = Archivio();
    Future<List<String>> ids() async => [
      for (final c in await colonnineDellArchivioComeSiVuole(
        ProfiloVeicolo.esempio,
        archivio,
        da: Future.value(archivioProva),
      ))
        c.id,
    ];

    // Di base da 50 kW in su: solo la rapida.
    expect(await ids(), ['rapida']);
    // «Tutte» vuol dire tutte, anche la lenta da 11 kW.
    await archivio.salvaPreferenze(const PreferenzeRicarica(potenzaMinimaKw: PreferenzeRicarica.tutte));
    expect(await ids(), ['lenta', 'plenitude', 'rapida']);
    // Un operatore che non si vuole vedere non si vede nemmeno qui.
    await archivio.salvaPreferenze(
      PreferenzeRicarica(potenzaMinimaKw: PreferenzeRicarica.tutte, operatoriEsclusi: {operatoreNormale('Ionity')}),
    );
    expect(await ids(), ['lenta', 'plenitude']);
  });

  testWidgets('tutte le colonnine: partono quando le chiede la mappa, e si rifanno se cambia la scelta', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    var giri = 0;
    final vicini = GestoreVicini(
      auto: a.auto,
      posizione: a.posizione,
      distributori: (_) async => const [],
      colonnine: (_, _) async => const [],
      tutte: (_) async {
        giri++;
        return archivioProva.tutte.toList();
      },
    );
    addTearDown(vicini.dispose);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(giri, 0, reason: 'senza la mappa non si caricano');

    vicini.avviaTutte();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(giri, 1);
    expect(vicini.versioneTutte, 1);
    expect(vicini.tutte.map((c) => c.id), ['lenta', 'plenitude', 'rapida']);
    // Una qualunque si trova anche se non è fra quelle intorno: è quella
    // che si tocca sulla mappa.
    expect(vicini.colonnina('rapida')?.nome, 'Posto rapida');
    // Sulla mappa solo dove, quale e quanti kW: sono decine di migliaia.
    final elementi = vicini.datiTutte()['features']! as List;
    expect(elementi, hasLength(3));
    expect((elementi[1] as Map)['properties'], {'id': 'plenitude', 'kw': 22, 'prese': 1});

    // Chiamarla due volte non la rifà.
    vicini.avviaTutte();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(giri, 1);

    // Cambiata una scelta in «Ricarica»: si rifà subito.
    await tester.runAsync(() => a.archivio.salvaPreferenze(const PreferenzeRicarica(potenzaMinimaKw: 100)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(giri, 2);
    expect(vicini.versioneTutte, 2);
  });

  testWidgets('una colonnina lontana toccata sulla mappa tiene lo stato di adesso', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    final vicini = GestoreVicini(
      auto: a.auto,
      posizione: a.posizione,
      distributori: (_) async => const [],
      // Intorno a te nessuna: la rapida di Milano si tocca sulla mappa di
      // tutta Italia.
      colonnine: (_, _) async => const [],
      tutte: (_) async => archivioProva.tutte.toList(),
      statoAdesso: (c) async => Colonnina(
        id: c.id,
        nome: c.nome,
        posizione: c.posizione,
        operatore: c.operatore,
        fonte: c.fonte,
        connettori: [for (final p in c.connettori) p.conStato(StatoPresa.disponibile)],
      ),
    );
    addTearDown(vicini.dispose);
    vicini.avviaTutte();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(vicini.colonnina('rapida')!.connettori.single.stato, StatoPresa.sconosciuto);

    await tester.runAsync(() => vicini.statoAdesso('rapida'));
    // La scheda la ritrova con [colonnina]: lì deve esserci lo stato nuovo.
    expect(vicini.colonnina('rapida')!.connettori.single.stato, StatoPresa.disponibile);
  });

  test('lo stile: tutte le colonnine raggruppate, sotto quelle intorno a te, e si toccano', () {
    final stile = stileMappa(scuro: false);
    final sorgente = (stile['sources']! as Map)[sorgenteTutte] as Map;
    expect(sorgente['cluster'], isTrue);
    final strati = [for (final l in (stile['layers']! as List).cast<Map>()) l['id']];
    expect(strati.indexOf('gdanav-tutte-gruppi'), lessThan(strati.indexOf('gdanav-vicine')));
    expect(strati.indexOf('gdanav-tutte'), lessThan(strati.indexOf('gdanav-vicine')));
    expect(stratiToccabili, containsAll(['gdanav-tutte', 'gdanav-tutte-gruppi']));
  });

  /* «Al Centro Direzionale è 1 ma sono 200 prese», e «fai vedere il numero
   * all'esterno»: un'icona è un posto, e il numero che conta sono le prese. */
  test('il numero delle prese: nel bollino fuori dall\'icona, e sommato nei gruppi', () {
    final isolaA3 = Colonnina(
      id: 'pun:a3',
      nome: 'Centro Direzionale Isola A3',
      operatore: 'Plenitude',
      posizione: const Punto(40.858, 14.279),
      connettori: [for (var i = 0; i < 202; i++) const Connettore(tipo: TipoConnettore.tipo2, potenzaKw: 22)],
      fonte: 'pun',
    );
    final mista = Colonnina(
      id: 'mista',
      nome: 'Area di servizio',
      posizione: const Punto(41.9, 12.5),
      connettori: const [
        Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150),
        Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150),
        Connettore(tipo: TipoConnettore.chademo, potenzaKw: 50),
      ],
    );
    // Si contano le prese che l'auto può usare.
    expect(preseAdatte(isolaA3, {TipoConnettore.ccs2, TipoConnettore.tipo2}), 202);
    expect(preseAdatte(mista, {TipoConnettore.ccs2, TipoConnettore.tipo2}), 2);
    final dati = datiColonnineTutte([isolaA3, mista], {TipoConnettore.ccs2, TipoConnettore.tipo2});
    expect([for (final e in (dati['features']! as List).cast<Map>()) (e['properties'] as Map)['prese']], [202, 2]);
    expect(
      ((datiColonnineVicine([isolaA3], {TipoConnettore.tipo2})['features']! as List).single as Map)['properties'],
      containsPair('prese', 202),
    );

    final stile = stileMappa(scuro: true);
    // I gruppi sommano le prese, e il numero nel cerchio è quella somma.
    final sorgente = (stile['sources']! as Map)[sorgenteTutte] as Map;
    expect(sorgente['clusterProperties'], {
      'prese': [
        '+',
        ['get', 'prese'],
      ],
    });
    final strati = (stile['layers']! as List).cast<Map>();
    Map strato(String id) => strati.singleWhere((l) => l['id'] == id);
    expect('${(strato('gdanav-tutte-numeri')['layout'] as Map)['text-field']}', contains('prese'));
    expect('${(strato('gdanav-tutte-numeri')['layout'] as Map)['text-field']}', isNot(contains('point_count')));
    // Il bollino: un cerchio bianco e il numero, spostati in alto a destra
    // sullo schermo, subito sopra l'icona a cui appartengono.
    final ordine = [for (final l in strati) l['id']];
    for (final icona in ['gdanav-tutte', 'gdanav-vicine']) {
      final fondo = strato('$icona-prese-fondo'), numero = strato('$icona-prese');
      expect(ordine.indexOf('$icona-prese-fondo'), ordine.indexOf(icona) + 1);
      expect(ordine.indexOf('$icona-prese'), ordine.indexOf(icona) + 2);
      expect((fondo['paint'] as Map)['circle-translate-anchor'], 'viewport');
      expect((numero['paint'] as Map)['text-translate'], (fondo['paint'] as Map)['circle-translate']);
      // Una presa sola non ha bollino: l'icona basta.
      expect('${fondo['filter']}', contains('[>, [get, prese], 1]'));
    }
    // Sui gruppi niente bollino: il numero ce l'hanno dentro.
    expect('${strato('gdanav-tutte-prese-fondo')['filter']}', contains('point_count'));
  });
}
