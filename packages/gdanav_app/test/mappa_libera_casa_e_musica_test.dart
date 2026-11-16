// La casa e la musica anche a mappa libera, senza un percorso: sul telefono,
// e sullo schermo dell'auto (Android Auto e CarPlay) appena è acceso. Dal
// campo: «Lavatrice finita» arrivata sul telefono ma non in Android Auto, e
// «non vedo musica da nessuna parte» sulla mappa senza destinazione. Nomi
// inventati.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_app/componenti/avviso_di_casa.dart';
import 'package:gdanav_app/componenti/mini_lettore.dart';
import 'package:gdanav_app/gdanav_app.dart' show GdanavApp;
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_casa_in_guida.dart';

import 'aiuti.dart';

/// Una notifica come la manda il postino di GdAHome (`al_navigatore.dart`).
Map<String, Object?> _lavatrice() => {
  'v': 1,
  'id': 'lavatrice-1',
  'tipo': 'elettrodomestici',
  'cat': 'casa',
  'urg': 'normale',
  'titolo': '🧺 Lavatrice finita',
  'testo': '1 h 52 min · 0,21 €',
  'quando': 1790000000000,
  '_casa': 'Villa Gialla',
  '_casa_id': 'casa-1',
};

/// Il campanello: importante, quindi anche a voce.
Map<String, Object?> _campanello({String id = 'campanello-1'}) => {
  'v': 1,
  'id': id,
  'tipo': 'campanello',
  'cat': 'sicurezza',
  'urg': 'urgente',
  'titolo': '🔔 Suonano al cancello',
  'testo': 'Corriere',
  'quando': 1790000000000,
  '_casa': 'Villa Gialla',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('gli avvisi di casa fuori dalla guida', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('senza percorso passano con lo schermo dell\'auto acceso o la mappa in vista', () async {
      final guida = ChangeNotifier();
      final frasi = <String>[];
      final g = GestoreCasaInGuida(
        archivio: Archivio(),
        coda: CodaAvvisiDiCasa(onVoce: frasi.add),
        inGuida: () => false,
        guida: guida,
      );
      addTearDown(g.dispose);
      await g.carica();
      // Né guida, né auto, né mappa: resta solo sul telefono.
      g.arrivata(_lavatrice());
      expect(g.coda!.attuale, isNull);
      // Android Auto acceso, mappa libera (il caso del campo).
      g.schermoDellAuto(true);
      g.arrivata(_lavatrice());
      expect(g.coda!.attuale?.titolo, 'Lavatrice finita');
      expect(g.coda!.attuale?.casa, 'Villa Gialla');
      // Scesi dall'auto: la coda si svuota.
      g.schermoDellAuto(false);
      expect(g.coda!.attuale, isNull);
      // La mappa del telefono davanti: la scheda sì, la voce no.
      final prima = frasi.length;
      g.mappaInVista(true);
      g.arrivata(_campanello());
      expect(g.coda!.attuale?.titolo, 'Suonano al cancello');
      expect(frasi.length, prima, reason: 'a mappa libera sul telefono non si parla');
      g.mappaInVista(false);
      expect(g.coda!.attuale, isNull);
    });

    test('in auto a mappa libera l\'avviso si dice anche a voce', () async {
      final frasi = <String>[];
      final g = GestoreCasaInGuida(
        archivio: Archivio(),
        coda: CodaAvvisiDiCasa(onVoce: frasi.add),
        inGuida: () => false,
      );
      addTearDown(g.dispose);
      await g.carica();
      g.schermoDellAuto(true);
      g.arrivata(_campanello());
      expect(frasi, ['Suonano al cancello']);
    });
  });

  testWidgets('«Lavatrice finita» va ad Android Auto anche senza percorso', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    const canale = MethodChannel('gdanav/schermo_auto');
    final chiamate = <MethodCall>[];
    final messaggero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messaggero.setMockMethodCallHandler(canale, (c) async {
      chiamate.add(c);
      return null;
    });
    addTearDown(() => messaggero.setMockMethodCallHandler(canale, null));
    final a = await ambiente(tester, km: 20);
    // Il filo di GdAHome (`ascoltaLeNotifiche`): qui un flusso.
    final notifiche = StreamController<Map<String, Object?>>();
    addTearDown(notifiche.close);
    final casa = GestoreCasaInGuida(
      archivio: a.archivio,
      notifiche: notifiche.stream,
      inGuida: () => a.guida.attiva,
      guida: a.guida,
    );
    addTearDown(casa.dispose);
    await tester.runAsync(casa.carica);
    final ponte = PonteAuto(
      viaggio: a.viaggio,
      guida: a.guida,
      posizione: a.posizione,
      casaInGuida: casa,
      canale: canale,
    )..avvia();
    addTearDown(ponte.ferma);
    await tester.pump();

    Future<void> dallAuto(String metodo, Map<String, Object?> dati) async {
      await tester.runAsync(
        () => messaggero.handlePlatformMessage(
          'gdanav/schermo_auto',
          const StandardMethodCodec().encodeMethodCall(MethodCall(metodo, dati)),
          (_) {},
        ),
      );
      await tester.pump();
    }

    Future<List<Map<Object?, Object?>>> mandati() async {
      // L'icona si disegna fuori dal tempo finto.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      return [
        for (final c in chiamate)
          if (c.method == 'avviso_casa') c.arguments as Map<Object?, Object?>,
      ];
    }

    expect(a.guida.attiva, isFalse, reason: 'mappa libera: nessun percorso');
    // Lo schermo dell'auto si accende (`SessioneGdanav.onStart`).
    await dallAuto('in_auto', {'si': true});
    notifiche.add(_lavatrice());
    await tester.pump();
    final arrivati = await mandati();
    expect(arrivati.last['titolo'], 'Lavatrice finita');
    expect(arrivati.last['testo'], '1 h 52 min · 0,21 €');
    // Spento lo schermo dell'auto, via anche dall'auto.
    await dallAuto('in_auto', {'si': false});
    expect((await mandati()).last, isEmpty);
    casa.coda?.chiudi();
  });

  group('sul telefono, a mappa libera', () {
    Future<({GestoreCasaInGuida casa, CodaAvvisiDiCasa coda, LettoreFinto lettore})> apri(
      WidgetTester tester, {
      bool musica = true,
    }) async {
      preparaPiattaforma(portachiavi: impostazioniComplete);
      final a = await ambiente(tester, km: 20);
      tester.view
        ..physicalSize = const Size(390 * 3, 844 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final lettore = LettoreFinto(
        brani: const [BranoInAscolto(titolo: 'Strade di notte', artista: 'Le Lucciole')],
      );
      addTearDown(lettore.dispose);
      final coda = CodaAvvisiDiCasa(durata: const Duration(seconds: 9));
      final casa = GestoreCasaInGuida(
        archivio: a.archivio,
        coda: coda,
        lettore: lettore,
        inGuida: () => a.guida.attiva,
        guida: a.guida,
      );
      addTearDown(casa.dispose);
      await tester.runAsync(casa.carica);
      if (!musica) await tester.runAsync(() => casa.cambiaMusica(false));
      await tester.pumpWidget(
        GdanavApp(
          posizione: a.posizione,
          archivio: a.archivio,
          auto: a.auto,
          viaggio: a.viaggio,
          guida: a.guida,
          segnalazioni: a.segnalazioni,
          casaInGuida: casa,
          mappa: (context, c) => const ColoredBox(color: Colors.grey),
        ),
      );
      await tester.pumpAndSettle();
      return (casa: casa, coda: coda, lettore: lettore);
    }

    testWidgets('il mini-lettore c\'è, in cima al pannello, largo, senza coprire la mappa', (tester) async {
      await apri(tester);
      expect(find.text('Dove andiamo?'), findsOneWidget, reason: 'nessun percorso');
      final lettore = find.byKey(const Key('mini-lettore'));
      expect(lettore, findsOneWidget);
      expect(find.text('Strade di notte'), findsOneWidget);
      final r = tester.getRect(lettore);
      final pannello = tester.getRect(
        find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Material)).first,
      );
      // Dentro il pannello, sopra «Dove andiamo?»: la mappa resta libera.
      expect(r.top, greaterThanOrEqualTo(pannello.top));
      expect(r.bottom, lessThanOrEqualTo(tester.getRect(find.text('Dove andiamo?')).top));
      // Largo quasi quanto lo schermo: il titolo si legge (nelle prove i
      // caratteri sono quadrati, la misura del testo non direbbe niente).
      expect(r.width, greaterThan(320));
      // Né «Segnala» né i tasti della mappa ci finiscono sopra.
      expect(r.overlaps(tester.getRect(find.byTooltip('Segnala').first)), isFalse);
      expect(r.overlaps(tester.getRect(find.byTooltip('Dove sono').first)), isFalse);
      // E i tasti vanno al lettore.
      await tester.tap(find.byKey(const Key('lettore-successivo')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('con «Musica nel navigatore» spenta non c\'è', (tester) async {
      await apri(tester, musica: false);
      expect(find.text('Dove andiamo?'), findsOneWidget);
      expect(find.byKey(const Key('mini-lettore')), findsNothing);
      expect(find.byKey(const Key('invito-musica')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('senza il permesso, da fermi, l\'invito una volta', (tester) async {
      final x = await apri(tester);
      x.lettore
        ..permesso = false
        ..notifyListeners();
      await tester.pump();
      expect(find.byKey(const Key('invito-musica')), findsOneWidget);
      await tester.tap(find.byKey(const Key('invito-musica-si')));
      await tester.pump();
      expect(x.lettore.comandi, contains('permesso'));
      expect(x.casa.invitoDaMostrare, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('l\'avviso di casa arriva anche senza percorso, sotto il menu', (tester) async {
      final x = await apri(tester);
      x.casa.arrivata(_lavatrice());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final scheda = find.byKey(const Key('avviso-casa'));
      expect(scheda, findsOneWidget);
      expect(find.text('Lavatrice finita'), findsOneWidget);
      final r = tester.getRect(scheda);
      expect(r.top, greaterThan(tester.getRect(find.byTooltip('Menu').first).bottom));
      expect(r.overlaps(tester.getRect(find.byTooltip('Dove sono').first)), isFalse);
      expect(r.overlaps(tester.getRect(find.byKey(const Key('mini-lettore')))), isFalse);
      x.coda.chiudi();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
