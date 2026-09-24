import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/indicatore_batteria.dart';
import '../componenti/vetro.dart';
import '../mappa/controllo_mappa.dart';
import '../mappa/mappa_viaggio.dart';
import '../stato/archivio.dart';
import '../stato/gestore_auto.dart';
import '../stato/gestore_guida.dart';
import '../stato/gestore_posizione.dart';
import '../stato/gestore_viaggio.dart';
import 'abbina_home_assistant.dart';
import 'cerca_destinazione.dart';
import 'dettaglio_colonnina.dart';
import 'fonte_dati_auto.dart';
import 'impostazioni.dart';
import 'la_tua_auto.dart';
import 'ricarica.dart';
import 'scheda_viaggio.dart';
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
  });

  final GestoreAuto auto;
  final GestoreViaggio viaggio;
  final Archivio archivio;
  final GestoreGuida guida;
  final GestorePosizione posizione;

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

  GestoreViaggio get viaggio => widget.viaggio;

  @override
  void initState() {
    super.initState();
    _ricaricaPreferenze();
    widget.chiediPosizione?.call().then((ok) {
      if (ok) widget.posizione.avvia();
    });
  }

  void _avvia() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SchermataGuida(guida: widget.guida, posizione: widget.posizione, mappa: widget.mappa),
    ),
  );

  @override
  void dispose() {
    controllo.dispose();
    super.dispose();
  }

  Future<void> _ricaricaPreferenze() async {
    final p = await widget.archivio.preferenze();
    if (mounted) setState(() => _preferenze = p);
  }

  Future<void> _cerca() async {
    final luogo = await Navigator.of(context).push<Luogo>(
      MaterialPageRoute(
        builder: (_) => CercaDestinazione(luoghi: viaggio.luoghi, vicinoA: viaggio.ultimaPosizione),
      ),
    );
    if (luogo != null) await viaggio.vaiA(luogo);
  }

  Future<void> _apri(Widget schermata) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => schermata));
    await _ricaricaPreferenze();
    // Auto o preferenze cambiate: il viaggio aperto si ricalcola.
    if (viaggio.stato is ViaggioPronto && viaggio.destinazione != null) await viaggio.pianifica(viaggio.destinazione!);
  }

  void _impostazioni() => _apri(SchermataImpostazioni(archivio: widget.archivio));

  void _menu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (contesto) {
        void vai(Widget w) {
          Navigator.of(contesto).pop();
          _apri(w);
        }

        final ha = widget.auto.abbinamento;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _VoceMenu(
                icona: Icons.electric_car,
                titolo: 'La tua auto',
                sotto: widget.auto.veicolo.nome,
                onTap: () => vai(LaTuaAuto(auto: widget.auto, posizione: widget.posizione)),
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
                icona: Icons.dns_outlined,
                titolo: 'Servizi',
                sotto: 'Server dei percorsi e colonnine',
                onTap: () => vai(SchermataImpostazioni(archivio: widget.archivio)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Vetro(
                    raggio: 28,
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
                            onTap: _cerca,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
                              child: Row(
                                children: [
                                  Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      'Dove vuoi andare?',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(tooltip: 'Menu', icon: const Icon(Icons.menu), onPressed: _menu),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListenableBuilder(
                    listenable: widget.auto,
                    builder: (context, _) =>
                        IndicatoreBatteria(auto: widget.auto, onTap: () => mostraFonteDatiAuto(context, widget.auto)),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: MediaQuery.paddingOf(context).top + 150,
            child: ListenableBuilder(
              listenable: controllo,
              builder: (context, _) => Column(
                children: [
                  _BottoneMappa(
                    tooltip: controllo.inclinata ? 'Vista dall\'alto' : 'Vista 3D',
                    onPressed: controllo.alternaInclinazione,
                    child: Text(
                      controllo.inclinata ? '2D' : '3D',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BottoneMappa(
                    tooltip: 'Dove sono',
                    onPressed: controllo.centra,
                    child: Icon(Icons.my_location, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: SchedaViaggio(
              gestore: viaggio,
              apriImpostazioni: _impostazioni,
              onAvvia: _avvia,
              soglia: _preferenze.minimoArrivo,
            ),
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
      child: SizedBox.square(dimension: 48, child: Center(child: child)),
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
