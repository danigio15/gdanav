import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/stile.dart';

/// Il percorso col traffico, come in Waze: la coda è una striscia dentro la
/// linea celeste, più stretta e in mezzo; ai lati resta il celeste.
void main() {
  List<Map<String, Object?>> strati(Map<String, Object> stile) =>
      (stile['layers']! as List).cast<Map<String, Object?>>();

  /// La larghezza di uno strato a [zoom], dall'interpolazione esponenziale
  /// fra zoom 12 e 18 (gli estremi bastano a confrontare).
  double larghezza(Map<String, Object?> strato, double zoom) {
    final w = (strato['paint']! as Map)['line-width']! as List;
    final (z0, v0, z1, v1) = (w[3] as num, w[4] as num, w[5] as num, w[6] as num);
    expect([z0, z1], [12, 18]);
    return zoom <= z0 ? v0.toDouble() : v1.toDouble();
  }

  for (final (scuro, perAuto) in [(false, false), (true, false), (false, true), (true, true)]) {
    test('${scuro ? 'scuro' : 'chiaro'}${perAuto ? ', in auto' : ''}: la coda sta dentro la linea, sopra di lei', () {
      final tutti = strati(stileMappa(scuro: scuro, chiaveTraffico: 'CHIAVE', perAuto: perAuto));
      final ids = [for (final l in tutti) l['id']];
      Map<String, Object?> s(String id) => tutti.singleWhere((l) => l['id'] == id);

      // Dal basso: bordo, linea, coda, frecce.
      expect(ids.indexOf('percorso-bordo'), lessThan(ids.indexOf('percorso')));
      expect(ids.indexOf('percorso'), lessThan(ids.indexOf('code')));
      expect(ids.indexOf('code'), lessThan(ids.indexOf('percorso-frecce')));
      // Il traffico di tutte le strade resta sotto il percorso.
      expect(ids.indexOf(stratoTraffico), lessThan(ids.indexOf('percorso-bordo')));
      expect((s('code'))['source'], sorgenteCode);

      for (final z in [12.0, 18.0]) {
        final bordo = larghezza(s('percorso-bordo'), z);
        final linea = larghezza(s('percorso'), z);
        final coda = larghezza(s('code'), z);
        expect(linea, lessThan(bordo));
        // Più stretta della linea, ai lati resta un bordo celeste; ma il
        // rosso è la cosa che si legge: come in Waze, due terzi abbondanti.
        expect(coda, lessThan(linea * 0.8));
        expect(coda, greaterThan(linea * 0.6));
      }
    });
  }

  test('la linea del percorso è un po\' più larga di prima', () {
    // Prima 5,5 e 18: con la coda dentro, i bordi celesti devono vedersi.
    expect(larghezzaPercorso.$1, greaterThan(5.5));
    expect(larghezzaPercorso.$2, greaterThan(18));
  });
}
