/* Gli operatori che non si vogliono vedere.
 *
 * «Escludere gli operatori»: si spegne chi non si usa — nessun abbonamento,
 * un'app che non funziona, prezzi che non tornano — e le sue colonnine
 * smettono di comparire. Si esclude e non si include, e non è un dettaglio:
 * un elenco di quelli buoni farebbe sparire in silenzio un operatore nuovo, e
 * a chi guarda sembrerebbe che lì non c'è niente.
 */
import 'package:gdanav_core/gdanav_core.dart';
import 'package:test/test.dart';

Colonnina _c(String id, String? operatore, {double kw = 150}) => Colonnina(
      id: id,
      nome: id,
      posizione: const Punto(45.0, 9.0),
      operatore: operatore,
      connettori: [Connettore(tipo: TipoConnettore.ccs2, potenzaKw: kw)],
    );

void main() {
  test('lo stesso operatore scritto in tre modi è lo stesso operatore', () {
    /* Le fonti lo scrivono ognuna a modo suo, e chi sceglie sceglie una
     * volta. */
    expect(operatoreNormale('Enel X'), 'enel x');
    expect(operatoreNormale('  ENEL   X '), 'enel x');
    expect(operatoreNormale('enel x'), 'enel x');
    expect(operatoreNormale(null), '');
    expect(operatoreNormale('   '), '');
  });

  test('si esclude chi si è scelto, e nessun altro', () {
    final ionity = _c('a', 'Ionity');
    final enel = _c('b', 'ENEL  X');
    final senzaNome = _c('c', null);
    const spenti = {'enel x'};

    expect(operatoreEscluso(enel, spenti), isTrue);
    expect(operatoreEscluso(ionity, spenti), isFalse);
    /* Una colonnina senza operatore non si esclude mai: non si può tenere
     * fuori quello che non ha un nome, e una colonnina in più si guarda —
     * una in meno non si trova. */
    expect(operatoreEscluso(senzaNome, spenti), isFalse);
    expect(operatoreEscluso(enel, const {}), isFalse, reason: 'nessuno spento: si vede tutto');

    expect(
      senzaGliEsclusi([ionity, enel, senzaNome], spenti).map((c) => c.id),
      ['a', 'c'],
    );
    expect(senzaGliEsclusi([ionity, enel], const {}), hasLength(2));
  });

  test('gli operatori si offrono dal più diffuso, scritti come li scrive la fonte', () {
    /* È l'elenco da cui si sceglie chi non vedere: in cima quelli che si
     * incontrano davvero, e col nome che si legge sulla colonnina — non con
     * quello ridotto per il confronto. */
    final elenco = operatoriFra([
      _c('1', 'Ionity'),
      _c('2', 'Enel X'),
      _c('3', 'enel x'),
      _c('4', null),
      _c('5', 'Enel X'),
      _c('6', ''),
    ]);
    expect(elenco, ['Enel X', 'Ionity']);
  });

  test('la scelta si scrive e si rilegge', () {
    const p = PreferenzeRicarica(operatoriEsclusi: {'enel x', 'be charge'});
    final riletta = PreferenzeRicarica.daJson(p.toJson());
    expect(riletta.operatoriEsclusi, {'enel x', 'be charge'});
    /* Le vecchie preferenze non ce l'hanno, e chi non ha scelto vede tutto. */
    expect(PreferenzeRicarica.daJson(const {'minimo_arrivo': 20.0}).operatoriEsclusi, isEmpty);
    /* E quello che si rilegge è ridotto come si confronta, da qualunque parte
     * arrivi. */
    expect(
      PreferenzeRicarica.daJson(const {
        'operatori_esclusi': ['  IONITY ', ''],
      }).operatoriEsclusi,
      {'ionity'},
    );
  });

  test('una sosta spenta non si propone, ma quella scelta a mano resta', () {
    final linea = Linea([const Punto(45.0, 9.0), const Punto(45.0, 9.02)]);
    final colonnine = [_c('a', 'Ionity'), _c('b', 'Enel X')];
    final senzaEnel = colonnineSulPercorso(
      linea,
      colonnine,
      compatibili: {TipoConnettore.ccs2},
      operatoriEsclusi: const {'enel x'},
    );
    expect(senzaEnel.map((s) => s.id), ['a']);

    /* Chi guida scavalca un filtro che ha messo lui: una sosta scelta a mano
     * resta anche se il suo operatore è spento. */
    final conLaScelta = colonnineSulPercorso(
      linea,
      colonnine,
      compatibili: {TipoConnettore.ccs2},
      operatoriEsclusi: const {'enel x'},
      obbligate: const {'b'},
    );
    expect(conLaScelta.map((s) => s.id), containsAll(['a', 'b']));
  });
}
