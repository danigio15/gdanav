import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/main.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_auto.dart';
import 'package:gdanav/stato/gestore_consumo.dart';
import 'package:gdanav/stato/gestore_guida.dart';
import 'package:gdanav/stato/gestore_posizione.dart';
import 'package:gdanav/stato/gestore_segnalazioni.dart';
import 'package:gdanav/stato/gestore_viaggio.dart';
import 'package:gdanav/stato/voce.dart';
import 'package:gdanav_core/gdanav_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Il portachiavi vuoto, e Android Auto collegato ma zitto: come un'auto
/// che non passa i dati al telefono.
void preparaPiattaforma({Map<String, String> portachiavi = const {}}) {
  FlutterSecureStorage.setMockInitialValues(Map.of(portachiavi));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
    const EventChannel('gdanav/auto'),
    MockStreamHandler.inline(onListen: (_, _) {}),
  );
}

class LuoghiFinti implements FonteLuoghi {
  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async => [
    const Luogo(nome: 'Bologna', descrizione: 'Emilia-Romagna', posizione: Punto(44.49, 11.34)),
  ];
}

class ColonnineFinte implements FonteColonnine {
  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async => [
    for (var km = 60; km < 500; km += 60)
      Colonnina(
        id: 'c$km',
        nome: 'Area $km',
        posizione: Punto(42 + km * 0.009, 12.002),
        // Ogni seconda area è piena; le altre hanno 2 prese libere su 4.
        connettori: [
          for (var i = 0; i < 4; i++)
            Connettore(
              tipo: TipoConnettore.ccs2,
              potenzaKw: 150,
              stato: km % 120 == 0 || i >= 2 ? StatoPresa.occupata : StatoPresa.disponibile,
            ),
        ],
      ),
  ];
}

/// Una strada dritta verso nord lunga [km], a 120 km/h.
PercorsoCalcolato dritta(int km) {
  final punti = [for (var i = 0; i <= km; i++) Punto(42 + i * 0.009, 12)];
  final linea = Linea(punti);
  return PercorsoCalcolato(
    punti: punti,
    tratti: [
      for (var i = 1; i < punti.length; i++)
        Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 120),
    ],
    manovre: const [],
    // Mezza strada in città, mezza fuori.
    limiti: [for (var i = 0; i < km; i++) i < km / 2 ? 50 : 90],
  );
}

CostruisciPianificatore pianificatoreFinto(int km) =>
    (_, profilo, preferenze) => PianificatoreViaggio(
      percorsi: (_) async => dritta(km),
      colonnine: ColonnineFinte(),
      profilo: profilo,
      preferenze: preferenze,
    );

/// Scrive quello che direbbe, invece di dirlo.
class VoceFinta implements Voce {
  final frasi = <String>[];

  @override
  Future<void> parla(String frase) async => frasi.add(frase);

  @override
  Future<void> zitta() async {}
}

class Ambiente {
  Ambiente(
    this.archivio,
    this.auto,
    this.viaggio,
    this.guida,
    this.posizioni,
    this.voce,
    this.posizione,
    this.gps,
    this.segnalazioni,
    this.relay,
  );
  final Archivio archivio;
  final GestoreAuto auto;
  final GestoreViaggio viaggio;
  final GestoreGuida guida;

  /// Il GPS finto della guida: le prove ci mettono le posizioni.
  final StreamController<Punto> posizioni;
  final VoceFinta voce;
  final GestorePosizione posizione;

  /// Il GPS finto del segnaposto.
  final StreamController<Lettura> gps;

  /// Le segnalazioni, su un relay finto in memoria.
  final GestoreSegnalazioni segnalazioni;
  final RelayFinto relay;

  Widget app() => GdanavApp(
    posizione: posizione,
    archivio: archivio,
    auto: auto,
    viaggio: viaggio,
    guida: guida,
    segnalazioni: segnalazioni,
    mappa: (_, _) => const ColoredBox(color: Colors.grey),
  );
}

Future<Ambiente> ambiente(WidgetTester tester, {int km = 500, Punto? posizione = const Punto(42, 12)}) async {
  // Uno schermo da telefono, non gli 800×600 delle prove.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final archivio = Archivio();
  final auto = GestoreAuto(archivio: archivio);
  await tester.runAsync(auto.avvia);
  addTearDown(auto.dispose);
  final consumo = GestoreConsumo(archivio);
  await tester.runAsync(() => consumo.carica(auto.veicolo.id));
  final viaggio = GestoreViaggio(
    archivio: archivio,
    auto: auto,
    consumo: consumo,
    posizione: () async => posizione,
    costruisci: pianificatoreFinto(km),
    luoghi: LuoghiFinti(),
  );
  final posizioni = StreamController<Punto>.broadcast();
  addTearDown(posizioni.close);
  final voce = VoceFinta();
  final guida = GestoreGuida(
    viaggio: viaggio,
    auto: auto,
    posizioni: () => posizioni.stream,
    voce: voce,
    consumo: consumo,
  );
  addTearDown(guida.dispose);
  final gps = StreamController<Lettura>.broadcast();
  addTearDown(gps.close);
  final segnaposto = GestorePosizione(archivio: archivio, letture: () => gps.stream);
  await tester.runAsync(segnaposto.carica);
  addTearDown(segnaposto.dispose);
  final relay = RelayFinto();
  final segnalazioni = GestoreSegnalazioni(
    posizione: segnaposto,
    cliente: ClienteSegnalazioni(Uri.parse('https://relay.esempio.dev/'), client: MockClient(relay.risponde)),
  );
  addTearDown(segnalazioni.dispose);
  return Ambiente(archivio, auto, viaggio, guida, posizioni, voce, segnaposto, gps, segnalazioni, relay);
}

const impostazioniComplete = {
  'impostazioni': '{"valhalla":"https://valhalla.esempio.dev/","chiave_valhalla":"","chiave_ocm":"ocm"}',
};

/// Tira su la scheda del viaggio e la scorre: i contenuti in fondo si
/// costruiscono solo quando si vedono.
Future<void> scorriScheda(WidgetTester tester, {int volte = 2}) async {
  for (var i = 0; i < volte; i++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
}

/// Il relay delle segnalazioni, in memoria.
class RelayFinto {
  final segnalazioni = <Map<String, Object?>>[];
  final voti = <(String, bool)>[];
  var _n = 0;

  Future<http.Response> risponde(http.Request r) async {
    if (r.method == 'GET') return http.Response(jsonEncode({'segnalazioni': segnalazioni}), 200);
    final corpo = jsonDecode(r.body) as Map<String, Object?>;
    if (r.url.path.endsWith('/voto')) {
      final id = r.url.pathSegments[2];
      voti.add((id, corpo['ancora']! as bool));
      return http.Response(jsonEncode(segnalazioni.firstWhere((s) => s['id'] == id)), 200);
    }
    final s = {...corpo, 'id': 'z~segnalazione${_n++}', 'creata': 0, 'conferme': 0};
    segnalazioni.add(s);
    return http.Response(jsonEncode(s), 201);
  }
}
