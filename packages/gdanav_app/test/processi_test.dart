// In che processo gira cosa, su Android. Lo schermo dell'auto legge la musica
// (`LettoreTelefono`) e gli avvisi di casa (`PonteAuto`) da oggetti Kotlin
// statici, e GdAHome passa le notifiche al navigatore con
// `IsolateNameServer`: tutte cose che valgono **dentro un processo solo**.
// Se un giorno il servizio dell'auto, l'ascolto delle notifiche o l'app
// finissero in un `android:process` loro, l'auto resterebbe senza musica e
// senza avvisi, zitta. Questa prova se ne accorge prima.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// I processi dichiarati nel manifesto: nome del componente → processo.
Map<String, String> processi(String manifesto) {
  final testo = File(manifesto).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  final risultato = <String, String>{};
  for (final m in RegExp(r'<(service|activity|receiver|provider)\b([^>]*)>', dotAll: true).allMatches(testo)) {
    final attributi = m.group(2)!;
    final nome = RegExp(r'android:name="([^"]+)"').firstMatch(attributi)?.group(1);
    final processo = RegExp(r'android:process="([^"]+)"').firstMatch(attributi)?.group(1);
    if (nome != null && processo != null) risultato[nome] = processo;
  }
  return risultato;
}

void main() {
  test('nel pacchetto solo la scena 3D ha un processo suo', () {
    final p = processi('android/src/main/AndroidManifest.xml');
    expect(p, {'it.gdanav.gdanav_app.auto.Scena3dServizio': ':mappa3d'});
    // L'ascolto delle notifiche (la chiave della musica) sta con l'app.
    final testo = File('android/src/main/AndroidManifest.xml').readAsStringSync();
    expect(testo, contains('it.gdanav.gdanav_app.musica.AscoltoNotifiche'));
    expect(testo, contains('android:label="GdANav: musica"'));
  });

  test('nell\'app GdANav il servizio dell\'auto e l\'attività stanno nel processo dell\'app', () {
    const manifesto = '../../app/android/app/src/main/AndroidManifest.xml';
    if (!File(manifesto).existsSync()) return;
    expect(processi(manifesto), isEmpty);
    final testo = File(manifesto).readAsStringSync();
    expect(testo, contains('GdanavCarAppService'));
    expect(testo, isNot(contains('android:process')));
  });
}
