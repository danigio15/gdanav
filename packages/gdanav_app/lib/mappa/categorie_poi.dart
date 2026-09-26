/// Le categorie dei punti di interesse sulla mappa, come in Google Maps:
/// un colore e un'icona per tipo (cibo arancio, negozi blu, alloggi rosa,
/// salute rosso, cultura verde acqua, verde verde…). Le chiavi sono i valori
/// di OpenStreetMap che OpenMapTiles mette in `subclass` o `class`.
library;

class CategoriaPoi {
  const CategoriaPoi(this.nome, this.etichetta, this.colore, this.valori);

  /// Il nome dell'icona sulla mappa è `poi-<nome>`.
  final String nome;

  /// Come si chiama nella scheda («Ristorante»).
  final String etichetta;

  /// Colore dell'icona e del nome, in esadecimale.
  final String colore;
  final List<String> valori;

  String get immagine => 'poi-$nome';
}

const _cibo = '#E8710A', _negozi = '#1A73E8', _alloggi = '#D01884', _salute = '#D93025';
const _cultura = '#129EAF', _servizi = '#5F6368', _verde = '#1E8E3E', _auto = '#4F6EB0';

const categoriePoi = [
  CategoriaPoi('ristorante', 'Ristorante', _cibo, ['restaurant', 'food_court', 'bbq']),
  CategoriaPoi('fastfood', 'Fast food', _cibo, ['fast_food']),
  CategoriaPoi('caffe', 'Caffè e pasticceria', _cibo, ['cafe', 'bakery', 'ice_cream', 'confectionery', 'pastry']),
  CategoriaPoi('bar', 'Bar e pub', _cibo, ['bar', 'pub', 'beer', 'biergarten', 'nightclub', 'wine']),
  CategoriaPoi('spesa', 'Supermercato e alimentari', _negozi, [
    'supermarket',
    'convenience',
    'grocery',
    'greengrocer',
    'butcher',
    'deli',
    'alcohol',
    'beverages',
    'marketplace',
    'cheese',
    'seafood',
  ]),
  CategoriaPoi('negozio', 'Negozio', _negozi, [
    'shop',
    'clothes',
    'clothing_store',
    'shoes',
    'jewelry',
    'books',
    'furniture',
    'mobile_phone',
    'electronics',
    'department_store',
    'mall',
    'gift',
    'toys',
    'florist',
    'optician',
    'beauty',
    'hairdresser',
    'sports',
    'bicycle',
    'variety_store',
    'boutique',
    'bags',
    'computer',
    'outdoor',
    'pet',
    'art',
    'music',
    'photography',
    'second_hand',
    'interior_decoration',
    'doityourself',
    'hardware',
    'kiosk',
    'tobacco',
    'stationery',
    'copyshop',
    'tattoo',
    'travel_agency',
    'laundry',
    'dry_cleaning',
    'antiques',
    'hearing_aids',
    'cosmetics',
    'perfumery',
    'garden_centre',
  ]),
  CategoriaPoi('hotel', 'Hotel e alloggi', _alloggi, [
    'hotel',
    'guest_house',
    'hostel',
    'motel',
    'lodging',
    'apartment',
    'camp_site',
    'caravan_site',
    'chalet',
  ]),
  CategoriaPoi('ospedale', 'Ospedale e medici', _salute, ['hospital', 'clinic', 'doctors', 'dentist']),
  CategoriaPoi('farmacia', 'Farmacia', _salute, ['pharmacy', 'chemist']),
  CategoriaPoi('parcheggio', 'Parcheggio', _auto, ['parking']),
  CategoriaPoi('officina', 'Auto e officina', _auto, ['car_repair', 'car', 'car_wash', 'car_parts']),
  CategoriaPoi('benzina', 'Distributore', '#F08A24', ['fuel']),
  CategoriaPoi('ricarica', 'Colonnina di ricarica', '#16A34A', ['charging_station']),
  CategoriaPoi('cultura', 'Cultura e turismo', _cultura, [
    'museum',
    'theatre',
    'cinema',
    'arts_centre',
    'artwork',
    'gallery',
    'library',
    'attraction',
    'viewpoint',
    'information',
    'monument',
    'castle',
    'zoo',
    'aquarium',
    'theme_park',
    'memorial',
    'ruins',
  ]),
  CategoriaPoi('culto', 'Luogo di culto', _servizi, ['place_of_worship']),
  CategoriaPoi('scuola', 'Scuola e università', _servizi, [
    'school',
    'college',
    'university',
    'kindergarten',
    'childcare',
  ]),
  CategoriaPoi('banca', 'Banca e bancomat', _servizi, ['bank', 'atm', 'bureau_de_change']),
  CategoriaPoi('servizi', 'Servizi pubblici', _servizi, [
    'post_office',
    'police',
    'townhall',
    'fire_station',
    'community_centre',
    'courthouse',
    'embassy',
    'post',
  ]),
  CategoriaPoi('verde', 'Parco e sport', _verde, [
    'park',
    'garden',
    'picnic_site',
    'playground',
    'dog_park',
    'sports_centre',
    'pitch',
    'stadium',
    'swimming_pool',
  ]),
];

/// Tutto il resto.
const poiAltro = CategoriaPoi('altro', 'Luogo', '#7B8794', []);

/// La categoria di un punto dai suoi valori OpenStreetMap.
CategoriaPoi categoriaPoi(String? subclass, String? classe) {
  for (final v in [subclass, classe]) {
    if (v == null) continue;
    for (final c in categoriePoi) {
      if (c.valori.contains(v)) return c;
    }
  }
  return poiAltro;
}

/// L'espressione di MapLibre che sceglie, da `subclass` o `class`, il valore
/// [di] della categoria (l'icona o il colore).
List<Object> esprPoi(Object Function(CategoriaPoi c) di) {
  List<Object> match(String campo, Object altrimenti) => [
    'match',
    [
      'coalesce',
      ['get', campo],
      '',
    ],
    for (final c in categoriePoi) ...[c.valori, di(c)],
    altrimenti,
  ];
  return match('subclass', match('class', di(poiAltro)));
}
