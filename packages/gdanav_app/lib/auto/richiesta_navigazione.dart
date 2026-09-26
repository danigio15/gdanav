import 'package:gdanav_core/gdanav_core.dart';

/// Una richiesta di navigazione arrivata all'auto (NF-6, VC-1): «Ok Google,
/// naviga verso…» o un'altra app che chiede un percorso. Android Auto la
/// manda come `geo:`: `geo:45.46,9.19?q=Duomo`, `geo:0,0?q=Via Roma 1,
/// Milano`, `geo:0,0?q=45.46,9.19(Duomo)`, con `intent=add_a_stop` per una
/// tappa. Si accetta anche `google.navigation:q=…`.
class RichiestaNavigazione {
  const RichiestaNavigazione({this.testo, this.punto, this.tappa = false});

  /// Cosa cercare, o il nome del posto se c'è già il punto.
  final String? testo;
  final Punto? punto;

  /// Una tappa da aggiungere al viaggio, non una meta nuova.
  final bool tappa;

  static final _coordinate = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*(?:\((.*)\))?\s*$');

  /// `null` se non c'è né un posto né qualcosa da cercare.
  static RichiestaNavigazione? leggi(String uri) {
    final due = uri.indexOf(':');
    if (due < 0) return null;
    final schema = uri.substring(0, due).toLowerCase();
    if (schema != 'geo' && schema != 'google.navigation') return null;
    var resto = uri.substring(due + 1);
    if (resto.startsWith('//')) resto = resto.substring(2);
    final domanda = resto.indexOf('?');
    final percorso = schema == 'geo' ? (domanda < 0 ? resto : resto.substring(0, domanda)) : '';
    final query = schema == 'geo' ? (domanda < 0 ? '' : resto.substring(domanda + 1)) : resto;
    final parametri = <String, String>{};
    for (final parte in query.split('&')) {
      if (parte.isEmpty) continue;
      final uguale = parte.indexOf('=');
      final chiave = uguale < 0 ? parte : parte.substring(0, uguale);
      final valore = uguale < 0 ? '' : parte.substring(uguale + 1);
      parametri[chiave] = _decodifica(valore);
    }
    final tappa = parametri['intent'] == 'add_a_stop';
    var q = parametri['q']?.trim();
    if (q != null && q.isEmpty) q = null;

    // Le coordinate nel percorso (geo:45.46,9.19), se non sono 0,0.
    Punto? punto;
    final c = _coordinate.firstMatch(percorso.split(';').first);
    if (c != null) {
      final lat = double.parse(c.group(1)!), lon = double.parse(c.group(2)!);
      if (lat != 0 || lon != 0) punto = Punto(lat, lon);
    }
    // O nella domanda: q=45.46,9.19(Duomo).
    if (q != null) {
      final cq = _coordinate.firstMatch(q);
      if (cq != null) {
        punto = Punto(double.parse(cq.group(1)!), double.parse(cq.group(2)!));
        final nome = cq.group(3)?.trim();
        q = nome == null || nome.isEmpty ? null : nome;
      }
    }
    if (punto == null && q == null) return null;
    return RichiestaNavigazione(testo: q, punto: punto, tappa: tappa);
  }

  static String _decodifica(String s) {
    try {
      return Uri.decodeQueryComponent(s);
    } catch (_) {
      return s.replaceAll('+', ' ');
    }
  }
}
