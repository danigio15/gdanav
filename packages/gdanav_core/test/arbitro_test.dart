import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  final ora = DateTime.utc(2026, 9, 23, 10);
  StatoAuto lettura(TipoSorgente s, double batteria, Duration fa) =>
      StatoAuto(sorgente: s, letto: ora.subtract(fa), batteria: batteria);

  ArbitroSorgenti nuovo() => ArbitroSorgenti(capacitaUtileKwh: 60);

  test('senza letture non sa niente', () {
    expect(nuovo().statoAttuale(ora), isNull);
  });

  test("in automatico vince l'auto se è fresca", () {
    final a = nuovo()
      ..registra(lettura(TipoSorgente.homeAssistant, 80, const Duration(minutes: 1)))
      ..registra(lettura(TipoSorgente.androidAuto, 78, const Duration(seconds: 5)));
    expect(a.statoAttuale(ora)!.sorgente, TipoSorgente.androidAuto);
  });

  test('Android Auto vecchio lascia il posto a Home Assistant fresco', () {
    final a = nuovo()
      ..registra(lettura(TipoSorgente.androidAuto, 78, const Duration(minutes: 2)))
      ..registra(lettura(TipoSorgente.homeAssistant, 76, const Duration(minutes: 1)));
    final s = a.statoAttuale(ora)!;
    expect(s.sorgente, TipoSorgente.homeAssistant);
    expect(s.batteria, 76);
  });

  test('senza niente di fresco stima dalla lettura più recente', () {
    final a = nuovo()
      ..registra(lettura(TipoSorgente.homeAssistant, 80, const Duration(minutes: 30)))
      ..registraConsumo(6); // 6 kWh su 60 = 10 punti
    final s = a.statoAttuale(ora)!;
    expect(s.sorgente, TipoSorgente.stima);
    expect(s.batteria, closeTo(70, 1e-9));
  });

  test('una lettura nuova azzera la stima della sua sorgente', () {
    final a = nuovo()
      ..registra(lettura(TipoSorgente.manuale, 90, const Duration(hours: 1)))
      ..registraConsumo(12)
      ..registra(lettura(TipoSorgente.manuale, 85, const Duration(minutes: 1)));
    final s = a.statoAttuale(ora)!;
    expect(s.sorgente, TipoSorgente.manuale);
    expect(s.batteria, 85);
  });

  test('ignora una lettura arrivata in ritardo', () {
    final a = nuovo()
      ..registra(lettura(TipoSorgente.obd, 70, const Duration(seconds: 1)))
      ..registra(lettura(TipoSorgente.obd, 75, const Duration(seconds: 10)));
    expect(a.statoAttuale(ora)!.batteria, 70);
  });

  test('in modalità fissa usa solo quella sorgente, anche se vecchia', () {
    final a = nuovo()
      ..modalita = const Fissa(TipoSorgente.homeAssistant)
      ..registra(lettura(TipoSorgente.androidAuto, 78, const Duration(seconds: 5)))
      ..registra(lettura(TipoSorgente.homeAssistant, 81, const Duration(minutes: 40)));
    final s = a.statoAttuale(ora)!;
    expect(s.sorgente, TipoSorgente.homeAssistant);
    expect(s.batteria, 81);
  });

  test('in modalità fissa senza dati di quella sorgente non ripiega', () {
    final a = nuovo()
      ..modalita = const Fissa(TipoSorgente.obd)
      ..registra(lettura(TipoSorgente.androidAuto, 78, const Duration(seconds: 5)));
    expect(a.statoAttuale(ora), isNull);
  });
}
