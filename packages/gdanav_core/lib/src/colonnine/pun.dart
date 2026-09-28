import '../geo/geo.dart';
import 'colonnina.dart';

/// La Piattaforma Unica Nazionale dei punti di ricarica (GSE/MASE), in CSV:
/// una riga per punto di ricarica. Nell'archivio c'è l'estrazione di oggi
/// dall'API del portale (`tools/pun/estrai.py`, come la legge AgID), con
/// licenza CC BY 4.0; il lettore legge anche la fotografia del 2024 di
/// onData, che ha le stesse colonne.
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
  /// Come la vuole citata la licenza CC BY 4.0: di chi sono i dati e con che
  /// licenza. L'archivio viene dall'API del portale, non più da onData: il
  /// titolare è il GSE, come lo cita AgID nel Cruscotto Italia.
  static const attribuzione = 'PUN (GSE), CC BY 4.0';

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
    // Scritti nei nomi dei posti stessi: «IONITY Brenner», «Edison Next -
    // Borgo Virgilio», «Powerstop - Ambrosi», «EUROSPIN - Palermo»,
    // «R220 - Comune di Marcaria».
    'IOY': 'Ionity',
    'EDN': 'Edison Next',
    'VCC': 'Powerstop',
    'ESP': 'Eurospin',
    '220': 'R220',
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
    // Solo nell'estrazione di oggi dall'API (tools/pun/estrai.py): il nome
    // dell'azienda. Nel CSV di onData non c'è.
    final cAzienda = intestazione.indexOf('operatore');

    final perLuogo = <String, _Luogo>{};
    for (final r in righe.skip(1)) {
      if (r.length < intestazione.length) continue;
      // Non costruita, o tolta: per chi guida non c'è.
      final stato = r[cStato].trim().toUpperCase();
      if (stato == 'PLANNED' || stato == 'REMOVED') continue;
      final lat = double.tryParse(r[cLat]), lon = double.tryParse(r[cLon]);
      if (lat == null || lon == null || lat == 0 || lon == 0) continue;
      final presa = Pun.presa(r[cStandard], r[cPotenza]);
      if (presa == null) continue;
      final id = r[cLuogo].trim();
      if (id.isEmpty) continue;
      final luogo = perLuogo.putIfAbsent(
        id,
        () => _Luogo(
          id,
          r[cNome].trim(),
          r[cIndirizzo].trim(),
          _operatore(r[cEvse], azienda: cAzienda >= 0 ? r[cAzienda] : ''),
        ),
      );
      luogo.lat.add(lat);
      luogo.lon.add(lon);
      luogo.prese.add(presa);
      if (r[cEvse].trim() case final e when e.isNotEmpty) luogo.evse.add(e);
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
          evse: l.evse,
        ),
    ];
  }

  /// La presa di un punto di ricarica: la migliore fra quelle che ha.
  /// [standard] e [watt] come nel CSV: liste separate da virgole. La usa
  /// anche lo stato di adesso ([DisponibilitaPun]).
  static Connettore? presa(String standard, String watt) {
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

  /// Chi gestisce il punto di ricarica. Prima il nome con cui lo si chiama
  /// ([operatori], dal codice dentro l'EVSE ID), poi quello dell'azienda
  /// scritto nella PUN ([nomeAzienda]), e solo alla fine il codice.
  static String? _operatore(String evse, {String azienda = ''}) {
    final codice = codiceOperatore(evse);
    if (operatori[codice] case final noto?) return noto;
    final nome = nomeAzienda(azienda);
    if (nome.isNotEmpty) return nome;
    return codice;
  }

  /// Dall'EVSE ID `IT*BEC*EW003907*1` il codice dell'operatore, `BEC`; anche
  /// dalla forma senza asterischi, `ITGESE822979393` → `GES`.
  ///
  /// Il codice (party ID) è di tre caratteri per definizione: nei dati c'è
  /// anche `IT*REVEPGS564*1*2`, e prendere «REVEPGS564» per un operatore
  /// vorrebbe dire inventarne uno.
  static String? codiceOperatore(String evse) {
    final e = evse.trim().toUpperCase();
    if (!e.contains('*')) return RegExp(r'^[A-Z]{2}([A-Z0-9]{3})E').firstMatch(e)?.group(1);
    final pezzi = e.split('*');
    if (pezzi.length < 3) return null;
    final codice = pezzi[1].trim();
    return RegExp(r'^[A-Z0-9]{3}$').hasMatch(codice) ? codice : null;
  }

  static final _formaGiuridica = RegExp(
    r"[\s,]+(unipersonale|in liquidazione|s\.?\s?r\.?\s?l\.?(\s?s\.?)?|s\.?\s?p\.?\s?a\.?|s\.?\s?n\.?\s?c\.?|"
    r"s\.?\s?a\.?\s?s\.?|s\.?\s?c\.?\s?a\.?\s?r\.?\s?l\.?|soc(\.|ietà|ieta')?\s?coop(\.|erativa)?[^,]*|"
    r"societ(à|a') (a responsabilit(à|a') limitata( semplificata)?|per azioni|cooperativa[^,]*|consortile[^,]*)|"
    r"gmbh|ag|b\.?\s?v\.?|ltd\.?)\.?$",
    caseSensitive: false,
  );
  static const _minuscole = {'di', 'da', 'del', 'della', 'dei', 'e', 'ed', 'la', 'il', 'lo', 'per', 'in', 'con', 'su'};

  /// Il nome di un'azienda come lo si dice: senza la forma giuridica, e non
  /// tutto in maiuscolo. «A2A E.MOBILITY S.R.L.» → «A2A E.Mobility»,
  /// «ACEA ENERGIA SPA» → «Acea Energia». Le parole di tre lettere o meno
  /// restano come sono: sono quasi sempre sigle (ASM, ACE, A2A).
  static String nomeAzienda(String azienda) {
    var n = azienda.trim().replaceAll(RegExp(r'\s+'), ' ');
    for (var prima = ''; prima != n;) {
      prima = n;
      n = n.replaceFirst(_formaGiuridica, '').trim();
    }
    if (n.isNotEmpty && n == n.toUpperCase()) {
      n = n.split(' ').indexed.map((x) {
        final (i, p) = x;
        if (i > 0 && _minuscole.contains(p.toLowerCase())) return p.toLowerCase();
        return p.replaceAllMapped(
          RegExp(r'[A-ZÀ-Ý]{4,}'),
          (m) => m[0]![0] + m[0]!.substring(1).toLowerCase(),
        );
      }).join(' ');
    }
    return n;
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
  final evse = <String>[];
}
