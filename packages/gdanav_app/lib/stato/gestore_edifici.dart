import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../sorgenti/pmtiles.dart';

/// Gli edifici veri per la scena 3D, da Overture Maps.
///
/// «Lungo il percorso voglio vedere le cose reali.» Le tessere di OpenFreeMap
/// hanno gli edifici di OpenStreetMap, e in tanti paesi non li ha disegnati
/// nessuno: a Carinaro, entro 150 m da via Torretta, 5 edifici dove è tutto
/// costruito. Overture unisce quelli di OpenStreetMap a quelli che Microsoft
/// ha ricavato dalle foto dal satellite, con l'altezza: lì sono 43.
///
/// Gli edifici sono in pacchetti, uno per cella z8 (circa 150 km di lato),
/// nella release «edifici» del repository di GdANav (vedi
/// `strumenti/edifici/prepara.py`). Il pacchetto della zona si scarica una
/// volta, su una rete che non si paga a consumo, e poi si legge dal telefono:
/// nessun server da chiamare a ogni tessera, e va anche senza rete. Finché
/// non c'è, la scena usa gli edifici di sempre.
///
/// Finché il pacchetto intero non c'è (non si è mai stati sul Wi-Fi con la
/// scena aperta, o la zona è nuova: in auto il telefono va coi dati a
/// consumo), le tessere si leggono una per una dal pacchetto della release,
/// a pezzi (HTTP «Range», vedi [SorgenteHttp]): una ventina di kilobyte per
/// tessera, al più [limiteAConsumo] al giorno sui dati a consumo. Quelle lette
/// restano sul telefono ([limiteCopie] in tutto), e tornando per la stessa
/// strada non si richiedono.
///
/// Ogni mese il pacchetto si rifà con l'ultimo rilascio di Overture. Ognuno
/// sul telefono si ricorda da che versione viene (un file accanto, `.versione`):
/// quando l'indice ne dice un'altra, lo si riscarica alle stesse condizioni, e
/// intanto la scena continua con quello di prima finché il nuovo non è
/// arrivato intero.
class GestoreEdifici {
  GestoreEdifici({
    http.Client? client,
    Future<Directory> Function()? cartella,
    Future<bool> Function()? aConsumo,
    Uri? base,
    this.indiceValido = const Duration(days: 1),
    this.riprovaIndice = const Duration(minutes: 5),
    this.limiteAConsumo = 30 * 1000 * 1000,
    this.limiteCopie = 80 * 1000 * 1000,
    this.riprovaInRete = const Duration(minutes: 1),
    DateTime Function()? orologio,
  }) : _http = client ?? http.Client(),
       _ora = orologio ?? DateTime.now,
       _cartellaDi = cartella ?? (() async => Directory('${(await getApplicationSupportDirectory()).path}/edifici')),
       _aConsumo = aConsumo ?? reteAConsumo,
       _base = base ?? Uri.parse('https://github.com/danigio15/gdanav/releases/download/edifici/');

  /// Quello dell'app, per chi apre la scena 3D (anche sull'auto).
  static GestoreEdifici? attuale;

  /// Lo zoom delle celle dei pacchetti.
  static const zoomCelle = 8;

  /// Chi dice gli edifici d'Overture, da scrivere sulla mappa.
  static const attribuzione = '© Overture Maps Foundation, Microsoft';

  final http.Client _http;
  final Future<Directory> Function() _cartellaDi;
  final Future<bool> Function() _aConsumo;
  final Uri _base;

  /// Ogni quanto si rilegge l'indice dei pacchetti.
  final Duration indiceValido;

  /// Quanti byte al giorno si leggono in rete, a tessere, sui dati a consumo.
  final int limiteAConsumo;

  /// Quanti byte di tessere lette in rete si tengono sul telefono.
  final int limiteCopie;

  /// Dopo un pacchetto in rete che non si è aperto, quanto si aspetta a riprovare.
  final Duration riprovaInRete;

  final DateTime Function() _ora;

  /// I pacchetti letti in rete, a pezzi, per cella (finché non c'è quello intero).
  final _inRete = <String, Future<LettorePmtiles?>>{};

  /// Quando un pacchetto in rete non si è aperto: fino a [riprovaInRete] dopo non si richiede.
  final _inReteFallito = <String, DateTime>{};

  /// I byte letti in rete oggi ([_giornoConsumo]), sui dati a consumo.
  int? _consumoOggi;
  String? _giornoConsumo;

  /// Le copie scritte da quando si è guardato quanto pesano.
  var _copieNuove = 0;

  final _lettori = <String, Future<LettorePmtiles?>>{};

  /// Gli scaricamenti in corso: chi chiede la stessa cella aspetta quello.
  final _inArrivo = <String, Future<bool>>{};
  Map<String, VocePacchetto>? _indice;
  DateTime? _indiceLetto;

  /// L'ultima volta che si è chiesto l'indice, riuscita o no: senza rete non
  /// lo si richiede a ogni tessera.
  DateTime? _indiceChiesto;

  /// Ogni quanto si riprova a leggere l'indice quando non è arrivato.
  final Duration riprovaIndice;

  /// Le celle già confrontate con l'indice di adesso: si riguardano quando
  /// l'indice si rilegge (una volta al giorno), non a ogni tessera.
  final _controllate = <String>{};

  /// La cella z8 che contiene la tessera [z]/[x]/[y] (z ≥ 8), come «8/x/y».
  static String cellaDi(int z, int x, int y) {
    final s = z - zoomCelle;
    return '$zoomCelle/${x >> s}/${y >> s}';
  }

  static String fileDi(String cella) => 'edifici-${cella.replaceAll('/', '-')}.pmtiles';

  /// La tessera [z]/[x]/[y] coi soli edifici: dal pacchetto della sua zona,
  /// se è sul telefono; altrimenti la si legge in rete (vedi [_tesseraInRete])
  /// e il pacchetto intero si chiede. `null`: non ci sono (la scena usa gli
  /// edifici di sempre).
  Future<Uint8List?> tessera(int z, int x, int y) async {
    if (z < zoomCelle) return null;
    final cella = cellaDi(z, x, y);
    try {
      final l = await _lettore(cella);
      if (l == null) {
        // Il pacchetto intero, quando si può; intanto questa tessera, in rete.
        unawaited(scarica(cella));
        return await _tesseraInRete(cella, z, x, y);
      }
      // C'è: si guarda, una volta per indice, se ne è uscito uno più nuovo.
      if (!_controllate.contains(cella) || _daRileggere) unawaited(scarica(cella));
      return await l.tessera(z, x, y);
    } catch (e) {
      debugPrint('edifici $cella: $e');
      return null;
    }
  }

  Future<LettorePmtiles?> _lettore(String cella) => _lettori[cella] ??= () async {
    final f = File('${(await _cartellaDi()).path}/${fileDi(cella)}');
    if (!await f.exists()) {
      _lettori.remove(cella);
      return null;
    }
    try {
      return await LettorePmtiles.apri(f.path);
    } on FormatException {
      // Un file rovinato: via, e alla prossima si riscarica.
      await f.delete().catchError((Object _) => f);
      _lettori.remove(cella);
      return null;
    }
  }();

  /// Scarica il pacchetto di [cella] se c'è nell'indice, la rete non si paga
  /// a consumo, e sul telefono non c'è già (o c'è di una versione vecchia).
  /// Torna `true` se adesso un pacchetto c'è.
  Future<bool> scarica(String cella) => _inArrivo[cella] ??= _scarica(cella).whenComplete(() {
    // Senza graffe tornerebbe il futuro tolto, cioè questo: si aspetterebbe da solo.
    _inArrivo.remove(cella);
  });

  static File _fileVersione(File pacchetto) => File('${pacchetto.path}.versione');

  Future<bool> _scarica(String cella) async {
    var presente = false;
    try {
      final dir = await _cartellaDi();
      final f = File('${dir.path}/${fileDi(cella)}');
      presente = await f.exists();
      final indice = await _leggiIndice();
      _controllate.add(cella);
      final voce = indice?[cella];
      // Senza indice (niente rete) o senza la cella si tiene quello che c'è.
      if (voce == null) return presente;
      if (presente && await _aggiornato(f, voce)) return true;
      if (await _aConsumo()) return presente;
      await dir.create(recursive: true);
      final mezzo = File('${f.path}.mezzo');
      final r = await _http.send(http.Request('GET', _base.resolve(fileDi(cella))));
      if (r.statusCode != 200) return presente;
      final s = mezzo.openWrite();
      await r.stream.pipe(s);
      if (await mezzo.length() != voce.byte) {
        await mezzo.delete();
        return presente;
      }
      // Il nuovo al posto del vecchio: chi legge il vecchio lo finisce (il
      // file aperto resta suo), le tessere dopo vengono dal nuovo.
      await mezzo.rename(f.path);
      await _fileVersione(f).writeAsString(voce.versione);
      final vecchio = _lettori.remove(cella);
      if (vecchio != null) unawaited(_chiudiPoi(vecchio));
      // Col pacchetto intero le tessere lette in rete non servono più.
      _inRete.remove(cella);
      await _cartellaCopie(dir, cella).delete(recursive: true).catchError((Object _) => dir);
      return true;
    } catch (e) {
      debugPrint('edifici: non scaricato $cella: $e');
      return presente;
    }
  }

  /// La tessera letta in rete, a pezzi, dal pacchetto della release: dalla
  /// copia sul telefono se c'è (della versione dell'indice), altrimenti una
  /// richiesta. Sui dati a consumo al più [limiteAConsumo] byte al giorno.
  Future<Uint8List?> _tesseraInRete(String cella, int z, int x, int y) async {
    final indice = await _leggiIndice();
    final voce = indice?[cella];
    if (voce == null) return null;
    final dir = await _cartellaDi();
    final copie = _cartellaCopie(dir, cella);
    final copia = File('${copie.path}/$z-$x-$y.mvt');
    final versione = File('${copie.path}/versione');
    if (await copia.exists()) {
      if (await versione.exists() && (await versione.readAsString()).trim() == voce.versione) {
        final b = await copia.readAsBytes();
        // Vuota: in quella tessera di edifici non ce ne sono.
        return b.isEmpty ? null : b;
      }
      // Di un pacchetto vecchio: via tutte.
      await copie.delete(recursive: true).catchError((Object _) => copie);
    }
    final aConsumo = await _aConsumo();
    if (aConsumo && await _consumati() >= limiteAConsumo) return null;
    final fallito = _inReteFallito[cella];
    if (fallito != null && _ora().difference(fallito) < riprovaInRete) return null;
    final lettore = await (_inRete[cella] ??= _apriInRete(cella, voce));
    if (lettore == null) return null;
    final dati = await lettore.tessera(z, x, y);
    // Intanto è arrivato il pacchetto intero (lo scarica [tessera] in
    // sottofondo, e ha già tolto le copie): una copia adesso resterebbe lì.
    if (await File('${dir.path}/${fileDi(cella)}').exists()) return dati;
    try {
      await copie.create(recursive: true);
      if (!await versione.exists()) await versione.writeAsString(voce.versione);
      await copia.writeAsBytes(dati ?? Uint8List(0), flush: false);
      if (++_copieNuove >= 40) {
        _copieNuove = 0;
        unawaited(_potaCopie(dir));
      }
    } catch (e) {
      debugPrint('edifici: copia non scritta $cella: $e');
    }
    return dati;
  }

  Future<LettorePmtiles?> _apriInRete(String cella, VocePacchetto voce) async {
    try {
      final sorgente = SorgenteHttp(_http, _base.resolve(fileDi(cella)), letti: _conta);
      return await LettorePmtiles.daSorgente(sorgente.leggi, lunghezza: voce.byte);
    } catch (e) {
      debugPrint('edifici: in rete non si apre $cella: $e');
      _inRete.remove(cella);
      _inReteFallito[cella] = _ora();
      return null;
    }
  }

  static Directory _cartellaCopie(Directory dir, String cella) =>
      Directory('${dir.path}/tessere/${cella.replaceAll('/', '-')}');

  String _oggi() {
    final o = _ora();
    return '${o.year}-${o.month}-${o.day}';
  }

  File _fileConsumo(Directory dir) => File('${dir.path}/consumo-in-rete.json');

  /// I byte letti in rete oggi (si ricordano anche chiudendo l'app).
  Future<int> _consumati() async {
    final oggi = _oggi();
    if (_giornoConsumo == oggi && _consumoOggi != null) return _consumoOggi!;
    var n = 0;
    try {
      final f = _fileConsumo(await _cartellaDi());
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map && j['giorno'] == oggi && j['byte'] is num) n = (j['byte'] as num).toInt();
      }
    } catch (_) {}
    _giornoConsumo = oggi;
    _consumoOggi = n;
    return n;
  }

  /// Conta i byte arrivati (tutti: anche sul Wi-Fi, ma il limite vale solo a consumo).
  void _conta(int byte) {
    unawaited(() async {
      try {
        if (!await _aConsumo()) return;
        final n = await _consumati() + byte;
        _consumoOggi = n;
        final dir = await _cartellaDi();
        await dir.create(recursive: true);
        await _fileConsumo(dir).writeAsString(jsonEncode({'giorno': _giornoConsumo, 'byte': n}));
      } catch (_) {}
    }());
  }

  /// Le copie delle tessere oltre [limiteCopie]: via le più vecchie.
  Future<void> _potaCopie(Directory dir) async {
    try {
      final radice = Directory('${dir.path}/tessere');
      if (!await radice.exists()) return;
      final file = <(File, FileStat)>[];
      await for (final e in radice.list(recursive: true)) {
        if (e is File && e.path.endsWith('.mvt')) file.add((e, await e.stat()));
      }
      var tot = file.fold<int>(0, (a, f) => a + f.$2.size);
      if (tot <= limiteCopie) return;
      file.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (f, st) in file) {
        if (tot <= limiteCopie * 3 ~/ 4) break;
        await f.delete().catchError((Object _) => f);
        tot -= st.size;
      }
    } catch (_) {}
  }

  /// Se il pacchetto [f] sul telefono è quello che dice l'indice.
  Future<bool> _aggiornato(File f, VocePacchetto voce) async {
    final v = _fileVersione(f);
    if (await v.exists()) return (await v.readAsString()).trim() == voce.versione;
    // Scaricato prima che si segnasse la versione: se pesa uguale è lui.
    if (await f.length() == voce.byte) {
      await v.writeAsString(voce.versione);
      return true;
    }
    return false;
  }

  /// Chiude un lettore sostituito, dopo che chi ci stava leggendo ha finito.
  Future<void> _chiudiPoi(Future<LettorePmtiles?> lettore) async {
    await Future<void>.delayed(const Duration(seconds: 10));
    try {
      await (await lettore)?.chiudi();
    } catch (_) {}
  }

  /// Se è ora di rileggere l'indice: è vecchio, e non lo si è appena chiesto.
  bool get _daRileggere {
    final adesso = DateTime.now();
    final letto = _indiceLetto, chiesto = _indiceChiesto;
    if (letto != null && adesso.difference(letto) < indiceValido) return false;
    return chiesto == null || adesso.difference(chiesto) >= riprovaIndice;
  }

  /// L'indice dei pacchetti: cella → byte e versione. Si rilegge una volta al
  /// giorno; a ogni rilettura le celle si riconfrontano.
  Future<Map<String, VocePacchetto>?> _leggiIndice() async {
    if (!_daRileggere) return _indice;
    _indiceChiesto = DateTime.now();
    try {
      final r = await _http.get(_base.resolve('indice.json')).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return _indice;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final celle = j is Map ? j['celle'] : null;
      if (celle is! Map) return _indice;
      final rilascio = '${j['rilascio_overture'] ?? ''}';
      _indice = {
        for (final MapEntry(:key, :value) in celle.entries)
          if (value is Map && value['byte'] is num)
            '$key': VocePacchetto(
              byte: (value['byte'] as num).toInt(),
              // Il rilascio e il peso: un pacchetto rifatto con lo stesso
              // rilascio ma diverso (lo strumento è cambiato) si riscarica.
              versione: '$rilascio/${(value['byte'] as num).toInt()}',
            ),
      };
      _indiceLetto = DateTime.now();
      _controllate.clear();
      // Un indice nuovo può dire pacchetti nuovi: quelli in rete si riaprono.
      _inRete.clear();
      _inReteFallito.clear();
    } catch (_) {}
    return _indice;
  }
}

/// Un pacchetto nell'indice: quanto pesa e di che versione è.
class VocePacchetto {
  const VocePacchetto({required this.byte, required this.versione});
  final int byte;
  final String versione;
}

/// Se la rete di adesso si paga a consumo (i dati del telefono, un hotspot).
/// Nel dubbio sì: un pacchetto può pesare un centinaio di megabyte.
Future<bool> reteAConsumo() async {
  try {
    return await const MethodChannel('gdanav/rete').invokeMethod<bool>('aConsumo') ?? true;
  } catch (_) {
    return true;
  }
}
