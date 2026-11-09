import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/auto/ponte_auto.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  test('la striscia del traffico va all\'auto: dove sta ogni coda, i minuti e quanto manca', () {
    // «Su Android Auto non esce la linea ai lati del traffico con i minuti in più.»
    const s = StrisciaTraffico(
      code: [
        CodaInStriscia(da: 0, a: 0.1, livello: 3, minuti: 4, distanzaM: 0),
        CodaInStriscia(da: 0.4, a: 0.6, livello: 2, minuti: 3, distanzaM: 15000),
      ],
      scalaM: 100000,
      restantiM: 150000,
    );
    final d = datiStriscia(s);
    expect(d['tagliata'], isTrue);
    final code = d['code']! as List;
    expect(code, hasLength(2));
    expect(code[0], {'da': 0.0, 'a': 0.1, 'livello': 3, 'minuti': 4, 'sotto': 'ci sei'});
    expect((code[1] as Map)['minuti'], 3);
    expect((code[1] as Map)['sotto'], distanzaBreve(15000));
  });
}
