import 'package:flutter_test/flutter_test.dart';
import 'package:gdanav_app/componenti/vista_svincolo.dart';

void main() {
  test('su uno schermo largo il popup dello svincolo non va oltre i 520', () {
    expect(PopupSvincolo.larghezzaSu(400), 376);
    expect(PopupSvincolo.larghezzaSu(1100), PopupSvincolo.larghezzaMassima);
  });
}
