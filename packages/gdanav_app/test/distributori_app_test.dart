import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/stato/distributori.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'aiuti.dart';

/// Due distributori veri-finti vicino alla partenza della strada di prova.
ClienteDistributori distributoriFinti() => ClienteDistributori(
  server: [Uri.parse('https://overpass.esempio/api')],
  client: MockClient(
    (_) async => http.Response(
      jsonEncode({
        'elements': [
          {
            'type': 'node',
            'id': 7,
            'lat': 42.005,
            'lon': 12.004,
            'tags': {
              'amenity': 'fuel',
              'name': 'Eni Nord',
              'brand': 'Eni',
              'fuel:diesel': 'yes',
              'opening_hours': '24/7',
            },
          },
          {
            'type': 'node',
            'id': 8,
            'lat': 42.02,
            'lon': 12.0,
            'tags': {'amenity': 'fuel', 'brand': 'Q8', 'fuel:octane_95': 'yes', 'fuel:lpg': 'yes'},
          },
        ],
      }),
      200,
    ),
  ),
);

void main() {
  setUp(() {
    clienteDistributori = distributoriFinti();
    dimenticaDistributori();
  });

  testWidgets("auto termica: il tasto dei distributori, l'elenco dal più vicino e si parte", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20, posizione: const Punto(42, 12));
    await tester.pumpWidget(a.app());
    await tester.pump();
    // Con l'elettrica il tasto non c'è.
    expect(find.byKey(const Key('distributori')), findsNothing);
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    await tester.pump();
    expect(find.byKey(const Key('distributori')), findsOneWidget);

    // Senza posizione lo dice; con la posizione arriva l'elenco.
    a.posizione.avvia();
    a.gps.add(const Lettura(Punto(42, 12)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.tap(find.byKey(const Key('distributori')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Distributori vicini'), findsOneWidget);
    final eni = find.byKey(const Key('distributore-osm-node-7'));
    expect(eni, findsOneWidget);
    expect(find.textContaining('Diesel · 24 ore'), findsOneWidget);
    expect(find.textContaining('Benzina, GPL'), findsOneWidget);
    // Il più vicino in cima.
    expect(tester.getTopLeft(eni).dy, lessThan(tester.getTopLeft(find.byKey(const Key('distributore-osm-node-8'))).dy));

    await tester.tap(eni);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(a.viaggio.destinazione?.nome, 'Eni Nord');
    expect((a.viaggio.stato as ViaggioPronto).termica, isTrue);
  });

  testWidgets('in guida si passa dal distributore e poi si prosegue verso la meta', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final tappe = <List<Punto>>[];
    final a = await ambiente(
      tester,
      km: 20,
      costruisci: (_, profilo, preferenze, _) => PianificatoreViaggio(
        percorsi: (t) async {
          tappe.add(t);
          return dritta(20);
        },
        colonnine: ColonnineFinte(),
        profilo: profilo,
        preferenze: preferenze,
      ),
    );
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    expect(tappe.last, hasLength(2));
    a.guida.avvia();
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[1]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

    const eni = Luogo(nome: 'Eni Nord', posizione: Punto(42.05, 12.001));
    await tester.runAsync(() => a.guida.passaDa(eni));
    expect(a.viaggio.destinazione?.nome, 'Nord');
    expect(a.viaggio.tappa, eni);
    expect(tappe.last, hasLength(3));
    expect(tappe.last[1], eni.posizione);
    expect(a.voce.frasi.last, contains('Passo da Eni Nord'));

    // Arrivati al distributore la tappa è fatta: i ricalcoli vanno dritti alla meta.
    a.posizioni.add(const Punto(42.0502, 12.001));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(a.viaggio.tappa, isNull);
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets("sull'auto: i distributori vicini, e in guida ci si passa", (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    const canale = MethodChannel('gdanav/schermo_auto');
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (_) async => null);
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester, km: 20);
    final ponte = PonteAuto(viaggio: a.viaggio, guida: a.guida, posizione: a.posizione, auto: a.auto, canale: canale)
      ..avvia();
    addTearDown(ponte.ferma);
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    a.posizione.avvia();
    a.gps.add(const Lettura(Punto(42, 12)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

    Future<Object?> chiama(String metodo, [Object? argomenti]) async {
      Object? esito;
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(MethodCall(metodo, argomenti)),
          (dati) => esito = const StandardMethodCodec().decodeEnvelope(dati!),
        ),
      );
      return esito;
    }

    final elenco = (await chiama('distributori'))! as List;
    expect(elenco, hasLength(2));
    expect((elenco.first as Map)['nome'], 'Eni Nord');
    expect((elenco.first as Map)['descrizione'], contains('Diesel'));

    // Fermi: «passa» vuol dire andarci.
    await chiama('passa', {'nome': 'Eni Nord', 'lat': 42.005, 'lon': 12.004});
    expect(a.viaggio.destinazione?.nome, 'Eni Nord');
    expect(a.guida.attiva, isTrue);
    await tester.runAsync(a.guida.ferma);
  });

  testWidgets('coi prezzi del Ministero: prezzo del tuo carburante, più economici, e sull\'auto', (tester) async {
    final oggi = DateTime.now();
    clienteDistributori = _Finti([
      Distributore(
        id: 'mimit-1',
        nome: 'Eni',
        marca: 'Eni',
        posizione: const Punto(42.003, 12),
        indirizzo: 'Viale Roma 1',
        aggiornato: DateTime(oggi.year, oggi.month, oggi.day, 7, 12),
        prezzi: const [
          Prezzo(carburante: Carburante.benzina, euro: 1.859, self: true),
          Prezzo(carburante: Carburante.diesel, euro: 1.759, self: true),
        ],
        carburanti: const {Carburante.benzina, Carburante.diesel},
      ),
      const Distributore(
        id: 'mimit-2',
        nome: 'Rossi Carburanti',
        posizione: Punto(42.02, 12),
        prezzi: [
          Prezzo(carburante: Carburante.benzina, euro: 1.749, self: true),
          Prezzo(carburante: Carburante.diesel, euro: 1.799, self: false),
        ],
        carburanti: {Carburante.benzina, Carburante.diesel},
      ),
    ]);
    dimenticaDistributori();
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20, posizione: const Punto(42, 12));
    await tester.runAsync(() => a.auto.impostaElettrica(false));
    await tester.runAsync(() => a.auto.impostaCarburante(Carburante.diesel));
    expect(await tester.runAsync(a.archivio.carburante), Carburante.diesel);
    await tester.pumpWidget(a.app());
    await tester.pump();
    a.posizione.avvia();
    a.gps.add(const Lettura(Punto(42, 12)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.tap(find.byKey(const Key('distributori')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    // Il diesel dell'auto: 1,759 all'Eni (il più economico) e 1,799 servito da Rossi.
    expect(
      find.descendant(of: find.byKey(const Key('prezzo-mimit-1')), matching: find.text('1,759 €')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key('prezzo-mimit-2')), matching: find.text('servito')),
      findsOneWidget,
    );
    expect(find.textContaining('prezzo di oggi 07:12'), findsOneWidget);
    expect(find.textContaining('Osservaprezzi'), findsOneWidget);
    double y(String id) => tester.getTopLeft(find.byKey(Key('distributore-$id'))).dy;
    expect(y('mimit-1'), lessThan(y('mimit-2'))); // il più vicino in cima

    // Benzina e più economici: Rossi sale in cima.
    await tester.tap(find.byKey(const Key('carburante-benzina')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Più economici'));
    await tester.pumpAndSettle();
    expect(find.text('1,749 €'), findsOneWidget);
    expect(y('mimit-2'), lessThan(y('mimit-1')));
    await tester.tap(find.byKey(const Key('distributore-mimit-2')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(a.viaggio.destinazione?.nome, 'Rossi Carburanti');
    expect(a.viaggio.destinazione?.descrizione, contains('Benzina 1,749 € self'));
  });
}

class _Finti implements FonteDistributori {
  _Finti(this.elenco);
  final List<Distributore> elenco;

  @override
  Future<List<Distributore>> vicino(Punto qui, {double km = 5, int quanti = 20}) async => elenco;
}
