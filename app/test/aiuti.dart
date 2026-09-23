import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav/main.dart';
import 'package:gdanav/stato/archivio.dart';
import 'package:gdanav/stato/gestore_auto.dart';
import 'package:gdanav/stato/gestore_viaggio.dart';
import 'package:gdanav_core/gdanav_core.dart';

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
        connettori: const [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 150)],
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
  );
}

CostruisciPianificatore pianificatoreFinto(int km) =>
    (_, profilo) => PianificatoreViaggio(percorsi: (_) async => dritta(km), colonnine: ColonnineFinte(), profilo: profilo);

class Ambiente {
  Ambiente(this.archivio, this.auto, this.viaggio);
  final Archivio archivio;
  final GestoreAuto auto;
  final GestoreViaggio viaggio;

  Widget app() => GdanavApp(
    archivio: archivio,
    auto: auto,
    viaggio: viaggio,
    mappa: (_) => const ColoredBox(color: Colors.grey),
  );
}

Future<Ambiente> ambiente(WidgetTester tester, {int km = 500, Punto? posizione = const Punto(42, 12)}) async {
  final archivio = Archivio();
  final auto = GestoreAuto(archivio: archivio);
  await tester.runAsync(auto.avvia);
  addTearDown(auto.dispose);
  final viaggio = GestoreViaggio(
    archivio: archivio,
    auto: auto,
    posizione: () async => posizione,
    costruisci: pianificatoreFinto(km),
    luoghi: LuoghiFinti(),
  );
  return Ambiente(archivio, auto, viaggio);
}

const impostazioniComplete = {
  'impostazioni': '{"valhalla":"https://valhalla.esempio.dev/","chiave_valhalla":"","chiave_ocm":"ocm"}',
};
