import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/csv_import_service.dart';
import 'package:zentho/domain/services/money_math.dart';

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

  test('imports mixed-currency rows and totals them in main currency', () {
    final checking = Account.create(
      name: 'Checking',
      type: AccountType.checking,
      currencyCode: 'USD',
      ownerProfileId: 'p1',
      visibility: VisibilityScope.shared,
    );
    final groceries = SpendCategory.create(
      name: 'Groceries',
      iconName: 'cart',
      colorHex: 1,
      isIncome: false,
    );
    final salary = SpendCategory.create(
      name: 'Salary',
      iconName: 'pay',
      colorHex: 1,
      isIncome: true,
    );

    const csv = '''
date,amount,type,category,account,note,currency,visibility
2026-08-01,100,income,Salary,Checking,Pay,USD,shared
2026-08-02,10,expense,Groceries,Checking,Market,EUR,shared
2026-08-03,5,expense,Groceries,Checking,Snacks,USD,private
2026-08-04,-8,expense,Groceries,Checking,Refund-style,USD,shared
''';

    final result = CsvImportService.parse(
      csvBody: csv,
      accounts: [checking],
      categories: [groceries, salary],
      ownerProfileId: 'p1',
      defaultCurrency: 'USD',
    );

    expect(result.transactions, hasLength(4));
    expect(result.skippedRows, 0);
    expect(result.transactions[3].amount, 8); // abs()
    expect(result.transactions[2].visibility, VisibilityScope.private);

    const rates = [
      CurrencyRate(code: 'USD', rateToMain: 1),
      CurrencyRate(code: 'EUR', rateToMain: 1.1),
    ];
    final income = MoneyMath.incomeInMonthMain(
      transactions: result.transactions,
      monthKeyValue: '2026-08',
      mainCurrency: 'USD',
      rates: rates,
    );
    final spent = MoneyMath.expenseInMonthMain(
      transactions: result.transactions,
      monthKeyValue: '2026-08',
      mainCurrency: 'USD',
      rates: rates,
    );
    expect(income, closeTo(100, 0.01));
    expect(spent, closeTo(10 * 1.1 + 5 + 8, 0.01));

    final sharedOnly = result.transactions
        .where((t) => t.visibility == VisibilityScope.shared)
        .toList();
    expect(
      MoneyMath.expenseInMonthMain(
        transactions: sharedOnly,
        monthKeyValue: '2026-08',
        mainCurrency: 'USD',
        rates: rates,
      ),
      closeTo(11 + 8, 0.01),
    );
  });

  test('skips unknown accounts, types, and blank rows', () {
    final account = Account.create(
      name: 'Checking',
      type: AccountType.checking,
      currencyCode: 'USD',
      ownerProfileId: 'p1',
      visibility: VisibilityScope.shared,
    );
    final groceries = SpendCategory.create(
      name: 'Groceries',
      iconName: 'cart',
      colorHex: 1,
      isIncome: false,
    );
    const csv = '''
date,amount,type,category,account,note,currency,visibility
2026-08-01,10,expense,Groceries,Checking,ok,USD,shared

2026-08-02,10,expense,Groceries,Missing,nope,USD,shared
2026-08-03,10,transfer,Groceries,Checking,bad,USD,shared
2026-08-04,10,expense,Salary,Checking,wrong-cat,USD,shared
''';
    final result = CsvImportService.parse(
      csvBody: csv,
      accounts: [account],
      categories: [groceries],
      ownerProfileId: 'p1',
      defaultCurrency: 'USD',
    );
    expect(result.transactions, hasLength(1));
    expect(result.skippedRows, 3);
    expect(result.errors, isNotEmpty);
  });

  test('defaults empty visibility and currency', () {
    final account = Account.create(
      name: 'Checking',
      type: AccountType.checking,
      currencyCode: 'USD',
      ownerProfileId: 'p1',
      visibility: VisibilityScope.shared,
    );
    final groceries = SpendCategory.create(
      name: 'Groceries',
      iconName: 'cart',
      colorHex: 1,
      isIncome: false,
    );
    const csv = '''
date,amount,type,category,account,note,currency,visibility
2026-08-01,12,expense,Groceries,Checking,x,,
''';
    final result = CsvImportService.parse(
      csvBody: csv,
      accounts: [account],
      categories: [groceries],
      ownerProfileId: 'p1',
      defaultCurrency: 'USD',
    );
    expect(result.transactions, hasLength(1));
    expect(result.transactions.single.visibility, VisibilityScope.shared);
    expect(result.transactions.single.currencyCode, 'USD');
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
