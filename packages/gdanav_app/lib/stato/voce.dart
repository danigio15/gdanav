import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

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

  /// Il «beep» degli avvisi scelti senza parole: due note brevi.
  Future<void> suona();
}

/* ─── Il beep ───────────────────────────────────────────────────────────
 *
 * Dal campo: «negli avvisi metterei Voce / Beep / Schermo / Spento». Chi
 * l'autovelox lo vuole sentire ma non ascoltare una frase ogni volta.
 *
 * Il suono lo fa l'app, senza file: due note brevi che salgono (come i
 * navigatori), scritte in un WAV la prima volta. */

/// Il beep in WAV: due note (880 e 1320 Hz) di [notaMs] con una pausa, a
/// 16 bit mono, che entrano e escono piano (senza «clic»).
Uint8List wavDelBeep({int frequenza = 22050, int notaMs = 110, int pausaMs = 60}) {
  final campioniNota = frequenza * notaMs ~/ 1000;
  final campioniPausa = frequenza * pausaMs ~/ 1000;
  final campioni = <int>[];
  void nota(double hz) {
    final bordo = campioniNota ~/ 8;
    for (var i = 0; i < campioniNota; i++) {
      final inviluppo = math.min(1.0, math.min(i, campioniNota - 1 - i) / bordo);
      campioni.add((math.sin(2 * math.pi * hz * i / frequenza) * inviluppo * 0.6 * 32767).round());
    }
  }

  nota(880);
  campioni.addAll(List.filled(campioniPausa, 0));
  nota(1320);
  final dati = campioni.length * 2;
  final b = ByteData(44 + dati);
  void testo(int o, String t) {
    for (var i = 0; i < t.length; i++) {
      b.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  testo(0, 'RIFF');
  b.setUint32(4, 36 + dati, Endian.little);
  testo(8, 'WAVE');
  testo(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, frequenza, Endian.little);
  b.setUint32(28, frequenza * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  testo(36, 'data');
  b.setUint32(40, dati, Endian.little);
  for (var i = 0; i < campioni.length; i++) {
    b.setInt16(44 + i * 2, campioni[i], Endian.little);
  }
  return b.buffer.asUint8List();
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

  AudioPlayer? _lettore;
  String? _fileBeep;

  @override
  Future<void> suona() async {
    try {
      var lettore = _lettore;
      if (lettore == null) {
        lettore = _lettore = AudioPlayer();
        // Come la voce: sul canale della navigazione, la musica si abbassa
        // per un attimo e poi torna su.
        await lettore.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              usageType: AndroidUsageType.assistanceNavigationGuidance,
              contentType: AndroidContentType.sonification,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {AVAudioSessionOptions.duckOthers, AVAudioSessionOptions.mixWithOthers},
            ),
          ),
        );
        await lettore.setReleaseMode(ReleaseMode.stop);
      }
      var file = _fileBeep;
      if (file == null) {
        final f = File('${(await getTemporaryDirectory()).path}/gdanav-beep.wav');
        await f.writeAsBytes(wavDelBeep(), flush: true);
        file = _fileBeep = f.path;
      }
      await lettore.stop();
      await lettore.play(DeviceFileSource(file, mimeType: 'audio/wav'));
    } catch (_) {
      // Senza suono si guida lo stesso: il riquadro c'è.
    }
  }
}
