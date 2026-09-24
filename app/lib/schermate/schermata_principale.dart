import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/indicatore_batteria.dart';
import '../componenti/vetro.dart';
import '../mappa/controllo_mappa.dart';
import '../mappa/mappa_viaggio.dart';
import '../stato/archivio.dart';
import '../stato/gestore_auto.dart';
import '../stato/gestore_consumo.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_luoghi.dart';
import '../stato/gestore_mappe_offline.dart';
import '../stato/gestore_segnalazioni.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_viaggio.dart';
import 'abbina_home_assistant.dart';
import 'cerca_destinazione.dart';
import 'dettaglio_colonnina.dart';
import 'diagnosi_auto.dart';
import 'fonte_dati_auto.dart';
import 'la_tua_auto.dart';
import 'mappe_offline.dart';
import 'pannello_partenza.dart';
import 'ricarica.dart';
import 'scheda_viaggio.dart';
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
    this.consumo,
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

  /// Il consumo imparato, da mostrare in «La tua auto».
  final GestoreConsumo? consumo;

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
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoceMenu(
                  icona: Icons.electric_car,
                  titolo: 'La tua auto',
                  sotto: widget.auto.veicolo.nome,
                  onTap: () => vai(LaTuaAuto(auto: widget.auto, posizione: widget.posizione, consumo: widget.consumo)),
                ),
                _VoceMenu(
                  icona: Icons.ev_station,
                  titolo: 'Ricarica',
                  sotto: riassuntoPreferenze(_preferenze),
                  onTap: () => vai(PreferenzeRicaricaSchermata(archivio: widget.archivio)),
                ),
                _VoceMenu(
                  icona: Icons.battery_charging_full,
                  titolo: 'Fonte dati auto',
                  sotto: 'Da dove arriva la batteria',
                  onTap: () {
                    Navigator.of(contesto).pop();
                    mostraFonteDatiAuto(context, widget.auto);
                  },
                ),
                _VoceMenu(
                  icona: Icons.home_outlined,
                  titolo: 'Home Assistant',
                  sotto: ha == null ? 'Non collegata' : 'Collegata${ha.nomeAuto.isEmpty ? '' : ' a ${ha.nomeAuto}'}',
                  onTap: () => vai(AbbinaHomeAssistant(gestore: widget.auto)),
                ),
                _VoceMenu(
                  icona: Icons.offline_pin_outlined,
                  titolo: 'Mappe offline',
                  sotto: 'Scarica le regioni per quando non c\'è rete',
                  onTap: () => vai(
                    MappeOffline(
                      gestore: widget.mappeOffline ?? GestoreMappeOffline(ArchivioMapLibre()),
                      qui: widget.posizione.qui,
                    ),
                  ),
                ),
                _VoceMenu(
                  icona: Icons.directions_car_filled_outlined,
                  titolo: 'Android Auto',
                  sotto: 'Controlla perché non compare sull\'auto',
                  onTap: () {
                    Navigator.of(contesto).pop();
                    mostraDiagnosiAuto(context);
                  },
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
                const SizedBox(width: 12),
                Flexible(
                  child: ListenableBuilder(
                    listenable: widget.auto,
                    builder: (context, _) =>
                        IndicatoreBatteria(auto: widget.auto, onTap: () => mostraFonteDatiAuto(context, widget.auto)),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 16,
            top: alto + 86,
            child: ListenableBuilder(
              listenable: controllo,
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
                      bottom: schermo * 0.36 + 14,
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
                          )
                        : SchedaViaggio(gestore: viaggio, onAvvia: _avvia, soglia: _preferenze.minimoArrivo),
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

class _VoceMenu extends StatelessWidget {
  const _VoceMenu({required this.icona, required this.titolo, required this.sotto, required this.onTap});

  final IconData icona;
  final String titolo;
  final String sotto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: s.primaryContainer,
        child: Icon(icona, color: s.onPrimaryContainer),
      ),
      title: Text(titolo, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(sotto, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
