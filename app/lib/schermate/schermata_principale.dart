import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/scheda_auto.dart';
import '../componenti/vetro.dart';
import '../mappa/controllo_mappa.dart';
import '../mappa/mappa_viaggio.dart';
import '../stato/archivio.dart';
import '../stato/gestore_auto.dart';
import '../stato/foto_auto.dart';
import '../stato/gestore_consumo.dart';
import '../stato/gestore_premium.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_luoghi.dart';
import '../stato/gestore_mappe_offline.dart';
import '../stato/gestore_meteo.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_viaggio.dart';
import '../stato/gestore_vicini.dart';
import 'abbina_home_assistant.dart';
import 'cerca_destinazione.dart';
import 'dettaglio_colonnina.dart';
import 'diagnosi_auto.dart';
import 'fonte_dati_auto.dart';
import 'importa_google.dart';
import 'la_tua_auto.dart';
import 'mappe_offline.dart';
import 'opzioni_percorso.dart';
import 'pannello_partenza.dart';
import 'premium.dart';
import 'ricarica.dart';
import 'scheda_viaggio.dart';
import 'distributori.dart';
import 'scheda_punto.dart';
import 'segnala.dart';
import 'schermata_guida.dart';

typedef CostruisciMappa = Widget Function(BuildContext context, ControlloMappa controllo);

class SchermataPrincipale extends StatefulWidget {
  const SchermataPrincipale({
    super.key,
    required this.auto,
    required this.viaggio,
    required this.archivio,
    required this.guida,
    required this.posizione,
    this.mappa,
    this.chiediPosizione,
    this.luoghi,
    this.segnalazioni,
    this.meteo,
    this.vicini,
    this.consumo,
    this.fotoAuto,
    this.premium,
    this.mappeOffline,
  });

  final GestoreAuto auto;
  final GestoreViaggio viaggio;
  final Archivio archivio;
  final GestoreGuida guida;
  final GestorePosizione posizione;

  /// Casa, Lavoro e recenti; se manca se ne crea uno sull'archivio.
  final GestoreLuoghi? luoghi;

  /// Le segnalazioni della comunità; se manca se ne crea uno sui servizi cablati.
  final GestoreSegnalazioni? segnalazioni;

  /// Il meteo lungo la strada (Premium); `null` nelle prove.
  final GestoreMeteo? meteo;

  /// Distributori o colonnine intorno, sulla mappa.
  final GestoreVicini? vicini;

  /// Il consumo imparato, da mostrare in «La tua auto».
  final GestoreConsumo? consumo;
  final GestoreFotoAuto? fotoAuto;

  /// Android Auto e Home Assistant; `null` (prove): tutto sbloccato.
  final GestorePremium? premium;

  /// Le mappe scaricate; se manca, quelle vere di MapLibre.
  final GestoreMappeOffline? mappeOffline;

  /// Chiede il permesso della posizione; nelle prove non c'è.
  final Future<bool> Function()? chiediPosizione;

  /// Nelle prove e nelle anteprime si passa un'altra mappa: quella vera vuole
  /// il codice nativo.
  final CostruisciMappa? mappa;

  @override
  State<SchermataPrincipale> createState() => _SchermataPrincipaleState();
}

class _SchermataPrincipaleState extends State<SchermataPrincipale> {
  final controllo = ControlloMappa();
  PreferenzeRicarica _preferenze = const PreferenzeRicarica();
  late final GestoreLuoghi luoghi = widget.luoghi ?? (GestoreLuoghi(widget.archivio)..carica());
  late final GestoreSegnalazioni segnalazioni = widget.segnalazioni ?? GestoreSegnalazioni(posizione: widget.posizione);

  GestoreViaggio get viaggio => widget.viaggio;

  @override
  void initState() {
    super.initState();
    _ricaricaPreferenze();
    widget.chiediPosizione?.call().then((ok) {
      if (ok) widget.posizione.avvia();
    });
    segnalazioni.avvia();
    widget.guida.addListener(_guidaDaFuori);
  }

  var _inGuida = false;

  Future<void> _avvia() async {
    if (_inGuida) return;
    _inGuida = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SchermataGuida(
          guida: widget.guida,
          posizione: widget.posizione,
          segnalazioni: segnalazioni,
          vicini: widget.vicini,
          mappa: widget.mappa,
        ),
      ),
    );
    _inGuida = false;
  }

  /// La guida partita dall'auto: anche il telefono passa alla guida.
  void _guidaDaFuori() {
    if (widget.guida.attiva && !_inGuida && mounted) _avvia();
  }

  @override
  void dispose() {
    widget.guida.removeListener(_guidaDaFuori);
    controllo.dispose();
    if (widget.segnalazioni == null) segnalazioni.dispose();
    super.dispose();
  }

  Future<void> _ricaricaPreferenze() async {
    final p = await widget.archivio.preferenze();
    if (mounted) setState(() => _preferenze = p);
  }

  Future<Luogo?> _scegli({String titolo = 'Dove andiamo?'}) => Navigator.of(context).push<Luogo>(
    MaterialPageRoute(
      builder: (_) => CercaDestinazione(
        luoghi: viaggio.luoghi,
        vicinoA: widget.posizione.qui ?? viaggio.ultimaPosizione,
        salvati: luoghi,
        titolo: titolo,
      ),
    ),
  );

  Future<void> _cerca() async {
    final luogo = await _scegli();
    if (luogo != null) await _vai(luogo);
  }

  Future<void> _vai(Luogo luogo) async {
    await luoghi.usato(luogo);
    await viaggio.vaiA(luogo);
  }

  /// La foto della propria auto: dalla galleria o scattata, copiata fra i
  /// file dell'app.
  Future<void> _foto() async {
    final da = await showModalBottomSheet<Object>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Scegli dalla galleria'),
              onTap: () => Navigator.of(c).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Scatta una foto'),
              onTap: () => Navigator.of(c).pop(ImageSource.camera),
            ),
            if (widget.auto.foto != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Togli la foto'),
                onTap: () => Navigator.of(c).pop('togli'),
              ),
          ],
        ),
      ),
    );
    if (da == 'togli') return widget.auto.impostaFoto(null);
    if (da is! ImageSource) return;
    try {
      final scelta = await ImagePicker().pickImage(source: da, maxWidth: 1200, imageQuality: 85);
      if (scelta == null) return;
      final cartella = await getApplicationDocumentsDirectory();
      // Un nome nuovo ogni volta: così l'immagine vecchia non resta in memoria.
      final destinazione = '${cartella.path}/auto_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(scelta.path).copy(destinazione);
      final vecchia = widget.auto.foto;
      await widget.auto.impostaFoto(destinazione);
      if (vecchia != null) await File(vecchia).delete().catchError((Object _) => File(vecchia));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Foto non caricata: $e')));
    }
  }

  Future<void> _preferito(TipoPreferito tipo) async {
    final gia = tipo == TipoPreferito.casa ? luoghi.casa : luoghi.lavoro;
    if (gia != null) return _vai(gia.luogo);
    await _imposta(tipo);
  }

  Future<void> _imposta(TipoPreferito tipo, {Preferito? vecchio}) async {
    final nome = switch (tipo) {
      TipoPreferito.casa => 'Casa',
      TipoPreferito.lavoro => 'Lavoro',
      TipoPreferito.altro => 'un preferito',
    };
    final luogo = await _scegli(titolo: 'Indirizzo di ${nome == 'un preferito' ? nome : nome.toLowerCase()}');
    if (luogo == null || !mounted) return;
    var etichetta = vecchio?.nome ?? '';
    if (tipo == TipoPreferito.altro) {
      etichetta = await _chiediNome(luogo.nome) ?? '';
      if (!mounted) return;
    }
    if (vecchio != null) await luoghi.togli(vecchio);
    await luoghi.salva(Preferito(tipo, luogo, nome: etichetta));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${Preferito(tipo, luogo, nome: etichetta).etichetta} salvato')));
    }
  }

  Future<String?> _chiediNome(String proposto) {
    final c = TextEditingController(text: proposto);
    return showDialog<String>(
      context: context,
      builder: (contesto) => AlertDialog(
        title: const Text('Come lo chiami?'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.of(contesto).pop(), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(contesto).pop(c.text.trim()), child: const Text('Salva')),
        ],
      ),
    );
  }

  void _modificaPreferito(Preferito p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (contesto) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(p.etichetta, style: Theme.of(contesto).textTheme.titleLarge),
              subtitle: Text(p.luogo.nome),
            ),
            ListTile(
              leading: const Icon(Icons.edit_location_alt_outlined),
              title: const Text('Cambia indirizzo'),
              onTap: () {
                Navigator.of(contesto).pop();
                _imposta(p.tipo, vecchio: p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Rimuovi'),
              onTap: () {
                Navigator.of(contesto).pop();
                luoghi.togli(p);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apri(Widget schermata) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => schermata));
    await _ricaricaPreferenze();
    // Auto o preferenze cambiate: il viaggio aperto si ricalcola.
    if (viaggio.stato is ViaggioPronto && viaggio.destinazione != null) await viaggio.pianifica(viaggio.destinazione!);
  }

  void _menu() {
    showModalBottomSheet<void>(
      context: context,
      // Alto quanto le voci e, sui telefoni piccoli, scorrevole: niente di tagliato.
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (contesto) {
        void vai(Widget w) {
          Navigator.of(contesto).pop();
          _apri(w);
        }

        final ha = widget.auto.abbinamento;
        final sbloccato = widget.premium?.sbloccato ?? true;
        final salvati = luoghi.altri.length;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TestaMenu(
                  auto: widget.auto,
                  onTap: () => vai(LaTuaAuto(auto: widget.auto, posizione: widget.posizione, consumo: widget.consumo)),
                ),
                _GruppoMenu(
                  titolo: 'Viaggio',
                  voci: [
                    _VoceMenu(
                      icona: Icons.alt_route_rounded,
                      colore: const Color(0xFF2563EB),
                      titolo: 'Percorso',
                      sotto: widget.viaggio.opzioni.riassunto,
                      onTap: () => vai(
                        OpzioniPercorsoSchermata(
                          iniziali: widget.viaggio.opzioni,
                          onCambia: widget.viaggio.cambiaOpzioni,
                        ),
                      ),
                    ),
                    // Ricarica e fonte della batteria servono solo all'elettrica.
                    if (widget.auto.elettrica)
                      _VoceMenu(
                        icona: Icons.ev_station_rounded,
                        colore: const Color(0xFF16A34A),
                        titolo: 'Ricarica',
                        sotto: riassuntoPreferenze(_preferenze),
                        onTap: () => vai(PreferenzeRicaricaSchermata(archivio: widget.archivio)),
                      ),
                    _VoceMenu(
                      key: const Key('menu-importa-google'),
                      icona: Icons.bookmarks_rounded,
                      colore: const Color(0xFFEA4335),
                      titolo: 'Importa da Google Maps',
                      sotto: salvati == 0 ? 'I posti che hai salvato, qui come preferiti' : '$salvati posti salvati',
                      onTap: () =>
                          vai(ImportaGoogleMaps(luoghi: luoghi, fonte: viaggio.luoghi, vicinoA: widget.posizione.qui)),
                    ),
                  ],
                ),
                _GruppoMenu(
                  titolo: 'Auto e collegamenti',
                  voci: [
                    if (widget.auto.elettrica)
                      _VoceMenu(
                        icona: Icons.battery_charging_full_rounded,
                        colore: const Color(0xFF0D9488),
                        titolo: 'Fonte dati auto',
                        sotto: 'Da dove arriva la batteria',
                        onTap: () {
                          Navigator.of(contesto).pop();
                          mostraFonteDatiAuto(context, widget.auto, consumo: widget.consumo);
                        },
                      ),
                    _VoceMenu(
                      icona: Icons.home_rounded,
                      colore: const Color(0xFF0EA5E9),
                      titolo: 'Home Assistant',
                      sotto: !sbloccato
                          ? 'Premium'
                          : ha == null
                          ? 'Non collegata'
                          : 'Collegata${ha.nomeAuto.isEmpty ? '' : ' a ${ha.nomeAuto}'}',
                      onTap: () => vai(
                        sbloccato
                            ? AbbinaHomeAssistant(gestore: widget.auto)
                            : SchermataPremium(premium: widget.premium!, perche: 'Home Assistant'),
                      ),
                    ),
                    _VoceMenu(
                      icona: Icons.directions_car_filled_rounded,
                      colore: const Color(0xFF475569),
                      titolo: 'Android Auto',
                      sotto: sbloccato ? 'Controlla perché non compare sull\'auto' : 'Premium',
                      onTap: () {
                        if (!sbloccato) return vai(SchermataPremium(premium: widget.premium!, perche: 'Android Auto'));
                        Navigator.of(contesto).pop();
                        mostraDiagnosiAuto(context);
                      },
                    ),
                  ],
                ),
                _GruppoMenu(
                  titolo: 'Mappe e abbonamento',
                  voci: [
                    _VoceMenu(
                      icona: Icons.download_for_offline_rounded,
                      colore: const Color(0xFF7C3AED),
                      titolo: 'Mappe offline',
                      sotto: 'Scarica le regioni per quando non c\'è rete',
                      onTap: () => vai(
                        MappeOffline(
                          gestore: widget.mappeOffline ?? GestoreMappeOffline(ArchivioMapLibre()),
                          qui: widget.posizione.qui,
                        ),
                      ),
                    ),
                    if (widget.premium case final p?)
                      _VoceMenu(
                        icona: Icons.workspace_premium_rounded,
                        colore: const Color(0xFFD97706),
                        titolo: 'Premium',
                        sotto: p.sbloccato
                            ? 'Attivo: Android Auto e Home Assistant'
                            : 'Sblocca Android Auto e Home Assistant',
                        onTap: () => vai(SchermataPremium(premium: p)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.paddingOf(context).top;
    final schermo = MediaQuery.sizeOf(context).height;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child:
                widget.mappa?.call(context, controllo) ??
                MappaViaggio(
                  gestore: viaggio,
                  controllo: controllo,
                  posizione: widget.posizione,
                  segnalazioni: segnalazioni,
                  onPuntoScelto: (p) => viaggio.vaiA(
                    Luogo(
                      nome: 'Punto sulla mappa',
                      posizione: Punto(p.latitude, p.longitude),
                      descrizione: '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                    ),
                  ),
                  onColonnina: (id) => mostraColonnina(context, viaggio, id),
                  vicini: widget.vicini,
                  onPunto: (p) => mostraPunto(
                    context,
                    p,
                    vicini: widget.vicini,
                    qui: widget.posizione.qui,
                    carburante: widget.auto.carburante,
                    onVai: (l) => viaggio.vaiA(l),
                  ),
                ),
          ),
          // In alto: il menu quadrato di Waze e la batteria.
          Positioned(
            left: 16,
            right: 16,
            top: alto + 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: 'Menu',
                  child: Vetro(
                    raggio: 18,
                    onTap: _menu,
                    child: const SizedBox.square(dimension: 60, child: Icon(Icons.menu_rounded, size: 32)),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            top: alto + 10,
            child: ListenableBuilder(
              listenable: Listenable.merge([controllo, widget.auto]),
              builder: (context, _) => Column(
                children: [
                  _BottoneMappa(
                    tooltip: controllo.inclinata ? 'Vista dall\'alto' : 'Vista 3D',
                    onPressed: controllo.alternaInclinazione,
                    child: Text(
                      controllo.inclinata ? '2D' : '3D',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _BottoneMappa(
                    tooltip: 'Dove sono',
                    onPressed: controllo.centra,
                    child: Icon(Icons.near_me_rounded, size: 28, color: Theme.of(context).colorScheme.primary),
                  ),
                  // Auto termica: i distributori qui intorno.
                  if (!widget.auto.elettrica) ...[
                    const SizedBox(height: 14),
                    BottoneDistributori(
                      onTap: () => mostraDistributori(
                        context,
                        qui: widget.posizione.qui,
                        carburante: widget.auto.carburante,
                        onScegli: (l) => viaggio.vaiA(l),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ListenableBuilder(
            listenable: viaggio,
            builder: (context, _) {
              final libero = viaggio.stato is NessunViaggio;
              return Stack(
                children: [
                  if (libero)
                    Positioned(
                      right: 16,
                      bottom: schermo * 0.5 + 14,
                      child: BottoneSegnala(onTap: () => mostraSegnala(context, segnalazioni)),
                    ),
                  Positioned.fill(
                    child: libero
                        ? PannelloPartenza(
                            luoghi: luoghi,
                            onCerca: _cerca,
                            onVai: _vai,
                            onPreferito: _preferito,
                            onNuovo: () => _imposta(TipoPreferito.altro),
                            onModificaPreferito: _modificaPreferito,
                            schedaAuto: ListenableBuilder(
                              listenable: widget.posizione,
                              builder: (context, _) => SchedaAuto(
                                auto: widget.auto,
                                segnaposto: widget.posizione.segnaposto,
                                onApriAuto: () => _apri(
                                  LaTuaAuto(auto: widget.auto, posizione: widget.posizione, consumo: widget.consumo),
                                ),
                                onFonte: () => mostraFonteDatiAuto(context, widget.auto, consumo: widget.consumo),
                                onFoto: _foto,
                                fotoCatalogo: widget.fotoAuto,
                              ),
                            ),
                          )
                        : SchedaViaggio(
                            gestore: viaggio,
                            onAvvia: _avvia,
                            soglia: _preferenze.minimoArrivo,
                            meteo: widget.meteo,
                            onCercaTappa: () => _scegli(titolo: 'Aggiungi una tappa'),
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BottoneMappa extends StatelessWidget {
  const _BottoneMappa({required this.tooltip, required this.onPressed, required this.child});

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Vetro(
      forma: BoxShape.circle,
      onTap: onPressed,
      child: SizedBox.square(dimension: 60, child: Center(child: child)),
    ),
  );
}

/// In cima al menu: la tua auto, grande, da toccare per cambiarla.
class _TestaMenu extends StatelessWidget {
  const _TestaMenu({required this.auto, required this.onTap});

  final GestoreAuto auto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final t = tema.textTheme;
    final batteria = auto.elettrica ? auto.stato?.batteria : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: tema.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: tema.colorScheme.primary, borderRadius: BorderRadius.circular(16)),
                  child: Icon(
                    auto.elettrica ? Icons.electric_car_rounded : Icons.directions_car_rounded,
                    color: tema.colorScheme.onPrimary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('La tua auto', style: t.labelLarge?.copyWith(color: tema.colorScheme.onPrimaryContainer)),
                      Text(
                        auto.elettrica ? auto.veicolo.nome : 'Auto termica',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleLarge?.copyWith(
                          color: tema.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (batteria != null)
                        Text(
                          '${batteria.round()}% di batteria',
                          style: t.bodyMedium?.copyWith(color: tema.colorScheme.onPrimaryContainer),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: tema.colorScheme.onPrimaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Un gruppo del menu: il titolo piccolo e le voci in una scheda sola.
class _GruppoMenu extends StatelessWidget {
  const _GruppoMenu({required this.titolo, required this.voci});

  final String titolo;
  final List<Widget> voci;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Text(
            titolo.toUpperCase(),
            style: tema.textTheme.labelMedium?.copyWith(
              color: tema.colorScheme.onSurfaceVariant,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Material(
          color: tema.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, v) in voci.indexed) ...[
                if (i > 0)
                  Divider(height: 1, indent: 64, color: tema.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                v,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _VoceMenu extends StatelessWidget {
  const _VoceMenu({
    super.key,
    required this.icona,
    required this.colore,
    required this.titolo,
    required this.sotto,
    required this.onTap,
  });

  final IconData icona;
  final Color colore;
  final String titolo;
  final String sotto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: colore, borderRadius: BorderRadius.circular(11)),
        child: Icon(icona, color: Colors.white, size: 22),
      ),
      title: Text(titolo, style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(sotto, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right_rounded, color: tema.colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
