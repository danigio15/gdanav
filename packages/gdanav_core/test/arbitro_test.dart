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

  group('i dati dell\'auto contro la stima (dal campo: auto 23% e 95 km, gdanav 21% e 88 km)', () {
    StatoAuto daCasa(double batteria, double km, Duration fa) => StatoAuto(
          sorgente: TipoSorgente.gdahome,
          letto: ora.subtract(fa),
          batteria: batteria,
          autonomiaKm: km,
        );

    test('una lettura nuova datata col suo ultimo cambio vale da quando arriva, e si mostra com\'è', () {
      final a = nuovo()
        ..registra(daCasa(25, 103, const Duration(minutes: 30)), ricevuto: ora.subtract(const Duration(minutes: 20)))
        // La guida consuma: 1,2 kWh su 60 sono due punti.
        ..registraConsumo(1.2, ora: ora.subtract(const Duration(minutes: 1)))
        // Arriva il dato nuovo, ma Home Assistant lo data un quarto d'ora fa.
        ..registra(daCasa(23, 95, const Duration(minutes: 15)), ricevuto: ora);
      final s = a.statoAttuale(ora)!;
      expect(s.sorgente, TipoSorgente.gdahome);
      expect(s.batteria, 23);
      expect(s.autonomiaKm, 95);
      // Finché è fresca, il consumo non la tocca.
      a.registraConsumo(0.3, ora: ora.add(const Duration(minutes: 2)));
      expect(a.statoAttuale(ora.add(const Duration(minutes: 2)))!.batteria, 23);
    });

    test('la stima comincia solo fra due letture, scala anche i km, e si riallinea alla lettura dopo', () {
      final a = nuovo()..registra(daCasa(23, 95, const Duration(minutes: 30)), ricevuto: ora);
      // Vecchia (la prima lettura vale dalla sua ora): la stima parte da lei.
      a.registraConsumo(0.6, ora: ora); // un punto
      final stimata = a.statoAttuale(ora)!;
      expect(stimata.sorgente, TipoSorgente.stima);
      expect(stimata.stimataDa, TipoSorgente.gdahome);
      expect(stimata.batteria, closeTo(22, 1e-9));
      expect(stimata.autonomiaKm, closeTo(95 * 22 / 23, 1e-9));
      // Arriva il dato vero: quello, non la stima.
      a.registra(daCasa(22.5, 93, const Duration(minutes: 12)), ricevuto: ora.add(const Duration(seconds: 30)));
      final vera = a.statoAttuale(ora.add(const Duration(seconds: 31)))!;
      expect(vera.sorgente, TipoSorgente.gdahome);
      expect(vera.batteria, 22.5);
      expect(vera.autonomiaKm, 93);
    });

    test('una lettura rimandata uguale non azzera la stima e non diventa fresca', () {
      final a = nuovo()..registra(daCasa(23, 95, const Duration(minutes: 30)));
      a.registraConsumo(0.6, ora: ora);
      a.registra(daCasa(23, 95, const Duration(minutes: 30)), ricevuto: ora);
      final s = a.statoAttuale(ora)!;
      expect(s.sorgente, TipoSorgente.stima);
      expect(s.batteria, closeTo(22, 1e-9));
    });
  });

  group("i dati nuovi dell'auto (GdAAuto)", () {
    StatoAuto daCasa(double batteria, Duration fa, {double? fuori, double? energia, double? capacita}) => StatoAuto(
          sorgente: TipoSorgente.homeAssistant,
          letto: ora.subtract(fa),
          batteria: batteria,
          temperaturaEsternaC: fuori,
          energiaKwh: energia,
          capacitaKwh: capacita,
        );

    test('la stessa batteria con altri dati li porta dentro, senza toccare la stima', () {
      final a = nuovo()..registra(daCasa(50, const Duration(minutes: 30), fuori: 12));
      a.registraConsumo(0.6, ora: ora); // un punto
      // Home Assistant la data con la batteria: stessa ora, ma fuori fa più freddo.
      a.registra(daCasa(50, const Duration(minutes: 30), fuori: 4), ricevuto: ora);
      final s = a.statoAttuale(ora)!;
      expect(s.temperaturaEsternaC, 4);
      expect(s.sorgente, TipoSorgente.stima);
      expect(s.batteria, closeTo(49, 1e-9));
    });

    test("l'energia che resta conta come la batteria: un decimo di kWh è una lettura nuova", () {
      final a = nuovo()..registra(daCasa(50, const Duration(minutes: 30), energia: 30.0));
      a.registraConsumo(0.6, ora: ora);
      a.registra(daCasa(50, const Duration(minutes: 30), energia: 29.7), ricevuto: ora);
      final s = a.statoAttuale(ora)!;
      expect(s.sorgente, TipoSorgente.homeAssistant);
      expect(s.energiaKwh, 29.7);
    });

    test('la stima conta i punti con la capacità vera, e scala anche l\'energia', () {
      final a = nuovo()..registra(daCasa(50, const Duration(hours: 1), energia: 20, capacita: 40));
      a.registraConsumo(4, ora: ora); // 4 kWh su 40 sono dieci punti, non sei e mezzo
      final s = a.statoAttuale(ora)!;
      expect(s.sorgente, TipoSorgente.stima);
      expect(s.batteria, closeTo(40, 1e-9));
      expect(s.energiaKwh, closeTo(16, 1e-9));
      expect(s.capacitaKwh, 40);
    });
  });
}
