/// I servizi esterni di gdanav, cablati qui: chi installa l'app non deve
/// scrivere indirizzi o chiavi. Per una build diversa si possono cambiare
/// alla compilazione con `--dart-define=NOME=valore`.
abstract final class Servizi {
  /// Chi calcola i percorsi: `tomtom` (se c'è la chiave) o `valhalla`.
  ///
  /// TomTom perché il suo piano gratuito dà 20.000 percorsi al mese e
  /// soprattutto conosce il traffico: il tempo di arrivo è quello di adesso.
  /// Valhalla resta la riserva, e serve a confrontare:
  /// `--dart-define=GDANAV_MOTORE_PERCORSI=valhalla`.
  static const motorePercorsi = String.fromEnvironment('GDANAV_MOTORE_PERCORSI', defaultValue: 'tomtom');

  /// La riserva dei percorsi: il server pubblico di FOSSGIS (OpenStreetMap
  /// Germania). È tenuto in piedi per prova, senza nessuna promessa verso
  /// chi ci appoggia sopra un'app: si usa solo se manca la chiave TomTom.
  static const valhalla = String.fromEnvironment(
    'GDANAV_VALHALLA',
    defaultValue: 'https://valhalla1.openstreetmap.de/',
  );
  static const chiaveValhalla = String.fromEnvironment('GDANAV_VALHALLA_CHIAVE');

  /// Le colonnine: Open Charge Map. Senza chiave risponde lo stesso, ma con
  /// meno richieste al minuto.
  static const chiaveOcm = String.fromEnvironment('GDANAV_OCM_CHIAVE', defaultValue: _chiaveOcm);

  /// Il traffico sulla mappa e i percorsi: TomTom, piano gratuito (200.000
  /// riquadri di traffico e 20.000 percorsi al mese). Senza chiave la mappa
  /// resta senza traffico e i percorsi tornano a Valhalla.
  static const chiaveTomTom = String.fromEnvironment('GDANAV_TOMTOM_CHIAVE', defaultValue: _chiaveTomTom);

  /// Le segnalazioni della comunità (incidenti, polizia, pericoli): il relay
  /// di gdanav su Cloudflare.
  static const segnalazioni = String.fromEnvironment('GDANAV_SEGNALAZIONI', defaultValue: _segnalazioni);

  /// Premium sbloccato per tutti, senza negozio:
  /// `--dart-define=GDANAV_TUTTO_SBLOCCATO=true`. Le build della CI lo
  /// accendono finche' la variabile del repository GDANAV_PAGAMENTI non e'
  /// «si» (la fase di prova, coi pagamenti spenti); da li' l'APK, il Play
  /// Store e l'App Store chiedono l'abbonamento (o un codice regalo).
  static const tuttoSbloccato = bool.fromEnvironment('GDANAV_TUTTO_SBLOCCATO');

  /// Il numero della build: la CI passa quello della corsa
  /// (`--dart-define=GDANAV_COSTRUZIONE=${{ github.run_number }}`), lo stesso
  /// del `--build-number`. 0 nelle build fatte a mano, che non si bloccano
  /// mai: vedi `GestoreAggiornamento`.
  static const costruzione = int.fromEnvironment('GDANAV_COSTRUZIONE');

  /// La versione più vecchia ancora buona: la dice il relay, in
  /// `GET /v1/versioni`.
  static Uri get versioni => Uri.parse(segnalazioni).resolve('v1/versioni');
}

// Le chiavi di gdanav.
const _chiaveOcm = '';
const _chiaveTomTom = '';
const _segnalazioni = 'https://gdanav.gdahome.org/';
