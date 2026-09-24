import 'package:flutter_tts/flutter_tts.dart';

/// Chi parla durante la guida. Nelle prove se ne usa una che scrive e basta.
abstract interface class Voce {
  Future<void> parla(String frase);
  Future<void> zitta();
}

class VoceTelefono implements Voce {
  final _tts = FlutterTts();
  var _pronta = false;

  @override
  Future<void> parla(String frase) async {
    try {
      if (!_pronta) {
        await _tts.setLanguage('it-IT');
        await _tts.setSpeechRate(0.5);
        _pronta = true;
      }
      await _tts.speak(frase);
    } catch (_) {
      // Senza sintesi vocale si guida lo stesso: il banner c'è.
    }
  }

  @override
  Future<void> zitta() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
