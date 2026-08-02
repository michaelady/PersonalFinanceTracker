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
  });
}
