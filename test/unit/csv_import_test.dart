import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/csv_import_service.dart';

void main() {
  test('parses valid CSV rows into transactions', () {
    final account = Account.create(
      name: 'Checking',
      type: AccountType.checking,
      currencyCode: 'USD',
      ownerProfileId: 'p1',
      visibility: VisibilityScope.shared,
    );
    final category = SpendCategory.create(
      name: 'Groceries',
      iconName: 'cart',
      colorHex: 1,
      isIncome: false,
    );

    const csv = '''
date,amount,type,category,account,note,currency,visibility
2026-08-01,42.5,expense,Groceries,Checking,Market,USD,shared
''';

    final result = CsvImportService.parse(
      csvBody: csv,
      accounts: [account],
      categories: [category],
      ownerProfileId: 'p1',
      defaultCurrency: 'USD',
    );

    expect(result.transactions, hasLength(1));
    expect(result.transactions.first.amount, 42.5);
    expect(result.skippedRows, 0);
  });

  test('reports missing columns', () {
    final result = CsvImportService.parse(
      csvBody: 'foo,bar\n1,2',
      accounts: const [],
      categories: const [],
      ownerProfileId: 'p1',
      defaultCurrency: 'USD',
    );
    expect(result.errors, isNotEmpty);
  });
}
