import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/stato/gestore_guida.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/voce.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Registra parla e zitta nell'ordine in cui arrivano.
class VoceRegistrata implements Voce {
  final eventi = <String>[];
  @override
  Future<void> parla(String frase) async => eventi.add('parla: $frase');
  @override
  Future<void> zitta() async => eventi.add('zitta');
  @override
  Future<void> suona() async => eventi.add('beep');
}

/* ── «Sei arrivato.» interrotto a metà ────────────────────────────────────
 *
 * All'arrivo la guida dice la frase e si chiude, e chiudendosi zittiva la
 * voce: della frase dell'arrivo si sentiva l'inizio, o niente. */
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('«Sei arrivato.» non viene zittito subito dopo averlo cominciato', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    final voce = VoceRegistrata();
    final guida = GestoreGuida(viaggio: a.viaggio, auto: a.auto, posizioni: () => a.posizioni.stream, voce: voce);
    guida.avvia();
    a.posizioni.add(punti[19]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    a.posizioni.add(punti.last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(guida.attiva, isFalse);
    final i = voce.eventi.indexOf('parla: Sei arrivato.');
    expect(i, isNonNegative);
    expect(
      voce.eventi.skip(i + 1),
      isNot(contains('zitta')),
      reason: 'ferma() chiama voce.zitta() appena dopo: la frase dell\'arrivo si interrompe',
    );
  });

  testWidgets('fermata a mano, la guida zittisce quello che sta dicendo', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    final voce = VoceRegistrata();
    final guida = GestoreGuida(viaggio: a.viaggio, auto: a.auto, posizioni: () => a.posizioni.stream, voce: voce);
    guida.avvia();
    await tester.runAsync(guida.ferma);
    expect(voce.eventi.last, 'zitta');
  });
}
