import 'dart:convert';

import '../geo/geo.dart';
import 'luoghi.dart';

/// Un posto salvato in Google Maps, com'è nell'esportazione di Google
/// Takeout: nome, indirizzo, coordinate (se ci sono) e in che elenco stava.
class LuogoGoogle {
  const LuogoGoogle({required this.nome, this.indirizzo = '', this.posizione, this.lista = '', this.nota = ''});

  final String nome;
  final String indirizzo;

  /// `null` se Google non le ha scritte (negli elenchi CSV di solito no).
  final Punto? posizione;

  /// «Preferiti», «Voglio andarci», «Luoghi salvati»…
  final String lista;
  final String nota;

  Luogo? get luogo => posizione == null ? null : Luogo(nome: nome, descrizione: indirizzo, posizione: posizione!);
}

/// Legge i file di Google Takeout coi posti salvati: il GeoJSON di «Maps (i
/// tuoi luoghi)» (`Saved Places.json`, `Labeled places.json`) e i CSV degli
/// elenchi di «Salvati» (uno per elenco: Title, Note, URL).
abstract final class ImportaGoogle {
  /// Da un file: GeoJSON se comincia con `{`, se no CSV. [nomeFile] dà il
  /// nome dell'elenco ai CSV.
  static List<LuogoGoogle> leggi(String testo, {String nomeFile = ''}) {
    final t = testo.trimLeft().replaceFirst('﻿', '');
    final lista = _nomeLista(nomeFile);
    if (t.startsWith('{')) return geoJson(t, lista: lista);
    return csv(t, lista: lista);
  }

  static String _nomeLista(String file) {
    final base = file.split(RegExp(r'[/\\]')).last;
    final i = base.lastIndexOf('.');
    return (i > 0 ? base.substring(0, i) : base).trim();
  }

  /// Il GeoJSON di Takeout: vecchio formato (`Title`, `Location`) e nuovo
  /// (`location.name`, `location.address`). Le coordinate [0,0] vogliono
  /// dire «non so».
  static List<LuogoGoogle> geoJson(String testo, {String lista = ''}) {
    final j = jsonDecode(testo);
    if (j is! Map) return const [];
    final fuori = <LuogoGoogle>[];
    for (final f in ((j['features'] as List?) ?? const []).whereType<Map>()) {
      final prop = (f['properties'] as Map?) ?? const {};
      final loc = (prop['location'] as Map?) ?? (prop['Location'] as Map?) ?? const {};
      final nome = [
        loc['name'],
        prop['Title'],
        prop['name'],
        loc['Business Name'],
        loc['address'],
        loc['Address'],
      ].whereType<String>().where((s) => s.trim().isNotEmpty).firstOrNull;
      final indirizzo = [loc['address'], loc['Address']].whereType<String>().firstOrNull ?? '';
      Punto? p;
      final c = (f['geometry'] as Map?)?['coordinates'];
      if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
        final lon = (c[0] as num).toDouble(), lat = (c[1] as num).toDouble();
        if (lat != 0 || lon != 0) p = Punto(lat, lon);
      }
      final geo = loc['Geo Coordinates'];
      if (p == null && geo is Map) {
        final lat = double.tryParse('${geo['Latitude']}'), lon = double.tryParse('${geo['Longitude']}');
        if (lat != null && lon != null && (lat != 0 || lon != 0)) p = Punto(lat, lon);
      }
      final url = [prop['google_maps_url'], prop['Google Maps URL']].whereType<String>().firstOrNull;
      p ??= url == null ? null : coordinateDaUrl(url);
      if (nome == null && p == null) continue;
      fuori.add(
        LuogoGoogle(
          nome: nome ?? 'Posto salvato',
          indirizzo: nome == indirizzo ? '' : indirizzo,
          posizione: p,
          lista: lista,
          nota: [prop['Comment'], prop['comment']].whereType<String>().firstOrNull ?? '',
        ),
      );
    }
    return fuori;
  }

  /// Un elenco CSV di «Salvati»: la prima riga dice le colonne (in inglese o
  /// in italiano).
  static List<LuogoGoogle> csv(String testo, {String lista = ''}) {
    final righe = righeCsv(testo);
    if (righe.isEmpty) return const [];
    final testa = [for (final c in righe.first) c.trim().toLowerCase()];
    int colonna(List<String> nomi) => testa.indexWhere(nomi.contains);
    final iNome = colonna(['title', 'titolo', 'nome', 'name']);
    final iUrl = colonna(['url', 'link']);
    final iNota = colonna(['note', 'nota', 'comment', 'commento']);
    if (iNome < 0 && iUrl < 0) return const [];
    final fuori = <LuogoGoogle>[];
    for (var r in righe.skip(1)) {
      // Un link con le virgole senza virgolette spezza la riga: i pezzi in
      // più tornano nel link.
      final troppi = r.length - testa.length;
      if (troppi > 0 && iUrl >= 0 && iUrl < r.length) {
        r = [...r.take(iUrl), r.sublist(iUrl, iUrl + troppi + 1).join(','), ...r.skip(iUrl + troppi + 1)];
      }
      String campo(int i) => i >= 0 && i < r.length ? r[i].trim() : '';
      final url = campo(iUrl);
      var nome = campo(iNome);
      if (nome.isEmpty) nome = nomeDaUrl(url) ?? '';
      final p = coordinateDaUrl(url);
      if (nome.isEmpty && p == null) continue;
      fuori.add(
        LuogoGoogle(nome: nome.isEmpty ? 'Posto salvato' : nome, posizione: p, lista: lista, nota: campo(iNota)),
      );
    }
    return fuori;
  }

  /// Le coordinate scritte nel link di Google Maps, se ci sono: `!3d…!4d…`,
  /// `@lat,lon`, `q=lat,lon`, `/search/lat,lon`.
  static Punto? coordinateDaUrl(String url) {
    final u = Uri.decodeFull(url);
    final d = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)').firstMatch(u);
    if (d != null) return _punto(d.group(1)!, d.group(2)!);
    for (final r in [
      RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)'),
      RegExp(r'[?&](?:q|query|ll|destination)=(-?\d+\.\d+),\s*(-?\d+\.\d+)'),
      RegExp(r'/(?:search|place|dir)/(-?\d+\.\d+),\s*\+?(-?\d+\.\d+)'),
    ]) {
      final m = r.firstMatch(u);
      if (m != null) return _punto(m.group(1)!, m.group(2)!);
    }
    return null;
  }

  /// Il nome nel link: `/maps/place/Colosseo/…` → «Colosseo».
  static String? nomeDaUrl(String url) {
    final m = RegExp(r'/maps/place/([^/@?]+)').firstMatch(url);
    if (m == null) return null;
    final n = Uri.decodeComponent(m.group(1)!.replaceAll('+', ' ')).trim();
    return n.isEmpty || coordinateDaUrl('/search/$n') != null ? null : n;
  }

  static Punto? _punto(String a, String b) {
    final lat = double.tryParse(a), lon = double.tryParse(b);
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180 || (lat == 0 && lon == 0)) return null;
    return Punto(lat, lon);
  }

  /// Le righe di un CSV, con le virgolette («"a, b"», «""»).
  static List<List<String>> righeCsv(String testo) {
    final righe = <List<String>>[];
    var riga = <String>[];
    final campo = StringBuffer();
    var virgolette = false;
    for (var i = 0; i < testo.length; i++) {
      final c = testo[i];
      if (virgolette) {
        if (c == '"') {
          if (i + 1 < testo.length && testo[i + 1] == '"') {
            campo.write('"');
            i++;
          } else {
            virgolette = false;
          }
        } else {
          campo.write(c);
        }
      } else if (c == '"') {
        virgolette = true;
      } else if (c == ',') {
        riga.add(campo.toString());
        campo.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < testo.length && testo[i + 1] == '\n') i++;
        riga.add(campo.toString());
        campo.clear();
        if (riga.any((x) => x.isNotEmpty)) righe.add(riga);
        riga = <String>[];
      } else {
        campo.write(c);
      }
    }
    riga.add(campo.toString());
    if (riga.any((x) => x.isNotEmpty)) righe.add(riga);
    return righe;
  }

  /// I posti senza coordinate si cercano per nome (una richiesta alla volta,
  /// al più [massimo]); quelli non trovati tornano in `mancanti`.
  static Future<({List<(LuogoGoogle, Luogo)> trovati, List<LuogoGoogle> mancanti})> risolvi(
    List<LuogoGoogle> posti,
    FonteLuoghi fonte, {
    int massimo = 300,
    Punto? vicinoA,
    void Function(int fatti, int totale)? avanzamento,
  }) async {
    final trovati = <(LuogoGoogle, Luogo)>[];
    final mancanti = <LuogoGoogle>[];
    var cercati = 0;
    for (final (i, p) in posti.indexed) {
      avanzamento?.call(i, posti.length);
      if (p.luogo case final l?) {
        trovati.add((p, l));
        continue;
      }
      if (cercati >= massimo) {
        mancanti.add(p);
        continue;
      }
      cercati++;
      try {
        final r = await fonte.cerca(p.nome, vicinoA: vicinoA);
        if (r.isEmpty) {
          mancanti.add(p);
        } else {
          final primo = r.first;
          trovati.add((
            p,
            Luogo(
              nome: p.nome,
              descrizione: primo.descrizione.isEmpty ? primo.nome : primo.descrizione,
              posizione: primo.posizione,
            ),
          ));
        }
      } catch (_) {
        mancanti.add(p);
      }
    }
    avanzamento?.call(posti.length, posti.length);
    return (trovati: trovati, mancanti: mancanti);
  }
}
