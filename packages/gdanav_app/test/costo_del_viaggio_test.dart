import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/sorgenti/sorgente_gdahome.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';

/// Dal campo: «per il costo del viaggio, soprattutto se elettrico, considera
/// se si parte da casa al 100% e verifica l'ultima ricarica a casa, come è
/// stata caricata; e capisci, o chiedi, quanto si è speso per la ricarica se
/// ci si ferma per strada. Da lì il conto preciso».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('partiti con la ricarica di casa, una sosta pagata: il conto preciso all\'arrivo', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final casa = SorgenteGdahome();
    addTearDown(casa.dispose);
    final chieste = <Map<String, Object?>>[];
    // La casa: ricaricata stanotte fino al 100%, 60 kWh, 24 col sole, 7,20 € di rete.
    casa.chiedi = (comando) async {
      chieste.add(comando);
      return {
        'ricariche': [
          {
            'nome': 'Auto',
            'finitaIl': DateTime.now().subtract(const Duration(hours: 9)).toIso8601String(),
            'socA': 100,
            'kwh': 60,
            'kwhSole': 24,
            'euroRete': 7.2,
          },
        ],
      };
    };
    final a = await ambiente(tester, km: 20, gdahome: casa);
    StatoAuto leggo(double batteria, {bool? inCarica}) => StatoAuto(
      sorgente: TipoSorgente.gdahome,
      letto: DateTime.now(),
      batteria: batteria,
      inCarica: inCarica,
    );
    casa.manda(leggo(100));
    await tester.pump();
    await tester.runAsync(() => a.viaggio.cambiaOpzioni(const OpzioniPercorso(ricalcoloAutomatico: false)));
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    expect(a.viaggio.stato, isA<ViaggioPronto>());
    a.guida.avvia();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    expect(chieste.single['type'], 'ponte/auto/ricariche-di-casa');
    expect(a.guida.ricaricaDiCasa?.euroAlKwh, closeTo(0.12, 1e-9));

    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[5]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    // Una sosta: dal 40% all'80%.
    casa.manda(leggo(40));
    casa.manda(leggo(40, inCarica: true));
    casa.manda(leggo(80, inCarica: true));
    casa.manda(leggo(80, inCarica: false));
    await tester.pump();
    expect(a.guida.ricaricheInViaggio, hasLength(1));
    expect(a.guida.daChiedere, 0);
    final presi = a.guida.ricaricheInViaggio.single.kwh;
    expect(presi, closeTo(0.4 * a.auto.veicolo.capacitaUtileKwh, 0.01));
    // «Quanto hai speso?»: 18 euro.
    a.guida.pagaRicarica(0, 18);
    expect(a.guida.daChiedere, isNull);

    // All'arrivo al 70%.
    casa.manda(leggo(70));
    await tester.pump();
    a.posizioni.add(punti.last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
    final r = a.guida.riepilogo!;
    final capacita = a.auto.veicolo.capacitaUtileKwh;
    // Consumati: 30 punti scesi più i 40 presi = 70% della batteria.
    expect(r.kwh, closeTo(0.7 * capacita, 0.01));
    expect(r.consumoStimato, isFalse);
    final e = r.energia!;
    // Tutta dalla batteria di casa (partiti al 100%): a 0,12 €/kWh.
    expect(e.kwhDaCasa, closeTo(0.7 * capacita, 0.01));
    expect(e.euroCasa, closeTo(0.7 * capacita * 0.12, 0.01));
    expect(e.kwhDalleSoste, closeTo(0, 1e-9));
    expect(r.righe.map((x) => x.$1), containsAll(['Da casa', 'Ricarica']));
    // Toccando la ricarica nel riepilogo si corregge quanto si è speso.
    a.guida.pagaRicarica(0, 20);
    expect(a.guida.riepilogo!.soste.single.euroPagati, 20);
  });
}
