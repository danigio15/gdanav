import 'elm327.dart';

/// Un giro di sola lettura per conoscere un'auto nuova: cosa sa dire in
/// OBD-II standard e quali centraline rispondono. Non scrive niente e non
/// apre sessioni diagnostiche: solo richieste di lettura.
///
/// Il rapporto si manda a chi sviluppa gdanav per scrivere il profilo PID
/// del modello, come si fa per ABRP.
class EsploraObd {
  EsploraObd(this.elm, {void Function(String riga)? onRiga}) : _onRiga = onRiga;

  final Elm327 elm;
  final void Function(String riga)? _onRiga;
  final _righe = <String>[];

  String get rapporto => _righe.join('\n');

  void _scrivi(String r) {
    _righe.add(r);
    _onRiga?.call(r);
  }

  /// Le centraline più comuni (11 bit): motore/VCU, BMS, cambio, ABS, clima,
  /// cruscotto… Si chiede a ognuna chi è (DID F190 = VIN, F187 = ricambio).
  static const centraline = ['7E0', '7E1', '7E2', '7E3', '7E4', '7E5', '7E6', '7E7', '7C6', '7B3', '744', '7A0'];

  Future<String> esegui() async {
    _scrivi('# gdanav · esplorazione OBD (sola lettura)');
    for (final c in ['ATI', 'AT@1', 'ATRV']) {
      await _comando(c);
    }
    await elm.inizializza();
    // I PID standard supportati, a blocchi di 32.
    final supportati = <int>[];
    for (var base = 0; base <= 0xC0; base += 0x20) {
      final pid = '01${base.toRadixString(16).padLeft(2, '0').toUpperCase()}';
      final b = await _richiesta(pid);
      if (b == null || b.length < 4) break;
      supportati.addAll(pidDaMaschera(base, b));
      // L'ultimo bit dice se c'è il blocco dopo.
      if (b[3] & 1 == 0) break;
    }
    await _comando('ATDP');
    _scrivi('PID 01 supportati: ${supportati.map((p) => p.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}');
    for (final pid in ['0902', '015B', '010D', '0146', '01A6', '0151', '0142']) {
      await _richiesta(pid);
    }
    for (final h in centraline) {
      for (final did in ['22F190', '22F187', '22F18C']) {
        await _richiesta(did, intestazione: h);
      }
    }
    _scrivi('# fine');
    return rapporto;
  }

  Future<void> _comando(String c) async {
    try {
      _scrivi('> $c\n${await elm.comando(c)}');
    } on ErroreObd catch (e) {
      _scrivi('> $c\n! ${e.messaggio}');
    }
  }

  Future<List<int>?> _richiesta(String pid, {String? intestazione}) async {
    try {
      final grezza = await elm.richiestaGrezza(pid, intestazione: intestazione);
      _scrivi('> ${intestazione == null ? '' : '[$intestazione] '}$pid\n${grezza.testo}');
      return grezza.dati;
    } on ErroreObd catch (e) {
      _scrivi('> $pid\n! ${e.messaggio}');
      return null;
    }
  }
}

/// Dalla maschera di 4 byte della richiesta 01xx ai PID supportati.
List<int> pidDaMaschera(int base, List<int> maschera) => [
      for (var i = 0; i < 32; i++)
        if (maschera[i ~/ 8] & (0x80 >> (i % 8)) != 0) base + i + 1,
    ];
