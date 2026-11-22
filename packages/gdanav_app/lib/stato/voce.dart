import 'dart:convert';
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

/// Quanto forte e quanto veloce parla la voce di guida. «Anche il discorso
/// audio deve essere modificabile», dall'auto: si sceglie lì (e vale anche sul
/// telefono), e [VoceTelefono] lo legge prima di ogni frase.
enum VolumeVoce {
  basso('Basso', 0.5),
  medio('Medio', 0.75),
  alto('Alto', 1.0);

  const VolumeVoce(this.nome, this.valore);
  final String nome;
  final double valore;
}

enum VelocitaVoce {
  lenta('Lenta', 0.42),
  normale('Normale', 0.5),
  veloce('Veloce', 0.6);

  const VelocitaVoce(this.nome, this.valore);
  final String nome;
  final double valore;
}

/// Il volume e la velocità di adesso, per chi parla. Li scrive chi li sceglie
/// (il menu dell'auto) e li carica l'app all'avvio.
final regolazioniVoce = ValueNotifier<(VolumeVoce, VelocitaVoce)>((VolumeVoce.alto, VelocitaVoce.normale));

/// Una voce del telefono, come la dà la sintesi vocale: il nome (quello
/// che la sintesi riconosce) e la lingua. Su iPhone c'è anche la qualità
/// (`default`, `enhanced`, `premium`), su Android a volte se serve la rete.
@immutable
class VoceDelTelefono {
  const VoceDelTelefono({required this.nome, required this.lingua, this.qualita, this.inRete = false});

  final String nome;
  final String lingua;
  final String? qualita;
  final bool inRete;

  /// Dalla mappa di `FlutterTts.getVoices`; `null` se non ha nome o lingua.
  static VoceDelTelefono? daSintesi(Object? m) {
    if (m is! Map) return null;
    final nome = m['name']?.toString() ?? '';
    final lingua = (m['locale'] ?? m['language'])?.toString() ?? '';
    if (nome.isEmpty || lingua.isEmpty) return null;
    final rete = m['network_required']?.toString();
    return VoceDelTelefono(
      nome: nome,
      lingua: lingua,
      qualita: m['quality']?.toString(),
      inRete: rete == '1' || rete == 'true',
    );
  }

  static VoceDelTelefono? daJson(String? testo) {
    if (testo == null || testo.isEmpty) return null;
    try {
      final m = jsonDecode(testo);
      if (m is! Map) return null;
      final nome = m['nome']?.toString() ?? '';
      final lingua = m['lingua']?.toString() ?? '';
      if (nome.isEmpty || lingua.isEmpty) return null;
      return VoceDelTelefono(nome: nome, lingua: lingua, qualita: m['qualita']?.toString());
    } catch (_) {
      return null;
    }
  }

  String get json => jsonEncode({'nome': nome, 'lingua': lingua, 'qualita': ?qualita});

  /// È italiana (`it-IT`, `it_IT`, `ita`…).
  bool get italiana => lingua.toLowerCase().startsWith('it');

  /// Come la si chiama nell'elenco: «Alice», non
  /// «com.apple.voice.compact.it-IT.Alice» né «it-it-x-itd-local».
  String get etichetta {
    if (nome.startsWith('com.apple.')) return nome.split('.').last;
    final android = RegExp(r'^[a-z]{2}-[a-z]{2}-x-([a-z]+)-(local|network)$', caseSensitive: false).firstMatch(nome);
    if (android != null) return 'Voce ${android.group(1)!.toUpperCase()}';
    return nome;
  }

  /// Sotto il nome: la qualità e se serve internet.
  String get dettaglio => [
    switch (qualita?.toLowerCase()) {
      'premium' => 'Qualità premium',
      'enhanced' => 'Qualità migliorata',
      _ => null,
    },
    if (inRete || nome.toLowerCase().endsWith('-network')) 'Serve internet',
  ].nonNulls.join(' · ');

  /// Le migliori prima (premium, migliorata), poi per nome.
  static int ordine(VoceDelTelefono a, VoceDelTelefono b) {
    int peso(VoceDelTelefono v) => switch (v.qualita?.toLowerCase()) {
      'premium' => 0,
      'enhanced' => 1,
      _ => 2,
    };
    final p = peso(a) - peso(b);
    return p != 0 ? p : a.etichetta.toLowerCase().compareTo(b.etichetta.toLowerCase());
  }

  @override
  bool operator ==(Object other) => other is VoceDelTelefono && other.nome == nome && other.lingua == lingua;

  @override
  int get hashCode => Object.hash(nome, lingua);
}

/// La voce scelta per la guida; `null` è quella predefinita del telefono.
///
/// «La voce che c'è è un po' fastidiosa»: si parlava sempre con la voce
/// italiana predefinita del sistema, e per cambiarla bisognava cercarla nelle
/// impostazioni del telefono. Si sceglie dal menu, «Voce di guida».
final voceScelta = ValueNotifier<VoceDelTelefono?>(null);

/// Le voci italiane del telefono, le migliori prima.
Future<List<VoceDelTelefono>> vociItalianeDelTelefono([FlutterTts? tts]) async {
  try {
    final tutte = await (tts ?? FlutterTts()).getVoices;
    final voci = {
      for (final m in (tutte is List ? tutte : const []))
        if (VoceDelTelefono.daSintesi(m) case final v? when v.italiana) v,
    }.toList()..sort(VoceDelTelefono.ordine);
    return voci;
  } catch (_) {
    return const [];
  }
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

  /// Volume e velocità già dati alla sintesi vocale.
  (VolumeVoce, VelocitaVoce)? _regolata;

  /// La voce già data alla sintesi vocale (vedi [voceScelta]); `false` finché
  /// non se n'è data nessuna.
  Object? _voceData = false;

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
      await _daiLaVoce(_tts, voceScelta.value, _voceData);
      _voceData = voceScelta.value;
      final r = regolazioniVoce.value;
      if (r != _regolata) {
        await _tts.setVolume(r.$1.valore);
        await _tts.setSpeechRate(r.$2.valore);
        _regolata = r;
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

  /// Dà alla sintesi la voce [v] se è cambiata da [prima]; `null` è la
  /// predefinita italiana. Una voce che il telefono non ha più (cancellata
  /// dalle impostazioni) non ferma niente: resta quella di prima.
  static Future<void> _daiLaVoce(FlutterTts tts, VoceDelTelefono? v, Object? prima) async {
    if (v == prima) return;
    try {
      if (v == null) {
        await tts.setLanguage('it-IT');
      } else {
        await tts.setVoice({'name': v.nome, 'locale': v.lingua});
      }
    } catch (_) {}
  }

  /// Fa sentire la voce [v] (la prova nella scelta della voce), con volume e
  /// velocità di adesso.
  static Future<void> prova(FlutterTts tts, VoceDelTelefono? v, String frase) async {
    try {
      await tts.stop();
      await tts.setLanguage('it-IT');
      await _daiLaVoce(tts, v, null);
      final r = regolazioniVoce.value;
      await tts.setVolume(r.$1.valore);
      await tts.setSpeechRate(r.$2.valore);
      await tts.speak(frase);
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
