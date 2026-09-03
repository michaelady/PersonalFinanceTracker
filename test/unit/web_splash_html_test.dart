import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web/index.html paints a static splash before Flutter boots', () {
    final html = File('web/index.html').readAsStringSync();

    expect(html.contains('id="zentho-splash"'), isTrue);
    expect(html.contains('zentho-spinner'), isTrue);
    expect(html.contains('#0B6E6E'), isTrue);
    expect(html.contains('#F7FBFA'), isTrue);
    expect(html.contains('flutter-first-frame'), isTrue);
    expect(html.contains('flt-glass-pane'), isTrue);
    expect(
      html.indexOf('id="zentho-splash"'),
      lessThan(html.indexOf('flutter_bootstrap.js')),
    );
    // Generated bootstrap is left as-is; a custom onEntrypointLoaded would
    // skip forwarding the Flutter build config to initializeEngine().
    expect(File('web/flutter_bootstrap.js').existsSync(), isFalse);
  });
}
