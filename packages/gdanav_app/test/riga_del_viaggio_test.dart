import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/riga_del_viaggio.dart';

/* «Dati auto e km all'arrivo sul telefono devono essere uguali ad Android
 * Auto.» La riga del telefono e quella della scheda dell'arrivo dell'auto
 * (`GuidaAuto.testoDelViaggio`) dicono le stesse cose nello stesso modo. */
void main() {
  String riga(List<PezzoViaggio> pezzi) => [for (final p in pezzi) '${p.prima}${p.testo}'].join(' · ');

  test('come in auto: batteria, km, arrivo e meteo', () {
    final pezzi = pezziDelViaggio(
      batteria: 51.4,
      autonomiaKm: 200.2,
      arrivo: 46.4,
      meteoEmoji: '☀',
      temperaturaC: 12.3,
    );
    expect(riga(pezzi), '🔋 51% · 200 km · arrivo 46% · ☀ 12°');
    expect(pezzi.firstWhere((p) => p.chiave == 'batteria-arrivo').tono, TonoPezzo.verde);
  });

  test('una stima si scrive col «~», e sotto il 20% la batteria è rossa', () {
    final pezzi = pezziDelViaggio(batteria: 18, stimata: true, autonomiaKm: 60, arrivo: 7);
    expect(riga(pezzi), '🔋 ~18% · ~60 km · arrivo 7%');
    expect(pezzi.first.tono, TonoPezzo.rosso);
    expect(pezzi.last.tono, TonoPezzo.rosso);
  });

  test("l'auto termica: niente batteria, il meteo resta", () {
    expect(riga(pezziDelViaggio(autonomiaKm: 300, arrivo: 50, temperaturaC: 8)), '8°');
  });
}
