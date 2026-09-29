import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  group('il nome dell\'azienda come lo si dice', () {
    test('senza la forma giuridica', () {
      expect(Pun.nomeAzienda('Be Charge S.r.l.'), 'Be Charge');
      expect(Pun.nomeAzienda('A.F. Energia S.r.l.'), 'A.F. Energia');
      expect(Pun.nomeAzienda('Repower Italia SpA'), 'Repower Italia');
      expect(Pun.nomeAzienda('Alfa Srls'), 'Alfa');
      expect(Pun.nomeAzienda('Beta S.R.L. UNIPERSONALE'), 'Beta');
      expect(Pun.nomeAzienda('Gamma società a responsabilità limitata'), 'Gamma');
      expect(Pun.nomeAzienda('Delta Soc. Coop. a r.l.'), 'Delta');
    });

    test('non tutto in maiuscolo, ma le sigle restano sigle', () {
      expect(Pun.nomeAzienda('A2A E.MOBILITY S.R.L.'), 'A2A E.Mobility');
      expect(Pun.nomeAzienda('ACEA ENERGIA'), 'Acea Energia');
      expect(Pun.nomeAzienda('DUFERCO ENERGIA S.P.A.'), 'Duferco Energia');
      // Tre lettere o meno restano come sono: è il prezzo per non rovinare
      // le sigle (ASM, ACE, A2A).
      expect(Pun.nomeAzienda('ENEL X WAY ITALIA S.R.L.'), 'Enel X WAY Italia');
      expect(Pun.nomeAzienda('COMUNE DI MILANO'), 'Comune di Milano');
      expect(Pun.nomeAzienda('ASM'), 'ASM');
    });

    test('un nome che contiene «società» non si tronca', () {
      expect(Pun.nomeAzienda('Nuova Società Elettrica Srl'), 'Nuova Società Elettrica');
    });

    test('vuoto resta vuoto', () {
      expect(Pun.nomeAzienda(''), '');
      expect(Pun.nomeAzienda('  '), '');
    });
  });

  group('il codice operatore dall\'EVSE ID', () {
    test('con gli asterischi e senza', () {
      expect(Pun.codiceOperatore('IT*BEC*EW003907*1'), 'BEC');
      expect(Pun.codiceOperatore('ITGESE822979393'), 'GES');
      expect(Pun.codiceOperatore('IT*ACE*E*ST*C*AIRSQT2T2240600515*2'), 'ACE');
    });

    test('quello che non è un codice non diventa un operatore', () {
      expect(Pun.codiceOperatore('IT*REVEPGS564*1*2'), isNull);
      expect(Pun.codiceOperatore('CP008-1'), isNull);
      expect(Pun.codiceOperatore(''), isNull);
    });
  });

  group("l'estrazione di oggi, con la colonna dell'operatore", () {
    const intestazione = 'id_location,nome_location,indirizzo,id_evse,stato,standard_del_connettore,'
        'potenza_erogabile,latitudine_evse,longitudine_evse,operatore';
    String riga(String luogo, String evse, String azienda) =>
        '$luogo,Parcheggio,"Via Roma 1, Napoli",$evse,AVAILABLE,IEC_62196_T2,22000,40.85,14.28,$azienda';

    test('il nome che conosciamo vince su quello dell\'azienda', () {
      final c = Pun.leggiCsv('$intestazione\n${riga('a', 'IT*ENX*E1*1', 'ENEL X WAY ITALIA S.R.L.')}\n');
      expect(c.single.operatore, 'Enel X');
    });

    test('un codice sconosciuto prende il nome dell\'azienda', () {
      final c = Pun.leggiCsv('$intestazione\n${riga('a', 'ITGESE822979393', 'GESTIONE ENERGIA SRL')}\n');
      expect(c.single.operatore, 'Gestione Energia');
    });

    test('senza azienda, il codice', () {
      final c = Pun.leggiCsv('$intestazione\n${riga('a', 'ITGESE822979393', '')}\n');
      expect(c.single.operatore, 'GES');
    });

    test('il CSV di onData, senza la colonna, si legge come prima', () {
      const vecchio = 'id_location,nome_location,indirizzo,id_evse,stato,standard_del_connettore,'
          'potenza_erogabile,latitudine_evse,longitudine_evse\n'
          'a,Parcheggio,Via Roma 1,IT*XYZ*E1*1,AVAILABLE,IEC_62196_T2,22000,40.85,14.28\n';
      expect(Pun.leggiCsv(vecchio).single.operatore, 'XYZ');
    });
  });
}
