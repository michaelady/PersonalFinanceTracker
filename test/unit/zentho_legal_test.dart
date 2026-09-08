import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/legal/zentho_legal.dart';

void main() {
  test('default privacy policy URL is the hosted placeholder', () {
    expect(
      ZenthoLegal.privacyPolicyUrl,
      'https://michaelady.github.io/PersonalFinanceTracker/privacy.html',
    );
    expect(ZenthoLegal.privacyPolicyUri.isScheme('https'), isTrue);
  });
}
