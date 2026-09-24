import '../colonnine/colonnina.dart';
import 'profilo_veicolo.dart';

/// Le auto elettriche più diffuse in Italia.
///
/// **Valori indicativi**, dalle schede tecniche pubbliche: capacità utile,
/// massa in ordine di marcia più il conducente, Cx per area frontale, picco
/// di ricarica in continua. La forma della curva è quella tipica; i dati
/// dell'auto (OBD, Home Assistant) la correggono col tempo.
final List<ProfiloVeicolo> catalogoVeicoli = [
  _auto('tesla-model-3-lr', 'Tesla', 'Model 3 Long Range', kwh: 75, kg: 1905, cda: 0.49, dc: 250),
  _auto('tesla-model-3-rwd', 'Tesla', 'Model 3 RWD', kwh: 57.5, kg: 1835, cda: 0.49, dc: 170),
  _auto('tesla-model-y-lr', 'Tesla', 'Model Y Long Range', kwh: 75, kg: 2055, cda: 0.60, dc: 250),
  _auto('tesla-model-y-rwd', 'Tesla', 'Model Y RWD', kwh: 57.5, kg: 1985, cda: 0.60, dc: 170),
  _auto('fiat-500e-42', 'Fiat', '500e 42 kWh', kwh: 37.3, kg: 1440, cda: 0.65, dc: 85),
  _auto('volkswagen-id3-58', 'Volkswagen', 'ID.3 Pro 58 kWh', kwh: 58, kg: 1887, cda: 0.63, dc: 120),
  _auto('volkswagen-id4-77', 'Volkswagen', 'ID.4 Pro 77 kWh', kwh: 77, kg: 2200, cda: 0.73, dc: 135),
  _auto('cupra-born-58', 'Cupra', 'Born 58 kWh', kwh: 58, kg: 1885, cda: 0.63, dc: 120),
  _auto('skoda-enyaq-85', 'Škoda', 'Enyaq 85', kwh: 77, kg: 2225, cda: 0.64, dc: 135),
  _auto('renault-megane-60', 'Renault', 'Mégane E-Tech 60 kWh', kwh: 60, kg: 1700, cda: 0.67, dc: 130, ac: 22),
  _auto('renault-5-52', 'Renault', '5 E-Tech 52 kWh', kwh: 52, kg: 1525, cda: 0.64, dc: 100),
  _auto('renault-zoe-r135', 'Renault', 'Zoe R135', kwh: 52, kg: 1652, cda: 0.73, dc: 50, ac: 22),
  _auto('dacia-spring', 'Dacia', 'Spring', kwh: 26.8, kg: 1050, cda: 0.76, dc: 30, ac: 7),
  _auto('peugeot-e208-51', 'Peugeot', 'e-208 51 kWh', kwh: 48, kg: 1605, cda: 0.64, dc: 100),
  _auto('peugeot-e2008-54', 'Peugeot', 'e-2008 54 kWh', kwh: 51, kg: 1700, cda: 0.72, dc: 100),
  _auto('jeep-avenger', 'Jeep', 'Avenger Elettrica', kwh: 51, kg: 1610, cda: 0.76, dc: 100),
  _auto('hyundai-kona-65', 'Hyundai', 'Kona Electric 65 kWh', kwh: 64.8, kg: 1815, cda: 0.65, dc: 102),
  _auto('hyundai-ioniq5-77', 'Hyundai', 'Ioniq 5 77 kWh', kwh: 74, kg: 2175, cda: 0.75, dc: 230),
  _auto('kia-ev6-77', 'Kia', 'EV6 77 kWh', kwh: 74, kg: 2130, cda: 0.67, dc: 235),
  _auto('kia-niro-ev', 'Kia', 'Niro EV', kwh: 64.8, kg: 1825, cda: 0.70, dc: 80),
  _auto('mg4-64', 'MG', 'MG4 64 kWh', kwh: 61.7, kg: 1835, cda: 0.67, dc: 135),
  _auto('byd-atto3', 'BYD', 'Atto 3', kwh: 60.5, kg: 1825, cda: 0.73, dc: 88),
  _auto('byd-dolphin-60', 'BYD', 'Dolphin 60 kWh', kwh: 60.4, kg: 1733, cda: 0.69, dc: 88),
  _auto('byd-seal-82', 'BYD', 'Seal 82 kWh', kwh: 82.5, kg: 2225, cda: 0.50, dc: 150),
  _auto('volvo-ex30-69', 'Volvo', 'EX30 69 kWh', kwh: 64, kg: 1925, cda: 0.64, dc: 153),
  _auto('polestar-2-lr', 'Polestar', '2 Long Range', kwh: 79, kg: 2125, cda: 0.65, dc: 205),
  _auto('bmw-i4-40', 'BMW', 'i4 eDrive40', kwh: 80.7, kg: 2200, cda: 0.55, dc: 205),
  _auto('mercedes-eqa-250', 'Mercedes-Benz', 'EQA 250+', kwh: 70.5, kg: 2120, cda: 0.70, dc: 100),
  _auto('smart-1', 'smart', '#1 Pro+', kwh: 62, kg: 1875, cda: 0.70, dc: 150, ac: 22),
  _auto(
    'nissan-leaf-e-plus',
    'Nissan',
    'Leaf e+ 59 kWh',
    kwh: 59,
    kg: 1806,
    cda: 0.64,
    dc: 100,
    ac: 6.6,
    connettori: const {TipoConnettore.chademo, TipoConnettore.tipo2},
  ),
];

ProfiloVeicolo? veicoloPerId(String id) =>
    id == ProfiloVeicolo.esempio.id ? ProfiloVeicolo.esempio : catalogoVeicoli.where((v) => v.id == id).firstOrNull;

ProfiloVeicolo _auto(
  String id,
  String marca,
  String modello, {
  required double kwh,
  required double kg,
  required double cda,
  required double dc,
  double ac = 11,
  Set<TipoConnettore> connettori = const {TipoConnettore.ccs2, TipoConnettore.tipo2},
}) =>
    ProfiloVeicolo(
      id: id,
      marca: marca,
      modello: modello,
      nome: '$marca $modello',
      massaKg: kg,
      cdA: cda,
      crr: 0.009,
      capacitaUtileKwh: kwh,
      curvaRicarica: ProfiloVeicolo.curvaTipica(dc),
      potenzaAcKw: ac,
      connettori: connettori,
    );
