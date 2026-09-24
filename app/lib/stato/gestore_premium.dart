import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../servizi.dart';
import 'archivio.dart';

/// Il prodotto da creare nella Play Console: Monetizza → Prodotti → Prodotti
/// in-app, non consumabile.
const idPremium = 'gdanav_premium';

/// Il negozio, visto dall'app: Google Play, o uno finto nelle prove.
abstract interface class NegozioPremium {
  Future<bool> disponibile();

  /// Il prezzo del Premium come lo scrive il negozio («2,99 €»); `null` se
  /// il prodotto non c'è (non ancora creato nella Play Console).
  Future<String?> prezzo();

  /// Gli acquisti: nuovi, ripristinati, falliti.
  Stream<List<PurchaseDetails>> get acquisti;

  Future<void> compra();
  Future<void> ripristina();
  Future<void> completa(PurchaseDetails p);
}

class NegozioGooglePlay implements NegozioPremium {
  final _iap = InAppPurchase.instance;
  ProductDetails? _prodotto;

  @override
  Future<bool> disponibile() => _iap.isAvailable();

  @override
  Future<String?> prezzo() async {
    final r = await _iap.queryProductDetails({idPremium});
    _prodotto = r.productDetails.where((p) => p.id == idPremium).firstOrNull;
    return _prodotto?.price;
  }

  @override
  Stream<List<PurchaseDetails>> get acquisti => _iap.purchaseStream;

  @override
  Future<void> compra() async {
    if (_prodotto == null) await prezzo();
    final p = _prodotto;
    if (p == null) throw StateError('Premium non disponibile nel negozio');
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
  }

  @override
  Future<void> ripristina() => _iap.restorePurchases();

  @override
  Future<void> completa(PurchaseDetails p) => _iap.completePurchase(p);
}

/// gdanav Premium: sblocca Android Auto e l'integrazione con Home Assistant.
/// Un acquisto solo, per sempre, legato all'account Google: si ripristina
/// reinstallando o cambiando telefono.
class GestorePremium extends ChangeNotifier {
  GestorePremium({required this.archivio, this.negozio, bool? tuttoSbloccato})
    : _tuttoSbloccato = tuttoSbloccato ?? Servizi.tuttoSbloccato;

  final Archivio archivio;

  /// `null`: nessun negozio (prove, iPhone per ora).
  final NegozioPremium? negozio;

  /// Le build d'anteprima (APK da GitHub) non passano dal Play Store: lì è
  /// tutto sbloccato.
  final bool _tuttoSbloccato;

  var sbloccato = false;

  /// Il prezzo da mostrare; `null` se il negozio non risponde.
  String? prezzo;

  /// Mentre Google Play lavora (acquisto in corso).
  var inCorso = false;

  /// L'ultimo problema da dire a chi compra.
  String? errore;

  StreamSubscription<List<PurchaseDetails>>? _iscrizione;

  /// Quello che si sa subito (dal telefono); il Play Store risponde dopo,
  /// senza far aspettare l'avvio dell'app.
  Future<void> carica() async {
    sbloccato = _tuttoSbloccato || await archivio.premium();
    notifyListeners();
    if (!_tuttoSbloccato) unawaited(_apriNegozio());
  }

  Future<void> _apriNegozio() async {
    final n = negozio;
    if (n == null) return;
    try {
      if (!await n.disponibile()) return;
      _iscrizione = n.acquisti.listen(_acquisti, onError: (Object e) => _errore('$e'));
      prezzo = await n.prezzo();
      notifyListeners();
      // Chi l'ha già comprato (altro telefono, reinstallazione) lo ritrova.
      await n.ripristina();
    } catch (e) {
      debugPrint('premium: $e');
    }
  }

  Future<void> compra() async {
    final n = negozio;
    if (n == null || sbloccato) return;
    errore = null;
    inCorso = true;
    notifyListeners();
    try {
      await n.compra();
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
    _iscrizione?.cancel();
    super.dispose();
  }
}
