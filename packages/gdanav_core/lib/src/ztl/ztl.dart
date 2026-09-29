import 'dart:convert';
import 'dart:math' as math;

import '../geo/geo.dart';
import 'orari.dart';

export 'orari.dart';

/// Che zona è: una ZTL (col permesso ci si passa, senza si gira al largo
/// quando è attiva) o un'area pedonale (in auto mai).
enum TipoZona { ztl, pedonale }

/// Un rettangolo sulla carta: sud, ovest, nord, est.
class Rettangolo {
  const Rettangolo(this.sud, this.ovest, this.nord, this.est);

  final double sud, ovest, nord, est;

  bool contiene(Punto p) => p.lat >= sud && p.lat <= nord && p.lon >= ovest && p.lon <= est;

  bool tocca(Rettangolo r) => r.sud <= nord && r.nord >= sud && r.ovest <= est && r.est >= ovest;

  /// Allargato (o stretto, se negativo) di [metri] per lato.
  Rettangolo allargato(double metri) {
    final dLat = metri / 111320;
    final dLon = metri / (111320 * math.cos((sud + nord) / 2 * math.pi / 180).abs().clamp(0.2, 1.0));
    return Rettangolo(sud - dLat, ovest - dLon, nord + dLat, est + dLon);
  }

  /// Per le `avoidAreas` di TomTom.
  Map<String, Object?> perTomTom() => {
        'southWestCorner': {'latitude': sud, 'longitude': ovest},
        'northEastCorner': {'latitude': nord, 'longitude': est},
      };

  static Rettangolo di(Iterable<Punto> punti) {
    var s = 90.0, o = 180.0, n = -90.0, e = -180.0;
    for (final p in punti) {
      s = math.min(s, p.lat);
      n = math.max(n, p.lat);
      o = math.min(o, p.lon);
      e = math.max(e, p.lon);
    }
    return Rettangolo(s, o, n, e);
  }

  @override
  bool operator ==(Object other) =>
      other is Rettangolo && other.sud == sud && other.ovest == ovest && other.nord == nord && other.est == est;

  @override
  int get hashCode => Object.hash(sud, ovest, nord, est);

  @override
  String toString() => 'Rettangolo($sud, $ovest, $nord, $est)';
}

/// Una ZTL o un'area pedonale, da OpenStreetMap.
class ZonaLimitata {
  ZonaLimitata({
    required this.id,
    required this.tipo,
    required this.nome,
    this.citta,
    this.orari,
    this.orariTesto,
    required this.anelli,
  }) : riquadro = Rettangolo.di(anelli.expand((a) => a));

  /// L'oggetto di OpenStreetMap: «w123» o «r456». Resta lo stesso da un
  /// archivio all'altro, ed è quello a cui si lega il permesso.
  final String id;
  final TipoZona tipo;

  /// «Centro storico», senza «ZTL» davanti.
  final String nome;

  /// La città, quando si sa: «Napoli».
  final String? citta;

  /// Quando è attiva. `null`: sempre (o l'orario scritto non si capisce).
  final OrariZtl? orari;

  /// L'orario com'è scritto in OpenStreetMap, anche quando non si capisce.
  final String? orariTesto;

  /// I contorni esterni. I buchi non servono: per girare al largo conta
  /// il bordo.
  final List<List<Punto>> anelli;

  final Rettangolo riquadro;

  /// «Napoli · Centro storico», o il nome solo.
  String get etichetta => citta == null || citta!.isEmpty ? nome : '$citta · $nome';

  /// Se è attiva a [quando]. Le aree pedonali lo sono sempre.
  bool attivaAlle(DateTime quando) => tipo == TipoZona.pedonale || (orari?.attivaAlle(quando) ?? true);

  /// Se [p] sta dentro (pari e dispari, su tutti i contorni).
  bool contiene(Punto p) {
    if (!riquadro.contiene(p)) return false;
    var dentro = false;
    for (final anello in anelli) {
      if (_nellAnello(anello, p)) dentro = !dentro;
    }
    return dentro;
  }

  static bool _nellAnello(List<Punto> a, Punto p) {
    var dentro = false;
    for (var i = 0, j = a.length - 1; i < a.length; j = i++) {
      final pi = a[i], pj = a[j];
      if ((pi.lat > p.lat) != (pj.lat > p.lat) &&
          p.lon < (pj.lon - pi.lon) * (p.lat - pi.lat) / (pj.lat - pi.lat) + pi.lon) {
        dentro = !dentro;
      }
    }
    return dentro;
  }

  /// Se il tratto da [a] a [b] attraversa un contorno: per i percorsi coi
  /// punti radi, che potrebbero saltare un angolo senza mettere un punto
  /// dentro.
  bool attraversa(Punto a, Punto b) {
    if (!riquadro.tocca(Rettangolo.di([a, b]))) return false;
    for (final anello in anelli) {
      for (var i = 0, j = anello.length - 1; i < anello.length; j = i++) {
        if (_siIncrociano(a, b, anello[j], anello[i])) return true;
      }
    }
    return false;
  }

  static bool _siIncrociano(Punto p1, Punto p2, Punto q1, Punto q2) {
    double lato(Punto a, Punto b, Punto c) => (b.lon - a.lon) * (c.lat - a.lat) - (b.lat - a.lat) * (c.lon - a.lon);
    final d1 = lato(q1, q2, p1), d2 = lato(q1, q2, p2), d3 = lato(p1, p2, q1), d4 = lato(p1, p2, q2);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  /// I rettangoli da evitare per girarle al largo: al massimo [quanti], e
  /// tutta la zona coperta.
  ///
  /// Un rettangolo solo, per una zona storta, prende dentro anche le strade
  /// fuori — spesso proprio quella che le gira intorno. Si taglia allora in
  /// strisce orizzontali, e di ogni striscia si prende il pezzo di zona che
  /// ci cade: la scala che ne viene sta molto più attaccata al bordo. Poi si
  /// stringe di [margineM] per lato, per lasciare libere le strade sul
  /// confine: i varchi sono lì, e la strada che gira intorno è fuori.
  List<Rettangolo> copertura({int quanti = 4, double margineM = 10}) {
    final perAnello = math.max(1, quanti ~/ math.max(1, anelli.length));
    final fuori = <Rettangolo>[];
    for (final anello in anelli) {
      final r = Rettangolo.di(anello);
      final strisce = math.max(1, perAnello);
      final alto = (r.nord - r.sud) / strisce;
      for (var k = 0; k < strisce; k++) {
        final s = r.sud + alto * k, n = k == strisce - 1 ? r.nord : r.sud + alto * (k + 1);
        final pezzo = _taglia(anello, s, n);
        if (pezzo.isEmpty) continue;
        fuori.add(Rettangolo.di(pezzo));
      }
    }
    final stretti = [
      for (final r in fuori)
        if (margineM > 0 && _abbastanzaGrande(r, margineM * 3)) r.allargato(-margineM) else r,
    ];
    return stretti.length <= quanti ? stretti : [Rettangolo.di(anelli.expand((a) => a)).allargato(-margineM)];
  }

  static bool _abbastanzaGrande(Rettangolo r, double metri) {
    final alto = (r.nord - r.sud) * 111320;
    final largo = (r.est - r.ovest) * 111320 * math.cos((r.sud + r.nord) / 2 * math.pi / 180);
    return alto > metri && largo > metri;
  }

  /// L'[anello] tagliato fra le latitudini [sud] e [nord] (Sutherland–Hodgman
  /// su due lati).
  static List<Punto> _taglia(List<Punto> anello, double sud, double nord) {
    List<Punto> contro(List<Punto> punti, bool Function(Punto) dentro, double lat) {
      if (punti.isEmpty) return punti;
      final out = <Punto>[];
      for (var i = 0; i < punti.length; i++) {
        final a = punti[(i + punti.length - 1) % punti.length], b = punti[i];
        final aDentro = dentro(a), bDentro = dentro(b);
        Punto incrocio() {
          final t = (lat - a.lat) / (b.lat - a.lat);
          return Punto(lat, a.lon + (b.lon - a.lon) * t);
        }

        if (bDentro) {
          if (!aDentro) out.add(incrocio());
          out.add(b);
        } else if (aDentro) {
          out.add(incrocio());
        }
      }
      return out;
    }

    final sopra = contro(anello, (p) => p.lat >= sud, sud);
    return contro(sopra, (p) => p.lat <= nord, nord);
  }
}

/// Cosa fa un percorso con le ZTL: quali gira al largo, da quali passa col
/// permesso, di quale chiedere, e se la meta è dentro. Viaggia col percorso
/// (`PercorsoCalcolato.ztl`), fino al foglio del viaggio.
class ZtlDelViaggio {
  const ZtlDelViaggio({
    this.evitate = const [],
    this.attraversate = const [],
    this.daChiedere,
    this.puntiPassandoci = const [],
    this.durataPassandoci,
    this.metaDentro,
    this.varco,
    this.nonEvitate = const [],
    this.pedonali = const [],
  });

  /// Attive e senza permesso (o senza risposta): il percorso le gira al
  /// largo. Non c'è quella della meta, che ha [metaDentro].
  final List<ZonaLimitata> evitate;

  /// Col permesso: il percorso ci passa.
  final List<ZonaLimitata> attraversate;

  /// La prima attiva di cui non si sa se c'è il permesso: la domanda.
  final ZonaLimitata? daChiedere;

  /// Il percorso che ci passa, per la domanda: la linea tratteggiata sulla
  /// mappa, e quanto ci si mette.
  final List<Punto> puntiPassandoci;
  final Duration? durataPassandoci;

  /// La meta è dentro questa ZTL, attiva e senza permesso: il percorso
  /// arriva al [varco], l'ultimo punto fuori sulla strada che ci entra.
  final ZonaLimitata? metaDentro;
  final Punto? varco;

  /// Quelle da cui non si è riusciti a stare fuori: non c'era un'altra
  /// strada, o TomTom non l'ha trovata.
  final List<ZonaLimitata> nonEvitate;

  /// Le aree pedonali che il percorso gira intorno.
  final List<ZonaLimitata> pedonali;

  static const nessuna = ZtlDelViaggio();

  bool get vuota =>
      evitate.isEmpty &&
      attraversate.isEmpty &&
      daChiedere == null &&
      metaDentro == null &&
      nonEvitate.isEmpty &&
      pedonali.isEmpty;

  /// Lo stesso, senza più la domanda: la risposta è arrivata.
  ZtlDelViaggio senzaDomanda() => ZtlDelViaggio(
        evitate: evitate,
        attraversate: attraversate,
        metaDentro: metaDentro,
        varco: varco,
        nonEvitate: nonEvitate,
        pedonali: pedonali,
      );
}

/// Dove un percorso entra in una ZTL.
class IngressoZtl {
  const IngressoZtl(this.zona, this.indice);

  final ZonaLimitata zona;

  /// Il primo punto del percorso dentro la zona.
  final int indice;
}

/// Tutte le ZTL e le aree pedonali d'Italia, da OpenStreetMap, con un
/// indice a celle per trovare subito quelle vicine.
class ArchivioZtl {
  ArchivioZtl(List<ZonaLimitata> zone, {this.generato}) : zone = List.unmodifiable(zone) {
    for (var i = 0; i < zone.length; i++) {
      final r = zone[i].riquadro;
      for (var la = _cella(r.sud); la <= _cella(r.nord); la++) {
        for (var lo = _cella(r.ovest); lo <= _cella(r.est); lo++) {
          (_celle[(la, lo)] ??= []).add(i);
        }
      }
    }
  }

  static final vuoto = ArchivioZtl(const []);

  final List<ZonaLimitata> zone;
  final DateTime? generato;
  final _celle = <(int, int), List<int>>{};

  /// Celle di un decimo di grado: una città ne occupa una o due.
  static int _cella(double gradi) => (gradi * 10).floor();

  int get quanteZtl => zone.where((z) => z.tipo == TipoZona.ztl).length;
  int get quantePedonali => zone.where((z) => z.tipo == TipoZona.pedonale).length;

  ZonaLimitata? perId(String id) => zone.where((z) => z.id == id).firstOrNull;

  /// Le zone che toccano [r].
  List<ZonaLimitata> nel(Rettangolo r) {
    final visti = <int>{};
    final fuori = <ZonaLimitata>[];
    for (var la = _cella(r.sud); la <= _cella(r.nord); la++) {
      for (var lo = _cella(r.ovest); lo <= _cella(r.est); lo++) {
        for (final i in _celle[(la, lo)] ?? const <int>[]) {
          if (visti.add(i) && zone[i].riquadro.tocca(r)) fuori.add(zone[i]);
        }
      }
    }
    return fuori;
  }

  /// Le zone entro [raggioM] da [qui].
  List<ZonaLimitata> vicine(Punto qui, double raggioM) =>
      nel(Rettangolo(qui.lat, qui.lon, qui.lat, qui.lon).allargato(raggioM));

  /// Le ZTL in cui entra il percorso [punti], nell'ordine in cui ci entra.
  /// Non conta quella in cui si parte già dentro: da lì si esce e basta.
  List<IngressoZtl> ztlSulPercorso(List<Punto> punti) {
    if (punti.length < 2) return const [];
    final fuori = <IngressoZtl>[];
    for (final z in nel(Rettangolo.di(punti))) {
      if (z.tipo != TipoZona.ztl) continue;
      final daDentro = z.contiene(punti.first);
      var eraDentro = daDentro;
      for (var i = 1; i < punti.length; i++) {
        final dentro =
            z.contiene(punti[i]) || (!eraDentro && z.attraversa(punti[i - 1], punti[i]) && _torna(z, punti, i));
        if (dentro && !eraDentro) {
          fuori.add(IngressoZtl(z, i));
          break;
        }
        eraDentro = dentro;
      }
    }
    fuori.sort((a, b) => a.indice.compareTo(b.indice));
    return fuori;
  }

  /// Un tratto che taglia un angolo della zona senza punti dentro: conta
  /// come entrarci solo se non è il bordo sfiorato di un soffio (il punto
  /// dopo è dentro, o il tratto è lungo).
  static bool _torna(ZonaLimitata z, List<Punto> punti, int i) =>
      distanzaM(punti[i - 1], punti[i]) > 60 || (i + 1 < punti.length && z.contiene(punti[i + 1]));

  /// Le aree pedonali che il percorso sfiora (entro [entroM]): quelle che
  /// gira intorno.
  List<ZonaLimitata> pedonaliLungo(List<Punto> punti, {double entroM = 20}) {
    if (punti.length < 2) return const [];
    final linea = Linea(punti);
    return [
      for (final z in nel(Rettangolo.di(punti).allargato(entroM)))
        if (z.tipo == TipoZona.pedonale && z.anelli.expand((a) => a).any((p) => linea.proietta(p).lontanoM <= entroM))
          z,
    ];
  }

  // ─── Il file ─────────────────────────────────────────────────────────

  /// L'archivio nel file dell'app: coordinate intere (1e5, un metro circa) e
  /// a differenze, che vuol dire numeri piccoli.
  ///
  /// `{"v":1,"generato":"…","z":[[id,tipo,nome,città,orari,[anello…]],…]}`
  /// con tipo 0 = ZTL e 1 = pedonale, e ogni anello `[lat0,lon0,dlat,dlon,…]`.
  static String scrivi(List<ZonaLimitata> zone, {DateTime? generato}) => jsonEncode({
        'v': 1,
        'generato': (generato ?? DateTime.now().toUtc()).toIso8601String(),
        'z': [
          for (final z in zone)
            [
              z.id,
              z.tipo.index,
              z.nome,
              z.citta ?? '',
              z.orariTesto ?? '',
              [for (final a in z.anelli) _codifica(a)],
            ],
        ],
      });

  static List<int> _codifica(List<Punto> anello) {
    final out = <int>[];
    var lat = 0, lon = 0;
    for (final p in anello) {
      final la = (p.lat * 1e5).round(), lo = (p.lon * 1e5).round();
      out
        ..add(la - lat)
        ..add(lo - lon);
      lat = la;
      lon = lo;
    }
    return out;
  }

  static List<Punto> _decodifica(List<Object?> numeri) {
    final out = <Punto>[];
    var lat = 0, lon = 0;
    for (var i = 0; i + 1 < numeri.length; i += 2) {
      lat += (numeri[i] as num).toInt();
      lon += (numeri[i + 1] as num).toInt();
      out.add(Punto(lat / 1e5, lon / 1e5));
    }
    return out;
  }

  static ArchivioZtl leggi(String testo) {
    final j = jsonDecode(testo) as Map<String, Object?>;
    final zone = <ZonaLimitata>[];
    for (final r in ((j['z'] as List?) ?? const []).whereType<List>()) {
      final anelli = [
        for (final a in (r[5] as List).whereType<List>())
          if (_decodifica(a) case final punti when punti.length >= 3) punti,
      ];
      if (anelli.isEmpty) continue;
      final tipo = (r[1] as num).toInt() == 1 ? TipoZona.pedonale : TipoZona.ztl;
      final orari = '${r[4]}';
      zone.add(ZonaLimitata(
        id: '${r[0]}',
        tipo: tipo,
        nome: '${r[2]}',
        citta: '${r[3]}'.isEmpty ? null : '${r[3]}',
        orari: tipo == TipoZona.ztl && orari.isNotEmpty ? _leggiOrari(orari) : null,
        orariTesto: orari.isEmpty ? null : orari,
        anelli: anelli,
      ));
    }
    return ArchivioZtl(zone, generato: DateTime.tryParse('${j['generato'] ?? ''}'));
  }

  /// Gli orari nel file sono il testo di OpenStreetMap: un divieto a tempo
  /// (con la «@») o un `opening_hours`.
  static OrariZtl? _leggiOrari(String testo) =>
      testo.contains('@') ? OrariZtl.daCondizione(testo) : OrariZtl.leggi(testo);
}
