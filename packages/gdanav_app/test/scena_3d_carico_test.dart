// «Quando è attiva la modalità 3D aumentata si rallenta anche lo smartphone:
// se lo utilizzo va lento il telefono e il navigatore.» Sull'auto la scena 3D
// pesa quanto le dice il telefono (il calore, il telefono in uso) e non
// disegna quando sull'auto c'è un'altra app. I messaggi li scrive Kotlin e li
// legge la pagina (`web3d/src/messaggi.js`): qui si controlla che parlino la
// stessa lingua, e che il processo della scena non salga di priorità.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/mappa/ponte_3d.dart';

const _auto = 'android/src/main/kotlin/it/gdanav/gdanav_app/auto';

void main() {
  test('la pagina conosce i messaggi che le manda Kotlin', () {
    final messaggi = File('web3d/src/messaggi.js').readAsStringSync();
    expect(messaggi, contains('carico: (m) =>'));
    expect(messaggi, contains('nascosta: (m) =>'));
    final carico = File('$_auto/CaricoScena3d.kt').readAsStringSync();
    expect(carico, contains("tipo:'carico',livello:\$livello,telefono:\$inUso"));
    final renderer = File('$_auto/RendererMappa.kt').readAsStringSync();
    expect(renderer, contains("tipo:'nascosta',si:"));
    // Prima che la mappa ci sia, i due messaggi non aspettano in coda.
    final principale = File('web3d/src/principale.js').readAsStringSync();
    expect(principale, contains("['stile', 'opzioni', 'pausa', 'carico', 'nascosta', 'leggera', 'corsie']"));
    // E quello del telefono (`msgLeggera`): con la scena anche sull'auto.
    expect(messaggi, contains('leggera: (m) =>'));
    expect(msgLeggera(true), {'v': 1, 'tipo': 'leggera', 'si': true});
  });

  test('la scena dentro e fuori dall’app ascolta il carico; la sessione dice se si vede', () {
    final scena = File('$_auto/Scena3dAuto.kt').readAsStringSync();
    expect(scena, contains('CaricoScena3d(context)'));
    expect(scena, contains('carico.ferma()'));
    final sessione = File('$_auto/SessioneGdanav.kt').readAsStringSync();
    expect(sessione, contains('RendererMappa.inVista(true)'));
    expect(sessione, contains('RendererMappa.inVista(false)'));
  });

  test('il processo della scena 3D non sale alla priorità dell’app davanti', () {
    final lontana = File('$_auto/Scena3dLontana.kt').readAsStringSync();
    final legame = RegExp(r'bindService\([^\n]*').firstMatch(lontana)!.group(0)!;
    expect(legame, contains('BIND_AUTO_CREATE'));
    expect(legame, isNot(contains('BIND_IMPORTANT')));
  });
}
