import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/schermate/la_tua_auto.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  List<String> cerca(String f) => [
    for (final v in catalogoVeicoli)
      if (corrisponde(v, f)) v.id,
  ];

  test('la ricerca delle auto ignora accenti, trattini e spazi', () {
    expect(semplice('Škoda Enyaq'), 'skoda enyaq');
    expect(semplice('Citroën ë-C4'), 'citroen e c4');
    expect(cerca('skoda enyaq'), contains('skoda-enyaq-85'));
    expect(cerca('id3'), contains('volkswagen-id3-58'));
    expect(cerca('ID.3 58'), contains('volkswagen-id3-58'));
    expect(cerca('tesla model y'), containsAll(['tesla-model-y-lr', 'tesla-model-y-rwd']));
    expect(cerca(''), hasLength(catalogoVeicoli.length));
    expect(cerca('nessunaautocosì'), isEmpty);
  });
}
