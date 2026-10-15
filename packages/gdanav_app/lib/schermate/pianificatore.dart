import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart' show Luogo;

import '../stato/viaggi_pianificati.dart';
import '../tema.dart';

/* ─── Il Pianificatore ─────────────────────────────────────────────────
 *
 * Le schermate approvate nelle fotografie (`test/foto/pianificatore_foto.dart`):
 * l'elenco dei viaggi, un viaggio programmato, un giro a tappe e un viaggio
 * di ogni settimana. Dentro gdahome i viaggi stanno nella casa, che avvisa
 * quando partire e accende il clima dell'auto; sono gli stessi della pagina
 * gdanav della plancia, da PC. In gdanav da sola stanno nel telefono. In
 * auto compaiono in cima a «Dove andiamo?». */

/// Sceglie un posto (la ricerca di gdanav, coi preferiti).
typedef ScegliPosto = Future<Luogo?> Function(String titolo);

/// Parte un viaggio pianificato adesso, con le sue tappe.
typedef AvviaViaggio = Future<void> Function(ViaggioPianificato viaggio);

/* ─── i pezzi ─────────────────────────────────────────────────────────── */

class _Scheda extends StatelessWidget {
  const _Scheda({required this.child, this.colore});
  final Widget child;
  final Color? colore;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colore ?? t.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

class _Titoletto extends StatelessWidget {
  const _Titoletto(this.testo);
  final String testo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Text(
      testo.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Pastiglia extends StatelessWidget {
  const _Pastiglia(this.testo, this.icona, this.colore);
  final String testo;
  final IconData icona;
  final Color colore;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: colore.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icona, size: 15, color: colore),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            testo,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colore),
          ),
        ),
      ],
    ),
  );
}

class _Tondo extends StatelessWidget {
  const _Tondo(this.icona, this.colore, {this.lato = 44});
  final IconData icona;
  final Color colore;
  final double lato;

  @override
  Widget build(BuildContext context) => Container(
    width: lato,
    height: lato,
    decoration: BoxDecoration(color: colore.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
    child: Icon(icona, color: colore, size: lato * 0.55),
  );
}

/// Un campo da scegliere: etichetta a sinistra, valore a destra.
class _Campo extends StatelessWidget {
  const _Campo(this.icona, this.etichetta, this.valore, {this.forte = false, this.onTap, super.key});
  final IconData icona;
  final String etichetta;
  final String valore;
  final bool forte;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icona, size: 22, color: t.colorScheme.primary),
            const SizedBox(width: 12),
            Text(etichetta, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                valore,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: forte ? 20 : 16,
                  fontWeight: forte ? FontWeight.w800 : FontWeight.w600,
                  color: forte ? t.colorScheme.primary : null,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Il riquadro che dice quando partire.
class _QuandoPartire extends StatelessWidget {
  const _QuandoPartire({required this.titolo, required this.ora, required this.righe});
  final String titolo;
  final String ora;
  final List<(IconData, String, Color?)> righe;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = ColoriGdanav.di(context);
    return _Scheda(
      colore: c.percorso.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titolo,
            style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          Text(
            ora,
            style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: c.percorso, height: 1.1),
          ),
          const SizedBox(height: 8),
          for (final (icona, testo, colore) in righe)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icona, size: 18, color: colore ?? t.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(testo, style: const TextStyle(fontSize: 15))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Interruttore extends StatelessWidget {
  const _Interruttore(this.icona, this.titolo, this.sotto, this.acceso, this.onChanged);
  final IconData icona;
  final String titolo;
  final String sotto;
  final bool acceso;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icona, color: onChanged == null ? t.disabledColor : t.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titolo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text(sotto, style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: acceso, onChanged: onChanged),
        ],
      ),
    );
  }
}

Widget _tastone(Widget child) => SafeArea(
  child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: child),
);

IconData _iconaDel(TipoViaggioPianificato t) => switch (t) {
  TipoViaggioPianificato.una => Icons.event_rounded,
  TipoViaggioPianificato.settimana => Icons.repeat_rounded,
  TipoViaggioPianificato.tappe => Icons.alt_route_rounded,
};

Color _coloreDel(TipoViaggioPianificato t, ColoriGdanav c) => switch (t) {
  TipoViaggioPianificato.una => c.percorso,
  TipoViaggioPianificato.settimana => c.libera,
  TipoViaggioPianificato.tappe => c.ignota,
};

/* ─── l'elenco ─────────────────────────────────────────────────────────── */

class SchermataPianificatore extends StatefulWidget {
  const SchermataPianificatore({
    super.key,
    required this.gestore,
    required this.scegli,
    required this.avvia,
    this.premium,
  });

  final GestoreViaggiPianificati gestore;
  final ScegliPosto scegli;
  final AvviaViaggio avvia;

  /// Apre Premium, quando il pianificatore è chiuso. `null`: si dice e basta.
  final VoidCallback? premium;

  @override
  State<SchermataPianificatore> createState() => _SchermataPianificatoreState();
}

class _SchermataPianificatoreState extends State<SchermataPianificatore> {
  GestoreViaggiPianificati get g => widget.gestore;

  @override
  void initState() {
    super.initState();
    unawaited(g.carica());
  }

  Future<void> _nuovo() async {
    final tipo = await showModalBottomSheet<TipoViaggioPianificato>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (tipo, titolo, sotto) in const [
              (TipoViaggioPianificato.una, 'Viaggio programmato', 'Un giorno, con l\'ora di arrivo o di partenza'),
              (TipoViaggioPianificato.settimana, 'Ogni settimana', 'Casa – Lavoro, nei giorni che scegli'),
              (TipoViaggioPianificato.tappe, 'Giro a tappe', 'Più fermate, con le soste'),
            ])
              ListTile(
                key: Key('nuovo-${tipo.name}'),
                leading: _Tondo(_iconaDel(tipo), _coloreDel(tipo, ColoriGdanav.di(c)), lato: 40),
                title: Text(titolo, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(sotto),
                onTap: () => Navigator.of(c).pop(tipo),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (tipo == null || !mounted) return;
    await _apri(ViaggioPianificato.nuovo(tipo, g.adesso));
  }

  Future<void> _apri(ViaggioPianificato v) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ModificaViaggio(gestore: g, iniziale: v, scegli: widget.scegli, avvia: widget.avvia),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: g,
      builder: (context, _) {
        final c = ColoriGdanav.di(context);
        final t = Theme.of(context);
        final adesso = g.adesso;
        final una = g.viaggi.where((v) => v.tipo == TipoViaggioPianificato.una).toList();
        final settimana = g.viaggi.where((v) => v.tipo == TipoViaggioPianificato.settimana).toList();
        final tappe = g.viaggi.where((v) => v.tipo == TipoViaggioPianificato.tappe).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Pianificatore')),
          body: RefreshIndicator(
            onRefresh: g.carica,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (!g.sbloccato)
                  _Scheda(
                    colore: t.colorScheme.tertiaryContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.workspace_premium_rounded, color: t.colorScheme.onTertiaryContainer),
                            const SizedBox(width: 8),
                            Text(
                              'Il pianificatore è con Premium',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: t.colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Viaggi programmati, di ogni settimana e a tappe, con l\'avviso quando partire e '
                          'l\'elenco anche su CarPlay e Android Auto.',
                          style: TextStyle(color: t.colorScheme.onTertiaryContainer),
                        ),
                        if (widget.premium != null) ...[
                          const SizedBox(height: 10),
                          FilledButton(onPressed: widget.premium, child: const Text('Scopri Premium')),
                        ],
                      ],
                    ),
                  ),
                if (g.errore case final e?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(e, style: TextStyle(color: t.colorScheme.error)),
                  ),
                if (g.viaggi.isEmpty && !g.caricando && g.sbloccato)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
                    child: Column(
                      children: [
                        _Tondo(Icons.event_rounded, c.percorso, lato: 64),
                        const SizedBox(height: 14),
                        const Text(
                          'Nessun viaggio pianificato',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          g.fonte.dellaCasa
                              ? 'Scrivi dove devi arrivare e a che ora: ti dico quando partire. Li trovi anche '
                                    'nella pagina gdanav della plancia, da PC, e in auto.'
                              : 'Scrivi dove devi arrivare e a che ora: ti dico quando partire. Li trovi anche '
                                    'su CarPlay e Android Auto.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: t.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                if (una.isNotEmpty) ...[
                  const _Titoletto('Prossimi'),
                  for (final v in una)
                    _RigaViaggio(v, adesso: adesso, dellaCasa: g.fonte.dellaCasa, onTap: () => _apri(v)),
                ],
                if (settimana.isNotEmpty) ...[
                  const _Titoletto('Ogni settimana'),
                  for (final v in settimana)
                    _RigaViaggio(v, adesso: adesso, dellaCasa: g.fonte.dellaCasa, onTap: () => _apri(v)),
                ],
                if (tappe.isNotEmpty) ...[
                  const _Titoletto('Giri salvati'),
                  for (final v in tappe)
                    _RigaViaggio(v, adesso: adesso, dellaCasa: g.fonte.dellaCasa, onTap: () => _apri(v)),
                ],
              ],
            ),
          ),
          bottomNavigationBar: _tastone(
            FilledButton.icon(
              key: const Key('pianificatore-nuovo'),
              onPressed: g.sbloccato ? _nuovo : widget.premium,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuovo viaggio'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            ),
          ),
        );
      },
    );
  }
}

/// Una riga dell'elenco dei viaggi.
class _RigaViaggio extends StatelessWidget {
  const _RigaViaggio(this.v, {required this.adesso, required this.dellaCasa, required this.onTap});
  final ViaggioPianificato v;
  final DateTime adesso;
  final bool dellaCasa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = ColoriGdanav.di(context);
    final p = v.prossima;
    final durata = durataDelViaggio(v, adesso);
    final dettagli = <Widget>[
      if (p != null && p.stimata && v.tipo != TipoViaggioPianificato.tappe)
        _Pastiglia(
          v.tipo == TipoViaggioPianificato.settimana
              ? '${giornoParlato(p.partenza, adesso)} alle ${oraDetta(p.partenza)}'
              : 'Parti alle ${oraDetta(p.partenza)}',
          Icons.schedule_rounded,
          c.percorso,
        ),
      if (durata != null) _Pastiglia(durataDetta(durata), Icons.timer_outlined, c.percorso),
      if (v.stima?.km case final km?) _Pastiglia('${km.round()} km', Icons.straighten_rounded, c.percorso),
      if (v.stima case final s? when s.frescaAlle(adesso)) _Pastiglia('col traffico', Icons.traffic_rounded, c.piena),
      if (dellaCasa && v.clima != null) _Pastiglia('clima acceso prima', Icons.ac_unit_rounded, c.ignota),
    ];
    final avviso = dellaCasa && v.avviso && p != null && p.partenza.isAfter(adesso)
        ? p.partenza.subtract(Duration(minutes: v.avvisoMin))
        : null;
    return GestureDetector(
      onTap: onTap,
      child: _Scheda(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Tondo(_iconaDel(v.tipo), _coloreDel(v.tipo, c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.titolo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(quandoDetto(v, adesso), style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: t.colorScheme.onSurfaceVariant),
              ],
            ),
            if (dettagli.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: dettagli),
            ],
            if (avviso != null && v.tipo == TipoViaggioPianificato.una) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_rounded, size: 20, color: t.colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        v.avvisoMin == 0
                            ? 'Ti avviso alle ${oraDetta(avviso)}, quando è ora di partire'
                            : 'Ti avviso alle ${oraDetta(avviso)}, ${v.avvisoMin} minuti prima di partire',
                        style: TextStyle(fontWeight: FontWeight.w600, color: t.colorScheme.onPrimaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/* ─── un viaggio, da scrivere ──────────────────────────────────────────── */

class ModificaViaggio extends StatefulWidget {
  const ModificaViaggio({
    super.key,
    required this.gestore,
    required this.iniziale,
    required this.scegli,
    required this.avvia,
  });

  final GestoreViaggiPianificati gestore;
  final ViaggioPianificato iniziale;
  final ScegliPosto scegli;
  final AvviaViaggio avvia;

  @override
  State<ModificaViaggio> createState() => _ModificaViaggioState();
}

class _ModificaViaggioState extends State<ModificaViaggio> {
  late ViaggioPianificato v = widget.iniziale;
  var _stimando = false;
  var _salvando = false;
  int _giro = 0;

  GestoreViaggiPianificati get g => widget.gestore;
  bool get dellaCasa => g.fonte.dellaCasa;

  @override
  void initState() {
    super.initState();
    if (v.stima == null || !(v.stima!.frescaAlle(g.adesso))) unawaited(_stima());
  }

  void _cambia(ViaggioPianificato nuovo, {bool strada = false}) {
    setState(() => v = strada ? nuovo.copia(stima: () => null) : nuovo);
    if (strada) unawaited(_stima());
  }

  /// La strada si ricalcola quando cambiano partenza o tappe; vale l'ultima.
  Future<void> _stima() async {
    if (v.tappe.isEmpty) return;
    final giro = ++_giro;
    setState(() => _stimando = true);
    final s = await g.stimaPer(v);
    if (!mounted || giro != _giro) return;
    setState(() {
      _stimando = false;
      if (s != null) v = v.copia(stima: () => s);
    });
  }

  Future<void> _salva() async {
    if (v.tappe.isEmpty) {
      _di(v.tipo == TipoViaggioPianificato.tappe ? 'Aggiungi almeno una tappa.' : 'Scegli dove vuoi andare.');
      return;
    }
    setState(() => _salvando = true);
    try {
      await g.salva(v);
      if (mounted) Navigator.of(context).pop();
    } on ErroreViaggi catch (e) {
      _di(e.messaggio);
    } catch (_) {
      _di('Non sono riuscito a salvare. Riprova.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _togli() async {
    final si = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Togliere il viaggio?'),
        content: Text('«${v.titolo}» non ci sarà più, nemmeno in auto e sulla plancia.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Togli')),
        ],
      ),
    );
    if (si != true) return;
    try {
      await g.togli(v);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _di('Non sono riuscito a toglierlo. Riprova.');
    }
  }

  Future<void> _avvia() async {
    if (v.tappe.isEmpty) return _di('Scegli dove vuoi andare.');
    final nav = Navigator.of(context);
    await widget.avvia(v);
    if (mounted) nav.popUntil((r) => r.isFirst);
  }

  void _di(String testo) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(testo)));
  }

  /* ── le scelte ── */

  Future<void> _meta() async {
    final l = await widget.scegli('Dove vuoi arrivare?');
    if (l == null) return;
    _cambia(v.copia(tappe: [PostoPianificato(l)]), strada: true);
  }

  Future<void> _partenza() async {
    final scelta = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.my_location_rounded),
              title: const Text('Da dove sono'),
              subtitle: const Text('Quando parto, dalla posizione del telefono'),
              onTap: () => Navigator.of(c).pop(0),
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: const Text('Scegli un posto'),
              onTap: () => Navigator.of(c).pop(1),
            ),
          ],
        ),
      ),
    );
    if (scelta == null) return;
    if (scelta == 0) return _cambia(v.copia(da: () => null), strada: true);
    final l = await widget.scegli('Da dove parti?');
    if (l != null) _cambia(v.copia(da: () => PostoPianificato(l)), strada: true);
  }

  Future<void> _giorno() async {
    final adesso = g.adesso;
    final oggi = DateTime(adesso.year, adesso.month, adesso.day);
    final ora = DateTime.tryParse(v.giorno ?? '') ?? oggi.add(const Duration(days: 1));
    final d = await showDatePicker(
      context: context,
      initialDate: ora.isBefore(oggi) ? oggi : ora,
      firstDate: oggi,
      lastDate: oggi.add(const Duration(days: 365)),
    );
    if (d != null) _cambia(v.copia(giorno: () => giornoDetto(d)));
  }

  Future<void> _ora() async {
    final m = oraBuona.firstMatch(v.ora);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(m?[1] ?? '9'), minute: int.parse(m?[2] ?? '0')),
      builder: (c, figlio) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: figlio!),
    );
    if (t == null) return;
    _cambia(v.copia(ora: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'));
  }

  Future<void> _nome() async {
    final c = TextEditingController(text: v.nome);
    final nome = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Nome del viaggio'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(hintText: v.titolo),
          onSubmitted: (s) => Navigator.of(d).pop(s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.of(d).pop(c.text), child: const Text('Ok')),
        ],
      ),
    );
    if (nome != null) _cambia(v.copia(nome: nome.trim()));
  }

  Future<void> _aggiungiTappa() async {
    if (v.tappe.length >= tappeAlPiu) return _di('Al più $tappeAlPiu tappe.');
    final l = await widget.scegli('Aggiungi una tappa');
    if (l == null) return;
    // La nuova va prima dell'ultima se l'ultima è dove si torna (la partenza).
    _cambia(v.copia(tappe: [...v.tappe, PostoPianificato(l, sostaMin: 15)]), strada: true);
  }

  Future<void> _sosta(int i) async {
    const scelte = [0, 5, 10, 15, 20, 30, 45, 60, 90, 120];
    final m = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Sosta a ${v.tappe[i].nome}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (final s in scelte)
                ListTile(
                  title: Text(s == 0 ? 'Solo passaggio' : durataDetta(Duration(minutes: s))),
                  trailing: s == v.tappe[i].sostaMin ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.of(c).pop(s),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Togli la tappa'),
                onTap: () => Navigator.of(c).pop(-1),
              ),
            ],
          ),
        ),
      ),
    );
    if (m == null) return;
    final tappe = List.of(v.tappe);
    if (m < 0) {
      tappe.removeAt(i);
      return _cambia(v.copia(tappe: tappe), strada: true);
    }
    tappe[i] = tappe[i].conSosta(m);
    _cambia(v.copia(tappe: tappe));
  }

  /* ── le parti ── */

  /// «Parti alle»: con la stima, l'ora in cui partire (o arrivare).
  Widget _quandoPartire(ColoriGdanav c) {
    final adesso = g.adesso;
    final p = prossimaVolta(v, adesso);
    final durata = durataDelViaggio(v, adesso);
    final s = v.stima;
    final righe = <(IconData, String, Color?)>[];
    if (v.tappe.isEmpty) {
      righe.add((Icons.place_outlined, 'Scegli la meta: ti dico a che ora partire.', null));
    } else if (_stimando) {
      righe.add((Icons.hourglass_top_rounded, 'Calcolo la strada…', null));
    } else if (s == null || durata == null) {
      righe.add((Icons.cloud_off_rounded, 'Non riesco a calcolare la strada adesso: riprovo prima di partire.', null));
    } else {
      final guida = durataDetta(s.durata);
      righe.add(
        s.frescaAlle(adesso)
            ? (Icons.traffic_rounded, 'Col traffico di adesso: $guida', c.piena)
            : (Icons.route_rounded, 'Senza traffico $guida, più un margine del 15%', null),
      );
      if (s.km case final km?) righe.add((Icons.straighten_rounded, '${km.round()} km', null));
      final soste = v.tappe.isEmpty ? 0 : v.tappe.sublist(0, v.tappe.length - 1).fold<int>(0, (t, x) => t + x.sostaMin);
      if (soste > 0) righe.add((Icons.local_cafe_outlined, 'Soste: ${durataDetta(Duration(minutes: soste))}', null));
      righe.add((
        Icons.update_rounded,
        dellaCasa
            ? (v.tipo == TipoViaggioPianificato.settimana
                  ? 'Ogni volta ti dico l\'ora giusta, col traffico di quel giorno'
                  : 'Lo ricalcolo col traffico prima di partire')
            : 'Lo ricalcolo col traffico quando apri gdanav',
        null,
      ));
    }
    final titolo = v.dicePartenza ? 'Arrivi alle' : 'Parti alle';
    final ora = p == null || durata == null || v.tappe.isEmpty
        ? '—'
        : v.dicePartenza
        ? oraDetta(p.arrivo)
        : oraDetta(p.partenza);
    return _QuandoPartire(titolo: titolo, ora: ora, righe: righe);
  }

  Widget _avvisi() {
    final sottoAvviso = !dellaCasa
        ? 'Gli avvisi arrivano con gdahome'
        : v.avvisoMin == 0
        ? 'Quando è ora di partire'
        : '${v.avvisoMin} minuti prima di partire';
    return _Scheda(
      child: Column(
        children: [
          _Interruttore(
            Icons.notifications_rounded,
            'Avvisami prima',
            sottoAvviso,
            dellaCasa && v.avviso,
            dellaCasa ? (si) => _cambia(v.copia(avviso: si)) : null,
          ),
          if (dellaCasa && v.clima != null)
            _Interruttore(
              Icons.ac_unit_rounded,
              'Prepara l\'auto',
              'Clima acceso ${v.climaMin} min prima (gdahome)',
              true,
              (_) => _cambia(v.copia(clima: () => null)),
            ),
          if (dellaCasa && v.garage != null)
            _Interruttore(
              Icons.garage_rounded,
              'Apri il garage',
              'Il tasto nell\'avviso: si apre solo se lo premi',
              true,
              (_) => _cambia(v.copia(garage: () => null)),
            ),
          if (dellaCasa && (v.clima == null || v.garage == null))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Il clima dell\'auto e il garage si scelgono nella pagina gdanav della plancia.',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _arrivoOPartenza() => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(value: true, label: Text('Arrivo entro')),
      ButtonSegment(value: false, label: Text('Parto alle')),
    ],
    selected: {v.arrivoEntro},
    onSelectionChanged: (s) => _cambia(v.copia(arrivoEntro: s.first)),
  );

  String get _daDetto => v.da?.nome ?? 'Da dove sono';
  String get _giornoDetto {
    final d = DateTime.tryParse(v.giorno ?? '');
    if (d == null) return 'Scegli';
    final parlato = giornoParlato(d, g.adesso);
    final lungo = giornoLungo(d);
    return parlato == 'Oggi' || parlato == 'Domani' ? '$parlato, ${lungo.substring(0, 3)} ${d.day}' : lungo;
  }

  String get _oraDetta => v.ora.startsWith('0') ? v.ora.substring(1) : v.ora;

  List<Widget> _programmato(ColoriGdanav c) => [
    _arrivoOPartenza(),
    const SizedBox(height: 12),
    _Scheda(
      child: Column(
        children: [
          _Campo(Icons.place_rounded, 'Dove', v.meta?.nome ?? 'Scegli', onTap: _meta, key: const Key('campo-dove')),
          const Divider(height: 1),
          _Campo(Icons.trip_origin_rounded, 'Da', _daDetto, onTap: _partenza),
          const Divider(height: 1),
          _Campo(Icons.calendar_today_rounded, 'Quando', _giornoDetto, onTap: _giorno),
          const Divider(height: 1),
          _Campo(
            Icons.flag_rounded,
            v.arrivoEntro ? 'Arrivo entro' : 'Parto alle',
            _oraDetta,
            forte: true,
            onTap: _ora,
          ),
        ],
      ),
    ),
    _quandoPartire(c),
    _avvisi(),
  ];

  List<Widget> _ricorrente(ColoriGdanav c) {
    final t = Theme.of(context);
    return [
      const _Titoletto('Quali giorni'),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 1; i <= 7; i++)
            InkWell(
              key: Key('giorno-$i'),
              customBorder: const CircleBorder(),
              onTap: () {
                final giorni = v.giorni.contains(i) ? [...v.giorni.where((g) => g != i)] : [...v.giorni, i]
                  ..sort();
                if (giorni.isNotEmpty) _cambia(v.copia(giorni: giorni));
              },
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: v.giorni.contains(i) ? t.colorScheme.primary : t.colorScheme.surfaceContainerHigh,
                ),
                child: Text(
                  const ['L', 'M', 'M', 'G', 'V', 'S', 'D'][i - 1],
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: v.giorni.contains(i) ? t.colorScheme.onPrimary : t.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      _arrivoOPartenza(),
      const SizedBox(height: 12),
      _Scheda(
        child: Column(
          children: [
            _Campo(Icons.home_rounded, 'Da', _daDetto, onTap: _partenza),
            const Divider(height: 1),
            _Campo(Icons.work_rounded, 'A', v.meta?.nome ?? 'Scegli', onTap: _meta, key: const Key('campo-dove')),
            const Divider(height: 1),
            _Campo(
              Icons.flag_rounded,
              v.arrivoEntro ? 'Arrivo entro' : 'Parto alle',
              _oraDetta,
              forte: true,
              onTap: _ora,
            ),
          ],
        ),
      ),
      _quandoPartire(c),
      if (dellaCasa) const _Titoletto('Con gdahome'),
      _avvisi(),
    ];
  }

  List<Widget> _aTappe(ColoriGdanav c) {
    final t = Theme.of(context);
    final adesso = g.adesso;
    final p = prossimaVolta(v, adesso);
    final durata = durataDelViaggio(v, adesso);
    Widget tappa(
      String ora,
      String nome,
      String sotto, {
      IconData icona = Icons.place_rounded,
      Color? colore,
      VoidCallback? onTap,
      bool ultima = false,
    }) => InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(ora, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          Column(
            children: [
              _Tondo(icona, colore ?? c.percorso, lato: 34),
              if (!ultima) Container(width: 3, height: 26, color: t.colorScheme.outlineVariant),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(sotto, style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (v.stima?.km case final km?) _Pastiglia('${km.round()} km', Icons.straighten_rounded, c.percorso),
          if (durata != null) _Pastiglia(durataDetta(durata), Icons.schedule_rounded, c.percorso),
          if (_stimando) _Pastiglia('calcolo la strada…', Icons.hourglass_top_rounded, c.ignota),
        ],
      ),
      const SizedBox(height: 14),
      _Scheda(
        child: Column(
          children: [
            _Campo(Icons.calendar_today_rounded, 'Quando', _giornoDetto, onTap: _giorno),
            const Divider(height: 1),
            _Campo(Icons.schedule_rounded, 'Parto alle', _oraDetta, forte: true, onTap: _ora),
          ],
        ),
      ),
      _Scheda(
        child: Column(
          children: [
            tappa(
              p == null ? '' : oraDetta(p.partenza),
              _daDetto,
              'Partenza',
              icona: Icons.home_rounded,
              colore: c.libera,
              onTap: _partenza,
              ultima: v.tappe.isEmpty,
            ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (da, a) {
                final tappe = List.of(v.tappe);
                final x = tappe.removeAt(da);
                tappe.insert(a, x);
                _cambia(v.copia(tappe: tappe), strada: true);
              },
              children: [
                for (var i = 0; i < v.tappe.length; i++)
                  Row(
                    key: ValueKey('tappa-$i-${v.tappe[i].nome}'),
                    children: [
                      Expanded(
                        child: tappa(
                          i == v.tappe.length - 1 && p != null && durata != null ? oraDetta(p.arrivo) : '',
                          v.tappe[i].nome,
                          i == v.tappe.length - 1
                              ? 'Arrivo'
                              : v.tappe[i].sostaMin == 0
                              ? 'Solo passaggio'
                              : 'Sosta ${durataDetta(Duration(minutes: v.tappe[i].sostaMin))}',
                          icona: i == v.tappe.length - 1 ? Icons.flag_rounded : Icons.place_rounded,
                          colore: i == v.tappe.length - 1 ? c.arrivo : null,
                          onTap: () => _sosta(i),
                          ultima: i == v.tappe.length - 1,
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.drag_handle_rounded, color: t.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
      OutlinedButton.icon(
        key: const Key('aggiungi-tappa'),
        onPressed: _aggiungiTappa,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Aggiungi una tappa'),
      ),
      const SizedBox(height: 8),
      Text(
        'Trascina le tappe per cambiare l\'ordine; toccane una per la sosta. Il giro si avvia anche da CarPlay e '
        'Android Auto.',
        style: TextStyle(fontSize: 13, color: t.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 12),
      _avvisi(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = ColoriGdanav.di(context);
    final esiste = v.id != null;
    final titolo = switch (v.tipo) {
      _ when v.nome.isNotEmpty || v.meta != null => v.titolo,
      TipoViaggioPianificato.una => 'Viaggio programmato',
      TipoViaggioPianificato.settimana => 'Ogni settimana',
      TipoViaggioPianificato.tappe => 'Giro a tappe',
    };
    final salva = FilledButton(
      key: const Key('salva-viaggio'),
      onPressed: _salvando ? null : _salva,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
      child: Text(v.tipo == TipoViaggioPianificato.tappe ? 'Salva il giro' : 'Salva il viaggio'),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(titolo),
        actions: [
          IconButton(icon: const Icon(Icons.edit_rounded), tooltip: 'Nome', onPressed: _nome),
          if (esiste) IconButton(icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Togli', onPressed: _togli),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: switch (v.tipo) {
          TipoViaggioPianificato.una => _programmato(c),
          TipoViaggioPianificato.settimana => _ricorrente(c),
          TipoViaggioPianificato.tappe => _aTappe(c),
        },
      ),
      bottomNavigationBar: _tastone(
        Row(
          children: [
            Expanded(child: salva),
            if (v.tappe.isNotEmpty) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('avvia-viaggio'),
                  onPressed: _avvia,
                  icon: const Icon(Icons.navigation_rounded),
                  label: const Text('Avvia ora'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
