import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/mappa/categorie_poi.dart';
import 'package:gdanav_app/mappa/stile.dart';
import 'package:gdanav_app/schermate/scheda_punto.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/gestore_vicini.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

final eni = Distributore(
  id: 'mimit-1',
  nome: 'Eni',
  marca: 'Eni',
  indirizzo: 'Viale Roma 1',
  posizione: const Punto(42.003, 12),
  aggiornato: DateTime.now(),
  prezzi: const [
    Prezzo(carburante: Carburante.benzina, euro: 1.859, self: true),
    Prezzo(carburante: Carburante.benzina, euro: 1.999, self: false),
    Prezzo(carburante: Carburante.diesel, euro: 1.759, self: true),
  ],
  carburanti: const {Carburante.benzina, Carburante.diesel},
);

const ionity = Colonnina(
  id: 'osm-node-9',
  nome: 'Ionity Roma Nord',
  operatore: 'IONITY',
  posizione: Punto(42.01, 12.01),
  connettori: [
    Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 350),
    Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 350),
  ],
  fonte: 'osm',
);

void main() {
  test('i punti di interesse come Google Maps: categoria, icona e colore dai valori di OpenStreetMap', () {
    expect(categoriaPoi('restaurant', 'restaurant').nome, 'ristorante');
    expect(categoriaPoi('clothes', 'shop').nome, 'negozio');
    expect(categoriaPoi(null, 'lodging').nome, 'hotel');
    expect(categoriaPoi('pharmacy', 'pharmacy').etichetta, 'Farmacia');
    expect(categoriaPoi('qualcosa', 'altro').nome, 'altro');
    final stile = stileMappa(scuro: false);
    final poi = (stile['layers']! as List).cast<Map>().firstWhere((l) => l['id'] == 'nomi-poi');
    expect((poi['layout'] as Map)['icon-image'], isA<List>());
    expect(stratiToccabili, containsAll(['nomi-poi', 'gdanav-distributori', 'gdanav-vicine']));
  });

  test('dal tocco sulla mappa al punto: distributore, colonnina, ristorante; il resto no', () {
    Map<String, Object?> e(Map<String, Object?> p) => {
      'properties': p,
      'geometry': {
        'type': 'Point',
        'coordinates': [12.0, 42.0],
      },
    };
    expect(PuntoToccato.daElemento(e({'tipo': 'distributore', 'id': 'mimit-1', 'nome': 'Eni'}))!.tipo, 'distributore');
    expect(PuntoToccato.daElemento(e({'tipo': 'colonnina', 'id': 'x', 'nome': 'Ionity'}))!.id, 'x');
    final r = PuntoToccato.daElemento(e({'class': 'restaurant', 'subclass': 'restaurant', 'name': 'Da Mario'}))!;
    expect((r.tipo, r.nome, r.posizione.lat), ('poi', 'Da Mario', 42.0));
    expect(PuntoToccato.daElemento(e({'class': 'restaurant'})), isNull);
    expect(PuntoToccato.daElemento(e({'id': 'sosta'})), isNull);
  });

  /* La scheda sopra la mappa dell'auto lascia vedere la mappa: il punto
   * toccato ha intorno un anello del colore del suo stato, sotto la sua
   * icona. Sul telefono la scheda copre la mappa, e l'anello non serve. */
  test('sulla mappa dell\'auto il punto della scheda aperta ha il suo anello', () {
    List<String> strati(Map<String, Object> s) => [
      for (final l in (s['layers']! as List).cast<Map>()) l['id'] as String,
    ];
    final auto = stileMappa(scuro: false, perAuto: true);
    final telefono = stileMappa(scuro: false);
    expect((auto['sources']! as Map)[sorgenteEvidenza], isNotNull);
    expect((telefono['sources']! as Map)[sorgenteEvidenza], isNull);
    expect(strati(telefono), isNot(contains('evidenza')));
    final ids = strati(auto);
    expect(ids.indexOf('evidenza-alone'), lessThan(ids.indexOf('evidenza')));
    expect(ids.indexOf('evidenza'), lessThan(ids.indexOf('gdanav-vicine')));
    expect(ids.indexOf('evidenza'), lessThan(ids.indexOf('gdanav-distributori')));
    final anello = (auto['layers']! as List).cast<Map>().singleWhere((l) => l['id'] == 'evidenza');
    final colore = (anello['paint'] as Map)['circle-stroke-color'] as List;
    // Verde la libera, arancio la piena, rosso la guasta; blu un distributore.
    expect(colore.sublist(2, 8), ['libera', '#16A34A', 'piena', '#D97706', 'guasta', '#DC2626']);
    expect(colore.last, startsWith('#'));
  });

  testWidgets('intorno a te: distributori con la termica, colonnine con l\'elettrica; e le schede al tocco', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    var chiesteColonnine = 0;
    final vicini = GestoreVicini(
      auto: a.auto,
      posizione: a.posizione,
      distributori: (_) async => [eni],
      colonnine: (_, _) async {
        chiesteColonnine++;
        return [ionity];
      },
    );
    addTearDown(vicini.dispose);
    a.posizione.avvia();
    a.gps.add(const Lettura(Punto(42, 12)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(vicini.colonnine, [ionity]);
    expect(vicini.distributori, isEmpty);
    final colonnine = vicini.dati()['gdanav-vicine']!['features']! as List;
    expect(((colonnine.single as Map)['properties'] as Map)['etichetta'], '350 kW');

    // Termica: i distributori, col prezzo del proprio carburante sulla mappa.
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    await tester.runAsync(() => a.auto.impostaCarburante(Carburante.diesel));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(vicini.distributori, [eni]);
    final pompe = vicini.dati()['gdanav-distributori']!['features']! as List;
    expect(((pompe.single as Map)['properties'] as Map)['etichetta'], '1,759');
    // Spostandosi di poco non si richiede.
    final prima = chiesteColonnine;
    a.gps.add(const Lettura(Punto(42.001, 12)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(chiesteColonnine, prima);

    // Tocco sul distributore: la scheda coi prezzi e «Vai».
    Luogo? scelto;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => mostraPunto(
                  context,
                  PuntoToccato(tipo: 'distributore', id: eni.id, nome: 'Eni', posizione: eni.posizione),
                  vicini: vicini,
                  qui: const Punto(42, 12),
                  carburante: Carburante.diesel,
                  onVai: (l) => scelto = l,
                ),
                child: const Text('apri'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scheda-punto-distributore')), findsOneWidget);
    expect(find.text('Eni · Viale Roma 1'), findsNothing); // la marca è il nome
    expect(find.text('Viale Roma 1'), findsOneWidget);
    expect(find.text('1,859 €'), findsOneWidget);
    expect(find.text('1,999 €'), findsOneWidget);
    expect(find.text('1,759 €'), findsOneWidget);
    expect(find.text('Servito'), findsOneWidget);
    expect(find.text('A 330 m da te'), findsOneWidget);
    await tester.tap(find.byKey(const Key('vai-punto')));
    await tester.pumpAndSettle();
    expect(scelto!.nome, 'Eni');
    expect(scelto!.descrizione, contains('Diesel 1,759 € self'));
  });

  testWidgets('sulla mappa dell\'auto: toccando un punto il telefono dice cosa è', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    const canale = MethodChannel('gdanav/schermo_auto');
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (_) async => null);
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester);
    final vicini = GestoreVicini(
      auto: a.auto,
      posizione: a.posizione,
      distributori: (_) async => [eni],
      colonnine: (_, _) async => [ionity],
    );
    addTearDown(vicini.dispose);
    final ponte = PonteAuto(
      viaggio: a.viaggio,
      guida: a.guida,
      posizione: a.posizione,
      auto: a.auto,
      vicini: vicini,
      canale: canale,
    )..avvia();
    addTearDown(ponte.ferma);
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    a.posizione.avvia();
    a.gps.add(const Lettura(Punto(42, 12)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));

    Future<Map> chiama(Map<String, Object?> argomenti) async {
      Object? esito;
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(MethodCall('punto', argomenti)),
          (dati) => esito = const StandardMethodCodec().decodeEnvelope(dati!),
        ),
      );
      return esito! as Map;
    }

    final d = await chiama({
      'proprieta': {'tipo': 'distributore', 'id': 'mimit-1', 'nome': 'Eni'},
      'lat': 42.003,
      'lon': 12.0,
    });
    expect(d['titolo'], 'Eni');
    final voci = [for (final v in d['voci'] as List) (v as Map).cast<String, Object?>()];
    expect(voci.first, {
      'icona': 'distributore',
      'colore': 'verde',
      'titolo': 'Distributore',
      'testo': '330 m · Viale Roma 1',
    });
    expect(voci[1], {
      'icona': 'prezzo',
      'colore': 'giallo',
      'titolo': 'Benzina: 1,859 € self · 1,999 € servito',
      'testo': null,
    });
    expect(voci.last['titolo'], 'Diesel: 1,759 € self');
    expect(voci.last['testo'], startsWith('prezzi comunicati'));
    expect(d['stato'], isNull);
    expect(d['vai'], 'Vai');
    final r = await chiama({
      'proprieta': {'class': 'restaurant', 'subclass': 'restaurant', 'name': 'Da Mario'},
      'lat': 42.0,
      'lon': 12.001,
    });
    expect((r['voci'] as List).single, containsPair('titolo', 'Ristorante'));
    expect((r['voci'] as List).single, containsPair('icona', 'luogo'));
    expect((r['luogo'] as Map)['nome'], 'Da Mario');
  });

  /* «Se interrogo la colonnina mi deve dare indicazione dei prezzi.» La
   * scheda in auto dice potenza, prese libere col loro colore, e la tariffa
   * della corrente con cui quell'auto caricherebbe lì. */
  testWidgets('sulla mappa dell\'auto: la colonnina toccata dice prese libere e prezzo', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    const canale = MethodChannel('gdanav/schermo_auto');
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (_) async => null);
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester);
    var stati = [StatoPresa.disponibile, StatoPresa.occupata];
    Prezzi? prezzi = const Prezzi({
      Corrente.ac: Tariffa(energia: (da: 0.59, a: 0.59)),
      Corrente.hpc: Tariffa(energia: (da: 0.69, a: 0.69), sosta: (da: 0.15, a: 0.15), avvio: (da: 1.14, a: 1.14)),
    });
    final vicini = GestoreVicini(
      auto: a.auto,
      posizione: a.posizione,
      distributori: (_) async => const [],
      colonnine: (_, _) async => [ionity],
      tutte: (_) async => const [],
      statiDiTutti: () async => const {},
      statoAdesso: (c) async => Colonnina(
        id: c.id,
        nome: c.nome,
        posizione: c.posizione,
        operatore: c.operatore,
        fonte: c.fonte,
        connettori: [for (final (i, p) in c.connettori.indexed) p.conStato(stati[i])],
        prezzi: prezzi,
      ),
      ogniQuanto: Duration.zero,
    );
    addTearDown(vicini.dispose);
    final ponte = PonteAuto(
      viaggio: a.viaggio,
      guida: a.guida,
      posizione: a.posizione,
      auto: a.auto,
      vicini: vicini,
      canale: canale,
    )..avvia();
    addTearDown(ponte.ferma);
    a.posizione.avvia();
    a.gps.add(const Lettura(Punto(42, 12)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(vicini.colonnina('osm-node-9'), isNotNull);

    Future<Map> tocca() async {
      Object? esito;
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('punto', {
              'proprieta': {'tipo': 'colonnina', 'id': 'osm-node-9', 'nome': 'Ionity Roma Nord'},
              'lat': 42.01,
              'lon': 12.01,
            }),
          ),
          (dati) => esito = const StandardMethodCodec().decodeEnvelope(dati!),
        ),
      );
      return esito! as Map;
    }

    final libera = await tocca();
    final voci = [for (final v in libera['voci'] as List) (v as Map).cast<String, Object?>()];
    expect(voci, hasLength(3));
    expect(voci[0], containsPair('icona', 'potenza'));
    expect(voci[0]['titolo'], '350 kW · IONITY');
    expect(voci[0]['testo'], endsWith('colonnina di ricarica'));
    expect(voci[1], {'icona': 'presa', 'colore': 'verde', 'titolo': '1 libera su 2', 'testo': 'stato di adesso'});
    // Una rapida: il prezzo della continua ad alta potenza, non dell'alternata.
    expect(voci[2], {
      'icona': 'prezzo',
      'colore': 'giallo',
      'titolo': '0,69 €/kWh ad alta potenza',
      'testo': 'sosta 0,15 €/min · avvio 1,14 €',
    });
    expect(libera['stato'], 'libera');
    expect((libera['luogo'] as Map)['descrizione'], '350 kW · IONITY');

    stati = [StatoPresa.occupata, StatoPresa.occupata];
    prezzi = Prezzi.nessuno;
    final piena = await tocca();
    final altre = [for (final v in piena['voci'] as List) (v as Map).cast<String, Object?>()];
    expect(altre[1], containsPair('colore', 'rosso'));
    expect(altre[1]['titolo'], 'Piena · 2 occupate');
    expect(altre[2], {
      'icona': 'prezzo',
      'colore': null,
      'titolo': 'Prezzo non comunicato',
      'testo': 'il gestore non lo manda alla PUN',
    });
    expect(piena['stato'], 'piena');
  });
}
