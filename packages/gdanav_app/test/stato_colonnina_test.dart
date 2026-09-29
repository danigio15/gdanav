import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/stato_colonnina.dart';
import 'package:gdanav_app/stato/gestore_premium.dart';
import 'package:gdanav_core/gdanav_core.dart';

void main() {
  tearDown(() => GestorePremium.attivo.value = false);

  group('la pastiglia dice quello che si sa', () {
    test('con lo stato vero lo dice', () {
      GestorePremium.attivo.value = true;
      expect(testoDisponibilita(const Disponibilita(libere: 2, occupate: 2, totali: 4)), '2 libere su 4');
      expect(testoDisponibilita(const Disponibilita(occupate: 4, totali: 4)), 'Piena · 4 occupate');
      expect(testoDisponibilita(const Disponibilita(guaste: 2, totali: 2)), 'Fuori servizio');
    });

    /* Il difetto visto in macchina: venti colonnine sulla mappa e venti
     * pastiglie «Stato non comunicato», che sembrano un guasto dell'app.
     * Il numero delle prese è un fatto e si sa sempre; lo stato di adesso
     * quasi nessun gestore italiano lo pubblica. */
    test('senza lo stato di adesso dice quante prese ci sono, non che non sa', () {
      GestorePremium.attivo.value = true;
      expect(testoDisponibilita(const Disponibilita(totali: 4)), '4 prese');
      expect(testoDisponibilita(const Disponibilita(totali: 1)), '1 presa');
    });

    test('senza nemmeno le prese, allora sì che lo dice', () {
      GestorePremium.attivo.value = true;
      expect(testoDisponibilita(const Disponibilita()), 'Stato non comunicato');
    });

    test('senza Premium la frase resta quella: lo stato c\'è, non è acceso', () {
      GestorePremium.attivo.value = false;
      expect(testoDisponibilita(const Disponibilita(totali: 4)), 'Libere/occupate con Premium');
    });
  });
}
