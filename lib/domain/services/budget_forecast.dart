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

/// Projects balances from current net worth.
///
/// Conservative monthly expense plan:
///   recurring expenses
///   + category budgets (planned spend)
///   + typical unbudgeted one-off spend
///
/// This intentionally keeps budgets even when a recurring bill exists in the
/// same category, so incomplete discretionary tracking does not inflate the
/// surplus. Recurring income/expenses still land on their real dates.
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
    final horizonEnd = DateTime(asOf.year, asOf.month + horizon.months, asOf.day);
    final monthEnd = DateTime(asOf.year, asOf.month + 1, 0);
    final yearEnd = DateTime(asOf.year, 12, 31);
    final simEnd = _maxDate(horizonEnd, _maxDate(monthEnd, yearEnd));

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

    final recurringTxs = transactions.where((t) => t.isRecurring).toList();
    final flows = [
      for (final tx in recurringTxs)
        _RecurringFlow(
          amount: _signedMain(tx, mainCurrency, rates),
          period: tx.recurrencePeriod,
          nextDue: _nextDueAfter(tx.date, tx.recurrencePeriod, asOf),
        ),
    ];

    final oneOffs = [
      for (final tx in transactions)
        if (!tx.isRecurring && _dateOnly(tx.date).isAfter(asOf))
          _OneOffFlow(
            date: _dateOnly(tx.date),
            amount: _signedMain(tx, mainCurrency, rates),
            coveredByBudgetBurn: tx.categoryId != null &&
                plan.budgetedCategoryIds.contains(tx.categoryId),
          ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    final recurringNetPerPeriod = recurringTxs.fold<double>(0, (sum, tx) {
      final signed = _signedMain(tx, mainCurrency, rates);
      return sum +
          normalizeToPeriod(signed, tx.recurrencePeriod, recurrence, asOf);
    });

    final monthlyNet = plan.monthlyNet;
    final daysInMonth = DateTime(asOf.year, asOf.month + 1, 0).day;

    var balance = current;
    double? endOfMonthBalance;
    double? endOfYearBalance;
    double? endOfPeriodBalance;
    final series = <ForecastPoint>[ForecastPoint(date: asOf, balance: balance)];
    var nextSample = recurrence.addTo(asOf);
    var oneOffIndex = 0;

    var day = asOf;
    while (day.isBefore(simEnd)) {
      day = day.add(const Duration(days: 1));
      balance += plan.dailyFor(day);

      while (oneOffIndex < oneOffs.length &&
          !oneOffs[oneOffIndex].date.isAfter(day)) {
        final oneOff = oneOffs[oneOffIndex];
        if (!oneOff.coveredByBudgetBurn) {
          balance += oneOff.amount;
        }
        oneOffIndex++;
      }

      for (final flow in flows) {
        while (!flow.nextDue.isAfter(day)) {
          balance += flow.amount;
          flow.nextDue = flow.period.addTo(flow.nextDue);
        }
      }

      if (_sameDay(day, monthEnd)) endOfMonthBalance = balance;
      if (_sameDay(day, yearEnd)) endOfYearBalance = balance;
      if (_sameDay(day, horizonEnd)) endOfPeriodBalance = balance;

      final onHorizonEnd = _sameDay(day, horizonEnd);
      if ((!day.isBefore(nextSample) && !day.isAfter(horizonEnd)) ||
          onHorizonEnd) {
        if (!series.any((p) => _sameDay(p.date, day))) {
          series.add(ForecastPoint(date: day, balance: balance));
        }
        while (!nextSample.isAfter(day)) {
          nextSample = recurrence.addTo(nextSample);
        }
      }
    }

    if (!_sameDay(series.last.date, horizonEnd) && !horizonEnd.isBefore(asOf)) {
      final atHorizon = series.lastWhere(
        (p) => !p.date.isAfter(horizonEnd),
        orElse: () => series.first,
      );
      endOfPeriodBalance ??= atHorizon.balance;
      if (!_sameDay(atHorizon.date, horizonEnd)) {
        series.add(
          ForecastPoint(
            date: horizonEnd,
            balance: endOfPeriodBalance,
          ),
        );
      }
    }

    final clipped = [
      for (final p in series)
        if (!p.date.isAfter(horizonEnd)) p,
    ];

    return BudgetForecastSummary(
      endOfMonthBalance: endOfMonthBalance ?? current,
      endOfPeriodBalance: endOfPeriodBalance ?? clipped.last.balance,
      endOfYearBalance: endOfYearBalance ?? endOfMonthBalance ?? current,
      monthlyNet: monthlyNet,
      dailyNet: monthlyNet / daysInMonth,
      recurringNetPerPeriod: recurringNetPerPeriod,
      recurringIncomeMonthly: plan.recurringIncomeMonthly,
      plannedExpensesMonthly: plan.plannedExpensesMonthly,
      series: _downsample(clipped, maxPoints: 180),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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

  static DateTime _maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

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

  static DateTime _nextDueAfter(
    DateTime anchor,
    RecurrencePeriod period,
    DateTime asOf,
  ) {
    var due = DateTime(anchor.year, anchor.month, anchor.day);
    for (var i = 0; i < 100000 && !due.isAfter(asOf); i++) {
      due = period.addTo(due);
    }
    return due;
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
    required this.asOf,
    required this.budgetedCategoryIds,
    required this.recurringIncomeMonthly,
    required this.plannedExpensesMonthly,
    required this.remainingThisMonthDaily,
    required this.steadyDaily,
  });

  final DateTime asOf;
  final Set<String> budgetedCategoryIds;
  final double recurringIncomeMonthly;
  final double plannedExpensesMonthly;
  final double remainingThisMonthDaily;
  final double steadyDaily;

  double get monthlyNet => recurringIncomeMonthly - plannedExpensesMonthly;

  factory _CashflowPlan.build({
    required List<MoneyTransaction> transactions,
    required List<BudgetCategory> budgets,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    required DateTime asOf,
  }) {
    final monthKey = MoneyMath.monthKey(asOf);
    final daysInMonth = DateTime(asOf.year, asOf.month + 1, 0).day;
    final daysLeft = (daysInMonth - asOf.day).clamp(0, 31);

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

    // Typical monthly one-offs outside budgeted categories.
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

    final plannedExpenses =
        recurringExpenses + allocated + unbudgetedNrAvg;

    // Rest-of-month budget burn: only non-recurring spend reduces the
    // remaining envelope, so already-paid rent does not zero out planned
    // housing/grocery spend for the rest of the month.
    var nonRecurringBudgetedToDate = 0.0;
    var futureNonRecurringBudgeted = 0.0;
    for (final tx in transactions) {
      if (tx.isRecurring || tx.type != TransactionType.expense) continue;
      if (MoneyMath.monthKey(tx.date) != monthKey) continue;
      if (tx.categoryId == null || !budgetedIds.contains(tx.categoryId)) {
        continue;
      }
      final amount = toMainAmount(tx);
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (day.isAfter(asOf)) {
        futureNonRecurringBudgeted += amount;
      } else {
        nonRecurringBudgetedToDate += amount;
      }
    }
    final remainingBudgets = (allocated -
            nonRecurringBudgetedToDate -
            futureNonRecurringBudgeted)
        .clamp(0.0, double.infinity)
        .toDouble();

    var unbudgetedNrSpentToDate = 0.0;
    for (final tx in transactions) {
      if (tx.isRecurring || tx.type != TransactionType.expense) continue;
      if (MoneyMath.monthKey(tx.date) != monthKey) continue;
      final budgeted =
          tx.categoryId != null && budgetedIds.contains(tx.categoryId);
      if (budgeted) continue;
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (day.isAfter(asOf)) continue;
      unbudgetedNrSpentToDate += toMainAmount(tx);
    }
    final remainingUnbudgetedNr = (unbudgetedNrAvg - unbudgetedNrSpentToDate)
        .clamp(0.0, double.infinity)
        .toDouble();

    final remainingThisMonth = remainingBudgets + remainingUnbudgetedNr;
    final remainingDaily =
        daysLeft == 0 ? 0.0 : -remainingThisMonth / daysLeft;
    final steadyDaily = daysInMonth == 0
        ? 0.0
        : -(allocated + unbudgetedNrAvg) / daysInMonth;

    return _CashflowPlan(
      asOf: asOf,
      budgetedCategoryIds: budgetedIds,
      recurringIncomeMonthly: recurringIncome,
      plannedExpensesMonthly: plannedExpenses,
      remainingThisMonthDaily: remainingDaily,
      steadyDaily: steadyDaily,
    );
  }

  double dailyFor(DateTime day) {
    if (day.year == asOf.year && day.month == asOf.month) {
      return remainingThisMonthDaily;
    }
    return steadyDaily;
  }
}

class _RecurringFlow {
  _RecurringFlow({
    required this.amount,
    required this.period,
    required this.nextDue,
  });

  final double amount;
  final RecurrencePeriod period;
  DateTime nextDue;
}

class _OneOffFlow {
  const _OneOffFlow({
    required this.date,
    required this.amount,
    required this.coveredByBudgetBurn,
  });

  final DateTime date;
  final double amount;
  final bool coveredByBudgetBurn;
}
