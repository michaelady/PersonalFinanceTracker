import '../models/models.dart';
import 'money_math.dart';

enum ForecastHorizon {
  m1(1, '1 month'),
  m2(2, '2 months'),
  m3(3, '3 months'),
  m6(6, '6 months'),
  y1(12, '1 year'),
  y2(24, '2 years'),
  y3(36, '3 years'),
  y5(60, '5 years'),
  y10(120, '10 years'),
  y20(240, '20 years'),
  y30(360, '30 years');

  const ForecastHorizon(this.months, this.label);
  final int months;
  final String label;
}

class ForecastPoint {
  const ForecastPoint({required this.date, required this.balance});

  final DateTime date;
  final double balance;
}

class BudgetForecastSummary {
  const BudgetForecastSummary({
    required this.endOfMonthBalance,
    required this.endOfYearBalance,
    required this.monthlyNet,
    required this.dailyNet,
    required this.series,
  });

  final double endOfMonthBalance;
  final double endOfYearBalance;
  final double monthlyNet;
  final double dailyNet;
  final List<ForecastPoint> series;
}

/// Projects balances from current net worth using recent cash-flow pace.
abstract final class BudgetForecast {
  static BudgetForecastSummary project({
    required List<Account> accounts,
    required List<MoneyTransaction> transactions,
    required List<BudgetCategory> budgets,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    required ForecastHorizon horizon,
    DateTime? now,
  }) {
    final asOf = now ?? DateTime.now();
    final current = MoneyMath.netWorthMain(
      accounts: accounts,
      transactions: transactions,
      mainCurrency: mainCurrency,
      rates: rates,
    );

    final pace = _pace(
      transactions: transactions,
      budgets: budgets,
      mainCurrency: mainCurrency,
      rates: rates,
      asOf: asOf,
    );

    final daysLeftInMonth =
        DateTime(asOf.year, asOf.month + 1, 0).day - asOf.day;
    final endOfMonth = current + pace.dailyNet * daysLeftInMonth;

    final monthOfYear = asOf.month;
    final monthsLeftInYear = 12 - monthOfYear;
    // Finish current month at daily pace, then remaining full months.
    final endOfYear = endOfMonth + pace.monthlyNet * monthsLeftInYear;

    final series = <ForecastPoint>[
      ForecastPoint(date: asOf, balance: current),
    ];
    var running = current;
    // Sample monthly points across the horizon (plus intra-month for short spans).
    if (horizon.months <= 1) {
      final end = DateTime(asOf.year, asOf.month + 1, 0);
      final days = end.difference(asOf).inDays.clamp(1, 31);
      for (var d = 1; d <= days; d++) {
        running = current + pace.dailyNet * d;
        series.add(
          ForecastPoint(date: asOf.add(Duration(days: d)), balance: running),
        );
      }
    } else {
      for (var m = 1; m <= horizon.months; m++) {
        // First month uses remaining-days pace, then full months.
        if (m == 1) {
          running = endOfMonth;
        } else {
          running += pace.monthlyNet;
        }
        final date = DateTime(asOf.year, asOf.month + m, 0);
        series.add(ForecastPoint(date: date, balance: running));
      }
    }

    return BudgetForecastSummary(
      endOfMonthBalance: endOfMonth,
      endOfYearBalance: endOfYear,
      monthlyNet: pace.monthlyNet,
      dailyNet: pace.dailyNet,
      series: series,
    );
  }

  static ({double dailyNet, double monthlyNet}) _pace({
    required List<MoneyTransaction> transactions,
    required List<BudgetCategory> budgets,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    required DateTime asOf,
  }) {
    final monthKey = MoneyMath.monthKey(asOf);
    final income = MoneyMath.incomeInMonthMain(
      transactions: transactions,
      monthKeyValue: monthKey,
      mainCurrency: mainCurrency,
      rates: rates,
    );
    final expense = MoneyMath.expenseInMonthMain(
      transactions: transactions,
      monthKeyValue: monthKey,
      mainCurrency: mainCurrency,
      rates: rates,
    );
    final dayOfMonth = asOf.day.clamp(1, 31);
    final daysInMonth = DateTime(asOf.year, asOf.month + 1, 0).day;

    // Prefer observed pace this month; if thin data, fall back to budgets.
    final allocated = MoneyMath.totalBudgetAllocated(
      budgets: budgets,
      monthKeyValue: monthKey,
    );

    double monthlyIncome;
    double monthlyExpense;

    if (income > 0 || expense > 0) {
      monthlyIncome = income / dayOfMonth * daysInMonth;
      monthlyExpense = expense / dayOfMonth * daysInMonth;
      // If budgets exist and observed spend is very low early in month,
      // blend toward allocated spend for a more realistic outlook.
      if (allocated > 0 && dayOfMonth <= 7) {
        monthlyExpense = (monthlyExpense + allocated) / 2;
      }
    } else if (allocated > 0) {
      monthlyIncome = 0;
      monthlyExpense = allocated;
    } else {
      // Look back up to 90 days for averages.
      final cutoff = asOf.subtract(const Duration(days: 90));
      final recent = transactions.where((t) => !t.date.isBefore(cutoff));
      var inc = 0.0;
      var exp = 0.0;
      for (final tx in recent) {
        final main = MoneyMath.toMain(
          amount: tx.amount,
          currencyCode: tx.currencyCode,
          mainCurrency: mainCurrency,
          rates: rates,
          overrideRate: tx.exchangeRateToMain,
        );
        if (tx.type == TransactionType.income) {
          inc += main;
        } else if (tx.type == TransactionType.expense) {
          exp += main;
        }
      }
      monthlyIncome = inc / 3;
      monthlyExpense = exp / 3;
    }

    final monthlyNet = monthlyIncome - monthlyExpense;
    final dailyNet = monthlyNet / daysInMonth;
    return (dailyNet: dailyNet, monthlyNet: monthlyNet);
  }
}
