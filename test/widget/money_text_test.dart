import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/theme/zentho_colors.dart';
import 'package:zentho/widgets/money_text.dart';

void main() {
  testWidgets('signed negative day change is red, not a positive abs value',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MoneyText(
            -17.99,
            currencyCode: 'USD',
            signed: true,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, contains('−'));
    expect(text.data, contains('17.99'));
    expect(text.data, isNot(contains('+')));
    expect(text.style?.color, ZenthoColors.coral);
  });

  testWidgets('signed positive day change stays teal, not unsigned',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MoneyText(
            17.99,
            currencyCode: 'USD',
            signed: true,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, contains('+'));
    expect(text.style?.color, ZenthoColors.tealDeep);
  });
}
