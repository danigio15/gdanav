import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/premium.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/stato/gestore_premium.dart';
import 'package:gdanav_app/tema.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'aiuti.dart';

/// Google Play finto: risponde come vogliamo.
class NegozioFinto implements NegozioPremium {
  NegozioFinto({this.giaComprato = false, this.esito = PurchaseStatus.purchased});

  final bool giaComprato;
  final PurchaseStatus esito;
  final _flusso = StreamController<List<PurchaseDetails>>.broadcast();
  final completati = <String>[];
  final comprati = <String>[];

  PurchaseDetails _acquisto(PurchaseStatus s) => PurchaseDetails(
    productID: idPremium,
    verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: '', source: 'finto'),
    transactionDate: '0',
    status: s,
    purchaseID: 'ordine-1',
  )..pendingCompletePurchase = s == PurchaseStatus.purchased;

  @override
  Stream<List<PurchaseDetails>> get acquisti => _flusso.stream;

  @override
  Future<bool> disponibile() async => true;

  @override
  Future<List<PianoPremium>> piani() async => const [
    PianoPremium(id: pianoMensile, prezzo: '3,00 €', giorniProva: 14),
    PianoPremium(id: pianoAnnuale, prezzo: '25,00 €', giorniProva: 14),
  ];

  @override
  Future<void> compra(String piano) async {
    comprati.add(piano);
    _flusso.add([_acquisto(esito)]);
  }

  @override
  Future<void> ripristina() async {
    if (giaComprato) _flusso.add([_acquisto(PurchaseStatus.restored)]);
  }

  @override
  Future<void> completa(PurchaseDetails p) async => completati.add(p.purchaseID!);
}

Future<void> pausa() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => GestorePremium.attivo.value = true);

  test('si compra: sbloccato, confermato a Google Play, e ricordato', () async {
    preparaPiattaforma();
    final negozio = NegozioFinto();
    final p = GestorePremium(
      archivio: Archivio(),
      negozio: negozio,
      tuttoSbloccato: false,
      attesaConferma: const Duration(milliseconds: 50),
    );
    await p.carica();
    await pausa();
    expect(p.sbloccato, isFalse);
    expect(p.piani.map((x) => x.id), [pianoMensile, pianoAnnuale]);
    await p.compra(pianoAnnuale);
    await pausa();
    expect(p.sbloccato, isTrue);
    expect(GestorePremium.attivo.value, isTrue);
    expect(negozio.comprati, [pianoAnnuale]);
    expect(negozio.completati, ['ordine-1']);
    expect(await Archivio().premium(), isTrue);

    // Riaperta l'app, anche senza negozio: sbloccato.
    final dopo = GestorePremium(archivio: Archivio(), tuttoSbloccato: false);
    await dopo.carica();
    expect(dopo.sbloccato, isTrue);
  });

  test('già comprato su un altro telefono: si ripristina da solo', () async {
    preparaPiattaforma();
    final p = GestorePremium(
      archivio: Archivio(),
      negozio: NegozioFinto(giaComprato: true),
      tuttoSbloccato: false,
      attesaConferma: const Duration(milliseconds: 50),
    );
    await p.carica();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(p.sbloccato, isTrue);
  });

  test("abbonamento scaduto o disdetto: il Play Store non lo conferma e Premium si chiude", () async {
    preparaPiattaforma();
    await Archivio().salvaPremium(true);
    final p = GestorePremium(
      archivio: Archivio(),
      negozio: NegozioFinto(),
      tuttoSbloccato: false,
      attesaConferma: const Duration(milliseconds: 50),
    );
    await p.carica();
    expect(p.sbloccato, isTrue); // subito: quello che si sapeva
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(p.sbloccato, isFalse);
    expect(GestorePremium.attivo.value, isFalse);
    expect(await Archivio().premium(), isFalse);

    // Senza negozio (niente rete, niente Play Store) resta com'era.
    await Archivio().salvaPremium(true);
    final senza = GestorePremium(archivio: Archivio(), tuttoSbloccato: false);
    await senza.carica();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(senza.sbloccato, isTrue);
  });

  test('annullato o fallito: resta bloccato, e l\'errore si dice', () async {
    preparaPiattaforma();
    final annullato = GestorePremium(
      archivio: Archivio(),
      negozio: NegozioFinto(esito: PurchaseStatus.canceled),
      tuttoSbloccato: false,
    );
    await annullato.carica();
    await pausa();
    await annullato.compra(pianoMensile);
    await pausa();
    expect(annullato.sbloccato, isFalse);
    expect(annullato.inCorso, isFalse);

    final fallito = GestorePremium(
      archivio: Archivio(),
      negozio: NegozioFinto(esito: PurchaseStatus.error),
      tuttoSbloccato: false,
    );
    await fallito.carica();
    await pausa();
    await fallito.compra(pianoMensile);
    await pausa();
    expect(fallito.sbloccato, isFalse);
    expect(fallito.errore, isNotNull);
  });

  test("l'anteprima da GitHub ha tutto sbloccato", () async {
    preparaPiattaforma();
    final p = GestorePremium(archivio: Archivio(), tuttoSbloccato: true);
    await p.carica();
    expect(p.sbloccato, isTrue);
  });

  testWidgets('senza Premium Home Assistant non si collega; comprato sì', (tester) async {
    preparaPiattaforma(
      portachiavi: {'abbinamento_home_assistant': Abbinamento.nuovo(relay: Uri.parse('wss://relay.esempio.dev')).uri},
    );
    final auto = GestoreAuto(archivio: Archivio())..homeAssistantConsentito = false;
    await tester.runAsync(auto.avvia);
    addTearDown(auto.dispose);
    expect(auto.abbinamento, isNotNull);
    expect(auto.disponibili, isNot(contains(TipoSorgente.homeAssistant)));
    await tester.runAsync(() => auto.consentiHomeAssistant(true));
    expect(auto.disponibili, contains(TipoSorgente.homeAssistant));
  });

  testWidgets('la schermata Premium: i due piani, la prova di 14 giorni, e poi «attivo»', (tester) async {
    preparaPiattaforma();
    final negozio = NegozioFinto();
    final p = GestorePremium(
      archivio: Archivio(),
      negozio: negozio,
      tuttoSbloccato: false,
      attesaConferma: const Duration(milliseconds: 20),
    );
    await tester.runAsync(() async {
      await p.carica();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: SchermataPremium(premium: p, perche: 'Il traffico'),
      ),
    );
    expect(find.textContaining('Il traffico fa parte di Premium'), findsOneWidget);
    expect(find.text('Previsioni meteo'), findsOneWidget);
    expect(find.text('25,00 €/anno'), findsOneWidget);
    expect(find.text('3,00 €/mese'), findsOneWidget);
    expect(find.text('Risparmi il 31%'), findsOneWidget);
    expect(find.text('Prova gratis per 14 giorni'), findsOneWidget);
    expect(find.textContaining('Poi 25,00 €/anno, rinnovo automatico'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('piano-mensile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('piano-mensile')));
    await tester.pump();
    expect(find.textContaining('Poi 3,00 €/mese'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('compra-premium')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('compra-premium')));
      await pausa();
    });
    await tester.pump();
    expect(negozio.comprati, [pianoMensile]);
    expect(find.text('Premium è attivo: grazie!'), findsOneWidget);
    expect(find.byKey(const Key('compra-premium')), findsNothing);
  });
}
