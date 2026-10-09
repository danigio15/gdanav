// «La batteria letta dall'auto fa parte di Premium: scrivila a mano», dentro
// gdahome con la casa Premium. Il Premium della casa arrivava mentre l'auto si
// accendeva, e l'auto non lo sentiva più.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/gdanav_app.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/gestore_auto.dart';
import 'package:gdanav_app/stato/gestore_premium.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

void main() {
  testWidgets('il Premium della casa arrivato durante l\'avvio vale anche per la batteria', (tester) async {
    preparaPiattaforma();
    final casa = ValueNotifier(false);
    final vettura = SorgenteGdahome();
    final premium = GestorePremium(archivio: Archivio(), ospite: casa, tuttoSbloccato: false);
    await tester.runAsync(premium.carica);
    final auto = GestoreAuto(archivio: Archivio(), gdahome: vettura)..premium = premium.sbloccato;
    addTearDown(auto.dispose);
    await tester.runAsync(auto.avvia);
    // Mentre l'auto si accendeva la casa ha detto «Premium», e nessuno ascoltava.
    casa.value = true;
    vettura
      ..collegamento(true)
      ..manda(StatoAuto(sorgente: TipoSorgente.gdahome, letto: DateTime.now(), batteria: 44));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(auto.premium, isFalse, reason: 'senza aggancio è il guasto visto in macchina');

    autoSegueIlPremium(auto, premium);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(auto.premium, isTrue);
    expect(auto.stato?.batteria, 44);
    expect(auto.percheSenzaDati, isNot(contains('Premium')));

    // E da lì in poi segue la casa.
    casa.value = false;
    await tester.pump(const Duration(milliseconds: 1));
    expect(auto.premium, isFalse);
    premium.dispose();
  });
}
