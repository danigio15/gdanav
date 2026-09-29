import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../stato/gestore_ztl.dart';

/// Il cartello della ZTL: tondo bianco, bordo rosso, «ZTL» nel mezzo.
class CartelloZtl extends StatelessWidget {
  const CartelloZtl({super.key, this.lato = 40});

  final double lato;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: lato,
    child: CustomPaint(painter: _PittoreCartello()),
  );
}

class _PittoreCartello extends CustomPainter {
  @override
  void paint(Canvas c, Size s) => _cartello(c, s.shortestSide);

  @override
  bool shouldRepaint(_PittoreCartello old) => false;
}

void _cartello(Canvas c, double lato) {
  final centro = Offset(lato / 2, lato / 2);
  c.drawCircle(centro, lato / 2, Paint()..color = const Color(0xFFD93025));
  c.drawCircle(centro, lato / 2 * 0.78, Paint()..color = Colors.white);
  final testo = TextPainter(
    text: TextSpan(
      text: 'ZTL',
      style: TextStyle(fontSize: lato * 0.27, fontWeight: FontWeight.w900, color: const Color(0xFF111111)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  testo.paint(c, centro - Offset(testo.width / 2, testo.height / 2));
}

/// Il cartello per lo schermo dell'auto, in PNG (`segnala-ztl`).
Future<Uint8List> cartelloZtlPng({double lato = 40, double scala = 3}) async {
  final registro = ui.PictureRecorder();
  final c = Canvas(registro)..scale(scala);
  _cartello(c, lato);
  final img = await registro.endRecording().toImage((lato * scala).round(), (lato * scala).round());
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

/// Cosa fa il percorso con le ZTL e le aree pedonali, in pastiglie: «⛔
/// Evita la ZTL Centro storico», «🚶 1 area pedonale».
class RigaZtl extends StatelessWidget {
  const RigaZtl({super.key, required this.ztl});

  final ZtlDelViaggio ztl;

  @override
  Widget build(BuildContext context) {
    final z = ztl;
    final pastiglie = <Widget>[
      if (z.metaDentro case final m?) _Pastiglia(rossa: true, testo: '⛔ La meta è nella ${m.titolo}: ti porto al varco'),
      // Quella di cui si chiede il permesso la dice già la domanda.
      for (final e in _unaPerNome(z.evitate))
        if (e.chiave != z.daChiedere?.chiave) _Pastiglia(rossa: true, testo: '⛔ Evita la ${e.titolo}'),
      for (final e in _unaPerNome(z.nonEvitate))
        _Pastiglia(rossa: true, testo: '⚠️ Entra nella ${e.titolo}: non c\'era un\'altra strada'),
      for (final e in _unaPerNome(z.attraversate)) _Pastiglia(testo: '✅ Nella ${e.titolo} col permesso'),
      if (z.pedonali.isNotEmpty)
        _Pastiglia(testo: z.pedonali.length == 1 ? '🚶 1 area pedonale' : '🚶 ${z.pedonali.length} aree pedonali'),
    ];
    if (pastiglie.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('riga-ztl'),
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 6, children: pastiglie),
    );
  }

  /// Una ZTL fatta di più pezzi si dice una volta.
  static List<ZonaLimitata> _unaPerNome(List<ZonaLimitata> zone) {
    final viste = <String>{};
    return [
      for (final z in zone)
        if (viste.add(z.chiave)) z,
    ];
  }
}

class _Pastiglia extends StatelessWidget {
  const _Pastiglia({required this.testo, this.rossa = false});

  final String testo;
  final bool rossa;

  @override
  Widget build(BuildContext context) {
    final scuro = Theme.of(context).brightness == Brightness.dark;
    final (fondo, colore) = rossa
        ? (scuro ? const Color(0xFF4C1D1D) : const Color(0xFFFEE2E2), scuro ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B))
        : (scuro ? const Color(0xFF374151) : const Color(0xFFE5E7EB), scuro ? const Color(0xFFE5E7EB) : const Color(0xFF374151));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
      child: Text(
        testo,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colore, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// La domanda, la prima volta che il percorso passerebbe da una ZTL attiva:
/// «Hai il permesso per entrare?». Senza risposta il percorso la evita.
class DomandaZtl extends StatelessWidget {
  const DomandaZtl({super.key, required this.percorso, required this.onRisposta, this.ora});

  final PercorsoCalcolato percorso;
  final void Function(ZonaLimitata zona, bool permesso) onRisposta;

  /// Adesso; nelle prove un'ora fissa.
  final DateTime? ora;

  @override
  Widget build(BuildContext context) {
    final z = percorso.ztl;
    final zona = z?.daChiedere;
    if (z == null || zona == null) return const SizedBox.shrink();
    final adesso = ora ?? DateTime.now();
    final t = Theme.of(context).textTheme;
    final scuro = Theme.of(context).brightness == Brightness.dark;
    final passandoci = z.durataPassandoci;
    final minuti = passandoci == null ? null : ((percorso.durata.inSeconds - passandoci.inSeconds) / 60).round();
    final guadagno = switch (minuti) {
      null => '',
      <= 0 => 'Passandoci ci metti uguale. ',
      1 => 'Passandoci arrivi 1 minuto prima. ',
      final m => 'Passandoci arrivi $m minuti prima. ',
    };
    final blu = Theme.of(context).colorScheme.primary;
    return Column(
      key: const Key('domanda-ztl'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scuro ? const Color(0xFF3B1414) : const Color(0xFFFEF2F2),
            border: Border.all(color: scuro ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('⛔ ${zona.titolo}, ${_quando(zona, adesso)}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                '${guadagno}Hai il permesso per entrare?',
                style: t.bodyMedium?.copyWith(color: scuro ? const Color(0xFFFCA5A5) : const Color(0xFF7F1D1D)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('ztl-si'),
                      onPressed: () => onRisposta(zona, true),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: blu, width: 1.5)),
                      child: const Text('Sì, ho il permesso'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const Key('ztl-no'),
                      onPressed: () => onRisposta(zona, false),
                      child: const Text('No, evitala'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Me lo ricordo per questa ZTL. Si cambia dal menu, in «ZTL e aree pedonali».',
          style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// «attiva ora (fino alle 18:00)», «attiva dalle 7:30», «attiva».
  static String _quando(ZonaLimitata z, DateTime ora) {
    final (:attiva, :cambia) = z.statoAlle(ora);
    if (cambia == null) return 'attiva';
    return attiva ? 'attiva ora (fino alle ${oraLunga(cambia)})' : 'attiva dalle ${oraLunga(cambia)}';
  }
}
