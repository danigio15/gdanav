import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:gdanav_core/gdanav_core.dart';

/// Il filo Bluetooth LE verso un dongle OBD ELM327 (Vgate iCar Pro, OBDLink
/// CX, Veepeak BLE…). Questi dongle espongono una caratteristica per
/// scrivere i comandi e una che notifica le risposte, quasi sempre nel
/// servizio FFF0 (o FFE0, 18F0): si usano quelle, altrimenti la prima coppia
/// che va bene.
class CanaleBle implements CanaleObd {
  CanaleBle._(this._connessione, this._scrivi, this._conRisposta);

  static final _ble = FlutterReactiveBle();
  static const _permessi = MethodChannel('gdanav/permessi');

  final StreamSubscription<ConnectionStateUpdate> _connessione;
  final Characteristic _scrivi;
  final bool _conRisposta;
  final _in = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _notifiche;

  /// Chiede i permessi Bluetooth (Android 12 e oltre) o la posizione (prima).
  /// Su iPhone il permesso lo chiede il sistema da sé alla prima ricerca:
  /// qui si dice di sì e basta.
  static Future<bool> permessi() async {
    try {
      return await _permessi.invokeMethod<bool>('bluetooth') ?? false;
    } on MissingPluginException {
      return defaultTargetPlatform == TargetPlatform.iOS;
    }
  }

  /// I dongle intorno: si cercano per nome, perché non tutti annunciano i
  /// servizi.
  static Stream<DiscoveredDevice> cerca() =>
      _ble.scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency).where((d) => d.name.isNotEmpty);

  /// Sembra un dongle OBD? Per metterlo in cima all'elenco.
  static bool sembraObd(String nome) => RegExp(
    r'obd|elm|vgate|icar|v-?link|veepeak|konnwei|carista|obdlink|vlinker',
    caseSensitive: false,
  ).hasMatch(nome);

  static final _serviziNoti = [
    Uuid.parse('fff0'),
    Uuid.parse('ffe0'),
    Uuid.parse('18f0'),
    Uuid.parse('e7810a71-73ae-499d-8c15-faa9aef0c3f2'),
  ];

  static Future<CanaleBle> apri(String id) async {
    final collegato = Completer<void>();
    final connessione = _ble
        .connectToDevice(id: id, connectionTimeout: const Duration(seconds: 15))
        .listen(
          (u) {
            if (u.connectionState == DeviceConnectionState.connected && !collegato.isCompleted) {
              collegato.complete();
            }
            if (u.connectionState == DeviceConnectionState.disconnected && !collegato.isCompleted) {
              collegato.completeError(const ErroreObd('il dongle non si collega'));
            }
          },
          onError: (Object e) {
            if (!collegato.isCompleted) collegato.completeError(ErroreObd('Bluetooth: $e'));
          },
        );
    try {
      await collegato.future.timeout(const Duration(seconds: 20));
      await _ble.discoverAllServices(id);
      final servizi = await _ble.getDiscoveredServices(id);
      servizi.sort((a, b) => (_serviziNoti.contains(a.id) ? 0 : 1).compareTo(_serviziNoti.contains(b.id) ? 0 : 1));
      for (final s in servizi) {
        final notifica = s.characteristics.where((c) => c.isNotifiable || c.isIndicatable).firstOrNull;
        final scrittura = s.characteristics
            .where((c) => c.isWritableWithoutResponse || c.isWritableWithResponse)
            .firstOrNull;
        if (notifica == null || scrittura == null) continue;
        final canale = CanaleBle._(connessione, scrittura, !scrittura.isWritableWithoutResponse);
        canale._notifiche = notifica.subscribe().listen(
          (b) => canale._in.add(latin1.decode(b, allowInvalid: true)),
          onError: (Object _) {},
        );
        return canale;
      }
      throw const ErroreObd('questo dispositivo non sembra un dongle OBD');
    } catch (_) {
      await connessione.cancel();
      rethrow;
    }
  }

  @override
  Stream<String> get ricevuti => _in.stream;

  /// A pezzi da 20 byte: il minimo che ogni dongle BLE accetta.
  @override
  Future<void> scrivi(String testo) async {
    final byte = latin1.encode(testo);
    for (var i = 0; i < byte.length; i += 20) {
      await _scrivi.write(byte.sublist(i, i + 20 > byte.length ? byte.length : i + 20), withResponse: _conRisposta);
    }
  }

  @override
  Future<void> chiudi() async {
    await _notifiche?.cancel();
    await _connessione.cancel();
    await _in.close();
  }
}
