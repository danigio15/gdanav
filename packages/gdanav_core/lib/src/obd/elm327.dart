import 'dart:async';

/// Il filo verso il dongle: Bluetooth LE nell'app, finto nelle prove.
/// Si scrivono comandi di testo; arrivano pezzi di testo, a volte a metà.
abstract interface class CanaleObd {
  Future<void> scrivi(String testo);
  Stream<String> get ricevuti;
  Future<void> chiudi();
}

class ErroreObd implements Exception {
  const ErroreObd(this.messaggio);
  final String messaggio;

  @override
  String toString() => 'OBD: $messaggio';
}

/// Parla con un dongle ELM327 (o compatibile: Vgate, OBDLink, Veepeak…):
/// comandi AT per prepararlo, poi richieste OBD-II o UDS alle centraline.
class Elm327 {
  Elm327(this.canale, {this.attesa = const Duration(seconds: 4)}) {
    _iscrizione = canale.ricevuti.listen(_arrivato);
  }

  final CanaleObd canale;

  /// Quanto aspettare il «>» con cui l'ELM327 dice che ha finito.
  final Duration attesa;

  late final StreamSubscription<String> _iscrizione;
  final _buffer = StringBuffer();
  Completer<String>? _risposta;
  String? _intestazione;

  // Un comando alla volta: l'ELM327 non sa fare due cose insieme.
  Future<void> _coda = Future.value();

  void _arrivato(String pezzo) {
    _buffer.write(pezzo);
    final testo = _buffer.toString();
    final fine = testo.indexOf('>');
    if (fine < 0) return;
    _buffer
      ..clear()
      ..write(testo.substring(fine + 1));
    final r = _risposta;
    _risposta = null;
    if (r != null && !r.isCompleted) r.complete(testo.substring(0, fine));
  }

  /// Manda un comando e restituisce la risposta, senza il «>».
  Future<String> comando(String c) {
    final fatto = Completer<String>();
    _coda = _coda.then((_) async {
      final r = _risposta = Completer<String>();
      await canale.scrivi('$c\r');
      try {
        fatto.complete((await r.future.timeout(attesa)).trim());
      } on TimeoutException {
        _risposta = null;
        fatto.completeError(ErroreObd('nessuna risposta a $c'));
      } catch (e) {
        fatto.completeError(e);
      }
    });
    return fatto.future;
  }

  /// Si parte puliti: niente eco, niente a capo, niente spazi, con le
  /// intestazioni (servono per rimettere insieme le risposte lunghe) e il
  /// protocollo scelto da solo.
  Future<void> inizializza() async {
    await comando('ATZ');
    for (final c in ['ATE0', 'ATL0', 'ATS0', 'ATH1', 'ATSP0']) {
      final r = await comando(c);
      if (!r.contains('OK')) throw ErroreObd('il dongle non accetta $c: $r');
    }
    _intestazione = null;
  }

  /// Una richiesta a una centralina: [pid] come «010D» o «220101»,
  /// [intestazione] come «7E4» se non va alla centralina motore.
  /// Restituisce i byte dei dati, dopo il servizio e il PID; `null` se
  /// l'auto non risponde a quella richiesta.
  Future<List<int>?> richiesta(String pid, {String? intestazione}) async =>
      (await richiestaGrezza(pid, intestazione: intestazione)).dati;

  /// Come [richiesta], ma con anche il testo com'è arrivato: per esplorare.
  Future<({String testo, List<int>? dati})> richiestaGrezza(String pid, {String? intestazione}) async {
    final h = intestazione ?? '7DF';
    if (h != _intestazione) {
      final r = await comando('ATSH$h');
      if (!r.contains('OK')) throw ErroreObd('intestazione $h rifiutata: $r');
      _intestazione = h;
    }
    final testo = await comando(pid);
    return (testo: testo, dati: leggiRisposta(testo, pid));
  }

  Future<void> chiudi() async {
    await _iscrizione.cancel();
    await canale.chiudi();
  }
}

/// Dalla risposta testuale dell'ELM327 (con intestazioni, senza spazi) ai
/// byte dei dati.
///
/// Una risposta corta sta in una riga: `7E8 03 41 0D 32` (lunghezza,
/// servizio + 0x40, PID, dati). Una lunga arriva in più righe ISO-TP: la
/// prima `10 LL …` con la lunghezza totale, poi `21 …`, `22 …` in ordine.
List<int>? leggiRisposta(String testo, String pid) {
  final righe = testo
      .split(RegExp(r'[\r\n]+'))
      .map((r) => r.replaceAll(' ', '').trim().toUpperCase())
      .where((r) => r.isNotEmpty && r != 'SEARCHING...')
      .toList();
  if (righe.isEmpty || righe.any((r) => r.contains('NODATA') || r.contains('ERROR') || r.contains('UNABLE'))) {
    return null;
  }
  // Le righe per centralina: con più centraline risponde la prima.
  final perMittente = <String, List<List<int>>>{};
  for (final r in righe) {
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(r)) continue;
    // Intestazione a 11 bit (3 cifre, righe dispari) o a 29 bit (8 cifre,
    // righe pari): i dati sono sempre byte interi.
    final lh = r.length.isOdd ? 3 : 8;
    if (r.length <= lh) continue;
    final dati = _byte(r.substring(lh));
    if (dati == null) continue;
    perMittente.putIfAbsent(r.substring(0, lh), () => []).add(dati);
  }
  if (perMittente.isEmpty) return null;
  final frame = perMittente.values.first;

  final List<int> messaggio;
  final primo = frame.first[0];
  if (primo >> 4 == 0) {
    // Frame singolo: il primo nibble è 0, il secondo la lunghezza.
    final n = primo & 0x0F;
    if (frame.first.length < n + 1) return null;
    messaggio = frame.first.sublist(1, n + 1);
  } else if (primo >> 4 == 1) {
    final n = ((primo & 0x0F) << 8) | frame.first[1];
    final tutti = <int>[...frame.first.sublist(2)];
    final seguenti = frame.skip(1).where((f) => f[0] >> 4 == 2).toList();
    for (final f in seguenti) {
      tutti.addAll(f.sublist(1));
    }
    if (tutti.length < n) return null;
    messaggio = tutti.sublist(0, n);
  } else {
    return null;
  }

  // Risposta positiva: servizio + 0x40, poi il PID ripetuto.
  final richiesta = _byte(pid);
  if (richiesta == null || messaggio.isEmpty) return null;
  if (messaggio[0] == 0x7F) return null; // risposta negativa
  if (messaggio[0] != richiesta[0] + 0x40) return null;
  final eco = richiesta.length - 1;
  if (messaggio.length < 1 + eco) return null;
  for (var i = 0; i < eco; i++) {
    if (messaggio[1 + i] != richiesta[1 + i]) return null;
  }
  return messaggio.sublist(1 + eco);
}

List<int>? _byte(String esadecimale) {
  if (esadecimale.length.isOdd) return null;
  return [
    for (var i = 0; i < esadecimale.length; i += 2) int.parse(esadecimale.substring(i, i + 2), radix: 16),
  ];
}
