import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/data/services/fx_rate_service.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/budget_forecast.dart';
import 'package:zentho/domain/services/recurrence_period.dart';
import 'package:zentho/domain/services/supported_currencies.dart';

void main() {
  group('BudgetForecast', () {
    test('projects end of month and year from paced cash flow', () {
      final owner = 'p1';
      final account = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: owner,
        visibility: VisibilityScope.shared,
        openingBalance: 1000,
      );
      final salary = SpendCategory.create(
        name: 'Salary',
        iconName: 'pay',
        colorHex: 1,
        isIncome: true,
      );
      final food = SpendCategory.create(
        name: 'Food',
        iconName: 'food',
        colorHex: 1,
        isIncome: false,
      );
      final asOf = DateTime(2026, 8, 15);
      final txs = [
        MoneyTransaction.create(
          type: TransactionType.income,
          amount: 3000,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: salary.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 1),
        ),
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 750,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: food.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 10),
        ),
      ];
      final rates = FxRateService.defaultRatesFor('USD');

      final summary = BudgetForecast.project(
        accounts: [account],
        transactions: txs,
        budgets: const [],
        mainCurrency: 'USD',
        rates: rates,
        horizon: ForecastHorizon.y1,
        recurrence: RecurrencePeriod.monthly,
        now: asOf,
      );

      expect(summary.series, isNotEmpty);
      expect(summary.series.first.date, asOf);
      expect(summary.monthlyNet, isNot(0));
    });

    test('applies recurring transactions by cadence', () {
      final owner = 'p1';
      final account = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: owner,
        visibility: VisibilityScope.shared,
        openingBalance: 0,
      );
      final sub = SpendCategory.create(
        name: 'Subs',
        iconName: 'sub',
        colorHex: 1,
        isIncome: false,
      );
      final asOf = DateTime(2026, 8, 1);
      final txs = [
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 10,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: sub.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 7, 1),
          isRecurring: true,
          recurrencePeriod: RecurrencePeriod.monthly,
          recurringLabel: 'Stream',
        ),
      ];

      final monthly = BudgetForecast.project(
        accounts: [account],
        transactions: txs,
        budgets: const [],
        mainCurrency: 'USD',
        rates: FxRateService.defaultRatesFor('USD'),
        horizon: ForecastHorizon.y1,
        recurrence: RecurrencePeriod.monthly,
        now: asOf,
      );

      final weekly = BudgetForecast.project(
        accounts: [account],
        transactions: txs,
        budgets: const [],
        mainCurrency: 'USD',
        rates: FxRateService.defaultRatesFor('USD'),
        horizon: ForecastHorizon.y1,
        recurrence: RecurrencePeriod.weekly,
        now: asOf,
      );

      // Same underlying monthly bill; normalized recurring net differs by selector.
      expect(monthly.recurringNetPerPeriod, closeTo(-10, 0.01));
      expect(weekly.recurringNetPerPeriod.abs(), lessThan(10));
      // Over a year, monthly recurrence should debit about 12 times.
      expect(monthly.series.last.balance, closeTo(-120, 15));
    });

    test('short horizon samples with daily recurrence', () {
      final owner = 'p1';
      final account = Account.create(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'USD',
        ownerProfileId: owner,
        visibility: VisibilityScope.shared,
        openingBalance: 500,
      );
      final summary = BudgetForecast.project(
        accounts: [account],
        transactions: const [],
        budgets: const [],
        mainCurrency: 'USD',
        rates: FxRateService.defaultRatesFor('USD'),
        horizon: ForecastHorizon.m1,
        recurrence: RecurrencePeriod.daily,
        now: DateTime(2026, 8, 20),
      );
      expect(summary.series.length, greaterThan(2));
    });
  });

  group('SupportedCurrencies', () {
    test('includes CHF and RON with USD defaults', () {
      expect(SupportedCurrencies.codes, containsAll(['CHF', 'RON']));
      final rates = FxRateService.defaultRatesFor('USD');
      expect(rates.any((r) => r.code == 'CHF'), isTrue);
      expect(rates.any((r) => r.code == 'RON'), isTrue);
      final chf = rates.firstWhere((r) => r.code == 'CHF').rateToMain;
      final ron = rates.firstWhere((r) => r.code == 'RON').rateToMain;
      expect(chf, closeTo(1.237569, 0.0001));
      expect(ron, closeTo(0.219213, 0.0001));
    });

    test('rebases defaults when main currency is EUR', () {
      final rates = FxRateService.defaultRatesFor('EUR');
      expect(rates.firstWhere((r) => r.code == 'EUR').rateToMain, 1);
      expect(
        rates.firstWhere((r) => r.code == 'USD').rateToMain,
        closeTo(1 / 1.151393, 0.001),
      );
    });
  });

  test('RecurrencePeriod defaults to monthly', () {
    expect(RecurrencePeriod.tryParse(null), RecurrencePeriod.monthly);
    expect(RecurrencePeriod.monthly.label, 'Monthly');
  });
}
