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

  test('1-year end equals current + Σ each item by its own recurrence', () {
    final summary = forecast();
    final current = MoneyMath.netWorthMain(
      accounts: snapshot.accounts,
      transactions: snapshot.transactions,
      mainCurrency: 'CHF',
      rates: snapshot.rates,
      asOf: asOf,
    );
    // Sample data is all monthly, so this also equals monthlyNet × 12.
    expect(
      summary.endOfPeriodBalance,
      closeTo(current + summary.monthlyNet * 12, 0.01),
    );
    expect(summary.series.last.balance, closeTo(summary.endOfPeriodBalance, 0.01));
  });

  test('housing budget is not stacked on top of recurring rent', () {
    final summary = forecast();
    // Income 9453; recurring 1982+1300+15.99; extra budget room:
    // groceries 450 + subs max(80-15.99,0) + housing max(3000-1982,0)
    // + unbudgeted one-off average.
    expect(summary.recurringIncomeMonthly, closeTo(9453, 0.01));
    // Planned expenses must stay below "recurring + full budgets" (3297.99+3530).
    expect(summary.plannedExpensesMonthly, lessThan(3297.99 + 3530));
    // And above bare recurring alone (budgets / one-offs still count).
    expect(summary.plannedExpensesMonthly, greaterThan(3297.99));
  });

  test('end of month does not add another full month of already-booked salary', () {
    final summary = forecast();
    final current = MoneyMath.netWorthMain(
      accounts: snapshot.accounts,
      transactions: snapshot.transactions,
      mainCurrency: 'CHF',
      rates: snapshot.rates,
      asOf: asOf,
    );
    final ledgeredMonthEnd = MoneyMath.netWorthMain(
      accounts: snapshot.accounts,
      transactions: snapshot.transactions,
      mainCurrency: 'CHF',
      rates: snapshot.rates,
      asOf: DateTime(2026, 8, 31),
    );
    // Future-dated August rows are in the month-end ledger, not in "today".
    expect(ledgeredMonthEnd, lessThan(current));
    // Old bug: EOM = today + a full extra typical month (double-counted August salary).
    expect(
      summary.endOfMonthBalance,
      isNot(closeTo(current + summary.monthlyNet, 1)),
    );
    expect(summary.endOfMonthBalance, lessThan(current + summary.monthlyNet));
    // EOM is ledger at month-end plus leftover envelopes, not another salary.
    expect(summary.endOfMonthBalance, lessThan(ledgeredMonthEnd + 2000));
  });

  test('calendar year from August is remaining August plus Sep–Dec', () {
    final summary = forecast();
    expect(
      summary.endOfYearBalance,
      closeTo(summary.endOfMonthBalance + summary.monthlyNet * 4, 0.01),
    );
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
