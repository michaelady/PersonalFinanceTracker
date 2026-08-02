import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/services/csv_data_exchange.dart';
import 'package:zentho/domain/services/money_math.dart';

void main() {
  late final snapshot = CsvDataExchange.importSnapshot(
    File('test/fixtures/zentho_export_sample.csv').readAsStringSync(),
  ).snapshot;

  final rates = snapshot.rates;
  const main = 'CHF';
  final account = snapshot.accounts.single;

  group('calculations against real user export', () {
    test('imports expected shape', () {
      expect(snapshot.settings.mainCurrency, 'CHF');
      expect(snapshot.accounts, hasLength(1));
      expect(account.currencyCode, 'EUR');
      expect(account.openingBalance, 2500);
      expect(snapshot.transactions, hasLength(8));
      expect(snapshot.budgets, hasLength(3));
    });

    test('FX converts EUR expenses into CHF consistently with ledger', () {
      final groceries = snapshot.transactions
          .firstWhere((t) => t.note == 'Market run');
      final inMain = MoneyMath.toMain(
        amount: groceries.amount,
        currencyCode: groceries.currencyCode,
        mainCurrency: main,
        rates: rates,
      );
      expect(inMain, closeTo(80.38704875325642, 0.0001));
    });

    test('account native balance converts mixed CHF/EUR activity correctly', () {
      // Includes the future-dated Aug 5 streaming row from the export.
      final native = MoneyMath.balanceNativeForAccount(
        account: account,
        transactions: snapshot.transactions,
        mainCurrency: main,
        rates: rates,
      );
      expect(native, closeTo(7767.004747999999, 0.01));

      final inMain = MoneyMath.balanceForAccount(
        account: account,
        transactions: snapshot.transactions,
        mainCurrency: main,
        rates: rates,
      );
      expect(inMain, closeTo(7226.465154447338, 0.01));
    });

    test('as-of cutoff excludes future-dated transactions from current balance', () {
      final asOf = DateTime.utc(2026, 8, 2);
      final native = MoneyMath.balanceNativeForAccount(
        account: account,
        transactions: snapshot.transactions,
        mainCurrency: main,
        rates: rates,
        asOf: asOf,
      );
      // Excludes Aug 3 groceries (86.4 EUR) and Aug 5 streaming (~17.19 EUR).
      expect(native, closeTo(7870.5908, 0.05));
    });

    test('net worth matches sole account balance in main currency', () {
      final net = MoneyMath.netWorthMain(
        accounts: snapshot.accounts,
        transactions: snapshot.transactions,
        mainCurrency: main,
        rates: rates,
      );
      expect(net, closeTo(7226.465154447338, 0.01));
    });

    test('August available-to-spend equals income minus expenses once', () {
      const month = '2026-08';
      final income = MoneyMath.incomeInMonthMain(
        transactions: snapshot.transactions,
        monthKeyValue: month,
        mainCurrency: main,
        rates: rates,
      );
      final spent = MoneyMath.expenseInMonthMain(
        transactions: snapshot.transactions,
        monthKeyValue: month,
        mainCurrency: main,
        rates: rates,
      );
      expect(income, closeTo(9453, 0.01));
      expect(spent, closeTo(4181.317130628954, 0.01));

      final available = MoneyMath.availableToSpend(
        transactions: snapshot.transactions,
        budgets: snapshot.budgets,
        monthKeyValue: month,
        mainCurrency: main,
        rates: rates,
      );

      // Must not double-count Housing overspend against the 100 CHF budget.
      expect(available, closeTo(income - spent, 0.01));
      expect(available, closeTo(5271.682869371046, 0.01));
      expect(available, greaterThan(4000));
      expect(available, lessThan(6000));
    });

    test('Housing category spend aggregates CHF rent + EUR charge', () {
      final housingId = snapshot.categories
          .firstWhere((c) => c.name == 'Housing')
          .id;
      final spent = MoneyMath.spentInCategoryMain(
        categoryId: housingId,
        monthKeyValue: '2026-08',
        transactions: snapshot.transactions,
        mainCurrency: main,
        rates: rates,
      );
      expect(spent, closeTo(2598.8589505024192, 0.01));
    });
  });
}
