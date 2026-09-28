import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/servizi.dart';
import 'package:gdanav_app/stato/archivio.dart';

void main() {
  group('chi calcola i percorsi', () {
    test('con la chiave TomTom si usa TomTom', () {
      expect(const Impostazioni(chiaveTomTom: 'una-chiave').percorsiDaTomTom, isTrue);
    });

    test('senza chiave si torna a Valhalla, non si resta a piedi', () {
      const senza = Impostazioni(valhalla: 'https://valhalla1.openstreetmap.de/');
      expect(senza.percorsiDaTomTom, isFalse);
      expect(senza.mancante, isNull);
    });

    test('con TomTom l\'indirizzo di Valhalla non serve più', () {
      expect(const Impostazioni(chiaveTomTom: 'una-chiave').mancante, isNull);
    });

    test('senza niente il viaggio non si può calcolare, e lo dice', () {
      expect(const Impostazioni().mancante, isNotNull);
    });

    test('la chiave TomTom si salva e si rilegge', () {
      const i = Impostazioni(valhalla: 'https://v/', chiaveOcm: 'o', chiaveTomTom: 't');
      final riletta = Impostazioni.daJson(i.toJson());
      expect(riletta.chiaveTomTom, 't');
      expect(riletta.percorsiDaTomTom, isTrue);
    });

    test('un archivio vecchio, senza il campo, prende la chiave cablata', () {
      final vecchia = Impostazioni.daJson(const {'valhalla': 'https://v/', 'chiave_ocm': 'o'});
      expect(vecchia.chiaveTomTom, Servizi.chiaveTomTom);
    });
  });
}
