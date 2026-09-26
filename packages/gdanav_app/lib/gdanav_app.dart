import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
import 'sorgenti/sorgente_gdahome.dart';
import 'tema.dart';

// Quello che serve a chi ospita gdanav per dargli l'auto: la fonte gdahome e
// la lettura che le si manda.
export 'package:gdanav_core/gdanav_core.dart' show StatoAuto, TipoSorgente;

export 'risorse.dart' show logoGdanav;
export 'schermate/schermata_principale.dart' show VoceOspite;
export 'sorgenti/sorgente_gdahome.dart';

/// Accende tutto quello che gdanav tiene in piedi — l'auto, il viaggio, la
/// guida, la posizione, le segnalazioni — e torna l'app pronta da disegnare.
///
/// La chiama `main` nell'app gdanav, e la chiama gdahome la prima volta che si
/// apre la sezione del navigatore: lì il portachiavi è un altro ([portachiavi],
/// per non mescolare le chiavi della casa con quelle di gdanav) e Android Auto
/// lo decide lei ([conLAuto]). Lì c'è anche [gdahome]: l'auto della
/// sezione Auto della sua plancia, coi dati in tempo reale dalla casa, senza
/// abbinamento.
Future<GdanavApp> preparaGdanav({
  FlutterSecureStorage? portachiavi,
  bool conLAuto = true,
  SorgenteGdahome? gdahome,
  bool senzaPremium = false,
}) async {
  final archivio = Archivio(portachiavi);
  // Premium (Android Auto e Home Assistant): si sa subito se è sbloccato,
  // il Play Store conferma dopo. [senzaPremium]: tutto sbloccato e niente
  // negozio né voce «Premium» (gdahome, finché i pagamenti non ci sono).
  final premium = senzaPremium
      ? GestorePremium(archivio: archivio, tuttoSbloccato: true)
      : GestorePremium(archivio: archivio, negozio: NegozioGooglePlay());
  await premium.carica();
  final auto = GestoreAuto(archivio: archivio, gdahome: gdahome)..homeAssistantConsentito = premium.sbloccato;
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
  // Lo schermo dell'auto: solo dove Android Auto è di gdanav.
  if (conLAuto) {
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
  }
  return GdanavApp(
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
    premium: senzaPremium ? null : premium,
    chiediPosizione: chiediPosizione,
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
      home: schermata(),
    );
  }

  /// La prima schermata, senza l'app intorno: la usa [GdanavDentro].
  Widget schermata({
    VoidCallback? menuOspite,
    Widget? iconaOspite,
    ValueNotifier<bool>? apriIlMenu,
    List<VoceOspite> vociOspite = const [],
  }) => SchermataPrincipale(
    menuOspite: menuOspite,
    iconaOspite: iconaOspite,
    apriIlMenu: apriIlMenu,
    vociOspite: vociOspite,
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
  );
}

/// gdanav dentro un'altra app: gdahome, che lo apre come una sua sezione.
///
/// Ha il suo tema e il suo navigatore: le schermate che gdanav apre sopra la
/// mappa restano dentro la sezione, col vestito di gdanav, e il resto
/// dell'app — la barra, il menu — resta dov'è. Il tasto Indietro lo decide chi
/// ospita: con [navigatore] in mano chiude prima le schermate di gdanav.
class GdanavDentro extends StatelessWidget {
  const GdanavDentro({
    super.key,
    required this.app,
    this.navigatore,
    this.menuOspite,
    this.iconaOspite,
    this.apriIlMenu,
    this.vociOspite = const [],
  });

  /// Il disegno del tasto del menu di chi ospita (il suo marchio).
  final Widget? iconaOspite;

  /// Le voci che chi ospita aggiunge al menu di gdanav.
  final List<VoceOspite> vociOspite;

  final GdanavApp app;
  final GlobalKey<NavigatorState>? navigatore;

  /// Il menu di chi ospita: lo apre il suo tasto, accanto al menu di gdanav.
  final VoidCallback? menuOspite;

  /// Per aprire da fuori il menu di gdanav (le sue impostazioni).
  final ValueNotifier<bool>? apriIlMenu;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: temaGdanav(MediaQuery.platformBrightnessOf(context)),
      child: HeroControllerScope.none(
        child: Navigator(
          key: navigatore,
          onGenerateRoute: (impostazioni) => MaterialPageRoute<void>(
            settings: impostazioni,
            builder: (_) => app.schermata(
              menuOspite: menuOspite,
              iconaOspite: iconaOspite,
              apriIlMenu: apriIlMenu,
              vociOspite: vociOspite,
            ),
          ),
        ),
      ),
    );
  }
}
