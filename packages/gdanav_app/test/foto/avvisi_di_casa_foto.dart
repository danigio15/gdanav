/// Le fotografie degli avvisi di casa e del mini-lettore in guida, sul
/// telefono: la guida vera di GdANav, con sotto la mappa 3D fotografata dal
/// banco (`web3d/collaudo`) e sopra le notifiche di casa (lavatrice,
/// antifurto, la domanda «Sì / No», auto in carica, il gruppo, l'allarme, chi
/// arriva) e la musica (anche l'invito per il permesso). In verticale e di
/// traverso, di giorno e di notte; e a mappa libera, senza percorso
/// (`libera-…`). E la pagina «Casa e musica in guida».
///
/// Quelle dell'auto (Android Auto, CarPlay) stanno in
/// `avvisi_di_casa_auto_foto.dart`.
///
/// Non è una prova: è un attrezzo per guardare. Si lancia a mano:
///
/// ```sh
/// SFONDI=/percorso/degli/sfondi COPERTINE=/percorso/copertine FOTO_CASA=/percorso/uscita \
///   flutter test --update-goldens test/foto/avvisi_di_casa_foto.dart
/// ```
///
/// Gli sfondi si chiamano `verticale-giorno.png`, `orizzontale-notte.png`…;
/// senza, la mappa resta grigia. Le copertine `copertina-1.png`….
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_posizione.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../aiuti.dart';

Future<void> _caratteri() async {
  final radice = Platform.environment['FLUTTER_ROOT'];
  if (radice == null || radice.isEmpty) return;
  final cartella = '$radice/bin/cache/artifacts/material_fonts';
  Future<ByteData> leggi(String nome) => File('$cartella/$nome').readAsBytes().then((b) => b.buffer.asByteData());
  for (final famiglia in ['Roboto', 'packages/gdanav_app/Roboto']) {
    final f = FontLoader(famiglia);
    for (final peso in ['Regular', 'Medium', 'Bold', 'Black']) {
      if (File('$cartella/Roboto-$peso.ttf').existsSync()) f.addFont(leggi('Roboto-$peso.ttf'));
    }
    await f.load();
  }
  if (File('$cartella/MaterialIcons-Regular.otf').existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(leggi('MaterialIcons-Regular.otf'))).load();
  }
}

final _dove = Platform.environment['FOTO_CASA'] ?? '../../../../collaudo/foto/avvisi-di-casa';
final _sfondi = Platform.environment['SFONDI'];
final _copertine = Platform.environment['COPERTINE'];

ImageProvider? _copertina(int n) {
  final f = _copertine == null ? null : File('$_copertine/copertina-$n.png');
  return f != null && f.existsSync() ? MemoryImage(f.readAsBytesSync()) : null;
}

/// Una strada verso nord ogni 100 m, con una svolta a destra fra 300 m e
/// poi una rotonda: la manovra in alto e il «Poi» sotto.
PercorsoCalcolato _strada() {
  final punti = [for (var i = 0; i <= 200; i++) Punto(42 + i * 0.0009, 12)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 50),
    ],
    manovre: const [
      Manovra(istruzione: 'Parti', lunghezzaM: 400, secondi: 30, inizio: 0, tipo: 1, strada: 'Via Appia'),
      Manovra(
        istruzione: 'Svolta a destra in Via Roma',
        lunghezzaM: 300,
        secondi: 25,
        inizio: 4,
        tipo: 10,
        strada: 'Via Roma',
      ),
      Manovra(
        istruzione: 'Alla rotonda prendi la seconda uscita',
        lunghezzaM: 19000,
        secondi: 1400,
        inizio: 7,
        tipo: 26,
        strada: 'Corso Europa',
        uscitaRotonda: 2,
      ),
      Manovra(istruzione: 'Sei arrivato', lunghezzaM: 0, secondi: 0, inizio: 200, tipo: 4),
    ],
    limiti: [for (var i = 0; i < 200; i++) 50],
  );
}

/// Le notifiche come le manda il ponte, passate dal riconoscitore vero.
AvvisoDiCasa _da(Map<String, Object?> busta) => AvvisoDiCasa.daNotifica({'v': 1, ...busta}, casa: 'Villa Gialla')!;

AvvisoDiCasa _lavatrice() => _da({
  'id': 'lavatrice',
  'tipo': 'elettrodomestici',
  'urg': 'normale',
  'titolo': '🧺 Lavatrice finita',
  'testo': '1 h 52 min · 0,9 kWh · 0,21 €',
  'entita': 'sensor.lavatrice_stato',
});

AvvisoDiCasa _antifurto() => _da({
  'id': 'antifurto',
  'tipo': 'inserimenti',
  'urg': 'normale',
  'titolo': '🛡️ Antifurto inserito',
  'testo': 'Totale · da Marta, alle 08:04',
  'azioni': [
    {'id': 'disinserisci', 'etichetta': 'Disinserisci'},
    {'id': 'guarda', 'etichetta': 'Guarda', 'apre': true},
  ],
});

AvvisoDiCasa _auto() => _da({
  'id': 'auto',
  'tipo': 'ha_notify',
  'urg': 'normale',
  'titolo': 'Auto carica all\'80%',
  'testo': 'Wallbox garage · 32 km aggiunti · pronta alle 08:40',
  'entita': 'sensor.wallbox_garage',
});

AvvisoDiCasa _allarme() => _da({
  'id': 'allarme',
  'tipo': 'antifurto',
  'urg': 'urgente',
  'titolo': '🚨 Allarme in casa',
  'testo': 'Movimento in soggiorno · sirena accesa',
  'azioni': [
    {'id': 'spegni-sirena', 'etichetta': 'Spegni sirena'},
    {'id': 'disinserisci', 'etichetta': 'Disinserisci'},
    {'id': 'guarda', 'etichetta': 'Guarda', 'apre': true},
  ],
});

AvvisoDiCasa _marta() => _da({
  'id': 'marta',
  'tipo': 'arrivi',
  'urg': 'bassa',
  'titolo': 'Marta è arrivata a casa',
  'testo': 'Alle 08:05 · in casa: Marta, nonno Piero',
});

final _brani = [
  BranoInAscolto(
    titolo: 'Strade di notte',
    artista: 'Le Lucciole',
    copertina: _copertina(1),
    durata: const Duration(minutes: 3, seconds: 21),
    posizione: const Duration(minutes: 1, seconds: 23),
  ),
  BranoInAscolto(titolo: 'Vento a favore', artista: 'Orsa Minore', copertina: _copertina(2)),
];
final _preferite = [
  PlaylistPreferita(id: 'viaggio', nome: 'Viaggio in auto', copertina: _copertina(3)),
  const PlaylistPreferita(id: 'mix', nome: 'Daily Mix 1'),
  const PlaylistPreferita(id: 'podcast', nome: 'Podcast'),
];

/// Una fotografia: cosa c'è sopra la mappa.
typedef _Caso = ({
  String nome,
  List<AvvisoDiCasa> Function() avvisi,
  bool musica,
  bool fermo,
  bool apri,
  bool chiusa,
  bool soloVerticale,
  bool soloGiorno,
  bool senzaPermesso,
  bool libera,
  String? tocca,
});

_Caso _caso(
  String nome,
  List<AvvisoDiCasa> Function() avvisi, {
  bool musica = false,
  bool fermo = false,
  bool apri = false,
  bool chiusa = false,
  bool soloVerticale = false,
  bool soloGiorno = false,
  bool senzaPermesso = false,
  bool libera = false,
  String? tocca,
}) => (
  nome: nome,
  avvisi: avvisi,
  musica: musica,
  fermo: fermo,
  apri: apri,
  chiusa: chiusa,
  soloVerticale: soloVerticale,
  soloGiorno: soloGiorno,
  senzaPermesso: senzaPermesso,
  libera: libera,
  tocca: tocca,
);

final _casi = <_Caso>[
  _caso('lavatrice', () => [_lavatrice()]),
  _caso('antifurto', () => [_antifurto()]),
  _caso('antifurto-conferma', () => [_antifurto()], tocca: 'Disinserisci'),
  _caso('auto-carica', () => [_auto()]),
  _caso('gruppo', () => [_lavatrice(), _antifurto(), _auto()]),
  _caso('gruppo-aperto-da-fermo', () => [_lavatrice(), _antifurto(), _auto()], fermo: true, apri: true),
  _caso('allarme', () => [_allarme()]),
  _caso('marta', () => [_marta()]),
  _caso('musica', () => [], musica: true),
  _caso('musica-lavatrice', () => [_lavatrice()], musica: true),
  _caso('musica-antifurto', () => [_antifurto()], musica: true),
  _caso('musica-da-fermo', () => [], musica: true, fermo: true),
  _caso('musica-chiusa', () => [_marta()], musica: true, chiusa: true, soloVerticale: true),
  _caso('musica-invito-da-fermo', () => [], musica: true, fermo: true, senzaPermesso: true),
  // A mappa libera, senza percorso: la musica sopra il pannello, l'avviso
  // sotto il menu.
  _caso('libera-musica', () => [], musica: true, libera: true),
  _caso('libera-musica-da-fermo', () => [], musica: true, fermo: true, libera: true),
  _caso('libera-musica-lavatrice', () => [_lavatrice()], musica: true, libera: true),
  _caso('libera-antifurto-da-fermo', () => [_antifurto()], musica: true, fermo: true, libera: true),
  _caso('libera-invito-da-fermo', () => [], musica: true, fermo: true, senzaPermesso: true, libera: true),
];

void main() {
  setUp(_caratteri);

  for (final verticale in [true, false]) {
    for (final notte in [false, true]) {
      final verso = verticale ? 'verticale' : 'orizzontale';
      final luce = notte ? 'notte' : 'giorno';
      for (final caso in _casi) {
        if (caso.soloVerticale && !verticale) continue;
        if (caso.soloGiorno && notte) continue;
        testWidgets('${caso.nome}, $verso, $luce', (tester) async {
          preparaPiattaforma(portachiavi: impostazioniComplete);
          final a = await ambiente(
            tester,
            km: 20,
            costruisci: (_, profilo, preferenze, _) {
              return PianificatoreViaggio(
                percorsi: (_) async => _strada(),
                colonnine: ColonnineFinte(),
                profilo: profilo,
                preferenze: preferenze,
              );
            },
          );
          tester.view
            ..physicalSize = const Size(390 * 3, 844 * 3)
            ..devicePixelRatio = 3
            ..padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
          tester.platformDispatcher.platformBrightnessTestValue = notte ? Brightness.dark : Brightness.light;
          addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
          final file = _sfondi == null ? null : File('$_sfondi/$verso-$luce.png');
          final fondo = file != null && file.existsSync() ? MemoryImage(file.readAsBytesSync()) : null;
          final coda = CodaAvvisiDiCasa(durata: const Duration(seconds: 9));
          final lettore = caso.musica
              ? LettoreFinto(brani: _brani, preferite: _preferite, permesso: !caso.senzaPermesso)
              : null;
          addTearDown(() => lettore?.dispose());
          final casa = GestoreCasaInGuida(archivio: a.archivio, coda: coda, lettore: lettore);
          addTearDown(casa.dispose);
          final app = GdanavApp(
            posizione: a.posizione,
            archivio: a.archivio,
            auto: a.auto,
            viaggio: a.viaggio,
            guida: a.guida,
            segnalazioni: a.segnalazioni,
            casaInGuida: casa,
            mappa: (context, c) => fondo == null
                ? const ColoredBox(color: Colors.grey)
                : Image(image: fondo, fit: BoxFit.cover, alignment: Alignment.center, gaplessPlayback: true),
          );
          await tester.pumpWidget(_conBarra(app, verticale: verticale, notte: notte));
          if (fondo != null) {
            await tester.runAsync(() => precacheImage(fondo, tester.element(find.byType(Scaffold).first)));
          }
          for (final b in [..._brani, ..._preferite.map((p) => BranoInAscolto(titolo: '', copertina: p.copertina))]) {
            if (b.copertina case final c?) {
              await tester.runAsync(() => precacheImage(c, tester.element(find.byType(Scaffold).first)));
            }
          }
          a.posizione.avvia();
          a.auto.manuale.imposta(90);
          await tester.pump();
          if (!caso.libera) {
            await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Villa Gialla', posizione: Punto(42.18, 12))));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Avvia'));
          }
          await tester.pumpAndSettle();
          // Di traverso si gira dopo «Avvia», come in macchina sul supporto.
          if (!verticale) {
            tester.view
              ..physicalSize = const Size(844 * 3, 390 * 3)
              ..padding = const FakeViewPadding(left: 47 * 3, right: 47 * 3, bottom: 21 * 3);
            await tester.pumpAndSettle();
          }
          const qui = Punto(42.0009, 12);
          await tester.runAsync(() async {
            a.gps.add(Lettura(qui, velocitaMs: caso.fermo ? 0 : 13.4, rotta: 0, precisioneM: 5));
            a.posizioni.add(qui);
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pump(const Duration(milliseconds: 200));
          for (final x in caso.avvisi()) {
            coda.aggiungi(x);
          }
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 1600));
          if (caso.apri) {
            await tester.tap(find.text('Mostra'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }
          if (caso.tocca case final t?) {
            await tester.tap(find.text(t));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }
          if (caso.chiusa) {
            await tester.tap(find.byKey(const Key('lettore-richiudi')));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
          }
          await expectLater(
            find.byKey(const Key('foto')),
            matchesGoldenFile('$_dove/telefono-$verso-$luce-${caso.nome}.png'),
          );
          coda.scelta = SceltaAvvisiDiCasa.nessuna;
          if (!caso.libera) await tester.runAsync(a.guida.ferma);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  // La pagina delle impostazioni, alta quanto serve per vederla tutta.
  for (final notte in [false, true]) {
    final luce = notte ? 'notte' : 'giorno';
    testWidgets('impostazioni, $luce', (tester) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 1840 * 3)
        ..devicePixelRatio = 3
        ..padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      preparaPiattaforma();
      final lettore = LettoreFinto(permesso: false);
      addTearDown(lettore.dispose);
      final casa = GestoreCasaInGuida(archivio: Archivio(), coda: CodaAvvisiDiCasa(), lettore: lettore);
      addTearDown(casa.dispose);
      await tester.runAsync(() async {
        await casa.carica();
        await casa.cambiaScelta(
          const SceltaAvvisiDiCasa()
              .conCategoria(CategoriaAvvisoDiCasa.clima, false)
              .conCategoria(CategoriaAvvisoDiCasa.aggiornamenti, false),
        );
      });
      final pagina = MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaGdanav(notte ? Brightness.dark : Brightness.light),
        home: NotificheNelNavigatoreSchermata(gestore: casa),
      );
      await tester.pumpWidget(_conBarra(pagina, verticale: true, notte: notte));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(const Key('foto')), matchesGoldenFile('$_dove/telefono-impostazioni-$luce.png'));
    });
  }
}

/// Una barra di stato finta, come sul telefono: l'ora e la batteria.
Widget _conBarra(Widget app, {required bool verticale, required bool notte}) {
  final chiaro = notte ? Colors.white : Colors.black;
  return KeyedSubtree(
    key: const Key('foto'),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          app,
          if (verticale)
            Positioned(
              top: 14,
              left: 40,
              right: 30,
              child: IgnorePointer(
                child: Row(
                  children: [
                    Text(
                      '08:06',
                      style: TextStyle(fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w700, color: chiaro),
                    ),
                    const Spacer(),
                    Icon(Icons.navigation_rounded, size: 15, color: chiaro),
                    const SizedBox(width: 6),
                    Icon(Icons.signal_cellular_alt_rounded, size: 17, color: chiaro),
                    const SizedBox(width: 4),
                    Icon(Icons.wifi_rounded, size: 17, color: chiaro),
                    const SizedBox(width: 4),
                    Icon(Icons.battery_5_bar_rounded, size: 18, color: chiaro),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
