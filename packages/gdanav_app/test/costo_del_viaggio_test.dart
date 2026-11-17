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
    StatoAuto leggo(double batteria, {bool? inCarica}) =>
        StatoAuto(sorgente: TipoSorgente.gdahome, letto: DateTime.now(), batteria: batteria, inCarica: inCarica);
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

  /// Un viaggio corto dentro GdAHome: si parte all'82% e si arriva al 78%.
  /// [casa] risponde quello che [risposta] dice in quel momento (`null`: non
  /// risponde).
  Future<RiepilogoViaggio> corto(
    WidgetTester tester,
    SorgenteGdahome casa,
    Object? Function() risposta, {
    void Function(Ambiente a)? allArrivo,
  }) async {
    casa.chiedi = (comando) async => risposta() ?? (throw StateError('la casa non è collegata'));
    final a = await ambiente(tester, km: 20, gdahome: casa);
    StatoAuto leggo(double batteria) =>
        StatoAuto(sorgente: TipoSorgente.gdahome, letto: DateTime.now(), batteria: batteria);
    casa.manda(leggo(82));
    await tester.pump();
    await tester.runAsync(() => a.viaggio.cambiaOpzioni(const OpzioniPercorso(ricalcoloAutomatico: false)));
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    a.guida.avvia();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    a.posizioni.add(punti[5]);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    casa.manda(leggo(78));
    await tester.pump();
    allArrivo?.call(a);
    a.posizioni.add(punti.last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pumpAndSettle();
    return a.guida.riepilogo!;
  }

  Map<String, Object?> ricarica({Duration fa = const Duration(days: 2), num socA = 100}) => {
    'nome': 'Auto',
    'finitaIl': DateTime.now().subtract(fa).toIso8601String(),
    'socA': socA,
    'kwh': 20,
    'kwhSole': 13,
    'euroRete': 1.75,
  };

  // Dal campo: «non è vero che non c'era una ricarica a casa: per portarla al
  // 100% ho ricaricato a casa». Partito all'82%, dopo altri viaggi.
  testWidgets('ricaricata a casa al 100% e partiti all\'82% dopo altri viaggi: il prezzo è quello della ricarica', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final casa = SorgenteGdahome();
    addTearDown(casa.dispose);
    final r = await corto(
      tester,
      casa,
      () => {
        'ricariche': [ricarica()],
        'prezzo': {'euroAlKwh': 0.25},
        'auto': ['Auto'],
      },
    );
    final e = r.energia!;
    expect(e.origine, PrezzoDiPartenza.ricarica);
    // 1,75 € di rete su 20 kWh: 8,75 centesimi al kWh, non i 30 delle opzioni.
    expect(e.euroCasa, closeTo(e.kwhDaCasa * 1.75 / 20, 1e-6));
    expect(e.quotaSole, closeTo(0.65, 1e-9));
    expect(r.senzaPrezzoVero, isNull);
    expect(r.righe.firstWhere((x) => x.$1 == 'Da casa').$2, endsWith('65% dal sole'));
    // Quattro punti di batteria: una misura larga, e lo si dice.
    expect(r.consumoStimato, isFalse);
    expect(r.kwhPiuOMeno, closeTo(r.kwh! / 4, 1e-6));
    expect(r.consumoTesto, startsWith('circa '));
    expect(r.note.single, startsWith('Energia misurata dai punti della batteria'));
  });

  testWidgets('la casa non risponde alla partenza ma all\'arrivo sì: il riepilogo si rifà col prezzo vero', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final casa = SorgenteGdahome();
    addTearDown(casa.dispose);
    var collegata = false;
    final r = await corto(
      tester,
      casa,
      () => collegata
          ? {
              'ricariche': [ricarica()],
              'prezzo': {'euroAlKwh': 0.25},
              'auto': ['Auto'],
            }
          : null,
      allArrivo: (_) => collegata = true,
    );
    expect(r.energia!.origine, PrezzoDiPartenza.ricarica);
    expect(r.senzaPrezzoVero, isNull);
  });

  testWidgets('la casa non risponde mai: il prezzo delle opzioni, detto come stima e col perché', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final casa = SorgenteGdahome();
    addTearDown(casa.dispose);
    final r = await corto(tester, casa, () => null);
    expect(r.energia!.origine, PrezzoDiPartenza.opzioni);
    expect(r.senzaPrezzoVero, SenzaPrezzoVero.casaMuta);
    expect(r.righe.map((x) => x.$1), isNot(contains('Da casa')));
    expect(r.righe.firstWhere((x) => x.$1 == 'Batteria').$2, endsWith('stima a 0,30 €/kWh'));
    expect(r.note.last, contains('la casa non ha risposto'));
  });

  testWidgets('la casa non ha visto ricariche ma ha la tariffa: il prezzo di casa; senza tariffa dice cosa manca', (
    tester,
  ) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final casa = SorgenteGdahome();
    addTearDown(casa.dispose);
    final r = await corto(
      tester,
      casa,
      () => {
        'ricariche': const <Object>[],
        'prezzo': {'euroAlKwh': 0.22},
        'auto': ['Auto'],
      },
    );
    final e = r.energia!;
    expect(e.origine, PrezzoDiPartenza.tariffa);
    expect(e.euroCasa, closeTo(e.kwhDaCasa * 0.22, 1e-6));
    expect(r.senzaPrezzoVero, SenzaPrezzoVero.senzaRicarica);
    expect(r.righe.firstWhere((x) => x.$1 == 'Da casa').$2, endsWith('prezzo di casa 0,22 €/kWh'));
  });

  testWidgets('la casa non ha il prezzo dell\'energia: lo dice, e dove si mette', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final casa = SorgenteGdahome();
    addTearDown(casa.dispose);
    final r = await corto(
      tester,
      casa,
      () => {
        'ricariche': [ricarica()..remove('euroRete')],
        'prezzo': null,
        'auto': ['Auto'],
      },
    );
    expect(r.energia!.origine, PrezzoDiPartenza.opzioni);
    expect(r.senzaPrezzoVero, SenzaPrezzoVero.senzaTariffa);
    expect(r.note.last, contains('plancia, sezione Energia'));
    expect(r.righeAuto.firstWhere((x) => x.$1 == 'Ricarica').$2, contains('in GdAHome manca il prezzo dell\'energia'));
  });

  testWidgets('caricato altrove dopo l\'ultima ricarica a casa: non è energia di casa, e lo dice', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final casa = SorgenteGdahome();
    addTearDown(casa.dispose);
    // A casa fino al 40%; si parte all'82%: il resto viene da un'altra parte.
    final r = await corto(
      tester,
      casa,
      () => {
        'ricariche': [ricarica(socA: 40)],
        'prezzo': {'euroAlKwh': 0.25},
        'auto': ['Auto'],
      },
    );
    expect(r.energia!.origine, PrezzoDiPartenza.opzioni);
    expect(r.senzaPrezzoVero, SenzaPrezzoVero.ricaricaAltrove);
    expect(r.righe.map((x) => x.$1), isNot(contains('Da casa')));
    expect(r.note.last, contains('hai caricato altrove'));
  });
}
