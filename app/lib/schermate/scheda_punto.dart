import 'package:flutter/material.dart';
import 'package:gdanav_core/gdanav_core.dart';

import '../componenti/icone_punti.dart';
import '../componenti/stato_colonnina.dart';
import '../mappa/categorie_poi.dart';
import '../stato/distributori.dart';
import '../stato/gestore_vicini.dart';
import 'dettaglio_colonnina.dart' show nomeConnettore;

/// Un punto toccato sulla mappa: un distributore, una colonnina vicina o
/// un punto di interesse (ristorante, negozio, museo…).
class PuntoToccato {
  const PuntoToccato({
    required this.tipo,
    required this.nome,
    required this.posizione,
    this.id,
    this.proprieta = const {},
  });

  /// 'distributore', 'colonnina' o 'poi'.
  final String tipo;
  final String? id;
  final String nome;
  final Punto posizione;
  final Map<String, Object?> proprieta;

  /// Da un elemento della mappa (le proprietà e il punto); `null` se non è
  /// un punto che sappiamo raccontare.
  static PuntoToccato? daElemento(Map<Object?, Object?> e) {
    final p = ((e['properties'] as Map?) ?? const {}).cast<String, Object?>();
    final g = (e['geometry'] as Map?)?.cast<String, Object?>();
    final xy = g?['coordinates'];
    if (xy is! List || xy.length < 2) return null;
    final dove = Punto((xy[1] as num).toDouble(), (xy[0] as num).toDouble());
    final nome = '${p['nome'] ?? p['name'] ?? ''}';
    return switch (p['tipo']) {
      'distributore' || 'colonnina' => PuntoToccato(
        tipo: p['tipo']! as String,
        id: p['id'] as String?,
        nome: nome,
        posizione: dove,
        proprieta: p,
      ),
      _ when p.containsKey('class') && nome.isNotEmpty => PuntoToccato(
        tipo: 'poi',
        nome: nome,
        posizione: dove,
        proprieta: p,
      ),
      _ => null,
    };
  }
}

/// La scheda del punto toccato: cosa è, le informazioni che abbiamo, e «Vai».
Future<void> mostraPunto(
  BuildContext context,
  PuntoToccato punto, {
  required ValueChanged<Luogo> onVai,
  GestoreVicini? vicini,
  Punto? qui,
  Carburante carburante = Carburante.benzina,
  String vai = 'Vai',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (contesto) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: _Scheda(
          punto: punto,
          vicini: vicini,
          qui: qui,
          carburante: carburante,
          vai: vai,
          onVai: (l) {
            Navigator.of(contesto).pop();
            onVai(l);
          },
        ),
      ),
    ),
  );
}

class _Scheda extends StatelessWidget {
  const _Scheda({
    required this.punto,
    required this.vicini,
    required this.qui,
    required this.carburante,
    required this.vai,
    required this.onVai,
  });

  final PuntoToccato punto;
  final GestoreVicini? vicini;
  final Punto? qui;
  final Carburante carburante;
  final String vai;
  final ValueChanged<Luogo> onVai;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muto = Theme.of(context).colorScheme.onSurfaceVariant;
    final distanza = qui == null ? null : distanzaM(qui!, punto.posizione);
    final km = distanza == null
        ? null
        : distanza < 1000
        ? '${(distanza / 10).round() * 10} m'
        : '${(distanza / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

    final (colore, icona, sopra) = switch (punto.tipo) {
      'distributore' => (const Color(0xFFF08A24), Icons.local_gas_station, 'DISTRIBUTORE'),
      'colonnina' => (const Color(0xFF16A34A), Icons.ev_station, 'COLONNINA DI RICARICA'),
      _ => () {
        final c = categoriaPoi(punto.proprieta['subclass'] as String?, punto.proprieta['class'] as String?);
        return (coloreHex(c.colore), iconaCategoria(c), c.etichetta.toUpperCase());
      }(),
    };
    final dettagli = <Widget>[];
    var descrizione = '';

    final d = punto.tipo == 'distributore' ? vicini?.distributore(punto.id ?? '') : null;
    final col = punto.tipo == 'colonnina' ? vicini?.colonnina(punto.id ?? '') : null;
    if (d != null) {
      descrizione = descriviDistributore(d, qui ?? d.posizione, carburante: carburante);
      if (d.indirizzo != null || (d.marca != null && d.marca != d.nome)) {
        dettagli.add(
          Text([if (d.marca != d.nome) ?d.marca, ?d.indirizzo].join(' · '), style: t.bodyMedium?.copyWith(color: muto)),
        );
      }
      final tipi = [
        for (final c in Carburante.values)
          if (d.prezzi.any((p) => p.carburante == c)) c,
      ];
      if (tipi.isNotEmpty) {
        dettagli.add(const SizedBox(height: 12));
        dettagli.add(Text('Prezzi', style: t.titleSmall));
        dettagli.add(const SizedBox(height: 6));
        Widget cella(String testo, {TextStyle? stile, TextAlign allinea = TextAlign.right}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(testo, textAlign: allinea, style: stile),
        );
        final intestazione = t.labelMedium?.copyWith(color: muto);
        dettagli.add(
          Table(
            key: const Key('prezzi'),
            columnWidths: const {0: FlexColumnWidth(1.2), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
            children: [
              TableRow(
                children: [
                  cella('', allinea: TextAlign.left),
                  cella('Self', stile: intestazione),
                  cella('Servito', stile: intestazione),
                ],
              ),
              for (final c in tipi)
                TableRow(
                  key: ValueKey('prezzi-${c.name}'),
                  children: [
                    cella(
                      c.nome,
                      allinea: TextAlign.left,
                      stile: t.bodyLarge?.copyWith(fontWeight: c == carburante ? FontWeight.w700 : null),
                    ),
                    cella(switch (d.prezzi
                        .where((p) => p.carburante == c && p.self)
                        .map((p) => p.euro)
                        .fold<double?>(null, _min)) {
                      final e? => euro(e),
                      null => '–',
                    }, stile: t.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    cella(switch (d.prezzi
                        .where((p) => p.carburante == c && !p.self)
                        .map((p) => p.euro)
                        .fold<double?>(null, _min)) {
                      final e? => euro(e),
                      null => '–',
                    }, stile: t.bodyLarge?.copyWith(color: muto)),
                  ],
                ),
            ],
          ),
        );
        if (quandoAggiornato(d.aggiornato) case final q?) {
          dettagli.add(Text('Prezzi comunicati $q · Osservaprezzi (MIMIT)', style: t.bodySmall?.copyWith(color: muto)));
        }
      } else if (d.carburanti.isNotEmpty) {
        dettagli.add(const SizedBox(height: 8));
        dettagli.add(Text(d.carburanti.map((c) => c.nome).join(', ')));
      }
      if (d.orari case final o?) {
        dettagli.add(const SizedBox(height: 8));
        dettagli.add(Text(d.sempreAperto ? 'Aperto 24 ore' : 'Orari: $o', style: t.bodyMedium));
      }
    } else if (col != null) {
      final c = col;
      final connettori = vicini!.auto.veicolo.connettori;
      final disp = c.disponibilitaPer(connettori);
      descrizione = '${c.potenzaNominalePer(connettori).round()} kW · ${testoDisponibilita(disp)}';
      if (c.operatore case final o? when o.isNotEmpty) {
        dettagli.add(Text(o, style: t.bodyMedium?.copyWith(color: muto)));
      }
      dettagli.add(const SizedBox(height: 12));
      dettagli.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [BadgePotenza(c.potenzaNominalePer(connettori)), BadgeDisponibilita(disp)],
        ),
      );
      final prese = <String, int>{};
      for (final p in c.connettori) {
        final k = '${nomeConnettore(p.tipo)} · ${p.potenzaKw.round()} kW';
        prese[k] = (prese[k] ?? 0) + 1;
      }
      if (prese.isNotEmpty) {
        dettagli.add(const SizedBox(height: 12));
        dettagli.add(Text('Prese', style: t.titleSmall));
        for (final MapEntry(:key, :value) in prese.entries) {
          dettagli.add(Padding(padding: const EdgeInsets.only(top: 4), child: Text('$value × $key')));
        }
      }
    }

    return Column(
      key: Key('scheda-punto-${punto.tipo}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: colore,
              child: Icon(icona, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sopra, style: t.labelSmall?.copyWith(color: colore, letterSpacing: 0.8)),
                  Text(punto.nome, style: t.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (km != null) Text('A $km da te', style: t.bodyMedium?.copyWith(color: muto)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...dettagli,
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('vai-punto'),
            icon: const Icon(Icons.navigation),
            label: Text(vai),
            onPressed: () => onVai(
              Luogo(
                nome: punto.nome,
                posizione: punto.posizione,
                descrizione: descrizione.isNotEmpty ? descrizione : sopra[0] + sopra.substring(1).toLowerCase(),
              ),
            ),
          ),
        ),
        if (punto.tipo == 'poi') ...[
          const SizedBox(height: 8),
          Text('Dati: © OpenStreetMap contributors', style: t.bodySmall?.copyWith(color: muto)),
        ],
      ],
    );
  }

  static double? _min(double? m, double e) => m == null || e < m ? e : m;
}

/// Il punto in poche righe, per la scheda sullo schermo dell'auto.
({String sopra, List<String> righe}) righePunto(
  PuntoToccato p, {
  GestoreVicini? vicini,
  Punto? qui,
  Carburante carburante = Carburante.benzina,
}) {
  final righe = <String>[];
  String? distanzaTesto;
  if (qui != null) {
    final m = distanzaM(qui, p.posizione);
    distanzaTesto = m < 1000
        ? '${(m / 10).round() * 10} m'
        : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }
  switch (p.tipo) {
    case 'distributore':
      final d = vicini?.distributore(p.id ?? '');
      righe.add([?distanzaTesto, ?d?.marca == d?.nome ? null : d?.marca, ?d?.indirizzo].join(' · '));
      if (d != null) {
        for (final c in Carburante.values) {
          final self = d.prezzi
              .where((x) => x.carburante == c && x.self)
              .map((x) => x.euro)
              .fold<double?>(null, _minimo);
          final servito = d.prezzi
              .where((x) => x.carburante == c && !x.self)
              .map((x) => x.euro)
              .fold<double?>(null, _minimo);
          if (self == null && servito == null) continue;
          righe.add(
            '${c.nome}: ${[if (self != null) '${euro(self)} self', if (servito != null) '${euro(servito)} servito'].join(' · ')}',
          );
        }
        if (quandoAggiornato(d.aggiornato) case final q?) righe.add('Prezzi comunicati $q');
      }
      return (sopra: 'Distributore', righe: righe.where((r) => r.isNotEmpty).toList());
    case 'colonnina':
      final c = vicini?.colonnina(p.id ?? '');
      if (c != null) {
        final connettori = vicini!.auto.veicolo.connettori;
        righe.add([?distanzaTesto, '${c.potenzaNominalePer(connettori).round()} kW', ?c.operatore].join(' · '));
        righe.add(testoDisponibilita(c.disponibilitaPer(connettori)));
      } else if (distanzaTesto != null) {
        righe.add(distanzaTesto);
      }
      return (sopra: 'Colonnina di ricarica', righe: righe);
    default:
      final cat = categoriaPoi(p.proprieta['subclass'] as String?, p.proprieta['class'] as String?);
      righe.add([cat.etichetta, ?distanzaTesto].join(' · '));
      return (sopra: cat.etichetta, righe: righe);
  }
}

double? _minimo(double? m, double e) => m == null || e < m ? e : m;
