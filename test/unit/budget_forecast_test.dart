import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/data/services/fx_rate_service.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/budget_forecast.dart';
import 'package:zentho/domain/services/recurrence_period.dart';
import 'package:zentho/domain/services/supported_currencies.dart';

void main() {
  group('BudgetForecast', () {
    test('projects end of month using budgets, not one-off MTD velocity', () {
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
          isRecurring: true,
          recurrencePeriod: RecurrencePeriod.monthly,
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
      final budgets = [
        BudgetCategory.create(
          categoryId: food.id,
          monthKey: '2026-08',
          allocated: 900,
          visibility: VisibilityScope.shared,
          ownerProfileId: owner,
        ),
      ];
      final rates = FxRateService.defaultRatesFor('USD');

      final summary = BudgetForecast.project(
        accounts: [account],
        transactions: txs,
        budgets: budgets,
        mainCurrency: 'USD',
        rates: rates,
        horizon: ForecastHorizon.y1,
        recurrence: RecurrencePeriod.monthly,
        now: asOf,
      );

      expect(summary.series, isNotEmpty);
      expect(summary.series.first.date, asOf);
      // Recurring +3000 minus budget plan 900.
      expect(summary.monthlyNet, closeTo(2100, 0.01));
      expect(summary.recurringNetPerPeriod, closeTo(3000, 0.01));
    });

    test('end of period follows horizon, not calendar year', () {
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
      final asOf = DateTime(2026, 8, 2);
      final txs = [
        MoneyTransaction.create(
          type: TransactionType.income,
          amount: 1000,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: salary.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 7, 2),
          isRecurring: true,
          recurrencePeriod: RecurrencePeriod.monthly,
        ),
      ];
      final rates = FxRateService.defaultRatesFor('USD');

      final summary = BudgetForecast.project(
        accounts: [account],
        transactions: txs,
        budgets: const [],
        mainCurrency: 'USD',
        rates: rates,
        horizon: ForecastHorizon.y30,
        recurrence: RecurrencePeriod.monthly,
        now: asOf,
      );

      expect(summary.series.last.date.year, greaterThan(2026));
      expect(summary.endOfPeriodBalance, summary.series.last.balance);
      // Calendar year-end must be much smaller than a 30-year horizon.
      expect(summary.endOfYearBalance, lessThan(summary.endOfPeriodBalance));
      expect(summary.endOfYearBalance, lessThan(20000));
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
      // July bill already in the ledger (-10) + 12 projected months = -130.
      expect(monthly.series.last.balance, closeTo(-130, 0.01));
    });

    test('sums each income and expense by its own recurrence over the period', () {
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
      final tax = SpendCategory.create(
        name: 'Tax',
        iconName: 'tax',
        colorHex: 1,
        isIncome: false,
      );
      final asOf = DateTime(2026, 8, 2);
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
          isRecurring: true,
          recurrencePeriod: RecurrencePeriod.monthly,
        ),
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 50,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: food.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 1),
          isRecurring: true,
          recurrencePeriod: RecurrencePeriod.weekly,
        ),
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 600,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: tax.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 1, 1),
          isRecurring: true,
          recurrencePeriod: RecurrencePeriod.year,
        ),
      ];

      final summary = BudgetForecast.project(
        accounts: [account],
        transactions: txs,
        budgets: const [],
        mainCurrency: 'USD',
        rates: FxRateService.defaultRatesFor('USD'),
        horizon: ForecastHorizon.y1,
        recurrence: RecurrencePeriod.monthly,
        now: asOf,
      );

      // Opening 1000 + already-booked Aug salary 3000 + weekly 50 + yearly 600.
      final current = 1000 + 3000 - 50 - 600;
      final weeklyPerYear = 50 * (365.25 / 7);
      final expectedDelta = 3000 * 12 - weeklyPerYear - 600;
      expect(summary.endOfPeriodBalance, closeTo(current + expectedDelta, 0.01));
      // Mixed cadences: period total is not "fake monthly × 12" from day-of-month math.
      expect(
        summary.monthlyNet,
        closeTo(3000 - 50 * (365.25 / 7) / 12 - 600 / 12, 0.01),
      );
    });

    test('budget only adds room above recurring bills in that category', () {
      final owner = 'p1';
      final account = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: owner,
        visibility: VisibilityScope.shared,
        openingBalance: 0,
      );
      final housing = SpendCategory.create(
        name: 'Housing',
        iconName: 'home',
        colorHex: 1,
        isIncome: false,
      );
      final asOf = DateTime(2026, 8, 2);
      final txs = [
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 2000,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: housing.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 1),
          isRecurring: true,
          recurrencePeriod: RecurrencePeriod.monthly,
        ),
      ];
      final budgets = [
        BudgetCategory.create(
          categoryId: housing.id,
          monthKey: '2026-08',
          allocated: 3000,
          visibility: VisibilityScope.shared,
          ownerProfileId: owner,
        ),
      ];

      final summary = BudgetForecast.project(
        accounts: [account],
        transactions: txs,
        budgets: budgets,
        mainCurrency: 'USD',
        rates: FxRateService.defaultRatesFor('USD'),
        horizon: ForecastHorizon.m1,
        recurrence: RecurrencePeriod.monthly,
        now: asOf,
      );

      // Recurring 2000 + leftover budget room 1000 = 3000, not 5000.
      expect(summary.plannedExpensesMonthly, closeTo(3000, 0.01));
      expect(summary.monthlyNet, closeTo(-3000, 0.01));
    });

    test('short horizon has start and end monthly points', () {
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
      expect(summary.series, hasLength(2));
      expect(summary.endOfPeriodBalance, closeTo(500, 0.01));
    });

    test('period end is exactly current plus monthly net times months', () {
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
      final asOf = DateTime(2026, 8, 2);
      final txs = [
        MoneyTransaction.create(
          type: TransactionType.income,
          amount: 500,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: salary.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 7, 2),
          isRecurring: true,
          recurrencePeriod: RecurrencePeriod.monthly,
        ),
      ];
      final summary = BudgetForecast.project(
        accounts: [account],
        transactions: txs,
        budgets: const [],
        mainCurrency: 'USD',
        rates: FxRateService.defaultRatesFor('USD'),
        horizon: ForecastHorizon.y1,
        recurrence: RecurrencePeriod.monthly,
        now: asOf,
      );
      // Opening 1000 + already-booked July salary 500 = current 1500.
      expect(summary.monthlyNet, closeTo(500, 0.01));
      expect(summary.endOfPeriodBalance, closeTo(1500 + 500 * 12, 0.01));
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
