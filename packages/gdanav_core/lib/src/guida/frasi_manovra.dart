/// Le frasi della manovra per lo schermo dell'auto, dalla più lunga alla più
/// corta.
///
/// Su uno schermo piccolo (una 500 con lo schermo da 800×480, CarPlay a
/// 400×240 punti) la scheda della manovra si mangiava tutto: «Alla rotonda
/// prendi l'uscita seconda in Via Faentina/SP253» su tre righe. CarPlay
/// (`CPManeuver.instructionVariants`) e Android Auto (le varianti di
/// `CarText`) sanno scegliere la frase che ci sta, ma solo se gliene diamo
/// più d'una, dalla più lunga. Qui si scrivono, una volta sola per tutti e
/// due: il codice dell'auto le passa e basta.
///
/// Nelle corte la sigla ripetuta della strada («/SP253») non c'è, e l'uscita
/// della rotonda è «2ª», non «seconda».
library;

import '../percorso/valhalla.dart';

/// Il «poi» (la manovra dopo, piccola sotto la scheda) si mostra solo se
/// arriva entro questi metri da quella di adesso, come fa Mappe di Apple: più
/// lontana è solo una riga che ruba la mappa.
const poiEntroM = 150.0;

/// Se mostrare il «poi» dopo [prossima]: [dopo] arriva subito dopo.
bool poiVicino(Manovra prossima, Manovra? dopo) => dopo != null && prossima.lunghezzaM < poiEntroM;

/// Le frasi della manovra [m], dalla più lunga alla più corta, senza doppioni:
///
/// «Alla rotonda prendi la 2ª uscita in Via Faentina», «Rotonda, 2ª uscita ·
/// Via Faentina», «Rotonda, 2ª uscita», «2ª uscita».
List<String> frasiManovra(Manovra m) {
  final a = _azione(m);
  final dove = _dove(m, a);
  return _inOrdine([
    dove == null ? a.lunga : '${a.lunga} ${a.legame} ${dove.lungo}',
    if (dove != null) a.soloStrada ? dove.corto : '${a.breve} · ${dove.corto}',
    a.breve,
    if (a.minima != null) a.minima!,
  ]);
}

/// Le frasi del «poi», dalla più lunga: «Poi a destra · Via Roma», «Poi a
/// destra», «Poi».
List<String> frasiPoi(Manovra m) {
  final a = _azione(m);
  final dove = _dove(m, a);
  final breve = '${a.breve[0].toLowerCase()}${a.breve.substring(1)}';
  return _inOrdine([
    if (dove != null) a.soloStrada ? 'Poi ${dove.corto}' : 'Poi $breve · ${dove.corto}',
    'Poi $breve',
    'Poi',
  ]);
}

/// L'ordinale femminile dell'uscita: «2ª».
String ordinaleUscita(int n) => '$nª';

/// L'uscita della rotonda scritta nella frase, quando il motore non la dà a
/// parte: «prendi la seconda uscita», «l'uscita seconda», «la 3a uscita».
int? uscitaDallaFrase(String frase) {
  final f = frase.toLowerCase();
  final cifra = RegExp(r"(\d{1,2})\s*[ªa°º]?\s+uscita|uscita\s+(?:n\.\s*)?(\d{1,2})\b").firstMatch(f);
  if (cifra != null) return int.tryParse(cifra.group(1) ?? cifra.group(2)!);
  final parola = RegExp(r'\b(' + _ordinali.join('|') + r')\b').allMatches(f);
  for (final p in parola) {
    // L'ordinale deve stare accanto a «uscita», non in un nome di strada.
    final vicino = f.substring((p.start - 12).clamp(0, f.length), (p.end + 12).clamp(0, f.length));
    if (vicino.contains('uscita')) return _ordinali.indexOf(p.group(1)!) + 1;
  }
  return null;
}

const _ordinali = [
  'prima',
  'seconda',
  'terza',
  'quarta',
  'quinta',
  'sesta',
  'settima',
  'ottava',
  'nona',
  'decima',
];

/// La sigla di una strada («SP253», «A14», «E45», «SS9dir», «RA 6»): un
/// doppione del nome, quando il nome c'è.
bool eSigla(String s) =>
    RegExp(r'^[A-Z]{1,3} ?\d{1,4}[A-Za-z]{0,3}(?: ?(?:dir|bis|var|racc|ter|radd)\.?)?$').hasMatch(s.trim());

/// La strada senza la sigla ripetuta: «Via Faentina/SP253» → «Via Faentina».
/// Se c'è solo la sigla resta quella («SS16»).
String stradaSenzaSigla(String strada) {
  final parti = _parti(strada);
  if (parti.isEmpty) return '';
  return parti.firstWhere((p) => !eSigla(p), orElse: () => parti.first);
}

List<String> _parti(String s) =>
    s.split(RegExp(r'\s*(?:/|;|·)\s*')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

/// Cosa fa la manovra, in tre lunghezze, e come si attacca la strada.
class _Azione {
  const _Azione(this.lunga, this.breve,
      {this.legame = 'in', this.minima, this.soloStrada = false, this.cartello = false});

  /// «Alla rotonda prendi la 2ª uscita».
  final String lunga;

  /// «Rotonda, 2ª uscita».
  final String breve;

  /// «2ª uscita», la più corta, se diversa da [breve].
  final String? minima;

  /// Fra la frase lunga e la strada: «in», «su», «verso».
  final String legame;

  /// Andando dritti la frase di mezzo è solo la strada: «Via Emilia».
  final bool soloStrada;

  /// Uscite e bivi: conta il cartello («Bologna, Ravenna»), non la strada.
  final bool cartello;
}

_Azione _azione(Manovra m) {
  switch (m.tipo) {
    case 26:
      final n = m.uscitaRotonda ?? uscitaDallaFrase(m.istruzione);
      if (n == null || n <= 0) return const _Azione('Alla rotonda prosegui', 'Rotonda');
      final u = ordinaleUscita(n);
      return _Azione('Alla rotonda prendi la $u uscita', 'Rotonda, $u uscita', minima: '$u uscita');
    case 27:
      return const _Azione('Esci dalla rotonda', 'Esci dalla rotonda', minima: 'Esci');
    case 9:
      return const _Azione('Svolta leggermente a destra', 'Leggera destra');
    case 10:
      return const _Azione('Gira a destra', 'A destra');
    case 11:
      return const _Azione('Svolta stretta a destra', 'Stretta a destra');
    case 16:
      return const _Azione('Svolta leggermente a sinistra', 'Leggera sinistra');
    case 15:
      return const _Azione('Gira a sinistra', 'A sinistra');
    case 14:
      return const _Azione('Svolta stretta a sinistra', 'Stretta a sinistra');
    case 12 || 13:
      return const _Azione('Fai inversione a U', 'Inversione');
    case 17:
      return const _Azione('Prendi la rampa', 'Rampa', legame: 'verso', cartello: true);
    case 18:
      return const _Azione('Prendi la rampa a destra', 'Rampa a destra',
          legame: 'verso', minima: 'Rampa', cartello: true);
    case 19:
      return const _Azione('Prendi la rampa a sinistra', 'Rampa a sinistra',
          legame: 'verso', minima: 'Rampa', cartello: true);
    case 20 || 21:
      final lato = m.tipo == 20 ? 'destra' : 'sinistra';
      if (m.uscita.isNotEmpty) {
        return _Azione("Prendi l'uscita ${m.uscita}", 'Uscita ${m.uscita}', legame: 'verso', cartello: true);
      }
      return _Azione('Esci a $lato', 'Esci a $lato', legame: 'verso', minima: 'Esci', cartello: true);
    case 22:
      return const _Azione('Al bivio resta al centro', 'Resta al centro', legame: 'verso', cartello: true);
    case 23:
      return const _Azione('Al bivio tieni la destra', 'Tieni la destra', legame: 'verso', cartello: true);
    case 24:
      return const _Azione('Al bivio tieni la sinistra', 'Tieni la sinistra', legame: 'verso', cartello: true);
    case 25:
      return const _Azione('Immettiti', 'Immettiti', legame: 'su');
    case 37:
      return const _Azione('Immettiti a destra', 'Immettiti', legame: 'su');
    case 38:
      return const _Azione('Immettiti a sinistra', 'Immettiti', legame: 'su');
    case 28:
      return const _Azione('Prendi il traghetto', 'Traghetto', legame: 'per');
    case 29:
      return const _Azione('Scendi dal traghetto', 'Scendi dal traghetto', legame: 'su', minima: 'Scendi');
    case 4:
      return const _Azione('Sei arrivato a destinazione', 'Arrivo', legame: 'in');
    case 5:
      return const _Azione('La destinazione è sulla destra', 'Arrivo, a destra', legame: '·', minima: 'Arrivo');
    case 6:
      return const _Azione('La destinazione è sulla sinistra', 'Arrivo, a sinistra', legame: '·', minima: 'Arrivo');
    case 1 || 2 || 3:
      return const _Azione('Parti', 'Parti', legame: 'su');
    default:
      return const _Azione('Prosegui', 'Prosegui', legame: 'su', soloStrada: true);
  }
}

/// Dove porta la manovra: lungo (col cartello intero) e corto (un nome solo,
/// senza sigle se c'è un nome).
({String lungo, String corto})? _dove(Manovra m, _Azione a) {
  if (a.cartello && m.verso.isNotEmpty) {
    final parti = _parti(m.verso.replaceAll(', ', ' · '));
    if (parti.isNotEmpty) {
      final nomi = parti.where((p) => !eSigla(p)).toList();
      return (lungo: parti.join(', '), corto: nomi.isNotEmpty ? nomi.first : parti.first);
    }
  }
  final strada = stradaSenzaSigla(m.strada.isNotEmpty ? m.strada : _stradaDallaFrase(m.istruzione));
  if (strada.isEmpty) return null;
  return (lungo: strada, corto: strada);
}

/// La strada in fondo alla frase del motore, quando non la dà a parte:
/// «Gira a destra in Via Roma» → «Via Roma». Solo nomi (con la maiuscola o
/// una sigla), non «per 2 km».
String _stradaDallaFrase(String frase) {
  final f = frase.trim().replaceAll(RegExp(r'[.!]+$'), '');
  final legami = RegExp(r'\s(?:in|su|verso|per|imboccando|sulla|sul)\s+').allMatches(f).toList();
  if (legami.isEmpty) return '';
  final coda = f.substring(legami.last.end).trim();
  if (coda.isEmpty || !RegExp(r'^[A-ZÀ-Ý]').hasMatch(coda)) return '';
  return coda;
}

/// Dalla più lunga alla più corta, senza doppioni né frasi vuote: CarPlay
/// prende la prima che ci sta.
List<String> _inOrdine(List<String> frasi) {
  final viste = <String>{};
  final pulite = [
    for (final f in frasi.map((f) => f.replaceAll(RegExp(r'\s+'), ' ').trim()))
      if (f.isNotEmpty && viste.add(f)) f,
  ];
  // Stabile: a parità di lunghezza resta l'ordine scritto.
  final indici = List.generate(pulite.length, (i) => i)
    ..sort((a, b) {
      final d = pulite[b].length - pulite[a].length;
      return d != 0 ? d : a - b;
    });
  return [for (final i in indici) pulite[i]];
}
