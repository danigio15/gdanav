// Le immagini delle schermate di Premium, gratis e Premium: non è una prova
// che gira con `flutter test` (sta fuori da test/), si lancia apposta:
//
//     flutter test test_render/render_test.dart
//
// Scrive i PNG in /home/user/render/gdanav/ (o in GDANAV_RENDER), a 390×844
// punti con densità 2, coi caratteri veri (Roboto e le icone Material dalla
// cache di Flutter). La mappa è un fondo grigio: quella vera vuole il nativo.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';
import 'package:gdanav_app/schermate/aggiorna_gdanav.dart';
import 'package:gdanav_app/schermate/fonte_dati_auto.dart';
import 'package:gdanav_app/schermate/premium.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_aggiornamento.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/stato/gestore_premium.dart';
import 'package:gdanav_app/stato/licenza.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../test/aiuti.dart';

final cartella = Platform.environment['GDANAV_RENDER'] ?? '/home/user/render/gdanav';
const _font = '/opt/sdk/flutter/bin/cache/artifacts/material_fonts';

/// La chiave pubblica **di prova** del contratto: qui serve solo a mostrare
/// «Ho un codice regalo», che nell'app compare quando la chiave vera c'è.
const _chiaveProva = '6P9sdqQtlHcmH7Ve_SgzmyJmxJS28CNORRJJfjI3rnI';

Future<void> _caricaFont() async {
  Future<ByteData> leggi(String nome) async => ByteData.sublistView(await File('$_font/$nome').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final peso in ['Light', 'Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(leggi('Roboto-$peso.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')..addFont(leggi('MaterialIcons-Regular.otf'))).load();
}

/// Il negozio coi prezzi che avranno le console (2,99 € e 29,99 €).
class _Negozio implements NegozioPremium {
  @override
  Stream<List<PurchaseDetails>> get acquisti => const Stream.empty();
  @override
  Future<bool> disponibile() async => true;
  @override
  Future<List<PianoPremium>> piani() async => const [
    PianoPremium(id: pianoMensile, prezzo: '2,99 €', giorniProva: 14),
    PianoPremium(id: pianoAnnuale, prezzo: '29,99 €', giorniProva: 14),
  ];
  @override
  Future<void> compra(String piano) async {}
  @override
  Future<void> ripristina() async {}
  @override
  Future<void> completa(PurchaseDetails p) async {}
}

final _chiave = GlobalKey();

Widget _cornice(Widget figlio) => RepaintBoundary(key: _chiave, child: figlio);

Future<void> _scatta(WidgetTester tester, String nome) async {
  await tester.pumpAndSettle();
  final confine = _chiave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  // Fuori dal tempo finto delle prove: la GPU e il disco sono veri.
  await tester.runAsync(() async {
    final immagine = await confine.toImage(pixelRatio: 2);
    final dati = await immagine.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$cartella/$nome.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(dati!.buffer.asUint8List());
    debugPrint('scritto ${f.path}');
  });
}

/// Una prova che disegna, con le ombre vere (le prove di solito le spengono).
void _rendi(String nome, Future<void> Function(WidgetTester tester) corpo) => testWidgets(nome, (tester) async {
  debugDisableShadows = false;
  try {
    await corpo(tester);
  } finally {
    debugDisableShadows = true;
  }
});

void _telefono(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
  tester.view.viewPadding = const FakeViewPadding(top: 141, bottom: 102);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(_caricaFont);
  tearDown(() => GestorePremium.attivo.value = true);

  _rendi('premium, gdanav da sola', (tester) async {
    _telefono(tester);
    preparaPiattaforma();
    final p = GestorePremium(
      archivio: Archivio(),
      negozio: _Negozio(),
      tuttoSbloccato: false,
      attesaConferma: Duration.zero,
      licenze: ClienteLicenze(client: MockClient((_) async => http.Response('{"gettoni":{}}', 200))),
      chiaveLicenze: _chiaveProva,
    );
    await tester.runAsync(() async {
      await p.carica();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    addTearDown(p.dispose);
    await tester.pumpWidget(
      _cornice(MaterialApp(debugShowCheckedModeBanner: false, theme: temaGdanav(Brightness.light), home: SchermataPremium(premium: p))),
    );
    await _scatta(tester, 'premium_da_sola');
    await tester.tap(find.byKey(const Key('codice-regalo')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('campo-codice')), 'GDA-7KQM-2XRT-9HVB');
    await _scatta(tester, 'premium_codice_regalo');
  });

  _rendi('premium, dentro gdahome', (tester) async {
    _telefono(tester);
    preparaPiattaforma();
    final p = GestorePremium(archivio: Archivio(), ospite: ValueNotifier(false), tuttoSbloccato: false);
    await tester.runAsync(p.carica);
    addTearDown(p.dispose);
    await tester.pumpWidget(
      _cornice(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaGdanav(Brightness.light),
          home: SchermataPremium(premium: p, perche: 'La batteria letta dall\'auto'),
        ),
      ),
    );
    await _scatta(tester, 'premium_dentro_gdahome');
  });

  _rendi('viaggio elettrico senza Premium: senza soste, con l\'avviso', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 420);
    _telefono(tester);
    final p = GestorePremium(archivio: a.archivio, tuttoSbloccato: false);
    await tester.runAsync(p.carica);
    addTearDown(p.dispose);
    expect(GestorePremium.attivo.value, isFalse);
    a.auto.manuale.imposta(62);
    await tester.runAsync(
      () => a.viaggio.vaiA(const Luogo(nome: 'Bologna', descrizione: 'Emilia-Romagna', posizione: Punto(44.49, 11.34))),
    );
    await tester.pumpWidget(_cornice(_app(a, p)));
    await _scatta(tester, 'viaggio_elettrico_senza_soste');
    // La scheda tirata su: l'avviso intero, col tasto.
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await _scatta(tester, 'viaggio_elettrico_senza_soste_aperta');
  });

  _rendi('fonte dati auto senza Premium', (tester) async {
    _telefono(tester);
    preparaPiattaforma();
    final auto = GestoreAuto(archivio: Archivio())..premium = false;
    await tester.runAsync(auto.avvia);
    addTearDown(auto.dispose);
    auto.manuale.imposta(62);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpWidget(
      _cornice(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaGdanav(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              backgroundColor: Colors.grey,
              body: Center(
                child: FilledButton(
                  onPressed: () => mostraFonteDatiAuto(context, auto, onPremium: () {}),
                  child: const Text('apri'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await _scatta(tester, 'fonte_dati_auto_bloccata');
  });

  _rendi('il menu, senza Premium', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    _telefono(tester);
    final p = GestorePremium(archivio: a.archivio, tuttoSbloccato: false);
    await tester.runAsync(p.carica);
    addTearDown(p.dispose);
    await tester.pumpWidget(_cornice(_app(a, p)));
    await tester.tap(find.byTooltip('Menu'));
    await _scatta(tester, 'menu_senza_premium');
    await tester.scrollUntilVisible(find.text('Mappe offline'), 200, scrollable: find.byType(Scrollable).last);
    await _scatta(tester, 'menu_senza_premium_fondo');
  });

  _rendi('il menu, con Premium', (tester) async {
    preparaPiattaforma(portachiavi: {...impostazioniComplete, 'premium': 'sì'});
    final a = await ambiente(tester);
    _telefono(tester);
    final p = GestorePremium(archivio: a.archivio, tuttoSbloccato: false);
    await tester.runAsync(p.carica);
    addTearDown(p.dispose);
    await tester.pumpWidget(_cornice(_app(a, p)));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Mappe offline'), 200, scrollable: find.byType(Scrollable).last);
    await _scatta(tester, 'menu_con_premium_fondo');
  });

  _rendi('versione da aggiornare', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester);
    _telefono(tester);
    final g = GestoreAggiornamento(
      archivio: a.archivio,
      client: MockClient((_) async => http.Response('{"gdanav":{"minima":50}}', 200)),
      costruzione: 40,
      debug: false,
    );
    await tester.runAsync(g.controlla);
    addTearDown(g.dispose);
    final p = GestorePremium(archivio: a.archivio, tuttoSbloccato: true);
    await tester.runAsync(p.carica);
    addTearDown(p.dispose);
    await tester.pumpWidget(
      _cornice(
        GdanavApp(
          posizione: a.posizione,
          archivio: a.archivio,
          auto: a.auto,
          viaggio: a.viaggio,
          guida: a.guida,
          premium: p,
          aggiornamento: g,
          mappa: (_, c) => const ColoredBox(color: Color(0xFFE5E7EB)),
        ),
      ),
    );
    await _immagini(tester);
    await _scatta(tester, 'aggiorna_gdanav');
    // L'APK di GitHub: anche la pagina delle versioni.
    await tester.pumpWidget(
      _cornice(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaGdanav(Brightness.light),
          home: const SchermataAggiorna(daGithub: true),
        ),
      ),
    );
    await _immagini(tester);
    await _scatta(tester, 'aggiorna_gdanav_apk');
  });
}

/// Le immagini (il logo) si leggono fuori dal tempo finto.
Future<void> _immagini(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
}

Widget _app(Ambiente a, GestorePremium p) => GdanavApp(
  posizione: a.posizione,
  archivio: a.archivio,
  auto: a.auto,
  viaggio: a.viaggio,
  guida: a.guida,
  segnalazioni: a.segnalazioni,
  premium: p,
  mappa: (_, c) => const ColoredBox(color: Color(0xFFE5E7EB)),
);
