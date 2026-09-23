import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

class FontiFinte implements FonteColonnine {
  FontiFinte(this.colonnine);
  final List<Colonnina> colonnine;
  var chiamate = 0;

  @override
  Future<List<Colonnina>> lungo(List<Punto> percorso, {double distanzaKm = 3}) async {
    chiamate++;
    return colonnine;
  }
}

void main() {
  // Una strada dritta verso nord: un punto ogni ~1,1 km, a 120 km/h.
  PercorsoCalcolato dritta(int km) {
    final punti = [for (var i = 0; i <= km; i++) Punto(42 + i * 0.009, 12)];
    final linea = Linea(punti);
    return PercorsoCalcolato(
      punti: punti,
      tratti: [
        for (var i = 1; i < punti.length; i++)
          Tratto(lunghezzaM: linea.cumulate[i] - linea.cumulate[i - 1], velocitaKmh: 120),
      ],
      manovre: const [],
    );
  }

  Colonnina colonnina(int km, {double kw = 150}) => Colonnina(
        id: 'c$km',
        nome: 'Area $km',
        posizione: Punto(42 + km * 0.009, 12.002),
        connettori: [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: kw)],
      );

  test('un viaggio corto non chiede nemmeno le colonnine', () async {
    final fonti = FontiFinte([colonnina(50)]);
    final p =
        PianificatoreViaggio(percorsi: (_) async => dritta(80), colonnine: fonti, profilo: ProfiloVeicolo.esempio);
    final v = await p.pianifica(partenza: const Punto(42, 12), arrivo: const Punto(43, 12), batteria: 90);
    expect(fonti.chiamate, 0);
    expect(v.piano!.soste, isEmpty);
  });

  test('un viaggio lungo si ferma alle colonnine lungo la strada', () async {
    final fonti = FontiFinte([for (var km = 60; km < 500; km += 60) colonnina(km)]);
    final p =
        PianificatoreViaggio(percorsi: (_) async => dritta(500), colonnine: fonti, profilo: ProfiloVeicolo.esempio);
    final v = await p.pianifica(partenza: const Punto(42, 12), arrivo: const Punto(46.5, 12), batteria: 80);
    expect(fonti.chiamate, 1);
    expect(v.colonnine, hasLength(8));
    expect(v.piano, isNotNull);
    expect(v.piano!.soste, isNotEmpty);
    expect(v.piano!.batteriaArrivo, greaterThanOrEqualTo(15));
  });

  test('le colonnine lente non contano per il viaggio', () async {
    final fonti = FontiFinte([for (var km = 60; km < 500; km += 60) colonnina(km, kw: 22)]);
    final p =
        PianificatoreViaggio(percorsi: (_) async => dritta(500), colonnine: fonti, profilo: ProfiloVeicolo.esempio);
    final v = await p.pianifica(partenza: const Punto(42, 12), arrivo: const Punto(46.5, 12), batteria: 80);
    expect(v.colonnine, isEmpty);
    expect(v.piano, isNull);
  });
}
