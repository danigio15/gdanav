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
    // Un viaggio più lungo della striscia: l'auto in fondo, come prima.
    expect(d['qui'], 0.0);
  });

  test('la striscia è il viaggio intero, e dice dove si è', () {
    // «La linea del traffico laterale non fa vedere dove mi trovo io.»
    // 30 km di viaggio, 10 fatti: si è a un terzo. La coda che comincia a
    // metà di quello che resta sta a due terzi del viaggio.
    const s = StrisciaTraffico(
      code: [CodaInStriscia(da: 0.5, a: 0.75, livello: 2, minuti: 3, distanzaM: 10000)],
      scalaM: 20000,
      restantiM: 20000,
    );
    final d = datiStriscia(s, percorsiM: 10000, lunghezzaM: 30000);
    expect(d['tagliata'], isFalse);
    expect(d['qui'], closeTo(1 / 3, 1e-9));
    final coda = (d['code']! as List).single as Map;
    expect(coda['da'], closeTo(2 / 3, 1e-9));
    expect(coda['a'], closeTo(5 / 6, 1e-9));
  });
}
