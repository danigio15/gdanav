import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Una WebView finta per le prove del 3D aumentato: non disegna niente,
/// ricorda quello che l'app le manda, e fa parlare la «pagina» quando la
/// prova vuole ([dallaPagina]).
class WebViewFinta extends WebViewPlatform {
  final controlli = <ControlloFinto>[];

  /// L'ultima WebView creata.
  ControlloFinto get ultimo => controlli.last;

  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) {
    final c = ControlloFinto(params);
    controlli.add(c);
    return c;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) =>
      NavigazioneFinta(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) => WidgetFinto(params);
}

class ControlloFinto extends PlatformWebViewController {
  ControlloFinto(super.params) : super.implementation();

  final canali = <String, JavaScriptChannelParams>{};
  final eseguiti = <String>[];
  String? caricata;

  /// I messaggi mandati alla pagina, decodificati (`gdanav3d.ricevi(...)`).
  List<Map<String, Object?>> get messaggi => [
    for (final js in eseguiti)
      if (RegExp(r'ricevi\((.*)\)\s*;?\s*$', dotAll: true).firstMatch(js)?.group(1) case final j?)
        if (_json(j) case final Map<String, Object?> m) m,
  ];

  static Object? _json(String s) {
    try {
      final v = jsonDecode(s);
      return v is String ? jsonDecode(v) : v;
    } catch (_) {
      return null;
    }
  }

  /// La pagina manda un messaggio all'app, sul canale [canale].
  void dallaPagina(String canale, Map<String, Object?> m) =>
      canali[canale]!.onMessageReceived(JavaScriptMessage(message: jsonEncode(m)));

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams javaScriptChannelParams) async {
    canali[javaScriptChannelParams.name] = javaScriptChannelParams;
  }

  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}

  @override
  Future<void> loadFlutterAsset(String key) async => caricata = key;

  @override
  Future<void> runJavaScript(String javaScript) async => eseguiti.add(javaScript);

  @override
  Future<void> setBackgroundColor(Color color) async {}
}

class NavigazioneFinta extends PlatformNavigationDelegate {
  NavigazioneFinta(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async {}

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback onWebResourceError) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}
}

class WidgetFinto extends PlatformWebViewWidget {
  WidgetFinto(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: Key('webview-finta'));
}
