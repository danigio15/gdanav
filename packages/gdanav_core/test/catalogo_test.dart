import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  group('catalogo delle auto', () {
    test('è ampio e gli id sono unici', () {
      expect(catalogoVeicoli.length, greaterThanOrEqualTo(200));
      final id = catalogoVeicoli.map((v) => v.id).toSet();
      expect(id, hasLength(catalogoVeicoli.length));
      for (final v in catalogoVeicoli) {
        expect(v.id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')), reason: v.id);
      }
    });

    test('i valori sono plausibili', () {
      for (final v in catalogoVeicoli) {
        expect(v.capacitaUtileKwh, inInclusiveRange(10, 130), reason: v.nome);
        expect(v.massaKg, inInclusiveRange(500, 3500), reason: v.nome);
        expect(v.cdA, inInclusiveRange(0.3, 1.5), reason: v.nome);
        // Nel catalogo ci sono solo auto che si ricaricano in continua.
        expect(v.piccoDcKw, inInclusiveRange(20, 400), reason: v.nome);
        expect(v.potenzaAcKw, greaterThan(0), reason: v.nome);
        expect(v.connettori, contains(TipoConnettore.tipo2), reason: v.nome);
        expect(
          v.connettori.contains(TipoConnettore.ccs2) || v.connettori.contains(TipoConnettore.chademo),
          isTrue,
          reason: v.nome,
        );
        expect(v.nome, '${v.marca} ${v.modello}');
      }
    });

    test('è ordinato per marca', () {
      final marche = <String>[];
      for (final v in catalogoVeicoli) {
        if (marche.isEmpty || marche.last != v.marca) marche.add(v.marca);
      }
      expect(marche.toSet(), hasLength(marche.length), reason: 'ogni marca in un solo blocco');
      String chiave(String m) => m.toLowerCase().replaceAll('š', 's');
      expect(marche, [...marche]..sort((a, b) => chiave(a).compareTo(chiave(b))));
    });

    test('gli id già salvati nelle preferenze esistono ancora', () {
      const storici = [
        'tesla-model-3-lr',
        'tesla-model-3-rwd',
        'tesla-model-y-lr',
        'tesla-model-y-rwd',
        'fiat-500e-42',
        'volkswagen-id3-58',
        'volkswagen-id4-77',
        'cupra-born-58',
        'skoda-enyaq-85',
        'renault-megane-60',
        'renault-5-52',
        'renault-zoe-r135',
        'dacia-spring',
        'peugeot-e208-51',
        'peugeot-e2008-54',
        'jeep-avenger',
        'hyundai-kona-65',
        'hyundai-ioniq5-77',
        'kia-ev6-77',
        'kia-niro-ev',
        'mg4-64',
        'byd-atto3',
        'byd-dolphin-60',
        'byd-seal-82',
        'volvo-ex30-69',
        'polestar-2-lr',
        'bmw-i4-40',
        'mercedes-eqa-250',
        'smart-1',
        'nissan-leaf-e-plus',
      ];
      for (final id in storici) {
        expect(veicoloPerId(id), isNotNull, reason: id);
      }
    });

    test('la Leaf usa il CHAdeMO', () {
      expect(veicoloPerId('nissan-leaf-e-plus')!.connettori, contains(TipoConnettore.chademo));
      expect(veicoloPerId('nissan-leaf-e-plus')!.connettori, isNot(contains(TipoConnettore.ccs2)));
    });
  });

  group('l\'auto scritta da gdahome', () {
    test('marca e modello come li scrive la plancia', () {
      expect(veicoloPerNome('Renault', 'Zoe R135')?.id, 'renault-zoe-r135');
      expect(veicoloPerNome('Tesla', 'Model 3 Long Range')?.id, 'tesla-model-3-lr');
      expect(veicoloPerNome('Tesla', 'Tesla Model 3 Long Range')?.id, 'tesla-model-3-lr');
      expect(veicoloPerNome('fiat', '500e', kwh: 37.3)?.marca, 'Fiat');
    });

    test('a parità di parole vince la batteria più vicina', () {
      expect(veicoloPerNome('Renault', '5 E-Tech', kwh: 52)?.id, 'renault-5-52');
      expect(veicoloPerNome('Renault', '5 E-Tech', kwh: 40)?.id, 'renault-5-40');
    });

    test('se non torna niente, niente', () {
      expect(veicoloPerNome('Renault', ''), isNull);
      expect(veicoloPerNome('Marca che non c\'è', 'Qualcosa'), isNull);
      expect(veicoloPerNome('Tesla', 'Cybertruck'), isNull);
    });
  });
}
