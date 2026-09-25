import 'dart:async';

import 'package:flutter/material.dart';

import 'auto/ponte_auto.dart';
import 'schermate/schermata_principale.dart';
import 'stato/archivio.dart';
import 'stato/gestore_auto.dart';
import 'stato/foto_auto.dart';
import 'stato/gestore_consumo.dart';
import 'stato/gestore_premium.dart';
import 'stato/gestore_guida.dart';
import 'stato/gestore_luoghi.dart';
import 'stato/gestore_meteo.dart';
import 'stato/gestore_posizione.dart';
import 'stato/gestore_segnalazioni.dart';
import 'stato/gestore_vicini.dart';
import 'stato/gestore_viaggio.dart';
import 'stato/posizione.dart';
import 'stato/voce.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final archivio = Archivio();
  // Premium (Android Auto e Home Assistant): si sa subito se è sbloccato,
  // il Play Store conferma dopo.
  final premium = GestorePremium(archivio: archivio, negozio: NegozioGooglePlay());
  await premium.carica();
  final auto = GestoreAuto(archivio: archivio)..homeAssistantConsentito = premium.sbloccato;
  await auto.avvia();
  premium.addListener(() => auto.consentiHomeAssistant(premium.sbloccato));
  // Il consumo imparato del modello scelto; cambiando auto si cambia storia.
  final consumo = GestoreConsumo(archivio);
  await consumo.carica(auto.veicolo.id);
  auto.addListener(() => consumo.carica(auto.veicolo.id));
  final viaggio = GestoreViaggio(archivio: archivio, auto: auto, posizione: posizioneAttuale, consumo: consumo);
  viaggio.opzioni = await archivio.opzioniPercorso();
  final guida = GestoreGuida(
    viaggio: viaggio,
    auto: auto,
    posizioni: posizioniGuida,
    voce: VoceTelefono(),
    consumo: consumo,
  );
  final posizione = GestorePosizione(archivio: archivio, letture: lettureGps);
  await posizione.carica();
  final segnalazioni = GestoreSegnalazioni(posizione: posizione, autovelox: archivioAutovelox());
  // Il meteo lungo la strada (Premium): nel consumo e sullo schermo.
  final meteo = GestoreMeteo(viaggio: viaggio, posizione: posizione);
  viaggio.stimaMeteo = meteo.stima;
  // Distributori o colonnine intorno, sulla mappa del telefono e dell'auto.
  final vicini = GestoreVicini(auto: auto, posizione: posizione);
  final luoghi = GestoreLuoghi(archivio);
  await luoghi.carica();
  // Le colonnine dentro l'app: si leggono mentre si guarda la mappa.
  unawaited(archivioColonnine());
  final fotoAuto = GestoreFotoAuto();
  await fotoAuto.carica();
  // Aperta da Android Auto la schermata del telefono non c'è: la posizione
  // parte subito, se il permesso è già stato dato.
  if (await haPosizione()) posizione.avvia();
  // Le segnalazioni servono anche con l'app aperta solo sull'auto.
  segnalazioni.avvia();
  final ponte = PonteAuto(
    viaggio: viaggio,
    guida: guida,
    posizione: posizione,
    luoghi: luoghi,
    auto: auto,
    segnalazioni: segnalazioni,
    meteo: meteo,
    vicini: vicini,
  )..avvia();
  ponte.premium(premium.sbloccato);
  premium.addListener(() => ponte.premium(premium.sbloccato));
  runApp(
    GdanavApp(
      archivio: archivio,
      auto: auto,
      viaggio: viaggio,
      guida: guida,
      posizione: posizione,
      segnalazioni: segnalazioni,
      meteo: meteo,
      vicini: vicini,
      luoghi: luoghi,
      consumo: consumo,
      fotoAuto: fotoAuto,
      premium: premium,
      chiediPosizione: chiediPosizione,
    ),
  );
}

class GdanavApp extends StatelessWidget {
  const GdanavApp({
    super.key,
    required this.archivio,
    required this.auto,
    required this.viaggio,
    required this.guida,
    required this.posizione,
    this.mappa,
    this.chiediPosizione,
    this.segnalazioni,
    this.meteo,
    this.vicini,
    this.luoghi,
    this.consumo,
    this.fotoAuto,
    this.premium,
  });

  final Archivio archivio;
  final GestoreAuto auto;
  final GestoreViaggio viaggio;
  final GestoreGuida guida;
  final GestorePosizione posizione;
  final Future<bool> Function()? chiediPosizione;
  final GestoreSegnalazioni? segnalazioni;
  final GestoreMeteo? meteo;
  final GestoreVicini? vicini;
  final GestoreLuoghi? luoghi;
  final GestoreConsumo? consumo;
  final GestoreFotoAuto? fotoAuto;

  /// `null` nelle prove: tutto sbloccato.
  final GestorePremium? premium;

  /// Nelle prove e nelle anteprime si passa un'altra mappa: quella vera vuole
  /// il codice nativo.
  final CostruisciMappa? mappa;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gdanav',
      debugShowCheckedModeBanner: false,
      theme: temaGdanav(Brightness.light),
      darkTheme: temaGdanav(Brightness.dark),
      home: SchermataPrincipale(
        auto: auto,
        viaggio: viaggio,
        archivio: archivio,
        guida: guida,
        posizione: posizione,
        mappa: mappa,
        chiediPosizione: chiediPosizione,
        segnalazioni: segnalazioni,
        meteo: meteo,
        vicini: vicini,
        luoghi: luoghi,
        consumo: consumo,
        fotoAuto: fotoAuto,
        premium: premium,
      ),
    );
  }
}
