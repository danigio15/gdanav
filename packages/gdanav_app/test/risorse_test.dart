import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/segnaposto.dart';
import 'package:gdanav_app/risorse.dart';

/// Le risorse si leggono col nome del pacchetto davanti: così le trovano sia
/// l'app gdanav sia gdahome. Se un nome è sbagliato lo si sa qui, e non sul
/// telefono con la mappa senza colonnine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('i file del pacchetto si trovano', () async {
    for (final nome in ['colonnine.json', 'autovelox.json', 'foto_auto.json']) {
      expect(await rootBundle.loadString('$radiceRisorse/$nome'), isNotEmpty, reason: nome);
    }
  });

  test('i segnaposto si trovano', () async {
    for (final s in Segnaposto.values) {
      expect((await rootBundle.load(s.asset)).lengthInBytes, greaterThan(0), reason: s.asset);
    }
  });
}
