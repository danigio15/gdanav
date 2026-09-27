import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/schermate/premium.dart';
import 'package:gdanav_app/stato/archivio.dart';
import 'package:gdanav_app/stato/chiave_licenze.dart';
import 'package:gdanav_app/stato/gestore_premium.dart';
import 'package:gdanav_app/stato/licenza.dart';
import 'package:gdanav_app/tema.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'aiuti.dart';

/// La coppia **di prova** del contratto (`docs/LICENZE.md` di gdahome): mai
/// in un file di produzione.
const pubblicaProva = '6P9sdqQtlHcmH7Ve_SgzmyJmxJS28CNORRJJfjI3rnI';
const privataProva = 'Q2Iu3eKMxw3Y1GS9MypZjXvjPfHB959KImNldY80xr0';

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

/// Un gettone come lo firma il quadro.
Future<String> firma(Map<String, Object?> payload, {String privata = privataProva}) async {
  final coppia = await Ed25519().newKeyPairFromSeed(base64Url.decode('$privata='));
  final primo = _b64(utf8.encode(jsonEncode(payload)));
  final f = await Ed25519().sign(ascii.encode(primo), keyPair: coppia);
  return '$primo.${_b64(f.bytes)}';
}

final adesso = DateTime.utc(2026, 9, 27, 12);
int ms(Duration d) => adesso.add(d).millisecondsSinceEpoch;

Map<String, Object?> payload(
  String sog, {
  String app = 'gdanav',
  Object? scade,
  Duration fino = const Duration(days: 8),
  int v = 1,
}) => {
  'v': v,
  'app': app,
  'sog': sog,
  'lic': 'lic_prova',
  'origine': 'regalo',
  'scade': scade,
  'fino': ms(fino),
  'emesso': ms(Duration.zero),
};

const telefono = 'tel_0123456789abcdef0123456789abcdef';

/// Il quadro finto: risponde ai codici e ai rinnovi come vogliamo.
class QuadroFinto {
  final codici = <String, String>{};
  final usati = <String>{};
  final chieste = <(String, Map<String, Object?>)>[];

  /// Cosa rende il rinnovo; `null`: rete giù.
  List<String>? rinnovo = const [];

  Future<http.Response> risponde(http.Request r) async {
    final corpo = jsonDecode(r.body) as Map<String, Object?>;
    chieste.add((r.url.path, corpo));
    Map<String, Object?> gettoni(List<String> g) => {
      'gettoni': {for (final (i, x) in g.indexed) i == 0 ? 'gdanav' : 'gdahome': x},
      'licenze': const [],
    };
    if (r.url.path == '/v1/licenze/riscatta') {
      final c = corpo['codice']! as String;
      if (!codici.containsKey(c)) return http.Response('{"errore":"codice-inesistente"}', 404);
      if (!usati.add(c)) return http.Response('{"errore":"codice-usato"}', 409);
      rinnovo = [codici[c]!];
      return http.Response(jsonEncode(gettoni(rinnovo!)), 200);
    }
    if (r.url.path == '/v1/licenze/telefono') {
      final g = rinnovo;
      if (g == null) throw http.ClientException('rete giù');
      return http.Response(jsonEncode(gettoni(g)), 200);
    }
    return http.Response('', 404);
  }
}

void main() {
  tearDown(() => GestorePremium.attivo.value = true);

  test('di serie la chiave è vuota: nessun gettone vale', () async {
    expect(chiavePubblicaLicenze, isEmpty);
    final g = await firma(payload(telefono));
    expect(await verificaGettone(g, soggetto: telefono, chiavePubblica: chiavePubblicaLicenze), isNull);
  });

  group('il gettone, verificato come dice il contratto', () {
    Future<GettoneLicenza?> verifica(String g, {String sog = telefono}) =>
        verificaGettone(g, soggetto: sog, chiavePubblica: pubblicaProva, adesso: adesso);

    test('valido: gdanav, e anche gdahome (Premium compreso)', () async {
      final g = await verifica(await firma(payload(telefono)));
      expect(g, isNotNull);
      expect(g!.app, 'gdanav');
      expect(g.scade, isNull);
      expect(g.fino, DateTime.fromMillisecondsSinceEpoch(ms(const Duration(days: 8))));
      expect(await verifica(await firma(payload(telefono, app: 'gdahome'))), isNotNull);
      expect(
        await verifica(await firma(payload(telefono, scade: ms(const Duration(days: 30))))),
        isA<GettoneLicenza>().having((g) => g.scade, 'scade', isNotNull),
      );
    });

    test('non vale: altro soggetto, scaduto, fino passato, versione o app sbagliata', () async {
      expect(await verifica(await firma(payload('tel_ffffffffffffffffffffffffffffffff'))), isNull);
      expect(await verifica(await firma(payload('casa_0123456789abcdef0123456789abcdef'))), isNull);
      expect(await verifica(await firma(payload(telefono, scade: ms(const Duration(minutes: -1))))), isNull);
      expect(await verifica(await firma(payload(telefono, fino: const Duration(minutes: -1)))), isNull);
      expect(await verifica(await firma(payload(telefono, v: 2))), isNull);
      expect(await verifica(await firma(payload(telefono, app: 'altro'))), isNull);
    });

    test('non vale: firma di un\'altra chiave, o gettone ritoccato', () async {
      final altra = _b64(List.generate(32, (i) => i));
      expect(await verifica(await firma(payload(telefono), privata: altra)), isNull);
      final buono = await firma(payload(telefono));
      final [primo, f] = buono.split('.');
      final ritoccato = _b64(utf8.encode(jsonEncode(payload(telefono, scade: null, fino: const Duration(days: 800)))));
      expect(await verifica('$ritoccato.$f'), isNull);
      expect(await verifica(primo), isNull);
      expect(await verifica('niente'), isNull);
    });
  });

  test('i codici si scrivono come si vuole, ma solo con l\'alfabeto giusto', () {
    expect(normalizzaCodice('gda-abcd-efgh-jkmn'), 'GDA-ABCD-EFGH-JKMN');
    expect(normalizzaCodice(' abcd efgh 2345 '), 'GDA-ABCD-EFGH-2345');
    expect(normalizzaCodice('GDA-ABCD-EFGH-JKM0'), isNull); // lo 0 non c'è
    expect(normalizzaCodice('GDA-ABCD-EFGH-IJKL'), isNull); // la I e la L nemmeno
    expect(normalizzaCodice('GDA-ABCD'), isNull);
  });

  test('l\'identità del telefono nasce una volta sola, nell\'archivio sicuro', () async {
    preparaPiattaforma();
    final a = await Archivio().identitaTelefono();
    expect(a.telefono, matches(RegExp(r'^tel_[0-9a-f]{32}$')));
    expect(a.segreto.length, greaterThanOrEqualTo(32));
    final b = await Archivio().identitaTelefono();
    expect(b, a);
  });

  group('i codici regalo di gdanav da sola', () {
    late QuadroFinto quadro;
    late IdentitaTelefono io;

    setUp(() async {
      preparaPiattaforma();
      quadro = QuadroFinto();
      io = await Archivio().identitaTelefono();
    });

    GestorePremium gestore() => GestorePremium(
      archivio: Archivio(),
      tuttoSbloccato: false,
      licenze: ClienteLicenze(client: MockClient(quadro.risponde)),
      chiaveLicenze: pubblicaProva,
    );

    test('riscattato: Premium attivo e ricordato; chiesto con telefono e segreto', () async {
      quadro.codici['GDA-ABCD-EFGH-JKMN'] = await firma({
        ...payload(io.telefono),
        'fino': DateTime.now().add(const Duration(days: 8)).millisecondsSinceEpoch,
      });
      final p = gestore();
      await p.carica();
      await pumpEventQueue();
      expect(p.sbloccato, isFalse);
      expect(p.codiciRegalo, isTrue);

      expect(await p.riscattaCodice('gda abcd efgh jkmn'), isTrue);
      expect(p.sbloccato, isTrue);
      expect(GestorePremium.attivo.value, isTrue);
      expect(p.licenza!.origine, 'regalo');
      final (via, corpo) = quadro.chieste.last;
      expect(via, '/v1/licenze/riscatta');
      expect(corpo, {'codice': 'GDA-ABCD-EFGH-JKMN', 'telefono': io.telefono, 'segreto': io.segreto});
      p.dispose();

      // Riaperta l'app, senza rete: il gettone salvato vale ancora.
      quadro.rinnovo = null;
      final dopo = gestore();
      await dopo.carica();
      await pumpEventQueue();
      expect(dopo.sbloccato, isTrue);
      expect(quadro.chieste.last.$1, '/v1/licenze/telefono');
      dopo.dispose();

      // Il quadro risponde senza gettoni: licenza tolta, Premium si chiude.
      quadro.rinnovo = const [];
      final tolta = gestore();
      await tolta.carica();
      await pumpEventQueue();
      expect(tolta.sbloccato, isFalse);
      expect(GestorePremium.attivo.value, isFalse);
      expect(await Archivio().gettoneLicenza(), isNull);
      tolta.dispose();
    });

    test('codice che non c\'è, già usato, scritto male, o per un altro telefono', () async {
      quadro.codici['GDA-AAAA-BBBB-CCCC'] = await firma(payload(io.telefono));
      quadro.usati.add('GDA-AAAA-BBBB-CCCC');
      quadro.codici['GDA-DDDD-EEEE-FFFF'] = await firma({
        ...payload('tel_ffffffffffffffffffffffffffffffff'),
        'fino': DateTime.now().add(const Duration(days: 8)).millisecondsSinceEpoch,
      });
      final p = gestore();
      await p.carica();
      await pumpEventQueue();

      expect(await p.riscattaCodice('GDA-2222-3333-4444'), isFalse);
      expect(p.erroreCodice, contains('non esiste'));
      expect(await p.riscattaCodice('GDA-AAAA-BBBB-CCCC'), isFalse);
      expect(p.erroreCodice, contains('già stato usato'));
      final prima = quadro.chieste.length;
      expect(await p.riscattaCodice('ciao'), isFalse);
      expect(p.erroreCodice, contains('GDA-XXXX-XXXX-XXXX'));
      expect(quadro.chieste.length, prima);
      expect(await p.riscattaCodice('GDA-DDDD-EEEE-FFFF'), isFalse);
      expect(p.erroreCodice, contains('non vale'));
      expect(p.sbloccato, isFalse);
      p.dispose();
    });

    test('senza chiave (di serie) i codici non si propongono e i gettoni si ignorano', () async {
      await Archivio().salvaGettoneLicenza(await firma(payload(io.telefono)));
      final p = GestorePremium(
        archivio: Archivio(),
        tuttoSbloccato: false,
        licenze: ClienteLicenze(client: MockClient(quadro.risponde)),
      );
      await p.carica();
      await pumpEventQueue();
      expect(p.codiciRegalo, isFalse);
      expect(p.sbloccato, isFalse);
      expect(quadro.chieste, isEmpty);
      p.dispose();
    });

    testWidgets('dalla schermata Premium: «Ho un codice regalo», e Premium è attivo', (tester) async {
      quadro.codici['GDA-ABCD-EFGH-JKMN'] = await firma({
        ...payload(io.telefono, scade: DateTime(2027, 3, 1).millisecondsSinceEpoch),
        'fino': DateTime.now().add(const Duration(days: 8)).millisecondsSinceEpoch,
      });
      final p = gestore();
      await tester.runAsync(() async {
        await p.carica();
        await pumpEventQueue();
      });
      addTearDown(p.dispose);
      await tester.pumpWidget(MaterialApp(theme: temaGdanav(Brightness.light), home: SchermataPremium(premium: p)));
      await tester.ensureVisible(find.byKey(const Key('codice-regalo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('codice-regalo')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-codice')), 'GDA-2222-3333-4444');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('riscatta-codice')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.textContaining('non esiste'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('campo-codice')), 'GDA-ABCD-EFGH-JKMN');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('riscatta-codice')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('campo-codice')), findsNothing);
      expect(find.text('Premium è attivo con un codice regalo, fino al 01/03/2027.'), findsOneWidget);
      expect(find.byKey(const Key('compra-premium')), findsNothing);
    });
  });
}
