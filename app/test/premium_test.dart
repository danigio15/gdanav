import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/schermate/premium.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_auto.dart';
import 'package:gdanav/stato/gestore_premium.dart';
import 'package:gdanav/tema.dart';
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
  var comprati = 0;

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
  Future<String?> prezzo() async => '2,99 €';

  @override
  Future<void> compra() async {
    comprati++;
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

  test('si compra: sbloccato, confermato a Google Play, e ricordato', () async {
    preparaPiattaforma();
    final negozio = NegozioFinto();
    final p = GestorePremium(archivio: Archivio(), negozio: negozio, tuttoSbloccato: false);
    await p.carica();
    await pausa();
    expect(p.sbloccato, isFalse);
    expect(p.prezzo, '2,99 €');
    await p.compra();
    await pausa();
    expect(p.sbloccato, isTrue);
    expect(negozio.completati, ['ordine-1']);
    expect(await Archivio().premium(), isTrue);

    // Riaperta l'app, anche senza negozio: sbloccato.
    final dopo = GestorePremium(archivio: Archivio(), tuttoSbloccato: false);
    await dopo.carica();
    expect(dopo.sbloccato, isTrue);
  });

  test('già comprato su un altro telefono: si ripristina da solo', () async {
    preparaPiattaforma();
    final p = GestorePremium(archivio: Archivio(), negozio: NegozioFinto(giaComprato: true), tuttoSbloccato: false);
    await p.carica();
    await pausa();
    expect(p.sbloccato, isTrue);
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
    await annullato.compra();
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
    await fallito.compra();
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

  testWidgets('la schermata Premium: prezzo, sblocca, e poi «attivo»', (tester) async {
    preparaPiattaforma();
    final p = GestorePremium(archivio: Archivio(), negozio: NegozioFinto(), tuttoSbloccato: false);
    await tester.runAsync(() async {
      await p.carica();
      await pausa();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: temaGdanav(Brightness.light),
        home: SchermataPremium(premium: p, perche: 'Android Auto'),
      ),
    );
    expect(find.textContaining('Android Auto fa parte di Premium'), findsOneWidget);
    expect(find.text('Sblocca a 2,99 €'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('compra-premium')));
      await pausa();
    });
    await tester.pump();
    expect(find.text('Premium è attivo: grazie!'), findsOneWidget);
    expect(find.byKey(const Key('compra-premium')), findsNothing);
  });
}
