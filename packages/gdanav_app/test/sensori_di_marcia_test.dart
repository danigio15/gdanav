import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/ponte_3d.dart';
import 'package:gdanav_app/schermate/diagnosi_auto.dart';
import 'package:gdanav_app/stato/gestore_guida.dart';
import 'package:gdanav_app/stato/gestore_viaggio.dart';
import 'package:gdanav_app/stato/sensori_di_marcia.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'aiuti.dart';
import 'voce_arrivo_test.dart' show VoceRegistrata;

/// Registra quello che arriva, e fa finta di essere tarata se si vuole.
class StimaFinta extends AccelerazioneDiMarcia {
  final campioni = <List<double>>[];
  final gravita_ = <List<double>>[];
  final velocita_ = <(double, bool)>[];
  final chiesteStrade = <(DateTime, DateTime, double)>[];
  bool finta = false;
  double stradaFinta = 0;

  @override
  void campione(DateTime t, double x, double y, double z) => campioni.add([x, y, z]);
  @override
  void gravita(DateTime t, double x, double y, double z) => gravita_.add([x, y, z]);
  @override
  void velocita(DateTime t, double ms, {required bool cruscotto}) => velocita_.add((ms, cruscotto));
  @override
  bool get tarata => finta;
  @override
  Duration? get ritardoGpsMisurato => finta ? const Duration(milliseconds: 600) : null;
  @override
  double? strada(DateTime da, DateTime a, double v0) {
    chiesteStrade.add((da, a, v0));
    return finta ? stradaFinta : null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('in guida i sensori vanno alla stima: l\'accelerazione, la gravità, la velocità del cruscotto', () async {
    final senza = StreamController<CampioneSensore>();
    final con = StreamController<CampioneSensore>();
    final stima = StimaFinta();
    ({double ms, DateTime alle})? auto = (ms: 10, alle: DateTime.utc(2026, 1, 1, 8));
    final s = SensoriDiMarcia(
      senzaGravita: () => senza.stream,
      conGravita: () => con.stream,
      velocitaAuto: () => auto,
      stima: stima,
    );
    s.avvia();
    expect(s.accesi, isTrue);
    final t = DateTime.utc(2026, 1, 1, 8);
    senza.add((t: t, x: 0.5, y: -1, z: 0.2));
    con.add((t: t, x: 0.5, y: 8.8, z: 4.2));
    senza.add((t: t.add(const Duration(milliseconds: 20)), x: 0.4, y: -1, z: 0.2));
    await Future<void>.delayed(Duration.zero);
    expect(stima.campioni, hasLength(2));
    // La gravità è l'accelerometro meno l'accelerazione dell'auto.
    expect(stima.gravita_.single, [0.0, 9.8, 4.0]);
    // La velocità del cruscotto una volta per lettura, non a ogni campione.
    expect(stima.velocita_, [(10.0, true)]);
    auto = (ms: 9, alle: DateTime.utc(2026, 1, 1, 8, 0, 1));
    senza.add((t: t.add(const Duration(milliseconds: 40)), x: 0.4, y: -1, z: 0.2));
    await Future<void>.delayed(Duration.zero);
    expect(stima.velocita_, [(10.0, true), (9.0, true)]);
    s.velocitaGps(t, 11);
    expect(stima.velocita_.last, (11.0, false));
    await s.ferma();
    expect(s.accesi, isFalse);
    expect(senza.hasListener, isFalse);
  });

  testWidgets('con l\'accelerometro tarato, la posizione stimata è quella che dicono le accelerazioni', (tester) async {
    preparaPiattaforma(portachiavi: impostazioniComplete);
    final a = await ambiente(tester, km: 20);
    a.auto.manuale.imposta(90);
    await tester.runAsync(() => a.viaggio.vaiA(const Luogo(nome: 'Nord', posizione: Punto(42.18, 12))));
    final punti = (a.viaggio.stato as ViaggioPronto).viaggio.percorso.punti;
    final stima = StimaFinta();
    final sensori = SensoriDiMarcia(
      senzaGravita: () => const Stream.empty(),
      conGravita: () => const Stream.empty(),
      stima: stima,
    );
    var ora = DateTime.utc(2026, 1, 1, 8);
    final guida = GestoreGuida(
      viaggio: a.viaggio,
      auto: a.auto,
      posizioni: () => a.posizioni.stream,
      voce: VoceRegistrata(),
      sensori: sensori,
      orologio: () => ora,
    );
    guida.avvia();
    expect(sensori.accesi, isTrue);
    final letta = ora;
    a.posizioni.add(PuntoInMoto(punti[2].lat, punti[2].lon, velocitaMs: 12, alle: letta));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    final qui = guida.avanzamento!.percorsiM;
    // La velocità del GPS va a tarare.
    expect(stima.velocita_, contains((12.0, false)));
    ora = ora.add(const Duration(milliseconds: 500));
    // Non tarata: come prima, alla velocità della lettura portata avanti.
    expect(guida.metriStimati(), closeTo(qui + 12 * (0.5 + 0.9), 0.01));
    // Tarata: la strada delle accelerazioni, dalla lettura com'era (il
    // ritardo del GPS misurato prima) ad adesso, partendo da 12 m/s.
    stima
      ..finta = true
      ..stradaFinta = 7.5;
    expect(guida.metriStimati(), closeTo(qui + 7.5, 1e-9));
    final (da, al, v0) = stima.chiesteStrade.last;
    expect(da, letta.subtract(const Duration(milliseconds: 600)));
    expect(al, ora);
    expect(v0, 12);
    await tester.runAsync(guida.ferma);
    expect(sensori.accesi, isFalse);
  });

  test('il messaggio dell\'accelerazione per la scena 3D', () {
    final m = msgAccelerazione(
      a: -3.456,
      alle: DateTime.utc(2026, 1, 1, 8),
      ritardo: const Duration(milliseconds: 600),
    );
    expect(m['tipo'], 'accelerazione');
    expect(m['a'], -3.46);
    expect(m['alle'], DateTime.utc(2026, 1, 1, 8).millisecondsSinceEpoch);
    expect(m['ritardo'], 0.6);
    expect(msgAccelerazione(a: 1, alle: DateTime.utc(2026)).containsKey('ritardo'), isFalse);
  });

  test('la diagnosi dice se arriva la velocità dell\'auto e se l\'accelerometro è tarato', () async {
    final senza = StreamController<CampioneSensore>();
    final stima = StimaFinta();
    final t = DateTime.utc(2026, 1, 1, 8);
    var n = 0;
    final s = SensoriDiMarcia(
      senzaGravita: () => senza.stream,
      conGravita: () => const Stream.empty(),
      velocitaAuto: () => (ms: 10, alle: t.add(Duration(milliseconds: 100 * n))),
      stima: stima,
    );
    var voci = vociFreccia(s, ora: t);
    expect(voci[0].$2, isFalse, reason: 'senza letture del cruscotto');
    expect(voci[1].$3, contains('Non ancora sentito'));
    s.avvia();
    for (n = 0; n <= 20; n++) {
      senza.add((t: t.add(Duration(milliseconds: 100 * n)), x: 0, y: 0, z: 0));
      await Future<void>.delayed(Duration.zero);
    }
    voci = vociFreccia(s, ora: t.add(const Duration(seconds: 2)));
    expect(voci[0].$2, isTrue);
    expect(voci[0].$3, contains('10,0 volte al secondo'));
    expect(voci[1].$3, contains('Si sta tarando'));
    stima.finta = true;
    expect(vociFreccia(s, ora: t)[1].$3, contains('GPS in ritardo di 0,6 s'));
    await s.ferma();
  });
}
