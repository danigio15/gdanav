import 'dart:math' as math;
import 'dart:typed_data';

import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

/* Geometrie inventate, in metri attorno a un'origine qualunque: nessun posto
 * vero. x verso est, y verso nord. */

const metriPerGrado = 111195.08;
const origine = Punto(44, 11.5);

Punto a(double est, double nord) => Punto(
    origine.lat + nord / metriPerGrado, origine.lon + est / (metriPerGrado * math.cos(origine.lat * math.pi / 180)));

(double, double) dove(Punto p) => (
      (p.lon - origine.lon) * metriPerGrado * math.cos(origine.lat * math.pi / 180),
      (p.lat - origine.lat) * metriPerGrado,
    );

double distanza(Punto p, (double, double) q) {
  final (x, y) = dove(p);
  return math.sqrt((x - q.$1) * (x - q.$1) + (y - q.$2) * (y - q.$2));
}

/// Quanto la linea [punti] passa vicino a [q] (sui segmenti, non solo sui
/// vertici).
double passaA(List<Punto> punti, (double, double) q) {
  var d = double.infinity;
  for (var i = 1; i < punti.length; i++) {
    final (ax, ay) = dove(punti[i - 1]);
    final (bx, by) = dove(punti[i]);
    final dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
    final t = l2 == 0 ? 0.0 : (((q.$1 - ax) * dx + (q.$2 - ay) * dy) / l2).clamp(0.0, 1.0);
    d = math.min(d, math.sqrt(math.pow(ax + t * dx - q.$1, 2) + math.pow(ay + t * dy - q.$2, 2)));
  }
  return d;
}

TrattoStrada strada(List<(double, double)> v, {int senso = 0, String classe = 'minor'}) =>
    TrattoStrada([for (final (x, y) in v) a(x, y)], senso: senso, classe: classe);

/// La linea di un fornitore per i [vertici]: un punto ogni [passo] metri, e
/// spostata di lato come quelle di TomTom ([sposta]). Con gli indici dei
/// vertici.
(List<Punto>, List<int>) linea(List<(double, double)> vertici, {double passo = 6, (double, double) sposta = (0, 0)}) {
  final out = <Punto>[], indici = <int>[0];
  for (var i = 1; i < vertici.length; i++) {
    final (ax, ay) = vertici[i - 1];
    final (bx, by) = vertici[i];
    final n = math.max(1, (math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) / passo).round());
    for (var k = 0; k < n; k++) {
      out.add(a(ax + (bx - ax) * k / n + sposta.$1, ay + (by - ay) * k / n + sposta.$2));
    }
    indici.add(out.length);
  }
  out.add(a(vertici.last.$1 + sposta.$1, vertici.last.$2 + sposta.$2));
  return (out, indici);
}

/// Un percorso coi [punti] e le manovre (indice, tipo, frase, strada).
PercorsoCalcolato percorso(List<Punto> punti, List<(int, int, String, String)> manovre) {
  final c = Linea(punti).cumulate;
  return PercorsoCalcolato(
    punti: punti,
    tratti: [Tratto(lunghezzaM: c.last, velocitaKmh: 36)],
    limiti: [for (var i = 0; i < punti.length - 1; i++) 50],
    manovre: [
      for (var k = 0; k < manovre.length; k++)
        Manovra(
          istruzione: manovre[k].$3,
          voce: manovre[k].$3,
          tipo: manovre[k].$2,
          strada: manovre[k].$4,
          inizio: manovre[k].$1,
          lunghezzaM: (k + 1 < manovre.length ? c[manovre[k + 1].$1] : c.last) - c[manovre[k].$1],
          secondi: ((k + 1 < manovre.length ? c[manovre[k + 1].$1] : c.last) - c[manovre[k].$1]) / 10,
        ),
    ],
  );
}

/* ─── Il triangolo ────────────────────────────────────────────────────────
 *
 * Si arriva da ovest-nord-ovest sulla strada principale. Il ramo «giusto»
 * si stacca per primo (in W) e scende a N, a senso unico verso N: «al
 * bivio tieni la destra». L'altro ramo parte più avanti (in V) ed è a senso
 * unico al contrario, da N verso V. Da N si prosegue verso sud. */
const w = (-15.0, 30.0), v = (5.0, 21.0), n = (0.0, 0.0);
final triangolo = [
  strada([(-160, 85), (-100, 60), (-57, 46), w]),
  strada([w, v, (120, -30), (220, -75)]),
  strada([w, n], senso: 1),
  strada([n, v], senso: 1),
  strada([n, (1, -60), (2, -230), (3, -400)]),
];

/// La linea del fornitore: dritta fino al vertice V e poi stretta a destra
/// sul ramo vietato, spostata di sette metri come quelle di TomTom.
PercorsoCalcolato dalVertice({(double, double) sposta = (0, 7)}) {
  final (p, i) = linea([(-160, 85), (-100, 60), (-57, 46), w, v, n, (1, -60), (2, -230), (3, -400)], sposta: sposta);
  return percorso(p, [
    (0, 1, 'Parti', 'Strada Principale'),
    (i[4], 11, 'Svolta stretta a destra in Via Nobel', 'Via Nobel'),
    (p.length - 1, 4, 'Sei arrivato a destinazione', ''),
  ]);
}

void main() {
  group('il triangolo dei sensi unici', () {
    test('la linea del fornitore passa dal vertice e va contromano: si ridisegna sul ramo giusto', () {
      final prima = dalVertice();
      // Oggi: la linea passa da V e scende sul ramo vietato.
      expect(passaA(prima.punti, v), lessThan(8));
      final c = correggiContromano(prima, triangolo);
      expect(c, isNotNull, reason: 'va contromano sul ramo da N a V: va corretto');
      final dopo = c!.percorso;
      // Non passa più dal vertice né dal ramo vietato…
      expect(passaA(dopo.punti, v), greaterThan(10));
      expect(passaA(dopo.punti, (2.5, 10.5)), greaterThan(6), reason: 'il mezzo del ramo vietato');
      // …ma dal ramo giusto, e da N.
      expect(passaA(dopo.punti, (-7.5, 15)), lessThan(6), reason: 'il mezzo del ramo giusto');
      expect(passaA(dopo.punti, n), lessThan(9));
      // La partenza e la meta sono quelle.
      expect(dopo.punti.first, prima.punti.first);
      expect(dopo.punti.last, prima.punti.last);
      // Una deviazione sola, corta.
      expect(c.deviazioni, hasLength(1));
      final d = c.deviazioni.single;
      expect(d.aM - d.daM, lessThan(250));
      expect(d.lunghezzaM, lessThanOrEqualTo((d.aM - d.daM) * 1.5));
    });

    test('il pezzo rifatto è segnato «sulla strada», col suo raccordo: la scena 3D non lo sposta', () {
      final prima = dalVertice();
      expect(prima.suStrada, isEmpty);
      final c = correggiContromano(prima, triangolo)!;
      final dopo = c.percorso;
      expect(dopo.suStrada, hasLength(1));
      final (da, fine, raccordo) = dopo.suStrada.single;
      final d = c.deviazioni.single;
      expect(da, closeTo(d.daM, 3), reason: 'parte dove si stacca dalla linea di prima');
      expect(fine - da, closeTo(d.lunghezzaM, 3));
      expect(raccordo, inInclusiveRange(1, 25));
      // In mezzo al pezzo, fuori dai raccordi, la linea è proprio sul ramo giusto.
      final cum = Linea(dopo.punti).cumulate;
      for (var i = 0; i < dopo.punti.length; i++) {
        if (cum[i] < da + raccordo || cum[i] > fine - raccordo) continue;
        final ramo = [a(w.$1, w.$2), a(n.$1, n.$2), a(1, -60)];
        expect(passaA(ramo, dove(dopo.punti[i])), lessThan(0.5), reason: 'a ${cum[i].round()} m');
      }
      // Anche sotto il traffico, che si rifà dal percorso senza.
      if (dopo.senzaTraffico case final s?) expect(s.suStrada, hasLength(1));
    });

    test('la manovra diventa «al bivio tieni la destra», nel punto dove si stacca il ramo giusto', () {
      final dopo = correggiContromano(dalVertice(), triangolo)!.percorso;
      expect(dopo.manovre.map((m) => m.tipo), [1, 23, 4]);
      final bivio = dopo.manovre[1];
      expect(bivio.istruzione, 'Al bivio tieni la destra verso Via Nobel');
      expect(bivio.voce, bivio.istruzione);
      expect(bivio.strada, 'Via Nobel');
      // Dove: al bivio W (la linea è ancora spostata di lato, qui).
      expect(distanza(dopo.punti[bivio.inizio], w), lessThan(10));
      // Le frasi per l'auto (Android Auto, CarPlay) vengono dalla stessa manovra.
      expect(frasiManovra(bivio).first, startsWith('Al bivio tieni la destra'));
      // Gli indici crescono, le lunghezze tornano con la geometria.
      final c = Linea(dopo.punti).cumulate;
      for (var k = 0; k + 1 < dopo.manovre.length; k++) {
        expect(dopo.manovre[k + 1].inizio, greaterThan(dopo.manovre[k].inizio));
        expect(dopo.manovre[k].lunghezzaM, closeTo(c[dopo.manovre[k + 1].inizio] - c[dopo.manovre[k].inizio], 0.5));
      }
      expect(dopo.limiti, hasLength(dopo.punti.length - 1));
    });

    test('con la linea spostata da ogni parte, o non spostata, va sempre sul ramo giusto', () {
      for (final s in [(0.0, 0.0), (0.0, 7.0), (6.0, 0.0), (-6.0, 4.0), (4.0, -6.0), (-8.0, -3.0)]) {
        final c = correggiContromano(dalVertice(sposta: s), triangolo);
        expect(c, isNotNull, reason: 'spostata di $s');
        expect(passaA(c!.percorso.punti, v), greaterThan(9), reason: 'spostata di $s');
        expect(c.percorso.manovre.map((m) => m.tipo), contains(23), reason: 'spostata di $s');
        // E senza riccioli né passi all'indietro dove si raccorda.
        expect(svoltaPiuStretta(c.percorso.punti), lessThan(90), reason: 'spostata di $s');
      }
    });

    test('in guida: sul ramo giusto non si esce di percorso, e si sente «al bivio tieni la destra»', () {
      final dopo = correggiContromano(dalVertice(), triangolo)!.percorso;
      final g = Guida(dopo);
      final detti = <String>[];
      // Si guida sulla strada vera: principale fino a W, poi il ramo giusto, poi verso sud.
      final (vero, _) = linea([(-160, 85), (-100, 60), (-57, 46), w, n, (1, -60), (2, -230)], passo: 9);
      for (final q in vero) {
        final av = g.aggiorna(q);
        expect(av.fuoriPercorso, isFalse, reason: 'a ${dove(q)}');
        if (av.daDire case final f?) detti.add(f);
      }
      expect(detti.where((f) => f.toLowerCase().contains('tieni la destra')), isNotEmpty);
      expect(detti.where((f) => f.contains('stretta')), isEmpty);
    });

    test('la guida corretta a metà strada resta a che punto era', () {
      final prima = dalVertice();
      final g = Guida(prima);
      final (vero, _) = linea([(-160, 85), (-100, 60), (-57, 46)], passo: 9);
      Avanzamento? ultimo;
      for (final q in vero) {
        ultimo = g.aggiorna(q);
      }
      final c = correggiContromano(prima, triangolo, daM: ultimo!.percorsiM, protettoM: ultimo.percorsiM + 20)!;
      final g2 = g.conCorrezione(c);
      final av = g2.aggiorna(a(-40, 40));
      expect(av.percorsiM, greaterThan(ultimo.percorsiM));
      expect(av.prossima!.tipo, 23);
      expect(av.allaProssimaM, closeTo(passaLungo(c.percorso, av.prossima!) - av.percorsiM, 0.5));
      expect(av.daDire, contains('tieni la destra'));
    });

    test('se l\'auto è già oltre il bivio giusto non si tocca niente (si ricalcolerà, come sempre)', () {
      final p = dalVertice();
      final l = Linea(p.punti);
      final oltreW = l.proietta(a(-3, 32)).lungoM;
      final diario = <String>[];
      expect(correggiContromano(p, triangolo, protettoM: oltreW, diario: diario.add), isNull);
      expect(diario, [contains('già passato')]);
    });
  });

  group('nei casi normali non cambia niente', () {
    test('una svolta stretta ma permessa, su strade a doppio senso', () {
      final strade = [
        strada([(0, -200), (0, 0)]),
        strada([(0, 0), (60, -100), (120, -200)])
      ];
      final (p, i) = linea([(0, -200), (0, 0), (60, -100), (120, -200)], sposta: (3, 5));
      final per =
          percorso(p, [(0, 1, 'Parti', ''), (i[1], 11, 'Svolta stretta a destra', ''), (p.length - 1, 4, '', '')]);
      expect(correggiContromano(per, strade), isNull);
    });

    test('una rotonda nel suo verso (antiorario), uscita a destra e uscita a sinistra', () {
      final anello = [
        for (var k = 0; k <= 36; k++)
          (20 * math.cos(k * math.pi / 18 - math.pi / 2), 20 * math.sin(k * math.pi / 18 - math.pi / 2))
      ];
      final strade = [
        strada(anello, senso: 1),
        strada([(0, -200), (0, -20)]),
        strada([(20, 0), (200, 0)]),
        strada([(-20, 0), (-200, 0)]),
      ];
      // A destra: da sud a est, un quarto di giro.
      final destra = [(0.0, -200.0), ...anello.sublist(0, 10), (200.0, 0.0)];
      // A sinistra: da sud a ovest, tre quarti di giro.
      final sinistra = [(0.0, -200.0), ...anello.sublist(0, 28), (-200.0, 0.0)];
      for (final giro in [destra, sinistra]) {
        for (final s in [(0.0, 0.0), (2.0, 4.0), (-3.0, -3.0)]) {
          final (p, _) = linea(giro, passo: 4, sposta: s);
          expect(correggiContromano(percorso(p, [(0, 1, '', ''), (p.length - 1, 4, '', '')]), strade), isNull);
        }
      }
    });

    test('sul viadotto sopra una strada a senso unico che va al contrario', () {
      final strade = [
        strada([(0, -400), (0, 400)], senso: 1, classe: 'primary'),
        // Sotto, sei metri più in là: un senso unico verso sud.
        strada([(6, 400), (6, -400)], senso: 1),
      ];
      final (p, _) = linea([(0, -400), (0, 400)], sposta: (4, 0));
      expect(correggiContromano(percorso(p, [(0, 1, '', ''), (p.length - 1, 4, '', '')]), strade), isNull);
    });

    test('strade a doppio senso, anche con la linea spostata di dieci metri', () {
      final strade = [
        strada([(-300, 0), (0, 0), (0, 300)]),
        strada([(0, 0), (300, 0)])
      ];
      final (p, _) = linea([(-300, 0), (0, 0), (0, 300)], sposta: (10, -10));
      expect(correggiContromano(percorso(p, [(0, 1, '', ''), (p.length - 1, 4, '', '')]), strade), isNull);
    });

    test('un senso unico nel verso giusto', () {
      final strade = [
        strada([(0, -300), (0, 300)], senso: 1),
        strada([(10, 300), (10, -300)], senso: -1)
      ];
      final (p, _) = linea([(0, -300), (0, 300)], sposta: (5, 0));
      expect(correggiContromano(percorso(p, [(0, 1, '', ''), (p.length - 1, 4, '', '')]), strade), isNull);
    });

    test('una carreggiata doppia: la linea spostata verso l\'altra resta sulla sua', () {
      final strade = [
        strada([(0, -400), (0, 400)], senso: 1, classe: 'trunk'),
        strada([(-20, 400), (-20, -400)], senso: 1, classe: 'trunk'),
      ];
      for (final dx in [-6.0, -9.0]) {
        final (p, _) = linea([(0, -400), (0, 400)], sposta: (dx, 0));
        expect(correggiContromano(percorso(p, [(0, 1, '', ''), (p.length - 1, 4, '', '')]), strade), isNull);
      }
    });

    test('contromano senza un\'alternativa corta: il percorso resta (niente giri lunghi)', () {
      // Un senso unico vietato e, per tornare, solo un giro di un chilometro.
      final strade = [
        strada([(0, -300), (0, 0)]),
        strada([(0, 300), (0, 0)], senso: 1),
        strada([(0, 300), (0, 600)]),
        strada([(0, 0), (500, 0), (500, 300), (0, 300)]),
      ];
      final (p, _) = linea([(0, -300), (0, 0), (0, 300), (0, 600)]);
      final diario = <String>[];
      expect(correggiContromano(percorso(p, [(0, 1, '', ''), (p.length - 1, 4, '', '')]), strade, diario: diario.add),
          isNull);
      // E nella diagnosi si legge perché.
      expect(diario, [contains('nessuna strada corta')]);
    });

    test('contromano proprio sulla meta: la meta non si sposta', () {
      final strade = [
        strada([(0, -300), (0, 0)]),
        strada([(0, 60), (0, 0)], senso: 1)
      ];
      final (p, _) = linea([(0, -300), (0, 0), (0, 40)]);
      expect(correggiContromano(percorso(p, [(0, 1, '', ''), (p.length - 1, 4, '', '')]), strade), isNull);
    });

    test('dove la mappa non ha strade non si dice niente', () {
      final (p, _) = linea([(0, -300), (0, 300)]);
      expect(correggiContromano(percorso(p, [(0, 1, '', ''), (p.length - 1, 4, '', '')]), const []), isNull);
      expect(
          correggiContromano(percorso(p, [(0, 1, '', ''), (p.length - 1, 4, '', '')]), [
            strada([(500, 0), (900, 0)], senso: 1)
          ]),
          isNull);
    });
  });

  group('le strade dalle tessere vettoriali', () {
    test('legge le linee del livello transportation, coi sensi unici, e salta il resto', () {
      final dati = tessera([
        (
          'water',
          [
            (<String, Object>{'class': 'lake'}, [(10, 10), (20, 20)])
          ]
        ),
        (
          'transportation',
          [
            (<String, Object>{'class': 'minor', 'oneway': 1}, [(2048, 2048), (2148, 2048), (2148, 1948)]),
            (<String, Object>{'class': 'primary', 'oneway': -1, 'brunnel': 'bridge'}, [(0, 0), (4096, 4096)]),
            (<String, Object>{'class': 'path'}, [(0, 4096), (4096, 0)]),
            (<String, Object>{'class': 'service'}, [(100, 100), (200, 100)]),
          ]
        ),
      ]);
      final t = tesseraDi(origine);
      final strade = stradeDaTessera(dati, zoomTessereStrade, t.x, t.y);
      expect(strade.map((s) => s.classe), ['minor', 'primary', 'service']);
      expect(strade.map((s) => s.senso), [1, -1, 0]);
      expect(strade[1].ponte, 'bridge');
      final m = strade.first.punti;
      expect(m, hasLength(3));
      // Verso est, poi verso nord (le y delle tessere crescono verso sud).
      expect(m[1].lon, greaterThan(m[0].lon));
      expect(m[1].lat, closeTo(m[0].lat, 1e-9));
      expect(m[2].lat, greaterThan(m[1].lat));
      // Il centro della tessera contiene l'origine? È nella tessera giusta.
      final centro = m.first;
      expect(tesseraDi(centro), t);
      expect(stradeDaTessera(Uint8List.fromList([1, 2, 3, 250]), 14, 0, 0), isEmpty);
    });

    test('le tessere attorno a una linea', () {
      final t = tessereAttorno([origine], marginiM: 10);
      expect(t, contains(tesseraDi(origine)));
      expect(tessereAttorno([origine], marginiM: 3000).length, greaterThan(4));
    });
  });
}

/// La svolta più stretta della linea, in gradi, fra pezzi di almeno un metro.
double svoltaPiuStretta(List<Punto> punti) {
  final pezzi = <double>[];
  var da = punti.first;
  for (final q in punti.skip(1)) {
    if (distanzaM(da, q) < 1) continue;
    pezzi.add(rottaGradi(da, q));
    da = q;
  }
  var peggio = 0.0;
  for (var i = 1; i < pezzi.length; i++) {
    peggio = math.max(peggio, diQuantoSiGira(pezzi[i - 1], pezzi[i]).abs());
  }
  return peggio;
}

/// I metri del punto di partenza della manovra [m] sul percorso [p].
double passaLungo(PercorsoCalcolato p, Manovra m) => Linea(p.punti).cumulate[m.inizio];

/* ─── Una tessera vettoriale, scritta a mano ───────────────────────────── */

Uint8List tessera(List<(String, List<(Map<String, Object>, List<(int, int)>)>)> livelli) {
  final out = <int>[];
  for (final (nome, elementi) in livelli) {
    final chiavi = <String>[], valori = <Object>[];
    final corpo = <int>[];
    _testo(corpo, 1, nome);
    for (final (props, linea) in elementi) {
      final etichette = <int>[];
      props.forEach((k, v) {
        if (!chiavi.contains(k)) chiavi.add(k);
        if (!valori.contains(v)) valori.add(v);
        etichette
          ..add(chiavi.indexOf(k))
          ..add(valori.indexOf(v));
      });
      final geo = <int>[];
      var cx = 0, cy = 0;
      for (var i = 0; i < linea.length; i++) {
        if (i == 0) geo.add(1 | (1 << 3));
        if (i == 1) geo.add(2 | ((linea.length - 1) << 3));
        geo
          ..add(_zz(linea[i].$1 - cx))
          ..add(_zz(linea[i].$2 - cy));
        cx = linea[i].$1;
        cy = linea[i].$2;
      }
      final el = <int>[];
      _pacco(el, 2, etichette);
      _varintCampo(el, 3, 2);
      _pacco(el, 4, geo);
      _sotto(corpo, 2, el);
    }
    for (final k in chiavi) {
      _testo(corpo, 3, k);
    }
    for (final v in valori) {
      final val = <int>[];
      if (v is String) {
        _testo(val, 1, v);
      } else if (v is int && v < 0) {
        _varintCampo(val, 6, _zz(v));
      } else if (v is int) {
        _varintCampo(val, 5, v);
      }
      _sotto(corpo, 4, val);
    }
    _varintCampo(corpo, 5, 4096);
    _varintCampo(corpo, 15, 2);
    _sotto(out, 3, corpo);
  }
  return Uint8List.fromList(out);
}

int _zz(int n) => (n << 1) ^ (n >> 63);

void _varint(List<int> b, int v) {
  while (v >= 0x80) {
    b.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  b.add(v);
}

void _varintCampo(List<int> b, int campo, int v) {
  _varint(b, campo << 3);
  _varint(b, v);
}

void _sotto(List<int> b, int campo, List<int> dentro) {
  _varint(b, (campo << 3) | 2);
  _varint(b, dentro.length);
  b.addAll(dentro);
}

void _testo(List<int> b, int campo, String s) => _sotto(b, campo, s.codeUnits);

void _pacco(List<int> b, int campo, List<int> valori) {
  final d = <int>[];
  for (final v in valori) {
    _varint(d, v);
  }
  _sotto(b, campo, d);
}
