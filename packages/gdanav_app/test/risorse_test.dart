import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/segnaposto.dart';
import 'package:gdanav_app/risorse.dart';
import 'package:gdanav_app/stato/gestore_ztl.dart';

/// Le risorse si leggono col nome del pacchetto davanti: così le trovano sia
/// l'app gdanav sia gdahome. Se un nome è sbagliato lo si sa qui, e non sul
/// telefono con la mappa senza colonnine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('i file del pacchetto si trovano', () async {
    for (final nome in ['colonnine.json', 'autovelox.json', 'foto_auto.json', 'ztl.json']) {
      expect(await rootBundle.loadString('$radiceRisorse/$nome'), isNotEmpty, reason: nome);
    }
    expect((await rootBundle.load(logoGdanav)).lengthInBytes, greaterThan(0));
  });

  test('le ZTL dentro l\'app si leggono, su un altro filo, con gli orari', () async {
    final a = await archivioZtl();
    expect(a.quanteZtl, greaterThan(150));
    expect(a.quantePedonali, greaterThan(1000));
    // Quelle con gli orari scritti li hanno capiti tutti.
    final conOrari = a.zone.where((z) => z.orariTesto != null).toList();
    expect(conOrari, isNotEmpty);
    // Il Tridente di Roma: nei giorni feriali di giorno è attivo.
    final tridente = a.zone.where((z) => z.citta == 'Roma' && z.nome == 'Tridente').firstOrNull;
    expect(tridente, isNotNull);
    expect(tridente!.attivaAlle(DateTime(2026, 9, 29, 11)), isTrue);
  });

  test('i segnaposto si trovano', () async {
    for (final s in Segnaposto.values) {
      expect((await rootBundle.load(s.asset)).lengthInBytes, greaterThan(0), reason: s.asset);
    }
  });
}
