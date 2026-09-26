import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../servizi.dart';
import 'archivio.dart';

/// L'abbonamento da creare nella Play Console (Monetizza → Prodotti →
/// Abbonamenti), con due piani base e, per ciascuno, l'offerta di prova.
const idPremium = 'gdanav_premium';
const pianoMensile = 'mensile';
const pianoAnnuale = 'annuale';

/// Un piano dell'abbonamento come lo propone il negozio.
class PianoPremium {
  const PianoPremium({required this.id, required this.prezzo, this.giorniProva = 0});

  /// [pianoMensile] o [pianoAnnuale].
  final String id;

  /// Il prezzo che si paga dopo la prova, come lo scrive il negozio.
  final String prezzo;

  /// 0: senza prova (già usata, o nessuna offerta).
  final int giorniProva;
}

/// Il negozio, visto dall'app: Google Play, o uno finto nelle prove.
abstract interface class NegozioPremium {
  Future<bool> disponibile();

  /// I piani in vendita; vuoto se l'abbonamento non c'è (non ancora creato
  /// nella Play Console).
  Future<List<PianoPremium>> piani();

  /// Gli acquisti: nuovi, ripristinati, falliti.
  Stream<List<PurchaseDetails>> get acquisti;

  Future<void> compra(String piano);
  Future<void> ripristina();
  Future<void> completa(PurchaseDetails p);
}

class NegozioGooglePlay implements NegozioPremium {
  final _iap = InAppPurchase.instance;
  final _perPiano = <String, GooglePlayProductDetails>{};

  @override
  Future<bool> disponibile() => _iap.isAvailable();

  @override
  Future<List<PianoPremium>> piani() async {
    final r = await _iap.queryProductDetails({idPremium});
    final piani = <String, PianoPremium>{};
    _perPiano.clear();
    for (final d in r.productDetails.whereType<GooglePlayProductDetails>()) {
      final i = d.subscriptionIndex;
      final offerta = i == null ? null : d.productDetails.subscriptionOfferDetails?[i];
      if (offerta == null || offerta.pricingPhases.isEmpty) continue;
      final fasi = offerta.pricingPhases;
      // La prova: una prima fase a prezzo zero («P14D» = 14 giorni).
      final prova = fasi.length > 1 && fasi.first.priceAmountMicros == 0 ? _giorni(fasi.first.billingPeriod) : 0;
      final gia = piani[offerta.basePlanId];
      // Per ogni piano si propone l'offerta con la prova, se c'è.
      if (gia == null || prova > gia.giorniProva) {
        piani[offerta.basePlanId] = PianoPremium(
          id: offerta.basePlanId,
          prezzo: fasi.last.formattedPrice,
          giorniProva: prova,
        );
        _perPiano[offerta.basePlanId] = d;
      }
    }
    return piani.values.toList();
  }

  /// «P14D», «P2W», «P1M» → giorni.
  static int _giorni(String periodo) {
    final m = RegExp(r'P(\d+)([DWM])').firstMatch(periodo);
    if (m == null) return 0;
    final n = int.parse(m.group(1)!);
    return switch (m.group(2)) {
      'W' => n * 7,
      'M' => n * 30,
      _ => n,
    };
  }

  @override
  Stream<List<PurchaseDetails>> get acquisti => _iap.purchaseStream;

  @override
  Future<void> compra(String piano) async {
    if (_perPiano.isEmpty) await piani();
    final d = _perPiano[piano];
    if (d == null) throw StateError('Piano $piano non disponibile nel negozio');
    // L'offerta (con la prova) la sceglie il dettaglio stesso.
    await _iap.buyNonConsumable(purchaseParam: GooglePlayPurchaseParam(productDetails: d));
  }

  @override
  Future<void> ripristina() => _iap.restorePurchases();

  @override
  Future<void> completa(PurchaseDetails p) => _iap.completePurchase(p);
}

/// gdanav Premium, in abbonamento (mensile o annuale, con la prova gratuita):
/// Android Auto, Home Assistant, traffico, colonnine libere/occupate,
/// autovelox. Si ritrova su un altro telefono con lo stesso account Google;
/// se l'abbonamento scade, si torna alla versione gratuita.
class GestorePremium extends ChangeNotifier {
  /// Premium attivo adesso, per chi non ha il gestore in mano (la mappa col
  /// traffico, il pianificatore con le colonnine in tempo reale, gli
  /// autovelox). Vero finché l'app non dice altro: le prove non passano dal
  /// negozio.
  static final attivo = ValueNotifier<bool>(true);

  GestorePremium({
    required this.archivio,
    this.negozio,
    this.ospite,
    bool? tuttoSbloccato,
    this.attesaConferma = const Duration(seconds: 8),
  }) : _tuttoSbloccato = tuttoSbloccato ?? Servizi.tuttoSbloccato;

  final Archivio archivio;

  /// `null`: nessun negozio (prove, iPhone per ora).
  final NegozioPremium? negozio;

  /// Dentro un'altra app (gdahome) Premium lo decide lei: se lì è stato
  /// comprato è tutto sbloccato, altrimenti no. Niente negozio di gdanav.
  final ValueListenable<bool>? ospite;

  /// Premium si compra nell'app che ospita gdanav, non qui.
  bool get daOspite => ospite != null;

  /// Solo le build fatte apposta con GDANAV_TUTTO_SBLOCCATO: le versioni
  /// pubblicate (APK e Play Store) chiedono l'abbonamento.
  final bool _tuttoSbloccato;

  /// Quanto si aspetta che il Play Store confermi l'abbonamento, prima di
  /// considerarlo scaduto.
  final Duration attesaConferma;

  var sbloccato = false;

  /// I piani da proporre; vuoto se il negozio non risponde.
  var piani = <PianoPremium>[];

  /// Mentre Google Play lavora (acquisto in corso).
  var inCorso = false;

  /// L'ultimo problema da dire a chi compra.
  String? errore;

  StreamSubscription<List<PurchaseDetails>>? _iscrizione;
  var _confermato = false;

  @override
  void notifyListeners() {
    attivo.value = sbloccato;
    super.notifyListeners();
  }

  /// Quello che si sa subito (dal telefono); il Play Store risponde dopo,
  /// senza far aspettare l'avvio dell'app.
  Future<void> carica() async {
    if (ospite case final o?) {
      sbloccato = _tuttoSbloccato || o.value;
      o.addListener(_dallOspite);
      notifyListeners();
      return;
    }
    sbloccato = _tuttoSbloccato || await archivio.premium();
    notifyListeners();
    if (!_tuttoSbloccato) unawaited(_apriNegozio());
  }

  void _dallOspite() {
    final si = _tuttoSbloccato || ospite!.value;
    if (si == sbloccato) return;
    sbloccato = si;
    notifyListeners();
  }

  Future<void> _apriNegozio() async {
    final n = negozio;
    if (n == null) return;
    try {
      if (!await n.disponibile()) return;
      _iscrizione = n.acquisti.listen(_acquisti, onError: (Object e) => _errore('$e'));
      piani = await n.piani();
      notifyListeners();
      // Gli abbonamenti attivi tornano da soli (altro telefono, reinstallazione).
      await n.ripristina();
      // Il negozio risponde ma non c'è un abbonamento attivo: scaduto o
      // disdetto. Senza rete non si arriva qui, e resta com'era.
      await Future<void>.delayed(attesaConferma);
      if (sbloccato && !_confermato && !inCorso) {
        sbloccato = false;
        await archivio.salvaPremium(false);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('premium: $e');
    }
  }

  Future<void> compra(String piano) async {
    final n = negozio;
    if (n == null || sbloccato) return;
    errore = null;
    inCorso = true;
    notifyListeners();
    try {
      await n.compra(piano);
    } catch (e) {
      _errore('Il Play Store non risponde. Riprova tra poco.');
    }
  }

  Future<void> ripristina() async {
    errore = null;
    notifyListeners();
    try {
      await negozio?.ripristina();
    } catch (e) {
      _errore('Il Play Store non risponde. Riprova tra poco.');
    }
  }

  Future<void> _acquisti(List<PurchaseDetails> elenco) async {
    for (final p in elenco.where((p) => p.productID == idPremium)) {
      switch (p.status) {
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          await _sblocca();
        case PurchaseStatus.error:
          _errore(p.error?.message ?? 'Acquisto non riuscito.');
        case PurchaseStatus.canceled:
          inCorso = false;
          notifyListeners();
        case PurchaseStatus.pending:
          inCorso = true;
          notifyListeners();
      }
      // Google Play vuole la conferma, altrimenti dopo tre giorni rimborsa.
      if (p.pendingCompletePurchase) await negozio?.completa(p);
    }
  }

  Future<void> _sblocca() async {
    _confermato = true;
    inCorso = false;
    errore = null;
    if (!sbloccato) {
      sbloccato = true;
      await archivio.salvaPremium(true);
    }
    notifyListeners();
  }

  void _errore(String messaggio) {
    inCorso = false;
    errore = messaggio;
    notifyListeners();
  }

  @override
  void dispose() {
    ospite?.removeListener(_dallOspite);
    _iscrizione?.cancel();
    super.dispose();
  }
}
