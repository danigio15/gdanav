import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Cosa si sente in guida. Il tasto dell'audio passa da uno al dopo:
/// Tutto, Solo avvisi, Silenzio, e di nuovo Tutto.
///
/// Prima c'era un muto solo, e spegneva tutto insieme: chi conosce la strada
/// e silenziava le indicazioni perdeva anche l'autovelox, la ZTL e il limite,
/// che sono proprio quello che conviene sentire quando la strada la si sa.
/// Così le due voci si separano: la **voce di guida** (le manovre e i messaggi
/// del viaggio) e gli **avvisi** (autovelox, segnalazioni, ZTL, limite).
enum ModoAudio {
  /// Indicazioni e avvisi.
  tutto('tutto', 'Tutto'),

  /// Niente indicazioni, ma gli avvisi sì.
  soloAvvisi('avvisi', 'Avvisi'),

  /// Niente di niente.
  silenzio('silenzio', 'Muto');

  const ModoAudio(this.chiave, this.etichetta);

  /// Come lo si chiama verso lo schermo dell'auto.
  final String chiave;

  /// Sotto l'icona del tasto: corta, ci sta in un dito.
  final String etichetta;

  /// Il prossimo, toccando il tasto.
  ModoAudio get dopo => values[(index + 1) % values.length];

  /// La voce di guida è spenta.
  bool get senzaGuida => this != tutto;

  /// Anche gli avvisi sono spenti.
  bool get senzaAvvisi => this == silenzio;
}

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
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          // Come i navigatori di sistema: abbassa la musica mentre parla, si
          // sente anche con lo schermo spento e in CarPlay, e poi la rialza.
          await _tts.setSharedInstance(true);
          await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers,
          ], IosTextToSpeechAudioMode.voicePrompt);
        } else {
          // Android: la voce sul canale della navigazione, che abbassa la
          // musica mentre parla invece di sovrapporsi (DD-1). Altrove non c'è.
          try {
            await _tts.setAudioAttributesForNavigation();
          } catch (_) {}
        }
        _pronta = true;
      }
      // Il fuoco audio per la frase, poi la musica torna su.
      await _tts.speak(frase, focus: true);
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
