import 'package:flutter/foundation.dart';
import 'package:gdanav_core/gdanav_core.dart';

import 'archivio.dart';

enum TipoPreferito { casa, lavoro, altro }

/// Un posto salvato: Casa, Lavoro, o un preferito col suo nome.
class Preferito {
  const Preferito(this.tipo, this.luogo, {this.nome = '', this.lista = ''});

  final TipoPreferito tipo;
  final Luogo luogo;

  /// Per gli «altro»: come l'ha chiamato chi l'ha salvato.
  final String nome;

  /// L'elenco da cui viene (importato da Google Maps: «Preferiti», «Voglio
  /// andarci»…); vuoto per quelli salvati qui.
  final String lista;

  String get etichetta => switch (tipo) {
    TipoPreferito.casa => 'Casa',
    TipoPreferito.lavoro => 'Lavoro',
    TipoPreferito.altro => nome.isEmpty ? luogo.nome : nome,
  };

  Map<String, Object?> toJson() => {
    'tipo': tipo.name,
    'nome': nome,
    if (lista.isNotEmpty) 'lista': lista,
    'luogo': luogoJson(luogo),
  };

  static Preferito? daJson(Object? j) {
    if (j is! Map) return null;
    final tipo = TipoPreferito.values.where((t) => t.name == j['tipo']).firstOrNull;
    final luogo = luogoDaJson(j['luogo']);
    if (tipo == null || luogo == null) return null;
    return Preferito(tipo, luogo, nome: j['nome'] as String? ?? '', lista: j['lista'] as String? ?? '');
  }
}

Map<String, Object?> luogoJson(Luogo l) => {
  'nome': l.nome,
  'descrizione': l.descrizione,
  'lat': l.posizione.lat,
  'lon': l.posizione.lon,
};

Luogo? luogoDaJson(Object? j) {
  if (j is! Map) return null;
  final lat = j['lat'], lon = j['lon'], nome = j['nome'];
  if (lat is! num || lon is! num || nome is! String) return null;
  return Luogo(
    nome: nome,
    descrizione: j['descrizione'] as String? ?? '',
    posizione: Punto(lat.toDouble(), lon.toDouble()),
  );
}

/// Casa, Lavoro, i preferiti e le ultime mete, come in Waze.
class GestoreLuoghi extends ChangeNotifier {
  GestoreLuoghi(this.archivio);

  final Archivio archivio;
  static const massimoRecenti = 15;

  var preferiti = <Preferito>[];
  var recenti = <Luogo>[];

  Preferito? get casa => preferiti.where((p) => p.tipo == TipoPreferito.casa).firstOrNull;
  Preferito? get lavoro => preferiti.where((p) => p.tipo == TipoPreferito.lavoro).firstOrNull;
  Iterable<Preferito> get altri => preferiti.where((p) => p.tipo == TipoPreferito.altro);

  Future<void> carica() async {
    final j = await archivio.luoghi();
    preferiti = [for (final p in (j['preferiti'] as List?) ?? const []) ?Preferito.daJson(p)];
    recenti = [for (final l in (j['recenti'] as List?) ?? const []) ?luogoDaJson(l)];
    notifyListeners();
  }

  Future<void> salva(Preferito p) async {
    // Casa e Lavoro sono uno solo: il nuovo prende il posto del vecchio.
    preferiti = [
      for (final q in preferiti)
        if (p.tipo == TipoPreferito.altro || q.tipo != p.tipo) q,
      p,
    ];
    await _scrivi();
  }

  /// Tanti preferiti insieme (un'importazione): quelli che ci sono già
  /// (stesso nome, a meno di 30 m) non si ripetono. Restituisce quanti ne
  /// sono entrati.
  Future<int> aggiungiTanti(Iterable<Preferito> nuovi) async {
    final lista = List.of(preferiti);
    var entrati = 0;
    for (final p in nuovi) {
      final doppio = lista.any(
        (q) => q.etichetta == p.etichetta && distanzaM(q.luogo.posizione, p.luogo.posizione) < 30,
      );
      if (doppio) continue;
      lista.add(p);
      entrati++;
    }
    preferiti = lista;
    await _scrivi();
    return entrati;
  }

  /// I preferiti che contengono [testo] nel nome o nell'indirizzo, per la
  /// ricerca.
  List<Preferito> cercaSalvati(String testo) {
    final t = testo.trim().toLowerCase();
    if (t.isEmpty) return const [];
    return [
      for (final p in preferiti)
        if (p.etichetta.toLowerCase().contains(t) || p.luogo.descrizione.toLowerCase().contains(t)) p,
    ];
  }

  Future<void> togli(Preferito p) async {
    preferiti = [
      for (final q in preferiti)
        if (!identical(q, p)) q,
    ];
    await _scrivi();
  }

  /// Una meta appena scelta va in cima ai recenti, una volta sola.
  Future<void> usato(Luogo l) async {
    recenti = [
      l,
      for (final r in recenti)
        if (!_stesso(r, l)) r,
    ].take(massimoRecenti).toList();
    await _scrivi();
  }

  Future<void> dimentica(Luogo l) async {
    recenti = [
      for (final r in recenti)
        if (!_stesso(r, l)) r,
    ];
    await _scrivi();
  }

  static bool _stesso(Luogo a, Luogo b) => a.nome == b.nome && distanzaM(a.posizione, b.posizione) < 30;

  Future<void> _scrivi() async {
    notifyListeners();
    await archivio.salvaLuoghi({
      'preferiti': [for (final p in preferiti) p.toJson()],
      'recenti': [for (final l in recenti) luogoJson(l)],
    });
  }
}
