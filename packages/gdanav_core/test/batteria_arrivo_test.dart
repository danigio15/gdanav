import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/* ── «95% adesso, mancano 4 km, e dice 94% all'arrivo» ────────────────────
 *
 * Una foto dal campo. Il piano veniva spostato in parallelo: lo scostamento
 * di adesso finiva sull'arrivo, e la pendenza restava quella del piano. Se il
 * piano sbaglia di quanto consuma, sbaglia anche l'arrivo — di tutto il
 * viaggio che manca, non di un po'. */
void main() {
  test('senza misure si torna allo spostamento in parallelo', () {
    // Il piano diceva 91% qui e 90% all'arrivo; siamo al 95%, quattro sopra.
    expect(
      batteriaAllArrivo(adesso: 95, pianoAdesso: 91, pianoArrivo: 90),
      closeTo(94, 0.001),
    );
  });

  test('con la macchina che beve come il piano, il conto non cambia', () {
    /* L'invariante che tiene onesta la correzione: fattore 1 deve dare
     * esattamente quello che dava prima. Se cambia qualcosa qui, la
     * correzione sta facendo anche altro. */
    for (final (adesso, qui, arrivo) in [(95.0, 91.0, 90.0), (40.0, 55.0, 12.0), (80.0, 80.0, 30.0)]) {
      expect(
        batteriaAllArrivo(adesso: adesso, pianoAdesso: qui, pianoArrivo: arrivo, fattore: 1),
        closeTo(batteriaAllArrivo(adesso: adesso, pianoAdesso: qui, pianoArrivo: arrivo), 0.001),
        reason: 'fattore 1 su ($adesso, $qui, $arrivo)',
      );
    }
  });

  test('bevendo il triplo del piano, il calo che resta triplica', () {
    // Il piano prevede un punto da qui all'arrivo; la macchina ne fa tre.
    expect(
      batteriaAllArrivo(adesso: 95, pianoAdesso: 91, pianoArrivo: 90, fattore: 3),
      closeTo(92, 0.001),
    );
  });

  test('bevendo meno del piano si arriva più su', () {
    expect(
      batteriaAllArrivo(adesso: 60, pianoAdesso: 60, pianoArrivo: 20, fattore: 0.5),
      closeTo(40, 0.001),
    );
  });

  test('non si scende sotto zero né si sale sopra cento', () {
    expect(batteriaAllArrivo(adesso: 10, pianoAdesso: 10, pianoArrivo: 2, fattore: 3), 0);
    expect(batteriaAllArrivo(adesso: 99, pianoAdesso: 99, pianoArrivo: 100, fattore: 3), 100);
  });

  test('con una colonnina davanti si corregge solo il tratto dopo la sosta', () {
    /* Alla colonnina si carica FINO all'80%, non DEL 30%: quanto si è
     * consumato prima non cambia con che batteria si riparte. Quindi conta
     * solo il calo dall'80% all'arrivo — e quello sì, va corretto. */
    expect(
      batteriaAllArrivo(
        adesso: 35,
        pianoAdesso: 50,
        pianoArrivo: 60,
        fattore: 2,
        dopoLUltimaSosta: 80,
      ),
      closeTo(40, 0.001), // 80 - (80 - 60) * 2
    );
    // E senza fattore resta lo spostamento in parallelo di prima.
    expect(
      batteriaAllArrivo(adesso: 35, pianoAdesso: 50, pianoArrivo: 60, dopoLUltimaSosta: 80),
      closeTo(45, 0.001),
    );
  });

  group('quanto beve davvero', () {
    test('sotto i cinque chilometri non si sa ancora', () {
      expect(fattoreDelConsumo(kmMisurati: 4.9, whMisurati: 4900 * 2, kwh100DelPiano: 18), isNull);
    });

    test('venti kWh/100 su un piano da diciotto fa poco più di uno', () {
      // 10 km, 2000 Wh = 20 kWh/100 km.
      expect(fattoreDelConsumo(kmMisurati: 10, whMisurati: 2000, kwh100DelPiano: 18), closeTo(20 / 18, 0.001));
    });

    test('una lettura impazzita non sposta l\'arrivo di venti punti', () {
      // 10 km e 20 kWh: 200 kWh/100 km, undici volte il piano. Si prende tre.
      expect(fattoreDelConsumo(kmMisurati: 10, whMisurati: 20000, kwh100DelPiano: 18), 3);
      expect(fattoreDelConsumo(kmMisurati: 10, whMisurati: 100, kwh100DelPiano: 18), 0.4);
    });

    test('senza piano, o senza consumo, non si inventa niente', () {
      expect(fattoreDelConsumo(kmMisurati: 10, whMisurati: 2000, kwh100DelPiano: 0), isNull);
      expect(fattoreDelConsumo(kmMisurati: 10, whMisurati: 0, kwh100DelPiano: 18), isNull);
    });
  });
}
