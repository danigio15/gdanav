import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  test("l'archivio va e torna, e trova quelli vicini", () {
    final testo = ArchivioAutovelox.scrivi([
      (45.46, 9.19, 50, 90.0),
      (45.47, 9.20, null, null),
      (41.9, 12.5, 130, null),
    ]);
    final a = ArchivioAutovelox.leggi(testo);
    expect(a.quanti, 3);
    final vicini = a.vicini(const Punto(45.465, 9.195), 5000);
    expect(vicini, hasLength(2));
    final primo = vicini.firstWhere((s) => s.limiteKmh == 50);
    expect(primo.fissa, isTrue);
    expect(primo.tipo, TipoSegnalazione.autovelox);
    expect(primo.avviso, 'Autovelox, limite 50');
    expect(vicini.firstWhere((s) => s.limiteKmh == null).avviso, 'Autovelox');
    expect(a.vicini(const Punto(41.9, 12.5), 1000).single.limiteKmh, 130);
  });

  test('la direzione: si avvisa solo chi va da quella parte', () {
    final est = Segnalazione(
      id: 'x',
      tipo: TipoSegnalazione.autovelox,
      punto: const Punto(45, 9),
      creata: DateTime(2026),
      direzioneGradi: 90,
    );
    expect(est.riguarda(80), isTrue);
    expect(est.riguarda(140), isTrue);
    expect(est.riguarda(270), isFalse);
    final nord = Segnalazione(
      id: 'y',
      tipo: TipoSegnalazione.autovelox,
      punto: const Punto(45, 9),
      creata: DateTime(2026),
      direzioneGradi: 10,
    );
    expect(nord.riguarda(340), isTrue);
    expect(nord.riguarda(190), isFalse);
  });
}
