import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/services/budget_forecast.dart';
import 'package:zentho/domain/services/csv_data_exchange.dart';
import 'package:zentho/domain/services/money_math.dart';
import 'package:zentho/domain/services/recurrence_period.dart';

void main() {
  final snapshot = CsvDataExchange.importSnapshot(
    File('test/fixtures/zentho_export_sample.csv').readAsStringSync(),
  ).snapshot;

  final asOf = DateTime(2026, 8, 2);

  BudgetForecastSummary forecast([ForecastHorizon horizon = ForecastHorizon.y1]) =>
      BudgetForecast.project(
        accounts: snapshot.accounts,
        transactions: snapshot.transactions,
        budgets: snapshot.budgets,
        mainCurrency: snapshot.settings.mainCurrency,
        rates: snapshot.rates,
        horizon: horizon,
        recurrence: RecurrencePeriod.monthly,
        now: asOf,
      );

  test('assumed income is recurring salary only', () {
    expect(forecast().recurringIncomeMonthly, closeTo(9453, 0.01));
  });

  test('1-year end equals current + monthly net × 12', () {
    final summary = forecast();
    final current = MoneyMath.netWorthMain(
      accounts: snapshot.accounts,
      transactions: snapshot.transactions,
      mainCurrency: 'CHF',
      rates: snapshot.rates,
      asOf: asOf,
    );
    expect(
      summary.endOfPeriodBalance,
      closeTo(current + summary.monthlyNet * 12, 0.01),
    );
    expect(summary.series.last.balance, closeTo(summary.endOfPeriodBalance, 0.01));
  });

  test('end of month is current + one monthly net', () {
    final summary = forecast();
    final current = MoneyMath.netWorthMain(
      accounts: snapshot.accounts,
      transactions: snapshot.transactions,
      mainCurrency: 'CHF',
      rates: snapshot.rates,
      asOf: asOf,
    );
    expect(summary.endOfMonthBalance, closeTo(current + summary.monthlyNet, 0.01));
  });

  test('calendar year from August is current + monthly net × 5', () {
    final summary = forecast();
    final current = MoneyMath.netWorthMain(
      accounts: snapshot.accounts,
      transactions: snapshot.transactions,
      mainCurrency: 'CHF',
      rates: snapshot.rates,
      asOf: asOf,
    );
    // Aug..Dec inclusive
    expect(summary.endOfYearBalance, closeTo(current + summary.monthlyNet * 5, 0.01));
    expect(summary.endOfYearBalance, lessThan(summary.endOfPeriodBalance));
  });

  test('projected monthly net matches income minus planned expenses', () {
    final summary = forecast();
    expect(
      summary.monthlyNet,
      closeTo(
        summary.recurringIncomeMonthly - summary.plannedExpensesMonthly,
        0.01,
      ),
    );
  });
}
