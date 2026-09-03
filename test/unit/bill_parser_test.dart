import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/bill_parser.dart';

void main() {
  group('BillParser', () {
    test('parses merchant, currency, total, and line items', () {
      const raw = '''
Migros Zurich
Date: 2026-07-15
Milk 1L          CHF 2.40
Bread            CHF 3.10
TOTAL            CHF 5.50
''';
      final bill = BillParser.parse(raw, fallbackCurrency: 'EUR');

      expect(bill.merchant, contains('Migros'));
      expect(bill.currencyCode, 'CHF');
      expect(bill.total, 5.50);
      expect(bill.date, DateTime(2026, 7, 15));
      expect(bill.lines.length, greaterThanOrEqualTo(2));
      expect(bill.suggestedCategoryName, 'Groceries');
      expect(
        bill.lines.any((l) => l.description.contains('Milk')),
        isTrue,
      );
    });

    test('falls back to single expense when only a total is present', () {
      const raw = '''
Starbucks
Amount due: EUR 12.50
''';
      final bill = BillParser.parse(raw, fallbackCurrency: 'USD');

      expect(bill.currencyCode, 'EUR');
      expect(bill.total, 12.50);
      expect(bill.lines, hasLength(1));
      expect(bill.lines.first.amount, 12.50);
      expect(bill.suggestedCategoryName, 'Dining');
    });

    test('uses fallback currency when none is detected', () {
      const raw = '''
Unknown shop
Something fancy 19.99
''';
      final bill = BillParser.parse(raw, fallbackCurrency: 'RON');
      expect(bill.currencyCode, 'RON');
      expect(bill.total, 19.99);
    });

    test('resolveCategoryId maps known names and falls back to Fun', () {
      final categories = [
        SpendCategory.create(
          name: 'Groceries',
          iconName: 'local_grocery_store',
          colorHex: 0xFF6FAE8F,
          isIncome: false,
        ),
        SpendCategory.create(
          name: 'Fun',
          iconName: 'celebration',
          colorHex: 0xFFE39B2E,
          isIncome: false,
        ),
        SpendCategory.create(
          name: 'Salary',
          iconName: 'payments',
          colorHex: 0xFF6FAE8F,
          isIncome: true,
        ),
      ];

      expect(
        BillParser.resolveCategoryId('Groceries', categories),
        categories.first.id,
      );
      expect(
        BillParser.resolveCategoryId('Unknown', categories),
        categories[1].id,
      );
    });

    test('keeps labeled TOTAL when grocery lines are CHF 1.00 short', () {
      const raw = '''
Coop Pronto
Date: 2026-09-03
Olive oil        CHF 12.90
Tomatoes         CHF 8.50
Cheese           CHF 4.20
Juice            CHF 6.40
Yogurt           CHF 3.00
Bread            CHF 2.50
Milk             CHF 4.80
Bananas          CHF 1.80
Apples           CHF 1.50
Carrots          CHF 1.25
TOTAL            CHF 47.85
''';
      final bill = BillParser.parse(raw, fallbackCurrency: 'EUR');

      expect(bill.currencyCode, 'CHF');
      expect(bill.printedTotal, closeTo(47.85, 0.001));
      expect(bill.total, closeTo(47.85, 0.001));
      expect(bill.lines, hasLength(10));
      expect(bill.itemsSum, closeTo(46.85, 0.001));
      expect(bill.printedTotalDelta, closeTo(1.00, 0.001));
      expect(bill.printedTotalMismatches, isTrue);
      expect(
        bill.lines.any((l) => l.description.toLowerCase().contains('total')),
        isFalse,
      );
      expect(bill.suggestedCategoryName, 'Groceries');
    });

    test('does not flag a mismatch when lines already equal TOTAL', () {
      const raw = '''
Migros Zurich
Milk 1L          CHF 2.40
Bread            CHF 3.10
TOTAL            CHF 5.50
''';
      final bill = BillParser.parse(raw, fallbackCurrency: 'CHF');
      expect(bill.printedTotal, closeTo(5.50, 0.001));
      expect(bill.printedTotalMismatches, isFalse);
      expect(bill.printedTotalDelta, closeTo(0, 0.001));
    });

    test('does not treat an inferred largest amount as a printed TOTAL', () {
      const raw = '''
Unknown shop
Something fancy 19.99
''';
      final bill = BillParser.parse(raw, fallbackCurrency: 'RON');
      expect(bill.printedTotal, isNull);
      expect(bill.printedTotalMismatches, isFalse);
    });

    test('restaurant merchant and drinks/service default to Dining', () {
      const raw = '''
Ristorante Adriatico
Espresso x2          CHF 7.00
Water 0.5L           CHF 4.50
Service              CHF 4.00
Tagliatelle          CHF 22.00
Insalata             CHF 12.00
Tiramisu             CHF 15.00
TOTAL                CHF 64.50
''';
      final bill = BillParser.parse(raw, fallbackCurrency: 'CHF');

      expect(bill.suggestedCategoryName, 'Dining');
      expect(bill.printedTotal, closeTo(64.50, 0.001));
      expect(bill.printedTotalMismatches, isFalse);
      expect(
        bill.lines.map((l) => l.categoryName).toSet(),
        equals({'Dining'}),
      );
    });
  });
}
