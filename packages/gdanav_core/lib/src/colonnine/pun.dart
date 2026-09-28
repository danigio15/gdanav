import '../geo/geo.dart';
import 'colonnina.dart';

/// La Piattaforma Unica Nazionale dei punti di ricarica (MASE), nella forma
/// in cui la pubblica onData: una riga per punto di ricarica, licenza
/// CC BY 4.0 — «Dati: PUN (MASE), elaborazione onData».
///
/// È la fonte che ha quello che OpenStreetMap non ha. Al Centro
/// Direzionale di Napoli OpenStreetMap conosce quattro stazioni e nove
/// prese; la PUN ci ha 842 punti di ricarica in quattordici posti — la
/// Centro Direzionale Isola A3 da 202, il Parcheggio P5 di Via Domenico
/// Aulisio da 194: gli stessi numeri che mostrano ABRP ed EVDC.
///
/// Una riga è un punto di ricarica (EVSE), cioè **un'auto alla volta**: se
/// ha più spine (CCS e CHAdeMO insieme) se ne tiene la migliore, perché
/// contarle tutte direbbe due auto dove se ne carica una.
///
/// Lo stato della riga non si usa. I dati sono una fotografia (quella di
/// onData è del 2024): una presa guasta allora oggi può andare, e dirla
/// guasta sarebbe una bugia peggio di «non si sa».
abstract final class Pun {
  /// I codici operatore (party ID) di cui si è sicuri. Gli altri restano
  /// il codice: meglio «GES» che un nome indovinato.
  static const operatori = {
    'ENX': 'Enel X',
    'BEC': 'Plenitude (Be Charge)',
    'PLN': 'Plenitude',
    'A2A': 'A2A',
    'EWI': 'Ewiva',
    'DUF': 'Duferco',
    'F2X': 'Free To X',
    'ION': 'Ionity',
    'TSL': 'Tesla',
    'TES': 'Tesla',
    // Confermati dai nomi dei posti: «Atlante - ToDream…», «Powy Metropark…».
    'ATE': 'Atlante',
    'PWY': 'Powy',
  };

  /// Le colonnine del CSV di onData (`pdr_latest_ready.csv`), una per posto
  /// (`id_location`), con le prese per auto adatte alle auto.
  static List<Colonnina> leggiCsv(String testo) {
    final righe = _csv(testo);
    if (righe.isEmpty) return const [];
    final intestazione = righe.first;
    int colonna(String nome) {
      final i = intestazione.indexOf(nome);
      if (i < 0) throw FormatException('PUN: manca la colonna «$nome»');
      return i;
    }

    final cLuogo = colonna('id_location');
    final cNome = colonna('nome_location');
    final cIndirizzo = colonna('indirizzo');
    final cEvse = colonna('id_evse');
    final cStato = colonna('stato');
    final cStandard = colonna('standard_del_connettore');
    final cPotenza = colonna('potenza_erogabile');
    final cLat = colonna('latitudine_evse');
    final cLon = colonna('longitudine_evse');

    final perLuogo = <String, _Luogo>{};
    for (final r in righe.skip(1)) {
      if (r.length < intestazione.length) continue;
      // Non costruita, o tolta: per chi guida non c'è.
      final stato = r[cStato].trim().toUpperCase();
      if (stato == 'PLANNED' || stato == 'REMOVED') continue;
      final lat = double.tryParse(r[cLat]), lon = double.tryParse(r[cLon]);
      if (lat == null || lon == null || lat == 0 || lon == 0) continue;
      final presa = _presa(r[cStandard], r[cPotenza]);
      if (presa == null) continue;
      final id = r[cLuogo].trim();
      if (id.isEmpty) continue;
      final luogo = perLuogo.putIfAbsent(
        id,
        () => _Luogo(id, r[cNome].trim(), r[cIndirizzo].trim(), _operatore(r[cEvse])),
      );
      luogo.lat.add(lat);
      luogo.lon.add(lon);
      luogo.prese.add(presa);
    }

    return [
      for (final l in perLuogo.values)
        Colonnina(
          id: 'pun:${l.id}',
          nome: _nome(l),
          operatore: l.operatore,
          // Il centro dei suoi punti di ricarica: in un parcheggio grande
          // stanno sparsi, e la colonnina è lì in mezzo.
          posizione: Punto(_media(l.lat), _media(l.lon)),
          connettori: l.prese,
          fonte: 'pun',
        ),
    ];
  }

  /// La presa di un punto di ricarica: la migliore fra quelle che ha.
  static Connettore? _presa(String standard, String watt) {
    final tipi = standard.split(',').map((s) => s.trim().toUpperCase()).where((s) => s.isNotEmpty);
    TipoConnettore? migliore;
    for (final t in tipi) {
      final tipo = switch (t) {
        'IEC_62196_T2_COMBO' => TipoConnettore.ccs2,
        'CHADEMO' => TipoConnettore.chademo,
        'IEC_62196_T2' => TipoConnettore.tipo2,
        'TESLA_S' || 'TESLA_R' => TipoConnettore.tesla,
        // Tipo 3A (le prese degli scooter), Schuko, Tipo 1: non per queste auto.
        _ => null,
      };
      if (tipo != null && (migliore == null || tipo.index < migliore.index)) migliore = tipo;
    }
    if (migliore == null) return null;
    // Con due spine la potenza è una lista («150000, 62500»): conta la più
    // alta. Leggerla come un numero solo scartava proprio le rapide doppie.
    final kw = watt.split(',').map((w) => double.tryParse(w.trim()) ?? 0).fold(0.0, (a, b) => b > a ? b : a) / 1000;
    if (kw <= 0) return null;
    return Connettore(tipo: migliore, potenzaKw: double.parse(kw.toStringAsFixed(1)));
  }

  /// Dall'EVSE ID `IT*BEC*EW003907*1` il codice dell'operatore, `BEC`.
  ///
  /// Il codice (party ID) è di tre caratteri per definizione: nei dati c'è
  /// anche `IT*REVEPGS564*1*2`, e prendere «REVEPGS564» per un operatore
  /// vorrebbe dire inventarne uno.
  static String? _operatore(String evse) {
    final pezzi = evse.split('*');
    if (pezzi.length < 3) return null;
    final codice = pezzi[1].trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{3}$').hasMatch(codice)) return null;
    return operatori[codice] ?? codice;
  }

  /// Il nome da mostrare. Molti posti hanno per nome un codice di macchina
  /// — `18XM32T77B3W000013`, `LOC69618`, `HPC162000003`, `AC_POLI_TN_04`,
  /// `IT*DUF*EI0046` — e a chi guida non dice niente: lì si mostra
  /// l'indirizzo. Un codice è tutto maiuscole, cifre e segni, senza spazi,
  /// con almeno una cifra.
  static bool sembraUnCodice(String nome) {
    final n = nome.trim();
    return n.isNotEmpty && !n.contains(' ') && RegExp(r'^[A-Z0-9*_\-.]+$').hasMatch(n) && RegExp(r'\d').hasMatch(n);
  }

  static String _nome(_Luogo l) {
    if (l.nome.isNotEmpty && !sembraUnCodice(l.nome)) return l.nome;
    if (l.indirizzo.isNotEmpty) return l.indirizzo;
    return l.operatore ?? 'Colonnina';
  }

  static double _media(List<double> v) => v.reduce((a, b) => a + b) / v.length;

  /// Un CSV come lo scrive onData: virgole, virgolette doppie attorno ai
  /// campi che le contengono, `""` per una virgoletta dentro un campo.
  static List<List<String>> _csv(String testo) {
    final righe = <List<String>>[];
    var campi = <String>[];
    final campo = StringBuffer();
    var dentro = false;
    for (var i = 0; i < testo.length; i++) {
      final c = testo[i];
      if (dentro) {
        if (c == '"') {
          if (i + 1 < testo.length && testo[i + 1] == '"') {
            campo.write('"');
            i++;
          } else {
            dentro = false;
          }
        } else {
          campo.write(c);
        }
      } else if (c == '"') {
        dentro = true;
      } else if (c == ',') {
        campi.add(campo.toString());
        campo.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < testo.length && testo[i + 1] == '\n') i++;
        campi.add(campo.toString());
        campo.clear();
        if (campi.length > 1 || campi.first.isNotEmpty) righe.add(campi);
        campi = <String>[];
      } else {
        campo.write(c);
      }
    }
    if (campo.isNotEmpty || campi.isNotEmpty) {
      campi.add(campo.toString());
      righe.add(campi);
    }
    return righe;
  }
}

class _Luogo {
  _Luogo(this.id, this.nome, this.indirizzo, this.operatore);

  final String id;
  final String nome;
  final String indirizzo;
  final String? operatore;
  final lat = <double>[];
  final lon = <double>[];
  final prese = <Connettore>[];
}
