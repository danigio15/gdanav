import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'abbinamento.dart';
import 'busta.dart';
import 'messaggio.dart';

/// Il filo fra l'app e la casa, attraverso il relay. Si riconnette da solo
/// con attese crescenti, fino a un minuto.
class ClienteRelay {
  ClienteRelay(this.abbinamento, {WebSocketChannel Function(Uri)? connetti})
      : _connetti = connetti ?? WebSocketChannel.connect;

  final Abbinamento abbinamento;
  final WebSocketChannel Function(Uri) _connetti;

  final _messaggi = StreamController<Messaggio>.broadcast();
  final _casaPresente = StreamController<bool>.broadcast();

  WebSocketChannel? _canale;
  Busta? _busta;
  var _attivo = false;
  var _tentativi = 0;
  Timer? _riprova;

  /// I messaggi della casa, già aperti e verificati.
  Stream<Messaggio> get messaggi => _messaggi.stream;

  /// `true` quando Home Assistant è collegato al relay.
  Stream<bool> get casaPresente => _casaPresente.stream;

  /// Per capire dove si ferma il filo, quando i dati non arrivano: il relay
  /// risponde? Home Assistant c'è dall'altra parte? Le buste si aprono?
  bool collegato = false;

  /// `null` finché il relay non l'ha detto.
  bool? casa;

  /// Le buste della casa aperte e quelle buttate (chiave sbagliata, orologio
  /// fuori tempo): tante buttate e nessuna aperta vuol dire abbinamento da
  /// rifare, o l'ora di Home Assistant o del telefono sbagliata.
  int aperte = 0;
  int scartate = 0;

  /// L'ultimo errore nel collegarsi al relay (rete, abbinamento rifiutato).
  String? ultimoErrore;

  Future<void> avvia() async {
    _attivo = true;
    _busta ??= await Busta.per(abbinamento);
    await _apri();
  }

  Future<void> ferma() async {
    _attivo = false;
    _riprova?.cancel();
    await _canale?.sink.close();
    _canale = null;
  }

  Future<void> manda(Messaggio m) async {
    final c = _canale;
    if (c == null) throw StateError('Relay non collegato');
    c.sink.add(await _busta!.chiudi(m, Mittente.app));
  }

  Future<void> _apri() async {
    final uri = await abbinamento.indirizzoRelay('app');
    final c = _connetti(uri);
    _canale = c;
    try {
      await c.ready;
      _tentativi = 0;
      collegato = true;
      ultimoErrore = null;
      await manda(Messaggio(tipo: TipoMessaggio.richiediStato));
    } catch (e) {
      ultimoErrore = '$e';
      _programmaRiprova();
      return;
    }
    c.stream.listen(_ricevi, onDone: _programmaRiprova, onError: (_) => _programmaRiprova());
  }

  Future<void> _ricevi(dynamic dato) async {
    if (dato is! String) return;
    final json = jsonDecode(dato) as Map<String, Object?>;
    // I messaggi del relay stesso sono in chiaro e non portano segreti.
    if (json.containsKey('relay')) {
      if (json['ruolo'] == 'casa') {
        casa = json['relay'] == 'presente';
        _casaPresente.add(casa!);
      }
      return;
    }
    try {
      _messaggi.add(await _busta!.apri(dato, Mittente.casa));
      aperte++;
    } on Object {
      scartate++;
      // Una busta che non si apre si butta: può essere rumore o un attacco,
      // in entrambi i casi non c'è niente da farci.
    }
  }

  void _programmaRiprova() {
    _canale = null;
    collegato = false;
    if (!_attivo) return;
    _riprova?.cancel();
    final secondi = [1, 2, 5, 10, 30, 60][_tentativi.clamp(0, 5)];
    _tentativi++;
    _riprova = Timer(Duration(seconds: secondi), _apri);
  }
}
