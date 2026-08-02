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

  BudgetForecastSummary forecast() => BudgetForecast.project(
        accounts: snapshot.accounts,
        transactions: snapshot.transactions,
        budgets: snapshot.budgets,
        mainCurrency: snapshot.settings.mainCurrency,
        rates: snapshot.rates,
        horizon: ForecastHorizon.y1,
        recurrence: RecurrencePeriod.monthly,
        now: asOf,
      );

  test('recurring monthly net matches salary minus recurring bills', () {
    final summary = forecast();
    // 9453 - 15.99 - 1300 - 1982
    expect(summary.recurringNetPerPeriod, closeTo(6155.01, 0.01));
  });

  test('projected monthly net is recurring minus budget plan, not MTD velocity', () {
    final summary = forecast();
    final allocated = MoneyMath.totalBudgetAllocated(
      budgets: snapshot.budgets,
      monthKeyValue: '2026-08',
    );
    expect(allocated, closeTo(3530, 0.01));
    // Must stay positive: 6155.01 - 3530 = 2625.01
    expect(summary.monthlyNet, closeTo(2625.01, 0.05));
    expect(summary.monthlyNet, greaterThan(0));
    // Old bug produced ~-2455 by extrapolating one-off spend forever.
    expect(summary.monthlyNet, isNot(closeTo(-2455.78, 1)));
  });

  test('end balances stay above current when recurring net is strongly positive', () {
    final summary = forecast();
    final current = MoneyMath.netWorthMain(
      accounts: snapshot.accounts,
      transactions: snapshot.transactions,
      mainCurrency: 'CHF',
      rates: snapshot.rates,
      asOf: asOf,
    );

    expect(current, greaterThan(7000));
    expect(summary.endOfMonthBalance, greaterThan(0));
    expect(summary.endOfYearBalance, greaterThan(summary.endOfMonthBalance));
    expect(summary.endOfPeriodBalance, greaterThan(summary.endOfYearBalance));
    // 1y projection should not crash to large negatives from MTD extrapolation.
    expect(summary.endOfPeriodBalance, greaterThan(current));
    expect(summary.endOfPeriodBalance, lessThan(current + 12 * 7000));
  });

  test('end of calendar year is before end of 1-year period from August', () {
    final summary = forecast();
    expect(summary.endOfYearBalance, lessThan(summary.endOfPeriodBalance));
  });
}
