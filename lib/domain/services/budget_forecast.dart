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

/// Cashflow forecast built from each income/expense and its own recurrence.
///
/// Over a horizon of N months:
///   periodDelta = Σ income×occurrences − Σ expense×occurrences
///               − extra budget room − typical unbudgeted one-offs
///   endBalance  = current net worth + periodDelta
///
/// Occurrences use each item’s cadence (weekly ≈ 52/year, monthly × N,
/// yearly × N/12, …). When every item is monthly, this equals
/// current + monthlyNet × N.
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

    final monthlyNet = plan.netOverMonths(1);
    final daysInMonth = DateTime(asOf.year, asOf.month + 1, 0).day;

    final recurringTxs = transactions.where((t) => t.isRecurring).toList();
    final recurringNetPerPeriod = recurringTxs.fold<double>(0, (sum, tx) {
      final signed = _signedMain(tx, mainCurrency, rates);
      return sum +
          normalizeToPeriod(signed, tx.recurrencePeriod, recurrence, asOf);
    });

    // Inclusive months left in the calendar year (Aug → Aug..Dec = 5).
    final monthsToYearEnd = 12 - asOf.month + 1;

    final endOfMonthBalance = current + plan.netOverMonths(1);
    final endOfYearBalance = current + plan.netOverMonths(monthsToYearEnd);
    final endOfPeriodBalance = current + plan.netOverMonths(horizon.months);

    final series = <ForecastPoint>[
      for (var i = 0; i <= horizon.months; i++)
        ForecastPoint(
          date: DateTime(asOf.year, asOf.month + i, asOf.day),
          balance: current + plan.netOverMonths(i),
        ),
    ];

    return BudgetForecastSummary(
      endOfMonthBalance: endOfMonthBalance,
      endOfPeriodBalance: endOfPeriodBalance,
      endOfYearBalance: endOfYearBalance,
      monthlyNet: monthlyNet,
      dailyNet: monthlyNet / daysInMonth,
      recurringNetPerPeriod: recurringNetPerPeriod,
      recurringIncomeMonthly: plan.incomeOverMonths(1),
      plannedExpensesMonthly: plan.expenseOverMonths(1),
      series: _downsample(series, maxPoints: 180),
    );
  }

  /// Average length of one cycle in months (calendar-agnostic).
  static double monthsPerCycle(RecurrencePeriod period) {
    switch (period) {
      case RecurrencePeriod.daily:
        return 12 / 365.25;
      case RecurrencePeriod.weekly:
        return 12 / (365.25 / 7);
      case RecurrencePeriod.monthly:
        return 1;
      case RecurrencePeriod.twoMonths:
        return 2;
      case RecurrencePeriod.quarter:
        return 3;
      case RecurrencePeriod.year:
        return 12;
    }
  }

  /// How many times a cadence fires across [months].
  static double occurrencesOverMonths(RecurrencePeriod period, num months) {
    if (months == 0) return 0;
    return months / monthsPerCycle(period);
  }

  /// [amount] contributed over [months] given its native [period].
  static double amountOverMonths(
    double amount,
    RecurrencePeriod period,
    num months,
  ) {
    return amount * occurrencesOverMonths(period, months);
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
    // [asOf] retained so existing call sites keep compiling; conversion is
    // calendar-length based and does not depend on the specific month.
    assert(asOf.year > 0);
    if (from == to) return amount;
    final monthly = amount / monthsPerCycle(from);
    return monthly * monthsPerCycle(to);
  }
}

class _CashflowPlan {
  _CashflowPlan({
    required this.recurringIncomes,
    required this.recurringExpenses,
    required this.extraBudgetMonthly,
    required this.unbudgetedOneOffMonthly,
  });

  final List<_RecurringAmount> recurringIncomes;
  final List<_RecurringAmount> recurringExpenses;
  final double extraBudgetMonthly;
  final double unbudgetedOneOffMonthly;

  double incomeOverMonths(num months) {
    var total = 0.0;
    for (final item in recurringIncomes) {
      total += BudgetForecast.amountOverMonths(item.amount, item.period, months);
    }
    return total;
  }

  double expenseOverMonths(num months) {
    var total = 0.0;
    for (final item in recurringExpenses) {
      total += BudgetForecast.amountOverMonths(item.amount, item.period, months);
    }
    return total + extraBudgetMonthly * months + unbudgetedOneOffMonthly * months;
  }

  double netOverMonths(num months) =>
      incomeOverMonths(months) - expenseOverMonths(months);

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

    double toMainAmount(MoneyTransaction tx) => MoneyMath.toMain(
          amount: tx.amount,
          currencyCode: tx.currencyCode,
          mainCurrency: mainCurrency,
          rates: rates,
          overrideRate: tx.exchangeRateToMain,
        );

    final incomes = <_RecurringAmount>[];
    final expenses = <_RecurringAmount>[];
    final recurringMonthlyByCategory = <String, double>{};

    for (final tx in transactions.where((t) => t.isRecurring)) {
      final amount = toMainAmount(tx);
      final item = _RecurringAmount(amount: amount, period: tx.recurrencePeriod);
      if (tx.type == TransactionType.income) {
        incomes.add(item);
      } else if (tx.type == TransactionType.expense) {
        expenses.add(item);
        final categoryId = tx.categoryId;
        if (categoryId != null) {
          final monthly = BudgetForecast.amountOverMonths(
            amount,
            tx.recurrencePeriod,
            1,
          );
          recurringMonthlyByCategory[categoryId] =
              (recurringMonthlyByCategory[categoryId] ?? 0) + monthly;
        }
      }
    }

    // Budgets are monthly envelopes. Only add the room not already covered by
    // recurring bills in that category (avoids rent + housing budget twice).
    var extraBudgetMonthly = 0.0;
    for (final budget in monthBudgets) {
      final covered = recurringMonthlyByCategory[budget.categoryId] ?? 0;
      final extra = budget.allocated - covered;
      if (extra > 0) extraBudgetMonthly += extra;
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
      recurringIncomes: incomes,
      recurringExpenses: expenses,
      extraBudgetMonthly: extraBudgetMonthly,
      unbudgetedOneOffMonthly: unbudgetedNrAvg,
    );
  }
}

class _RecurringAmount {
  const _RecurringAmount({required this.amount, required this.period});

  final double amount;
  final RecurrencePeriod period;
}
