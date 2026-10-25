import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo/geo.dart';
import 'luoghi.dart';
import 'luoghi_categorie.dart';

/// La ricerca di TomTom (Fuzzy Search), con la stessa chiave dei percorsi e
/// del traffico.
///
/// Photon conosce un numero civico solo se qualcuno l'ha mappato su
/// OpenStreetMap, e un'attività solo per nome: «Via Roma 10» tornava la via
/// senza il civico, e «farmacia» o «benzinaio» non trovavano niente. TomTom ha
/// i civici (anche quelli ricavati dai tratti di via) e cerca le attività per
/// categoria, in italiano: «farmacia» dà le farmacie vicine.
class ClienteTomTomLuoghi implements FonteLuoghi {
  ClienteTomTomLuoghi(this.chiave, {http.Client? client, Uri? indirizzo})
      : _http = client ?? http.Client(),
        indirizzo = indirizzo ?? Uri.parse('https://api.tomtom.com/search/2/search/');

  final String chiave;
  final Uri indirizzo;
  final http.Client _http;

  /// La ricerca delle sole attivita' (`poiSearch`), accanto alla Fuzzy.
  ///
  /// «Non mi trova le aziende»: la Fuzzy «mentre scrivi» mette davanti vie e
  /// indirizzi che cominciano con le stesse lettere, e in dieci risultati
  /// un'azienda col nome a meta' non entrava. La ricerca delle attivita'
  /// guarda solo quelle — negozi, locali, aziende, uffici — nei dintorni, e
  /// i suoi risultati si aggiungono a quelli della Fuzzy.
  Uri get indirizzoAttivita => indirizzo.resolve('../poiSearch/');

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    final q = testo.trim();
    if (q.length < 3) return const [];
    // Il testo sta nel percorso: si toglie la barra, che lo spezzerebbe.
    final pezzo = '${Uri.encodeComponent(q.replaceAll('/', ' '))}.json';
    final tutto = indirizzo.resolve(pezzo).replace(queryParameters: {
      'key': chiave,
      'language': 'it-IT',
      'limit': '10',
      // «Mentre scrivi»: «via roma 1» trova anche il 10 e il 12.
      'typeahead': 'true',
      if (vicinoA != null) ...{'lat': '${vicinoA.lat}', 'lon': '${vicinoA.lon}'},
    });
    final attivita = indirizzoAttivita.resolve(pezzo).replace(queryParameters: {
      'key': chiave,
      'language': 'it-IT',
      'limit': '20',
      if (vicinoA != null) ...{'lat': '${vicinoA.lat}', 'lon': '${vicinoA.lon}', 'radius': '50000'},
    });
    Future<List<Luogo>?> chiedi(Uri uri, {required bool obbligatoria}) async {
      try {
        final r = await _http.get(uri);
        if (r.statusCode != 200) throw Exception('TomTom ricerca: ${r.statusCode}');
        return leggi(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>);
      } catch (_) {
        if (obbligatoria) rethrow;
        return null;
      }
    }

    // Se le attivita' non rispondono resta la Fuzzy; se non risponde la
    // Fuzzy, l'errore e' suo (e chi chiama passa alle altre fonti).
    final risposte = await Future.wait([
      chiedi(tutto, obbligatoria: true),
      chiedi(attivita, obbligatoria: false),
    ]);
    final fuori = <Luogo>[];
    for (final l in [...?risposte[0], ...?risposte[1]]) {
      final doppio = fuori.any((g) =>
          LuoghiInsieme.normalizzato(g.nome) == LuoghiInsieme.normalizzato(l.nome) &&
          distanzaM(g.posizione, l.posizione) < 150);
      if (!doppio) fuori.add(l);
    }
    return fuori;
  }

  /// Legge la risposta della Fuzzy Search.
  static List<Luogo> leggi(Map<String, Object?> json) {
    final luoghi = <Luogo>[];
    for (final r in ((json['results'] as List?) ?? const []).whereType<Map>()) {
      final pos = r['position'];
      if (pos is! Map || pos['lat'] is! num || pos['lon'] is! num) continue;
      final a = ((r['address'] as Map?) ?? const {}).cast<String, Object?>();
      final via = a['streetName'] as String?;
      final civico = a['streetNumber'] as String?;
      final viaCivico = [via, civico].whereType<String>().where((s) => s.isNotEmpty).join(' ');
      final comune = (a['municipality'] as String?) ?? (a['localName'] as String?);
      final provincia = a['countrySecondarySubdivision'] as String?;
      final poi = r['poi'] as Map?;
      final String? nome;
      final List<String?> sotto;
      if (r['type'] == 'POI' && poi?['name'] is String) {
        nome = poi!['name'] as String;
        final categoria = ((poi['categories'] as List?) ?? const []).whereType<String>().firstOrNull;
        sotto = [
          if (categoria != null) _maiuscola(categoriaInItaliano(categoria)),
          viaCivico.isEmpty ? null : viaCivico,
          comune,
        ];
      } else if (viaCivico.isNotEmpty) {
        nome = viaCivico;
        sotto = [comune, provincia];
      } else {
        nome = comune ?? (a['freeformAddress'] as String?);
        sotto = [provincia, a['countrySubdivision'] as String?];
      }
      if (nome == null || nome.isEmpty) continue;
      final descrizione = sotto.whereType<String>().where((s) => s.isNotEmpty && s != nome).toSet().join(', ');
      luoghi.add(Luogo(
        nome: nome,
        descrizione: descrizione,
        posizione: Punto((pos['lat'] as num).toDouble(), (pos['lon'] as num).toDouble()),
      ));
    }
    return luoghi;
  }

  static String _maiuscola(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// TomTom le categorie le scrive in inglese anche con `language=it-IT`
  /// («General car repair servicing»): le piu' comuni si dicono in italiano.
  /// Quelle che non si conoscono restano come arrivano.
  static String categoriaInItaliano(String categoria) => _categorie[categoria.trim().toLowerCase()] ?? categoria;

  static const _categorie = {
    'general car repair servicing': 'officina',
    'car repair': 'officina',
    'repair facility': 'officina',
    'automotive dealer': 'concessionario',
    'tyre services': 'gommista',
    'car wash': 'autolavaggio',
    'petrol station': 'distributore',
    'electric vehicle station': 'colonnina di ricarica',
    'parking garage': 'parcheggio',
    'open parking area': 'parcheggio',
    'company': 'azienda',
    'government office': 'ufficio',
    'non governmental organization': 'associazione',
    'real estate agents': 'agenzia immobiliare',
    'bank': 'banca',
    'atm': 'bancomat',
    'post office': 'ufficio postale',
    'hotel': 'albergo',
    'hotel motel': 'albergo',
    'bed breakfast guest houses': 'bed and breakfast',
    'apartment': 'appartamento',
    'restaurant': 'ristorante',
    'italian': 'ristorante italiano',
    'pizza': 'pizzeria',
    'fast food': 'fast food',
    'cafe': 'bar',
    'cafe pub': 'bar',
    'pub': 'pub',
    'bar': 'bar',
    'food drinks: food shops': 'alimentari',
    'food drinks: grocers': 'alimentari',
    'grocers': 'alimentari',
    'bakery': 'panetteria',
    'supermarkets hypermarkets': 'supermercato',
    'supermarket': 'supermercato',
    'pharmacy': 'farmacia',
    'hospital polyclinic': 'ospedale',
    'hospital': 'ospedale',
    'health care service': 'servizio sanitario',
    'doctor': 'medico',
    'general practitioner': 'medico',
    'dentist': 'dentista',
    'veterinarian': 'veterinario',
    'school': 'scuola',
    'university': 'università',
    'church': 'chiesa',
    'place of worship': 'luogo di culto',
    'important tourist attraction': 'attrazione turistica',
    'museum': 'museo',
    'shop': 'negozio',
    'clothing shop': 'abbigliamento',
    'hairdresser': 'parrucchiere',
    'beauty salon': 'centro estetico',
    'fitness club center': 'palestra',
    'sports center': 'centro sportivo',
    'cinema': 'cinema',
    'nightlife': 'locale notturno',
    'railway station': 'stazione',
    'bus stop': 'fermata dell\'autobus',
    'airport': 'aeroporto',
    'police station': 'polizia',
    'city hall': 'municipio',
    'lawyer': 'avvocato',
    'accountant': 'commercialista',
  };
}

/// Prima una fonte, poi l'altra se la prima non risponde o non trova niente.
///
/// TomTom ha un piano gratuito: se finisce, o la rete del momento non lo
/// raggiunge, la ricerca non deve restare muta. Photon fa da riserva.
class LuoghiConRiserva implements FonteLuoghi {
  const LuoghiConRiserva(this.prima, this.riserva);

  final FonteLuoghi prima;
  final FonteLuoghi riserva;

  @override
  Future<List<Luogo>> cerca(String testo, {Punto? vicinoA}) async {
    try {
      final trovati = await prima.cerca(testo, vicinoA: vicinoA);
      if (trovati.isNotEmpty) return trovati;
    } catch (_) {
      // Si prova con la riserva; se sbaglia anche quella, lo dice lei.
    }
    return riserva.cerca(testo, vicinoA: vicinoA);
  }
}

/// Tutte e due le fonti insieme, e prima quello che si chiama come si e'
/// scritto.
///
/// «Esiste come locale ma non lo trovi»: «nonna ma burger» dava solo la
/// pizzeria con lo stesso nome davanti. TomTom e OpenStreetMap conoscono
/// locali diversi — un pub aperto da poco, un ristorante che solo uno dei due
/// ha — e usarne uno e tenere l'altro di riserva voleva dire perdere quelli
/// dell'altro. Adesso si chiedono insieme: i risultati si mettono uno dopo
/// l'altro, quelli doppi (stesso nome, a meno di 150 m) una volta sola, e in
/// testa vanno quelli col nome che contiene tutte le parole scritte, accenti
/// e maiuscole a parte. Se una fonte non risponde, resta l'altra.
///
/// «I pub non sono completi»: quando il testo e' una categoria («pub»,
/// «farmacia», «aziende») e si sa dove si e', si chiede anche la fonte delle
/// categorie ([LuoghiPerCategoria]) e la lista non e' piu' di dodici in
/// ordine di nome, ma di tutti — fino a [quantiPerCategoria] — in ordine di
/// distanza: chi cerca «pub» vuole i pub vicini, non quelli col nome giusto.
class LuoghiInsieme implements FonteLuoghi {
  const LuoghiInsieme(
    this.prima,
    this.seconda, {
    this.categorie,
    this.altre = const [],
    this.quanti = 15,
    this.quantiPerCategoria = 50,
  });

  final FonteLuoghi prima;
  final FonteLuoghi seconda;

  /// Le fonti in piu', chieste insieme alle prime due: HERE, che conosce le
  /// aziende dei registri delle imprese.
  final List<FonteLuoghi> altre;

  /// La fonte delle categorie, se c'e'.
  final FonteLuoghi? categorie;
  final int quanti;
  final int quantiPerCategoria;

  /// Oltre questa distanza un risultato resta solo se si chiama come si e'
  /// scritto.
  static const lontanoKm = 300;

  /// Il nome contiene tutte le parole scritte (anche a meta').
  static bool haTutteLeParole(Luogo l, String testo) {
    final parole = normalizzato(testo).split(' ').where((p) => p.length >= 2).toList();
    final nome = normalizzato(l.nome).split(' ');
    return parole.isNotEmpty && parole.every((p) => nome.any((n) => n.startsWith(p)));
  }

  /// Le forme della societa', senza punti.
  static const _sigle = {'spa', 'srl', 'srls', 'snc', 'sas'};

  /// Senza la forma della societa': «Verdi Servizi S.p.A.» dava alberghi e
  /// banche di Roma perche' «S.p.A.» pesava quanto il nome, e «verdi servizi
  /// spa napoli» cercava i centri benessere. Si toglie in fondo, scritta coi
  /// punti, o dopo almeno due parole; «terme spa napoli» resta com'e'.
  static String senzaSigla(String testo) {
    final parole = testo.trim().split(RegExp(r'\s+'));
    final tenute = <String>[];
    for (var i = 0; i < parole.length; i++) {
      final p = parole[i].toLowerCase();
      final sigla = _sigle.contains(p.replaceAll(RegExp(r'[.,]'), ''));
      final siCapisce = i == parole.length - 1 || p.contains('.') || tenute.length >= 2;
      if (sigla && tenute.isNotEmpty && siCapisce) continue;
      tenute.add(parole[i]);
    }
    final pulito = tenute.join(' ').replaceAll(RegExp(r'[\s,]+$'), '').trim();
    return pulito.length >= 3 ? pulito : testo;
  }

  @override
  Future<List<Luogo>> cerca(String scritto, {Punto? vicinoA}) async {
    final testo = senzaSigla(scritto);
    Future<List<Luogo>?> da(FonteLuoghi f) async {
      try {
        return await f.cerca(testo, vicinoA: vicinoA);
      } catch (_) {
        return null;
      }
    }

    final perCategoria = vicinoA != null && categoriaDi(testo) != null ? categorie : null;
    final risposte = await Future.wait([
      da(prima),
      da(seconda),
      for (final f in altre) da(f),
      if (perCategoria != null) da(perCategoria),
    ]);
    if (risposte.every((r) => r == null)) {
      // Nessuna ha risposto: lo dice la seconda, col suo errore.
      return seconda.cerca(testo, vicinoA: vicinoA);
    }
    final dellaCategoria = perCategoria != null ? risposte.last : null;
    final delleFonti = perCategoria != null ? risposte.sublist(0, risposte.length - 1) : risposte;
    final tutti = <Luogo>[];
    // Prima quelli della categoria, che sono sicuramente quello che si cerca.
    for (final l in [...?dellaCategoria, for (final r in delleFonti) ...?r]) {
      final doppio =
          tutti.any((g) => normalizzato(g.nome) == normalizzato(l.nome) && distanzaM(g.posizione, l.posizione) < 150);
      if (!doppio) tutti.add(l);
    }
    if (perCategoria != null) {
      final qui = vicinoA!;
      tutti.sort((a, b) => distanzaM(qui, a.posizione).compareTo(distanzaM(qui, b.posizione)));
      return tutti.take(quantiPerCategoria).toList();
    }
    // «verdi servizi» dava anche Cipro, la Spagna e il Canada: Photon cerca
    // in tutto il mondo. Lontano piu' di [lontanoKm] resta solo chi ha nel
    // nome tutte le parole scritte (chi cerca un posto preciso lo trova).
    final vicini = vicinoA == null
        ? tutti
        : tutti.where((l) => distanzaM(vicinoA, l.posizione) <= lontanoKm * 1000 || haTutteLeParole(l, testo)).toList();
    return ordinatiPerNome(vicini, testo, vicinoA: vicinoA).take(quanti).toList();
  }

  /// Minuscole, senza accenti e senza segni: «Nonna Mà» e «nonna ma» sono la
  /// stessa cosa.
  static String normalizzato(String s) {
    const accenti = {
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n'
    };
    final minuscolo = s.toLowerCase();
    final b = StringBuffer();
    for (final c in minuscolo.split('')) {
      b.write(accenti[c] ?? c);
    }
    return b.toString().replaceAll(RegExp(r"[^a-z0-9]+"), ' ').trim();
  }

  /// I luoghi in ordine di quante parole scritte hanno nel nome (contano
  /// anche quelle a meta': «burg» vale «burger»), poi nella riga sotto — la
  /// via, la citta': «verdi servizi napoli» vuole quelli di Napoli prima di
  /// quelli di Roma. In cima chi le ha tutte. A parita', il piu' vicino a
  /// [vicinoA], o l'ordine delle fonti se non si sa dove si e'.
  static List<Luogo> ordinatiPerNome(List<Luogo> luoghi, String testo, {Punto? vicinoA}) {
    final parole = normalizzato(testo).split(' ').where((p) => p.length >= 2).toList();
    if (parole.isEmpty) return luoghi;
    int punti(Luogo l) {
      final nome = normalizzato(l.nome).split(' ');
      final sotto = normalizzato(l.descrizione).split(' ');
      bool dentro(List<String> dove, String p) => dove.any((n) => n.startsWith(p));
      final nelNome = parole.where((p) => dentro(nome, p)).length;
      final nelSotto = parole.where((p) => !dentro(nome, p) && dentro(sotto, p)).length;
      if (nelNome == parole.length) return 4000 + nelNome;
      if (nelNome + nelSotto == parole.length) return 2000 + nelNome * 2;
      return nelNome * 2 + nelSotto;
    }

    double distanza(Luogo l) => vicinoA == null ? 0 : distanzaM(vicinoA, l.posizione);
    final conPunti = [for (var i = 0; i < luoghi.length; i++) (i, punti(luoghi[i]), distanza(luoghi[i]), luoghi[i])];
    conPunti.sort((a, b) {
      if (b.$2 != a.$2) return b.$2.compareTo(a.$2);
      if (a.$3 != b.$3) return a.$3.compareTo(b.$3);
      return a.$1.compareTo(b.$1);
    });
    return [for (final c in conPunti) c.$4];
  }
}
