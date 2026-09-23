import 'dart:io';

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

  // Percorso da un Valhalla vero, colonnine finte:
  // GDANAV_VALHALLA=http://127.0.0.1:8002/ (vedi il job «insieme» della CI).
  final vero = Platform.environment['GDANAV_VALHALLA'];
  test('con Valhalla vero, la batteria appena sufficiente chiede una sosta', () async {
    final valhalla = ClienteValhalla(Uri.parse(vero!));
    addTearDown(valhalla.chiudi);
    // Utrecht, dal centro verso sud-est: pochi chilometri.
    const partenza = Punto(52.0907, 5.1214), arrivo = Punto(52.064, 5.19);
    final percorso = await valhalla.calcola(const [partenza, arrivo]);
    final meta = percorso.punti[percorso.punti.length ~/ 2];
    final fonti = FontiFinte([
      Colonnina(
        id: 'utrecht',
        nome: 'A metà strada',
        posizione: meta,
        connettori: const [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: 50)],
      ),
    ]);
    final p = PianificatoreViaggio(percorsi: valhalla.calcola, colonnine: fonti, profilo: ProfiloVeicolo.esempio);

    final comodo = await p.pianifica(partenza: partenza, arrivo: arrivo, batteria: 60);
    expect(comodo.piano!.soste, isEmpty);
    expect(fonti.chiamate, 0);

    // Si parte con la soglia di arrivo (15%) più metà del consumo del
    // viaggio: si arriverebbe sotto, serve la colonnina a metà strada.
    final kWh = percorso.tratti.fold(0.0, (s, t) => s + energiaTrattoWh(t, ProfiloVeicolo.esempio)) / 1000;
    final percento = kWh / ProfiloVeicolo.esempio.capacitaUtileKwh * 100;
    final tirato = await p.pianifica(partenza: partenza, arrivo: arrivo, batteria: 15 + percento / 2);
    expect(fonti.chiamate, 1);
    expect(tirato.colonnine.single.id, 'utrecht');
    expect(tirato.piano!.soste.single.colonnina.id, 'utrecht');
  }, skip: vero == null ? 'serve GDANAV_VALHALLA' : false);
}
