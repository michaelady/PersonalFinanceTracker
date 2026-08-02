import '../models/models.dart';
import 'money_math.dart';
import 'recurrence_period.dart';

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
    required this.endOfPeriodBalance,
    required this.endOfYearBalance,
    required this.monthlyNet,
    required this.dailyNet,
    required this.recurringNetPerPeriod,
    required this.recurringIncomeMonthly,
    required this.plannedExpensesMonthly,
    required this.series,
  });

  final double endOfMonthBalance;
  final double endOfPeriodBalance;
  final double endOfYearBalance;
  final double monthlyNet;
  final double dailyNet;
  final double recurringNetPerPeriod;
  final double recurringIncomeMonthly;
  final double plannedExpensesMonthly;
  final List<ForecastPoint> series;

  bool get highSavingsRate {
    if (recurringIncomeMonthly <= 0) return false;
    return monthlyNet / recurringIncomeMonthly >= 0.25;
  }
}

/// Monthly cashflow forecast.
///
/// Planned monthly net = recurring income − (recurring expenses + budgets +
/// typical unbudgeted one-offs).
///
/// All horizon balances use the same monthly step:
///   balance(n) = current + monthlyNet × n
/// so “1 year” is exactly current + monthlyNet × 12.
abstract final class BudgetForecast {
  static BudgetForecastSummary project({
    required List<Account> accounts,
    required List<MoneyTransaction> transactions,
    required List<BudgetCategory> budgets,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    required ForecastHorizon horizon,
    RecurrencePeriod recurrence = RecurrencePeriod.monthly,
    DateTime? now,
  }) {
    final rawNow = now ?? DateTime.now();
    final asOf = DateTime(rawNow.year, rawNow.month, rawNow.day);

    final current = MoneyMath.netWorthMain(
      accounts: accounts,
      transactions: transactions,
      mainCurrency: mainCurrency,
      rates: rates,
      asOf: asOf,
    );

    final plan = _CashflowPlan.build(
      transactions: transactions,
      budgets: budgets,
      mainCurrency: mainCurrency,
      rates: rates,
      asOf: asOf,
    );

    final monthlyNet = plan.monthlyNet;
    final daysInMonth = DateTime(asOf.year, asOf.month + 1, 0).day;

    final recurringTxs = transactions.where((t) => t.isRecurring).toList();
    final recurringNetPerPeriod = recurringTxs.fold<double>(0, (sum, tx) {
      final signed = _signedMain(tx, mainCurrency, rates);
      return sum +
          normalizeToPeriod(signed, tx.recurrencePeriod, recurrence, asOf);
    });

    // Inclusive months left in the calendar year (Aug → Aug..Dec = 5).
    final monthsToYearEnd = 12 - asOf.month + 1;

    final endOfMonthBalance = current + monthlyNet;
    final endOfYearBalance = current + monthlyNet * monthsToYearEnd;
    final endOfPeriodBalance = current + monthlyNet * horizon.months;

    final series = <ForecastPoint>[
      for (var i = 0; i <= horizon.months; i++)
        ForecastPoint(
          date: DateTime(asOf.year, asOf.month + i, asOf.day),
          balance: current + monthlyNet * i,
        ),
    ];

    return BudgetForecastSummary(
      endOfMonthBalance: endOfMonthBalance,
      endOfPeriodBalance: endOfPeriodBalance,
      endOfYearBalance: endOfYearBalance,
      monthlyNet: monthlyNet,
      dailyNet: monthlyNet / daysInMonth,
      recurringNetPerPeriod: recurringNetPerPeriod,
      recurringIncomeMonthly: plan.recurringIncomeMonthly,
      plannedExpensesMonthly: plan.plannedExpensesMonthly,
      series: _downsample(series, maxPoints: 180),
    );
  }

  static List<ForecastPoint> _downsample(
    List<ForecastPoint> points, {
    required int maxPoints,
  }) {
    if (points.length <= maxPoints) return points;
    final result = <ForecastPoint>[points.first];
    final step = (points.length - 1) / (maxPoints - 1);
    for (var i = 1; i < maxPoints - 1; i++) {
      result.add(points[(i * step).round()]);
    }
    result.add(points.last);
    return result;
  }

  static double _signedMain(
    MoneyTransaction tx,
    String mainCurrency,
    List<CurrencyRate> rates,
  ) {
    final main = MoneyMath.toMain(
      amount: tx.amount,
      currencyCode: tx.currencyCode,
      mainCurrency: mainCurrency,
      rates: rates,
      overrideRate: tx.exchangeRateToMain,
    );
    return tx.type == TransactionType.expense ? -main : main;
  }

  static double normalizeToPeriod(
    double amount,
    RecurrencePeriod from,
    RecurrencePeriod to,
    DateTime asOf,
  ) {
    if (from == to) return amount;
    final daysInMonth = DateTime(asOf.year, asOf.month + 1, 0).day.toDouble();

    double dailyFor(RecurrencePeriod p, double value) {
      switch (p) {
        case RecurrencePeriod.daily:
          return value;
        case RecurrencePeriod.weekly:
          return value / 7;
        case RecurrencePeriod.monthly:
          return value / daysInMonth;
        case RecurrencePeriod.twoMonths:
          return value / (daysInMonth * 2);
        case RecurrencePeriod.quarter:
          return value / (daysInMonth * 3);
        case RecurrencePeriod.year:
          return value / 365;
      }
    }

    final daily = dailyFor(from, amount);
    switch (to) {
      case RecurrencePeriod.daily:
        return daily;
      case RecurrencePeriod.weekly:
        return daily * 7;
      case RecurrencePeriod.monthly:
        return daily * daysInMonth;
      case RecurrencePeriod.twoMonths:
        return daily * daysInMonth * 2;
      case RecurrencePeriod.quarter:
        return daily * daysInMonth * 3;
      case RecurrencePeriod.year:
        return daily * 365;
    }
  }
}

class _CashflowPlan {
  _CashflowPlan({
    required this.recurringIncomeMonthly,
    required this.plannedExpensesMonthly,
  });

  final double recurringIncomeMonthly;
  final double plannedExpensesMonthly;

  double get monthlyNet => recurringIncomeMonthly - plannedExpensesMonthly;

  factory _CashflowPlan.build({
    required List<MoneyTransaction> transactions,
    required List<BudgetCategory> budgets,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    required DateTime asOf,
  }) {
    final monthKey = MoneyMath.monthKey(asOf);
    final monthBudgets =
        budgets.where((b) => b.monthKey == monthKey).toList(growable: false);
    final budgetedIds = monthBudgets.map((b) => b.categoryId).toSet();
    final allocated = monthBudgets.fold<double>(0, (s, b) => s + b.allocated);

    double toMainAmount(MoneyTransaction tx) => MoneyMath.toMain(
          amount: tx.amount,
          currencyCode: tx.currencyCode,
          mainCurrency: mainCurrency,
          rates: rates,
          overrideRate: tx.exchangeRateToMain,
        );

    var recurringIncome = 0.0;
    var recurringExpenses = 0.0;
    for (final tx in transactions.where((t) => t.isRecurring)) {
      final monthly = BudgetForecast.normalizeToPeriod(
        toMainAmount(tx),
        tx.recurrencePeriod,
        RecurrencePeriod.monthly,
        asOf,
      );
      if (tx.type == TransactionType.income) {
        recurringIncome += monthly;
      } else if (tx.type == TransactionType.expense) {
        recurringExpenses += monthly;
      }
    }

    final nrByMonth = <String, double>{};
    for (final tx in transactions) {
      if (tx.isRecurring || tx.type != TransactionType.expense) continue;
      final budgeted =
          tx.categoryId != null && budgetedIds.contains(tx.categoryId);
      if (budgeted) continue;
      final key = MoneyMath.monthKey(tx.date);
      nrByMonth[key] = (nrByMonth[key] ?? 0) + toMainAmount(tx);
    }
    final unbudgetedNrAvg = nrByMonth.isEmpty
        ? 0.0
        : nrByMonth.values.reduce((a, b) => a + b) / nrByMonth.length;

    return _CashflowPlan(
      recurringIncomeMonthly: recurringIncome,
      plannedExpensesMonthly:
          recurringExpenses + allocated + unbudgetedNrAvg,
    );
  }
}
