import 'dart:convert';

import '../geo/geo.dart';
import 'colonnina.dart';
import 'colonnine_relay.dart';

/// Le colonnine rapide di mezza Europa dentro l'app: preparate in CI da
/// OpenStreetMap (`tool/colonnine_europa.dart`), si cercano in un attimo e
/// anche senza rete. Dove l'archivio non arriva, si chiede al relay solo
/// quei riquadri.
class ColonnineLocali implements FonteColonnine {
  ColonnineLocali(Future<ArchivioColonnine> archivio, {this.riserva}) : _archivio = archivio;

  final Future<ArchivioColonnine> _archivio;

  /// Per i riquadri fuori dall'archivio.
  final ClienteColonnineRelay? riserva;

  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async {
    final a = await _archivio;
    final riquadri = ClienteColonnineRelay.riquadri(percorso, distanzaKm);
    final trovate = <Colonnina>[];
    final mancanti = <(int, int)>{};
    for (final q in riquadri) {
      if (a.copre(q)) {
        trovate.addAll(a.nel(q));
      } else {
        mancanti.add(q);
      }
    }
    if (mancanti.isNotEmpty && riserva != null) {
      try {
        trovate.addAll(await riserva!.nei(mancanti));
      } catch (_) {
        // Fuori dall'archivio e relay giù: si pianifica con quel che c'è.
        if (trovate.isEmpty) rethrow;
      }
    }
    return trovate;
  }
}

/// Le colonnine divise per riquadri di mezzo grado.
class ArchivioColonnine {
  ArchivioColonnine(Iterable<Colonnina> colonnine, {this.generato, Set<(int, int)>? coperti}) {
    for (final c in colonnine) {
      (_perRiquadro[_riquadro(c.posizione)] ??= []).add(c);
    }
    if (coperti != null) {
      // Quelli cercati davvero, anche se senza colonnine.
      _coperti.addAll(coperti);
    } else {
      // Se non si sa: i riquadri con colonnine e quelli intorno.
      for (final (r, c) in _perRiquadro.keys.toList()) {
        for (var dr = -1; dr <= 1; dr++) {
          for (var dc = -1; dc <= 1; dc++) {
            _coperti.add((r + dr, c + dc));
          }
        }
      }
    }
  }

  static final vuoto = ArchivioColonnine(const []);

  final DateTime? generato;
  final _perRiquadro = <(int, int), List<Colonnina>>{};
  final _coperti = <(int, int)>{};

  int get quante => _perRiquadro.values.fold(0, (n, l) => n + l.length);

  bool copre((int, int) q) => _coperti.contains(q);
  List<Colonnina> nel((int, int) q) => _perRiquadro[q] ?? const [];

  static (int, int) _riquadro(Punto p) =>
      ((p.lat / ClienteColonnineRelay.lato).floor(), (p.lon / ClienteColonnineRelay.lato).floor());

  // --- il formato compatto ------------------------------------------------
  //
  // {"v":1,"generato":"…","q":[[riga,colonna],…],
  //  "c":[[lat,lon,"osm-node-1","nome","operatore",[[tipo,kw,quante],…]],…]}
  // q: i riquadri di mezzo grado cercati (anche vuoti).
  // tipo: 0 CCS2, 1 CHAdeMO, 2 Tipo 2, 3 Tesla.

  static const _tipi = [TipoConnettore.ccs2, TipoConnettore.chademo, TipoConnettore.tipo2, TipoConnettore.tesla];

  static String scrivi(List<Colonnina> colonnine, {DateTime? generato, Set<(int, int)>? coperti}) {
    final righe = [
      for (final c in colonnine)
        [
          double.parse(c.posizione.lat.toStringAsFixed(5)),
          double.parse(c.posizione.lon.toStringAsFixed(5)),
          c.id,
          c.nome,
          c.operatore ?? '',
          _prese(c.connettori),
        ],
    ];
    return jsonEncode({
      'v': 1,
      'generato': (generato ?? DateTime.now().toUtc()).toIso8601String(),
      if (coperti != null)
        'q': [
          for (final (r, c) in coperti) [r, c],
        ],
      'c': righe,
    });
  }

  static List<List<num>> _prese(List<Connettore> connettori) {
    final conta = <(int, double), int>{};
    for (final p in connettori) {
      final t = _tipi.indexOf(p.tipo);
      if (t < 0) continue;
      conta.update((t, p.potenzaKw), (n) => n + 1, ifAbsent: () => 1);
    }
    return [
      for (final MapEntry(key: (t, kw), value: n) in conta.entries) [t, kw == kw.roundToDouble() ? kw.round() : kw, n],
    ];
  }

  static ArchivioColonnine leggi(String testo) {
    final j = jsonDecode(testo) as Map<String, Object?>;
    if (j['v'] != 1) throw FormatException('Archivio colonnine: versione ${j['v']}');
    final colonnine = <Colonnina>[];
    for (final r in (j['c'] as List).cast<List>()) {
      colonnine.add(
        Colonnina(
          id: r[2] as String,
          nome: r[3] as String,
          operatore: (r[4] as String).isEmpty ? null : r[4] as String,
          posizione: Punto((r[0] as num).toDouble(), (r[1] as num).toDouble()),
          connettori: [
            for (final p in (r[5] as List).cast<List>())
              for (var i = 0; i < (p[2] as num).toInt(); i++)
                Connettore(tipo: _tipi[(p[0] as num).toInt()], potenzaKw: (p[1] as num).toDouble()),
          ],
          fonte: 'osm',
        ),
      );
    }
    final q = j['q'] as List?;
    return ArchivioColonnine(
      colonnine,
      generato: DateTime.tryParse('${j['generato']}'),
      coperti: q == null ? null : {for (final x in q.cast<List>()) ((x[0] as num).toInt(), (x[1] as num).toInt())},
    );
  }
}
