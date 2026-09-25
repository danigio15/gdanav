/// I servizi esterni di gdanav, cablati qui: chi installa l'app non deve
/// scrivere indirizzi o chiavi. Per una build diversa si possono cambiare
/// alla compilazione con `--dart-define=NOME=valore`.
abstract final class Servizi {
  /// I percorsi: il server pubblico di FOSSGIS (OpenStreetMap Germania).
  static const valhalla = String.fromEnvironment(
    'GDANAV_VALHALLA',
    defaultValue: 'https://valhalla1.openstreetmap.de/',
  );
  static const chiaveValhalla = String.fromEnvironment('GDANAV_VALHALLA_CHIAVE');

  /// Le colonnine: Open Charge Map. Senza chiave risponde lo stesso, ma con
  /// meno richieste al minuto.
  static const chiaveOcm = String.fromEnvironment('GDANAV_OCM_CHIAVE', defaultValue: _chiaveOcm);

  /// Il traffico: TomTom, piano gratuito (50.000 riquadri di mappa al
  /// giorno). Senza chiave la mappa resta senza traffico.
  static const chiaveTomTom = String.fromEnvironment('GDANAV_TOMTOM_CHIAVE', defaultValue: _chiaveTomTom);

  /// Le foto vere degli svincoli: Mapillary (gratuito, con la citazione).
  /// Senza chiave si vede lo svincolo disegnato.
  static const chiaveMapillary = String.fromEnvironment('GDANAV_MAPILLARY_TOKEN');

  /// Le segnalazioni della comunità (incidenti, polizia, pericoli): il relay
  /// di gdanav su Cloudflare.
  static const segnalazioni = String.fromEnvironment('GDANAV_SEGNALAZIONI', defaultValue: _segnalazioni);

  /// Le build d'anteprima (l'APK da GitHub, che non passa dal Play Store)
  /// hanno Premium già sbloccato; quella per il Play Store no.
  static const tuttoSbloccato = bool.fromEnvironment('GDANAV_TUTTO_SBLOCCATO');
}

// Le chiavi di gdanav.
const _chiaveOcm = '';
const _chiaveTomTom = '';
const _segnalazioni = 'https://gdanav.gdahome.org/';
