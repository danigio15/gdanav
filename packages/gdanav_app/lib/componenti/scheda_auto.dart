import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../mappa/segnaposto.dart';
import '../stato/foto_auto.dart';
import '../stato/gestore_auto.dart';
import '../tema.dart';
import 'indicatore_batteria.dart' show eta, nomeSorgente;

/// La tua auto nel pannello in basso, come in ABRP: nome, foto, batteria,
/// autonomia e se i dati arrivano davvero dall'auto.
class SchedaAuto extends StatelessWidget {
  const SchedaAuto({
    super.key,
    required this.auto,
    required this.segnaposto,
    required this.onApriAuto,
    required this.onFonte,
    required this.onFoto,
    this.fotoCatalogo,
  });

  final GestoreAuto auto;

  /// Il colore dell'auto disegnata è quello scelto per la mappa.
  final Segnaposto segnaposto;
  final VoidCallback onApriAuto;
  final VoidCallback onFonte;
  final VoidCallback onFoto;

  /// Le foto vere dei modelli; senza, l'auto disegnata.
  final GestoreFotoAuto? fotoCatalogo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Theme.of(context).colorScheme;
    final c = ColoriGdanav.di(context);
    return ListenableBuilder(
      listenable: Listenable.merge([auto, ?fotoCatalogo]),
      builder: (context, _) {
        // Auto termica: niente batteria né colonnine, solo la tua auto.
        if (!auto.elettrica) {
          return Material(
            key: const Key('scheda-auto-termica'),
            color: s.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onApriAuto,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'La tua auto',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const Icon(Icons.expand_more),
                            ],
                          ),
                          Text(
                            'Termica · benzina, diesel, GPL o ibrida',
                            maxLines: 2,
                            style: t.bodyLarge?.copyWith(color: s.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Foto(
                    propria: auto.foto != null && File(auto.foto!).existsSync() ? File(auto.foto!) : null,
                    catalogo: null,
                    colore: coloreAuto(segnaposto),
                    onFoto: onFoto,
                  ),
                ],
              ),
            ),
          );
        }
        final v = auto.veicolo;
        final st = auto.stato;
        final km = auto.autonomiaKm();
        final batteria = st?.batteria;
        final colore = switch (batteria) {
          null => s.outline,
          < 15 => c.guasta,
          < 30 => c.piena,
          _ => c.libera,
        };
        final (puntino, stato) = statoCollegamento(st, DateTime.now(), c, perche: auto.percheSenzaDati);
        final (titolo, sottotitolo) = nomeInDueRighe(v);
        return Material(
          color: s.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onApriAuto,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              v.id == ProfiloVeicolo.esempio.id ? 'Scegli la tua auto' : titolo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const Icon(Icons.expand_more),
                        ],
                      ),
                      Text(
                        v.id == ProfiloVeicolo.esempio.id ? v.modello : sottotitolo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyLarge?.copyWith(color: s.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(Icons.battery_std_rounded, color: colore, size: 30),
                              const SizedBox(width: 4),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    batteria == null ? '–' : '${batteria.round()}%',
                                    key: const Key('scheda-batteria'),
                                    style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: 1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (km != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text('≈ ${km.round()} km di autonomia', style: t.titleSmall),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Foto(
                      propria: auto.foto != null && File(auto.foto!).existsSync() ? File(auto.foto!) : null,
                      catalogo: v.id == ProfiloVeicolo.esempio.id ? null : fotoCatalogo?.file(v.id),
                      credito: fotoCatalogo?.info(v.id)?.credito,
                      colore: coloreAuto(segnaposto),
                      onFoto: onFoto,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (batteria ?? 0) / 100,
                    minHeight: 10,
                    color: colore,
                    backgroundColor: s.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.circle, size: 11, color: puntino),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(stato, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                      ),
                    ),
                    TextButton(
                      onPressed: onFonte,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Fonte dati'),
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
}

/// La foto nella scheda: la tua se l'hai scelta, se no quella vera del
/// modello (con autore e licenza sotto), se no l'auto disegnata.
class _Foto extends StatelessWidget {
  const _Foto({
    required this.propria,
    required this.catalogo,
    this.credito,
    required this.colore,
    required this.onFoto,
  });

  final File? propria;
  final File? catalogo;
  final String? credito;
  final Color colore;
  final VoidCallback onFoto;

  @override
  Widget build(BuildContext context) {
    final file = propria ?? catalogo;
    return Tooltip(
      message: 'Foto della tua auto',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onFoto,
        child: SizedBox(
          width: 124,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 80,
                width: 124,
                child: file != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(
                          file,
                          key: Key(propria != null ? 'foto-propria' : 'foto-modello'),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => CustomPaint(painter: AutoDisegnata(colore)),
                        ),
                      )
                    : CustomPaint(painter: AutoDisegnata(colore)),
              ),
              if (propria == null && catalogo != null && credito != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    credito!,
                    key: const Key('credito-foto'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Leapmotor» + «B10 67,1 kWh (Design, Pro Max)» → «Leapmotor B10» e
/// «67,1 kWh (Design, Pro Max)»: il nome sopra, la batteria sotto.
(String, String) nomeInDueRighe(ProfiloVeicolo v) {
  final m = RegExp(r'\s\d+(?:[.,]\d+)?\s?kWh').firstMatch(v.modello);
  if (m == null) return ('${v.marca} ${v.modello}', '');
  return ('${v.marca} ${v.modello.substring(0, m.start)}', v.modello.substring(m.start).trim());
}

/// Il puntino e la frase dello stato: verde se i dati arrivano freschi
/// dall'auto, ambra se sono vecchi, grigio se sono a mano o stimati.
/// Senza dati, [perche] dice cosa non va, se lo si sa.
(Color, String) statoCollegamento(StatoAuto? s, DateTime ora, ColoriGdanav c, {String? perche}) {
  if (s == null) return (c.ignota, perche ?? 'Nessun dato: tocca «Fonte dati»');
  final da = nomeSorgente(s.sorgente);
  return switch (s.sorgente) {
    TipoSorgente.manuale => (c.ignota, 'Batteria scritta a mano · ${eta(ora.difference(s.letto))}'),
    TipoSorgente.stima => (c.ignota, 'Batteria stimata'),
    _ when ora.difference(s.letto) > const Duration(minutes: 30) => (
      c.piena,
      'Ultimo dato da $da · ${eta(ora.difference(s.letto))}',
    ),
    _ => (c.libera, 'Connesso · $da · ${eta(ora.difference(s.letto))}'),
  };
}

Color coloreAuto(Segnaposto s) => switch (s) {
  Segnaposto.autoBianca => const Color(0xFFF1F3F5),
  Segnaposto.autoRossa => const Color(0xFFD23B3B),
  Segnaposto.autoNera => const Color(0xFF2A2E35),
  Segnaposto.autoGrigia => const Color(0xFF8C939C),
  _ => const Color(0xFF2F55C8),
};

/// Un SUV di tre quarti, disegnato: quando non c'è la foto della propria
/// auto. Nessuna immagine del costruttore.
class AutoDisegnata extends CustomPainter {
  const AutoDisegnata(this.colore);
  final Color colore;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final ombra = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(Rect.fromLTWH(w * 0.06, h * 0.80, w * 0.9, h * 0.14), ombra);

    final scuro = Color.lerp(colore, Colors.black, 0.35)!;
    final chiaro = Color.lerp(colore, Colors.white, 0.35)!;
    final corpo = Path()
      ..moveTo(w * 0.04, h * 0.70)
      ..quadraticBezierTo(w * 0.03, h * 0.52, w * 0.12, h * 0.47)
      ..lineTo(w * 0.30, h * 0.40)
      ..quadraticBezierTo(w * 0.40, h * 0.18, w * 0.55, h * 0.16)
      ..lineTo(w * 0.80, h * 0.17)
      ..quadraticBezierTo(w * 0.92, h * 0.19, w * 0.95, h * 0.40)
      ..quadraticBezierTo(w * 0.99, h * 0.52, w * 0.97, h * 0.70)
      ..quadraticBezierTo(w * 0.96, h * 0.80, w * 0.88, h * 0.80)
      ..lineTo(w * 0.12, h * 0.80)
      ..quadraticBezierTo(w * 0.05, h * 0.80, w * 0.04, h * 0.70)
      ..close();
    canvas.drawPath(
      corpo,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [chiaro, colore, scuro],
          stops: const [0, 0.45, 1],
        ).createShader(Offset.zero & size),
    );
    // Vetri.
    final vetri = Path()
      ..moveTo(w * 0.34, h * 0.40)
      ..quadraticBezierTo(w * 0.43, h * 0.23, w * 0.56, h * 0.22)
      ..lineTo(w * 0.79, h * 0.23)
      ..quadraticBezierTo(w * 0.87, h * 0.25, w * 0.89, h * 0.40)
      ..close();
    canvas.drawPath(vetri, Paint()..color = const Color(0xFF1E2530));
    canvas.drawLine(
      Offset(w * 0.60, h * 0.22),
      Offset(w * 0.60, h * 0.40),
      Paint()
        ..color = scuro
        ..strokeWidth = w * 0.015,
    );
    // Linea dei fari e fiancata.
    canvas.drawLine(
      Offset(w * 0.05, h * 0.55),
      Offset(w * 0.18, h * 0.52),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = h * 0.035
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(w * 0.20, h * 0.56),
      Offset(w * 0.94, h * 0.56),
      Paint()
        ..color = scuro.withValues(alpha: 0.5)
        ..strokeWidth = 1.2,
    );
    // Ruote.
    for (final x in [0.25, 0.78]) {
      final centro = Offset(w * x, h * 0.78);
      canvas.drawCircle(centro, h * 0.16, Paint()..color = const Color(0xFF16191E));
      canvas.drawCircle(centro, h * 0.09, Paint()..color = const Color(0xFF9AA1AB));
      canvas.drawCircle(centro, h * 0.035, Paint()..color = const Color(0xFF3A4048));
    }
  }

  @override
  bool shouldRepaint(AutoDisegnata vecchio) => vecchio.colore != colore;
}
