import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

void main() {
  // Lo stesso file lo legge la prova Python: se qualcuno cambia la
  // derivazione o la busta da una parte sola, una delle due diventa rossa.
  final vettore = jsonDecode(File('../../docs/vettore_prova.json').readAsStringSync()) as Map<String, Object?>;
  final chiave = Uint8List.fromList(List.generate(32, (i) => i));
  final a = Abbinamento(chiave: chiave, relay: Uri.parse('wss://relay.esempio.dev'), nomeAuto: 'Auto di prova');
  final ora = DateTime.parse(vettore['ts'] as String);

  group('abbinamento', () {
    test('canale e accesso come in Python', () async {
      expect(await a.canale(), vettore['canale']);
      expect(await a.accesso(), vettore['accesso']);
    });

    test('legge il QR fatto da Home Assistant', () async {
      final letto = Abbinamento.daUri(vettore['uri'] as String);
      expect(letto.chiave, chiave);
      expect(letto.relay, Uri.parse('wss://relay.esempio.dev'));
      expect(letto.nomeAuto, 'Auto di prova');
    });

    test('il proprio QR si rilegge uguale', () {
      final letto = Abbinamento.daUri(a.uri);
      expect(letto.chiave, chiave);
      expect(letto.nomeAuto, a.nomeAuto);
    });

    test('rifiuta un QR che non è di gdanav', () {
      expect(() => Abbinamento.daUri('https://esempio.dev/?k=x'), throwsFormatException);
      expect(() => Abbinamento.daUri('gdanav://abbina?v=2&k=x&r=y'), throwsFormatException);
    });

    test("l'indirizzo del relay porta canale, ruolo e accesso", () async {
      final uri = await a.indirizzoRelay('app');
      expect(uri.path, '/v1/canale/${vettore['canale']}');
      expect(uri.queryParameters, {'ruolo': 'app', 'accesso': vettore['accesso']});
    });
  });

  group('busta', () {
    test('apre la busta chiusa da Python', () async {
      final b = await Busta.per(a);
      final m = await b.apri(vettore['busta_casa'] as String, Mittente.casa, ora: ora);
      expect(m.tipo, TipoMessaggio.statoAuto);
      expect(m.id, '0123456789abcdef');
      expect(m.dati, {'batteria': 72.5, 'in_carica': false});
    });

    test('non apre una busta della casa come se fosse dell\'app', () async {
      final b = await Busta.per(a);
      expect(b.apri(vettore['busta_casa'] as String, Mittente.app, ora: ora), throwsA(anything));
    });

    test('non apre una busta vecchia', () async {
      final b = await Busta.per(a);
      expect(
        b.apri(vettore['busta_casa'] as String, Mittente.casa, ora: ora.add(const Duration(minutes: 6))),
        throwsFormatException,
      );
    });

    test('andata e ritorno', () async {
      final b = await Busta.per(a);
      final m = Messaggio(tipo: TipoMessaggio.viaggio, dati: {'in_viaggio': true, 'batteria_arrivo': 31});
      final aperto = await b.apri(await b.chiudi(m, Mittente.app), Mittente.app);
      expect(aperto.dati, m.dati);
      expect(aperto.id, m.id);
    });

    test('con un\'altra chiave non si apre', () async {
      final altra = Abbinamento.nuovo(relay: Uri.parse('wss://relay.esempio.dev'));
      final b = await Busta.per(altra);
      expect(b.apri(vettore['busta_casa'] as String, Mittente.casa, ora: ora), throwsA(anything));
    });
  });

  test('stato_auto diventa uno StatoAuto di Home Assistant', () {
    final m = Messaggio(tipo: TipoMessaggio.statoAuto, dati: {
      'batteria': 64,
      'autonomia_km': 280.5,
      'in_carica': true,
      'letto': '2026-09-23T09:50:00.000Z',
    });
    final s = SorgenteHomeAssistant.statoDaMessaggio(m)!;
    expect(s.sorgente, TipoSorgente.homeAssistant);
    expect(s.batteria, 64);
    expect(s.autonomiaKm, 280.5);
    expect(s.inCarica, isTrue);
    expect(s.letto, DateTime.utc(2026, 9, 23, 9, 50));
  });

  test('senza batteria non inventa niente', () {
    expect(SorgenteHomeAssistant.statoDaMessaggio(Messaggio(tipo: TipoMessaggio.statoAuto, dati: {'in_carica': true})),
        isNull);
  });
}
