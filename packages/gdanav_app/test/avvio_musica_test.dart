// Far partire la musica da zero dal navigatore: la pillola «▶ Spotify» quando
// niente suona, «Avvio Spotify…», il messaggio se non parte, la scelta
// dell'app («App della musica») e quello che va e torna dal lato nativo.
// Nomi inventati, tranne le app vere da far partire.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/avviso_di_casa.dart';
import 'package:gdanav_app/componenti/mini_lettore.dart';
import 'package:gdanav_app/gdanav_app.dart' show NotificheNelNavigatoreSchermata;
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_casa_in_guida.dart';
import 'package:gdanav_app/tema.dart';

const _spotify = AppDellaMusica(pacchetto: 'com.spotify.music', nome: 'Spotify');
const _yt = AppDellaMusica(pacchetto: 'com.google.android.apps.youtube.music', nome: 'YouTube Music');
const _radio = AppDellaMusica(pacchetto: 'it.esempio.radio', nome: 'Radio Lungomare');

Widget _lettore(LettoreMusicale l, {bool inMovimento = false}) => MaterialApp(
  theme: temaGdanav(Brightness.light),
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomCenter,
      child: MiniLettore(lettore: l, inMovimento: inMovimento),
    ),
  ),
);

String _testo(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('lettore-avvio-testo'))).data!;

void main() {
  group('la pillola ▶ quando niente suona', () {
    testWidgets('«▶ Spotify»: c\'è, si tocca tutta, e fa partire Spotify (da fermi)', (tester) async {
      final l = LettoreFinto(app: null, prossima: _spotify);
      addTearDown(l.dispose);
      await tester.pumpWidget(_lettore(l));
      expect(find.byKey(const Key('mini-lettore')), findsNothing);
      final pillola = find.byKey(const Key('lettore-avvio'));
      expect(pillola, findsOneWidget);
      expect(_testo(tester), 'Spotify');
      expect(find.bySemanticsLabel('Fai partire Spotify'), findsOneWidget);
      // Alta almeno 48: si prende col dito.
      expect(tester.getSize(pillola).height, greaterThanOrEqualTo(48));
      // Anche sul nome, non solo su ▶.
      await tester.tap(find.byKey(const Key('lettore-avvio-testo')));
      await tester.pump();
      expect(l.comandi, ['parti:fermo']);
      // Mentre parte: «Avvio Spotify…» coi tre puntini, e un altro tocco non
      // fa partire niente due volte.
      expect(_testo(tester), 'Avvio Spotify…');
      expect(find.byKey(const Key('lettore-avvio-in-corso')), findsOneWidget);
      await tester.tap(pillola);
      await tester.pump();
      expect(l.comandi, ['parti:fermo']);
      // Partita: arriva il brano, e al posto della pillola il riquadro.
      final suona = LettoreFinto(
        brani: const [BranoInAscolto(titolo: 'Strade di notte', artista: 'Le Lucciole')],
      );
      addTearDown(suona.dispose);
      await tester.pumpWidget(_lettore(suona));
      expect(find.byKey(const Key('lettore-avvio')), findsNothing);
      expect(find.byKey(const Key('mini-lettore')), findsOneWidget);
      expect(find.text('Strade di notte'), findsOneWidget);
    });

    testWidgets('in marcia ▶ parte lo stesso, ma senza aprire l\'app', (tester) async {
      final l = LettoreFinto(app: null, prossima: _spotify);
      addTearDown(l.dispose);
      await tester.pumpWidget(_lettore(l, inMovimento: true));
      await tester.tap(find.byKey(const Key('lettore-avvio')));
      await tester.pump();
      expect(l.comandi, ['parti']);
    });

    testWidgets('non partita: il messaggio nella pillola, per qualche secondo', (tester) async {
      final l = LettoreFinto(app: null, prossima: _spotify);
      addTearDown(l.dispose);
      await tester.pumpWidget(_lettore(l));
      l
        ..esito = 'Spotify non è partito: aprilo quando sei fermo'
        ..notifyListeners();
      await tester.pump();
      expect(_testo(tester), 'Spotify non è partito: aprilo quando sei fermo');
      l
        ..esito = null
        ..notifyListeners();
      await tester.pump();
      expect(_testo(tester), 'Spotify');
    });

    testWidgets('senza un\'app da far partire: da fermi la scelta, poi parte quella', (tester) async {
      final l = LettoreFinto(app: null, appInstallate: const [_radio, _yt]);
      addTearDown(l.dispose);
      await tester.pumpWidget(_lettore(l));
      expect(_testo(tester), 'Scegli la musica');
      expect(find.bySemanticsLabel('Scegli l\'app della musica'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lettore-avvio')));
      await tester.pumpAndSettle();
      expect(find.text('Quale musica far partire?'), findsOneWidget);
      expect(find.byKey(const Key('app-musica-${'com.google.android.apps.youtube.music'}')), findsOneWidget);
      await tester.tap(find.text('YouTube Music'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      // Parte: «Avvio YouTube Music…».
      expect(find.byKey(const Key('lettore-avvio-in-corso')), findsOneWidget);
      expect(_testo(tester), 'Avvio YouTube Music…');
      expect(find.text('Quale musica far partire?'), findsNothing);
      expect(l.comandi, ['scegli:com.google.android.apps.youtube.music', 'parti:fermo']);
      expect(l.prossima?.nome, 'YouTube Music');
    });

    testWidgets('senza un\'app da far partire, in marcia: niente elenco, si dice di scegliere da fermo', (
      tester,
    ) async {
      final l = LettoreFinto(app: null, appInstallate: const [_yt]);
      addTearDown(l.dispose);
      await tester.pumpWidget(_lettore(l, inMovimento: true));
      await tester.tap(find.byKey(const Key('lettore-avvio')));
      await tester.pumpAndSettle();
      expect(find.text('Quale musica far partire?'), findsNothing);
      expect(l.comandi, isEmpty);
      expect(_testo(tester), 'Scegli l\'app della musica da fermo');
      // Dopo qualche secondo torna com'era.
      await tester.pump(LettoreDelTelefono.durataEsito + const Duration(milliseconds: 100));
      expect(_testo(tester), 'Scegli la musica');
    });

    testWidgets('senza permesso, o sull\'iPhone, niente pillola', (tester) async {
      final senza = LettoreFinto(app: null, prossima: _spotify, permesso: false);
      addTearDown(senza.dispose);
      await tester.pumpWidget(_lettore(senza));
      expect(find.byKey(const Key('lettore-avvio')), findsNothing);
      final iPhone = LettoreFinto(app: null, fonte: FonteMusica.sistema);
      addTearDown(iPhone.dispose);
      await tester.pumpWidget(_lettore(iPhone));
      expect(find.byKey(const Key('lettore-avvio')), findsNothing);
    });
  });

  group('la scelta dell\'app', () {
    test('quale si vede scelta: la scelta, se no Spotify di serie, se no l\'ultima', () {
      const conSpotify = [_spotify, _yt];
      expect(const ElencoAppMusica(app: conSpotify).selezionata, 'com.spotify.music');
      expect(
        const ElencoAppMusica(app: conSpotify, scelta: 'com.google.android.apps.youtube.music').selezionata,
        _yt.pacchetto,
      );
      expect(const ElencoAppMusica(app: conSpotify, scelta: 'ultima').selezionata, 'ultima');
      // Una scelta disinstallata: di serie.
      expect(const ElencoAppMusica(app: conSpotify, scelta: 'via.di.qui').selezionata, 'com.spotify.music');
      // Senza Spotify: l'ultima che ha suonato.
      expect(const ElencoAppMusica(app: [_yt], ultima: 'it.esempio.radio').selezionata, 'ultima');
      expect(
        const ElencoAppMusica(app: [_yt, _radio], ultima: 'it.esempio.radio').nomeDi('it.esempio.radio'),
        'Radio Lungomare',
      );
    });

    testWidgets('nelle impostazioni: l\'elenco, Spotify di serie, e la scelta resta', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final musica = LettoreFinto(appInstallate: const [_spotify, _yt], ultima: _yt.pacchetto);
      addTearDown(musica.dispose);
      final g = GestoreCasaInGuida(archivio: Archivio(), coda: CodaAvvisiDiCasa(), lettore: musica);
      addTearDown(g.dispose);
      await tester.runAsync(g.carica);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaGdanav(Brightness.light),
          home: NotificheNelNavigatoreSchermata(gestore: g),
        ),
      );
      await tester.pump();
      // Fino alla nota sotto l'elenco: tutta la scelta in vista.
      await tester.scrollUntilVisible(find.textContaining('anche se è chiusa'), 200);
      expect(find.text('App della musica'), findsOneWidget);
      RadioGroup<String> gruppo() => tester.widget<RadioGroup<String>>(find.byType(RadioGroup<String>));
      expect(gruppo().groupValue, 'com.spotify.music');
      expect(find.text('Di serie'), findsOneWidget);
      // «L'ultima che ha suonato» dice quale.
      expect(
        find.descendant(of: find.byKey(const Key('app-musica-ultima')), matching: find.text('YouTube Music')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('app-musica-ultima')));
      await tester.pump();
      await tester.pump();
      expect(musica.comandi, contains('scegli:ultima'));
      expect(gruppo().groupValue, 'ultima');
      expect(find.text('Di serie'), findsNothing);
      // Spenta la musica, la scelta non c'è più.
      await tester.scrollUntilVisible(find.byKey(const Key('musica-nel-navigatore')), -200);
      await tester.tap(find.byKey(const Key('musica-nel-navigatore')));
      await tester.pump();
      expect(find.byKey(const Key('app-della-musica')), findsNothing);
    });

    testWidgets('sull\'iPhone, o senza permesso, la scelta non c\'è', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      for (final musica in [
        LettoreFinto(fonte: FonteMusica.sistema, appInstallate: const [_spotify]),
        LettoreFinto(permesso: false, appInstallate: const [_spotify]),
      ]) {
        addTearDown(musica.dispose);
        final g = GestoreCasaInGuida(archivio: Archivio(), lettore: musica);
        addTearDown(g.dispose);
        await tester.runAsync(g.carica);
        await tester.pumpWidget(
          MaterialApp(
            theme: temaGdanav(Brightness.light),
            home: NotificheNelNavigatoreSchermata(gestore: g),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('app-della-musica')), findsNothing);
      }
    });

    testWidgets('nessuna app della musica sul telefono: lo dice', (tester) async {
      final l = LettoreFinto(app: null);
      addTearDown(l.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SceltaAppDellaMusica(avvio: l)),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('app-musica-nessuna')), findsOneWidget);
      expect(find.byKey(const Key('app-musica-ultima')), findsOneWidget);
    });
  });

  group('dal lato nativo (Android)', () {
    const canale = MethodChannel('gdanav/musica');
    final chiamate = <MethodCall>[];
    Object? risposta;

    setUp(() {
      chiamate.clear();
      risposta = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canale, (c) async {
        chiamate.add(c);
        return risposta;
      });
    });
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canale, null),
    );

    testWidgets('lo stato: prossima, in avvio, l\'esito una volta e per qualche secondo', (tester) async {
      final l = LettoreDelTelefono(fonte: FonteMusica.telefono);
      addTearDown(l.dispose);
      final icona = Uint8List.fromList([137, 80, 78, 71]);
      l.leggi({
        'permesso': true,
        'avviabile': true,
        'prossima': {'pacchetto': 'com.spotify.music', 'nome': 'Spotify', 'icona': icona},
        'in_avvio': false,
      });
      expect(l.puoAvviare, isTrue);
      expect(l.prossima?.nome, 'Spotify');
      final prima = l.prossima?.icona;
      expect(prima, isNotNull);
      // La stessa icona non si rifà: non lampeggia.
      l.leggi({
        'permesso': true,
        'avviabile': true,
        'prossima': {'pacchetto': 'com.spotify.music', 'nome': 'Spotify', 'icona': Uint8List.fromList(icona)},
        'in_avvio': true,
        'nome_in_avvio': 'Spotify',
      });
      expect(identical(l.prossima?.icona, prima), isTrue);
      expect(l.inAvvio, isTrue);
      expect(l.nomeInAvvio, 'Spotify');
      // Non partita: il messaggio, e al lato nativo che è stato detto.
      final nonPartita = {'permesso': true, 'avviabile': true, 'esito': 'Spotify non è partito', 'esito_id': 3};
      l.leggi(nonPartita);
      await tester.pump();
      expect(l.esito, 'Spotify non è partito');
      expect(l.inAvvio, isFalse);
      expect(chiamate.map((c) => (c.method, c.arguments)), [('esitoDetto', 3)]);
      // Lo stesso esito che torna non si ridice, e non allunga il tempo.
      l.leggi(nonPartita);
      expect(chiamate, hasLength(1));
      await tester.pump(LettoreDelTelefono.durataEsito);
      expect(l.esito, isNull);
    });

    test('l\'iPhone non manda «avviabile»: niente avvio', () {
      final l = LettoreDelTelefono(fonte: FonteMusica.sistema);
      addTearDown(l.dispose);
      l.leggi({'permesso': true, 'titolo': ''});
      expect(l.puoAvviare, isFalse);
      expect(l.prossima, isNull);
    });

    test('▶ dice al lato nativo se si è fermi', () async {
      final l = LettoreDelTelefono(fonte: FonteMusica.telefono);
      addTearDown(l.dispose);
      await l.parti(daFermi: true);
      await l.parti(daFermi: false);
      expect(chiamate.map((c) => c.method), ['parti', 'parti']);
      expect(chiamate.map((c) => c.arguments), [
        {'da_fermi': true},
        {'da_fermi': false},
      ]);
    });

    test('l\'elenco delle app e la scelta', () async {
      final l = LettoreDelTelefono(fonte: FonteMusica.telefono);
      addTearDown(l.dispose);
      risposta = {
        'app': [
          {
            'pacchetto': 'com.spotify.music',
            'nome': 'Spotify',
            'icona': Uint8List.fromList([1, 2]),
          },
          {'pacchetto': 'it.esempio.radio', 'nome': 'Radio Lungomare', 'icona': null},
          {'nome': 'senza pacchetto'},
        ],
        'scelta': null,
        'ultima': 'it.esempio.radio',
        'effettiva': 'com.spotify.music',
        'ultimo_avvio': 'Spotify: browser rifiutato → tasto all\'app → suona dopo 1,2 s',
      };
      final e = await l.elencoApp();
      expect(e.app.map((a) => a.nome), ['Spotify', 'Radio Lungomare']);
      expect(e.app.first.icona, isNotNull);
      expect(e.app.last.icona, isNull);
      expect(e.selezionata, 'com.spotify.music');
      expect(e.ultimoAvvio, contains('tasto all\'app'));
      await l.scegliApp('ultima');
      expect(chiamate.last.method, 'scegliApp');
      expect(chiamate.last.arguments, 'ultima');
      await l.scegliApp(null);
      expect(chiamate.last.arguments, isNull);
    });

    test('un lato nativo che non sa le app (l\'iPhone, le prove): elenco vuoto', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canale, null);
      final l = LettoreDelTelefono(fonte: FonteMusica.sistema);
      addTearDown(l.dispose);
      final e = await l.elencoApp();
      expect(e.app, isEmpty);
      expect(e.selezionata, 'ultima');
      await l.parti(daFermi: true);
    });
  });
}
