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

  test('assumed income is recurring salary only', () {
    expect(forecast().recurringIncomeMonthly, closeTo(9453, 0.01));
  });

  test('planned expenses include recurring bills, budgets, and unbudgeted one-offs', () {
    final summary = forecast();
    final allocated = MoneyMath.totalBudgetAllocated(
      budgets: snapshot.budgets,
      monthKeyValue: '2026-08',
    );
    const recurringExpenses = 15.99 + 1300 + 1982;
    // July unbudgeted health 371.23 + August transport 186.08
    const unbudgetedNrAvg = (371.2318570896911 + 186.08113137327877) / 2;
    expect(allocated, closeTo(3530, 0.01));
    expect(
      summary.plannedExpensesMonthly,
      closeTo(recurringExpenses + allocated + unbudgetedNrAvg, 0.5),
    );
  });

  test('projected monthly net is lower than raw recurring surplus', () {
    final summary = forecast();
    expect(
      summary.monthlyNet,
      closeTo(
        summary.recurringIncomeMonthly - summary.plannedExpensesMonthly,
        0.01,
      ),
    );
    // Raw recurring surplus is +6155; after budgets + typical one-offs it
    // should land well below that (and below the previous 2625 card).
    expect(summary.monthlyNet, lessThan(2500));
    expect(summary.monthlyNet, greaterThan(1500));
    expect(summary.highSavingsRate, isFalse);
  });

  test('end of month is below current net worth after remaining planned spend', () {
    final summary = forecast();
    final current = MoneyMath.netWorthMain(
      accounts: snapshot.accounts,
      transactions: snapshot.transactions,
      mainCurrency: 'CHF',
      rates: snapshot.rates,
      asOf: asOf,
    );
    expect(summary.endOfMonthBalance, lessThan(current));
    // Previous model left ~6375; with remaining budgets still to burn it
    // should land meaningfully lower.
    expect(summary.endOfMonthBalance, lessThan(5000));
  });

  test('end of calendar year is before end of 1-year period from August', () {
    final summary = forecast();
    expect(summary.endOfYearBalance, lessThan(summary.endOfPeriodBalance));
  });
}
