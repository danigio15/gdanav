import 'dart:io';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/// Righe vere della PUN (onData, `pdr_latest_ready.csv`), scelte per i casi
/// difficili: due parcheggi del Centro Direzionale di Napoli, un Enel X col
/// nome in codice, un punto con due spine, uno solo Tipo 3A, uno
/// pianificato, uno guasto nel 2024.
List<Colonnina> esempio() => Pun.leggiCsv(File('test/dati/pun_esempio.csv').readAsStringSync());

Colonnina chiamata(List<Colonnina> c, String nome) => c.firstWhere((x) => x.nome.contains(nome));

void main() {
  group('la PUN come la pubblica onData', () {
    test("le sigle che i nomi dei posti spiegano hanno un nome, le altre restano sigle", () {
      const intestazione = 'id_location,nome_location,indirizzo,id_evse,stato,standard_del_connettore,'
          'potenza_erogabile,latitudine_evse,longitudine_evse';
      String riga(String luogo, String evse) =>
          '$luogo,$luogo,Via Roma 1,$evse,AVAILABLE,IEC_62196_T2_COMBO,300000,45.0,11.0';
      final c = Pun.leggiCsv([
        intestazione,
        riga('IONITY Affi', 'IT*IOY*E1*1'),
        riga('Edison Next - Curtatone', 'IT*EDN*E1*1'),
        riga('Via Roma', 'IT*GES*E1*1'),
      ].join('\n'));
      expect(c.map((x) => x.operatore), ['Ionity', 'Edison Next', 'GES']);
    });

    test('una colonnina per posto, non una per presa', () {
      final c = esempio();
      final isola = chiamata(c, 'Isola A3');
      expect(isola.connettori, hasLength(5));
      // Gli EVSE ID dei suoi punti, per chiederne lo stato di adesso.
      expect(isola.evse, hasLength(5));
      expect(isola.evse, everyElement(startsWith('IT*BEC*')));
      expect(isola.id, startsWith('pun:'));
      expect(isola.fonte, 'pun');
    });

    /* Il caso dal campo: la colonnina di Via Domenico Aulisio che ABRP ed
     * EVDC mostrano e gdanav no. È della rete Be Charge, oggi Plenitude. */
    test('il Parcheggio P5 di Via Domenico Aulisio, di Plenitude', () {
      final p5 = chiamata(esempio(), 'Parcheggio P5');
      expect(p5.connettori, hasLength(4));
      expect(p5.operatore, 'Plenitude (Be Charge)');
      expect(p5.connettori.every((x) => x.tipo == TipoConnettore.tipo2), isTrue);
      expect(p5.connettori.first.potenzaKw, closeTo(22.1, 0.1));
      // Al Centro Direzionale, non in mezzo al mare.
      expect(p5.posizione.lat, closeTo(40.855, 0.01));
      expect(p5.posizione.lon, closeTo(14.29, 0.01));
    });

    test('un nome che è un codice di macchina lascia il posto all\'indirizzo', () {
      final c = esempio();
      expect(c.any((x) => x.nome == '18XM32T77B3W000013'), isFalse);
      expect(c.any((x) => x.nome.startsWith('Via Galileo Ferraris')), isTrue);
    });

    test('i nomi-codice si riconoscono, i nomi veri no', () {
      for (final codice in ['18XM32T77B3W000013', 'LOC69618', 'HPC162000003', 'AC_POLI_TN_04', 'IT*DUF*EI0046']) {
        expect(Pun.sembraUnCodice(codice), isTrue, reason: codice);
      }
      for (final nome in ['Via Roma', 'Centro Direzionale Isola A3', 'A6 Torino - Savona', 'Parcheggio P5']) {
        expect(Pun.sembraUnCodice(nome), isFalse, reason: nome);
      }
    });

    /* Con due spine la potenza è una lista: «150000, 62500». Leggerla come
     * un numero solo scartava proprio le rapide doppie. */
    test('un punto con CCS e CHAdeMO è un\'auto sola, alla potenza più alta', () {
      final doppio = esempio().firstWhere((x) => x.connettori.any((p) => p.potenzaKw >= 100));
      expect(doppio.connettori, hasLength(1));
      expect(doppio.connettori.single.tipo, TipoConnettore.ccs2);
      expect(doppio.connettori.single.potenzaKw, 150);
    });

    test('le prese degli scooter (Tipo 3A) non sono per queste auto', () {
      expect(esempio().any((x) => x.nome.contains('BURRASCA')), isFalse);
    });

    test('un punto pianificato non esiste per chi guida', () {
      expect(esempio().any((x) => x.nome.contains('Hotel Flower')), isFalse);
    });

    /* I dati sono una fotografia del 2024. Una presa guasta allora oggi può
     * andare, e dirla guasta sarebbe una bugia peggio di «non si sa». */
    test('lo stato vecchio non si usa: resta sconosciuto', () {
      for (final c in esempio()) {
        expect(c.connettori.every((p) => p.stato == StatoPresa.sconosciuto), isTrue, reason: c.nome);
      }
    });

    test('un codice operatore che non è di tre caratteri non diventa un operatore', () {
      // Nei dati c'è `IT*REVEPGS564*1*2`: «REVEPGS564» non è un operatore.
      expect(esempio().any((x) => x.operatore == 'REVEPGS564'), isFalse);
    });

    test('un file senza le colonne giuste lo dice, non torna vuoto', () {
      expect(() => Pun.leggiCsv('a,b,c\n1,2,3\n'), throwsFormatException);
    });

    test('le virgole dentro le virgolette restano dentro il campo', () {
      // `capabilities` è «"CHIP_CARD_SUPPORT, RFID_READER"»: se si spezzasse,
      // le colonne dopo scivolerebbero e le coordinate diventerebbero altro.
      final c = esempio();
      expect(c.every((x) => x.posizione.lat > 35 && x.posizione.lat < 48), isTrue);
    });
  });
}
