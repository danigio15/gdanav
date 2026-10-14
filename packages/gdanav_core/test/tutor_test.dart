import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Il Tutor sul percorso: quando arriva, la media dentro, la fine.
void main() {
  // Una strada dritta verso nord, 20 km: un punto ogni chilometro circa.
  final punti = [for (var i = 0; i <= 20; i++) Punto(42 + i * 0.009, 12)];
  final linea = Linea(punti);
  // Il Tutor fra il km 5 e il km 10 (circa), sulla nostra carreggiata.
  final tutor = TrattoTutor(id: 't', inizio: punti[5], fine: punti[10], limiteKmh: 130);
  // Lo stesso tratto per chi va al contrario.
  final contrario = TrattoTutor(id: 'c', inizio: punti[12], fine: punti[8], limiteKmh: 130);
  final inizioM = linea.cumulate[5], fineM = linea.cumulate[10];

  test('si avvicina, si entra, la media dopo qualche secondo, la fine', () {
    final s = SeguiTutor();
    var ora = DateTime(2026, 10, 14, 10);
    expect(s.aggiorna(linea, inizioM - 3000, ora, [tutor, contrario]), isNull);
    final davanti = s.aggiorna(linea, inizioM - 800, ora, [tutor, contrario]);
    expect(davanti, isA<TutorDavanti>());
    expect((davanti! as TutorDavanti).metri, closeTo(800, 1));

    // Dentro, a 144 km/h (40 m/s): un passo al secondo.
    var m = inizioM + 10;
    var stato = s.aggiorna(linea, m, ora, [tutor]);
    expect(stato, isA<DentroTutor>());
    expect((stato! as DentroTutor).mediaKmh, isNull, reason: 'troppo presto');
    for (var i = 0; i < 30; i++) {
      ora = ora.add(const Duration(seconds: 1));
      m += 40;
      stato = s.aggiorna(linea, m, ora, [tutor]);
    }
    final dentro = stato! as DentroTutor;
    expect(dentro.mediaKmh, closeTo(144, 0.5));
    expect(dentro.sopra(), isTrue);
    expect(dentro.restantiM, closeTo(fineM - m, 1));

    // Fuori: com'è andata, una volta.
    ora = ora.add(const Duration(seconds: 100));
    final fine = s.aggiorna(linea, fineM + 50, ora, [tutor]);
    expect(fine, isA<FineTutor>());
    expect((fine! as FineTutor).mediaKmh, lessThan(144), reason: 'l\'ultimo pezzo, più lento, abbassa la media');
    expect(s.aggiorna(linea, fineM + 100, ora, [tutor]), isNull);
  });

  test('un ricalcolo nel mezzo non perde la strada fatta', () {
    final s = SeguiTutor();
    var ora = DateTime(2026, 10, 14, 10);
    s.aggiorna(linea, inizioM + 5, ora, [tutor]);
    for (var i = 0; i < 20; i++) {
      ora = ora.add(const Duration(seconds: 1));
      s.aggiorna(linea, inizioM + 5 + 30 * (i + 1), ora, [tutor]);
    }
    // Lo stesso percorso, ricalcolato da qui: i metri ripartono da zero.
    final nuova = Linea(punti.sublist(5));
    for (var i = 0; i < 10; i++) {
      ora = ora.add(const Duration(seconds: 1));
      final stato = s.aggiorna(nuova, 5 + 600 + 30 * (i + 1), ora, [tutor]);
      expect(stato, isA<DentroTutor>());
      if (i == 9) expect((stato! as DentroTutor).mediaKmh, closeTo(30 * 3.6 * 29 / 30, 4));
    }
  });

  test('un Tutor accanto alla strada, o dell\'altra carreggiata, non conta', () {
    final s = SeguiTutor();
    final lontano = TrattoTutor(
      id: 'l',
      inizio: Punto(punti[5].lat, 12.01),
      fine: Punto(punti[10].lat, 12.01),
      limiteKmh: 110,
    );
    expect(s.aggiorna(linea, linea.cumulate[9], DateTime(2026), [lontano, contrario]), isNull);
  });
}
