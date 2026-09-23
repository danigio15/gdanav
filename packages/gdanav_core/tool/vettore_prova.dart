import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gdanav_core/gdanav_core.dart';

/// Aggiunge al vettore di prova quello che scrive Dart, per la prova Python.
Future<void> main() async {
  final file = File('../../docs/vettore_prova.json');
  final v = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final a = Abbinamento(
    chiave: Uint8List.fromList(List.generate(32, (i) => i)),
    relay: Uri.parse('wss://relay.esempio.dev'),
    nomeAuto: 'Auto di prova',
  );
  final m = Messaggio(
    tipo: TipoMessaggio.viaggio,
    id: 'fedcba9876543210',
    ts: DateTime.utc(2026, 9, 23, 10),
    dati: {'in_viaggio': true, 'batteria_arrivo': 31},
  );
  v['uri_dart'] = a.uri;
  v['busta_app_dart'] = await (await Busta.per(a)).chiudi(m, Mittente.app, nonce: List.generate(12, (i) => 12 - i));
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(v)}\n');
}
