// La voce di guida: quale voce del telefono parla, scelta dal menu.
// «Volevo provare a cambiare la voce, quella che c'è è un po' fastidiosa.»
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/voce_guida.dart';
import 'package:gdanav_app/stato/voce.dart';

void main() {
  group('le voci del telefono', () {
    test('dalla sintesi: nome e lingua, la qualità di iPhone e la rete di Android', () {
      final ios = VoceDelTelefono.daSintesi({
        'name': 'com.apple.voice.premium.it-IT.Federica',
        'locale': 'it-IT',
        'quality': 'premium',
      })!;
      expect(ios.etichetta, 'Federica');
      expect(ios.dettaglio, 'Qualità premium');
      expect(ios.italiana, isTrue);
      final android = VoceDelTelefono.daSintesi({'name': 'it-it-x-itd-network', 'locale': 'it-IT'})!;
      expect(android.etichetta, 'Voce ITD');
      expect(android.dettaglio, 'Serve internet');
      expect(VoceDelTelefono.daSintesi({'name': 'Alice'}), isNull, reason: 'senza lingua non si sa');
      expect(VoceDelTelefono.daSintesi('niente'), isNull);
      expect(VoceDelTelefono.daSintesi({'name': 'Samantha', 'locale': 'en-US'})!.italiana, isFalse);
    });

    test('le migliori prima, poi per nome', () {
      final voci = [
        const VoceDelTelefono(nome: 'Luca', lingua: 'it-IT'),
        const VoceDelTelefono(nome: 'Alice', lingua: 'it-IT'),
        const VoceDelTelefono(nome: 'Federica', lingua: 'it-IT', qualita: 'premium'),
        const VoceDelTelefono(nome: 'Paola', lingua: 'it-IT', qualita: 'enhanced'),
      ]..sort(VoceDelTelefono.ordine);
      expect(voci.map((v) => v.nome), ['Federica', 'Paola', 'Alice', 'Luca']);
    });

    test('si salva e si rilegge; un testo rovinato è la predefinita', () {
      const v = VoceDelTelefono(nome: 'it-it-x-itc-local', lingua: 'it-IT', qualita: 'enhanced');
      expect(VoceDelTelefono.daJson(v.json), v);
      expect(VoceDelTelefono.daJson(v.json)!.qualita, 'enhanced');
      expect(VoceDelTelefono.daJson('{rotto'), isNull);
      expect(VoceDelTelefono.daJson(null), isNull);
    });
  });

  group('la scelta', () {
    const alice = VoceDelTelefono(nome: 'com.apple.voice.compact.it-IT.Alice', lingua: 'it-IT');
    const federica = VoceDelTelefono(
      nome: 'com.apple.voice.premium.it-IT.Federica',
      lingua: 'it-IT',
      qualita: 'premium',
    );

    Future<List<VoceDelTelefono?>> apri(WidgetTester tester) async {
      final sentite = <VoceDelTelefono?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: VoceGuidaSchermata(voci: () async => [federica, alice], prova: (v) async => sentite.add(v)),
        ),
      );
      await tester.pumpAndSettle();
      return sentite;
    }

    tearDown(() {
      voceScelta.value = null;
      regolazioniVoce.value = (VolumeVoce.alto, VelocitaVoce.normale);
    });

    testWidgets('toccata una voce si sceglie e si sente; la predefinita torna com\'era', (tester) async {
      final sentite = await apri(tester);
      expect(find.text('Predefinita del telefono'), findsOneWidget);
      expect(find.text('Federica'), findsOneWidget);
      expect(find.text('Qualità premium'), findsOneWidget);
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(voceScelta.value, alice);
      expect(sentite, [alice]);
      await tester.tap(find.byKey(const Key('voce-ascolta')));
      await tester.pumpAndSettle();
      expect(sentite, [alice, alice]);
      await tester.tap(find.text('Predefinita del telefono'));
      await tester.pumpAndSettle();
      expect(voceScelta.value, isNull);
    });

    testWidgets('volume e velocità anche dal telefono, non solo dall\'auto', (tester) async {
      await apri(tester);
      await tester.tap(find.text('Lenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medio'));
      await tester.pumpAndSettle();
      expect(regolazioniVoce.value, (VolumeVoce.medio, VelocitaVoce.lenta));
    });
  });
}
