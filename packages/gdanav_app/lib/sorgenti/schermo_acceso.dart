import 'package:flutter/services.dart';

/// Lo schermo del telefono acceso finché si guida.
///
/// «Quando il telefono non è collegato allo schermo dell'auto, il display si
/// spegne. Su iPhone diventa completamente nero, mentre su Android si
/// scurisce quasi fino al nero. Il navigatore dovrebbe funzionare anche senza
/// lo schermo dell'auto.» Nessuno chiedeva al sistema di lasciarlo acceso: il
/// telefono sul supporto, senza toccarlo, faceva quello che fa sempre — si
/// abbassa e poi si spegne. Adesso la schermata di guida lo chiede quando si
/// apre e lo restituisce quando si chiude.
///
/// Il lato nativo sta in `GdanavAppPlugin` (Swift e Kotlin), sul canale
/// `gdanav/schermo`: sull'iPhone il timer del blocco, su Android la finestra
/// che resta accesa. Un'app ospite che lo stesso schermo lo teneva gia'
/// acceso per conto suo (il pannello a muro di GdAHome) lo ritrova com'era.
class SchermoAcceso {
  SchermoAcceso._();

  static const _canale = MethodChannel('gdanav/schermo');

  /// Chiede (o restituisce) lo schermo acceso. Non solleva mai: un'app senza
  /// il pezzo nativo, o una prova, resta come prima.
  static Future<void> tieni(bool acceso) async {
    try {
      await _canale.invokeMethod<void>('acceso', acceso);
    } on MissingPluginException {
      // Una prova, o il web: niente da tenere acceso.
    } on PlatformException {
      // Senza finestra (l'app aperta solo dall'auto): non c'è schermo da tenere.
    }
  }
}
