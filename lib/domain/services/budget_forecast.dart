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
    required this.series,
  });

  final double endOfMonthBalance;
  /// Balance at the end of the selected prediction horizon.
  final double endOfPeriodBalance;
  /// Balance at the end of the current calendar year.
  final double endOfYearBalance;
  final double monthlyNet;
  final double dailyNet;
  final double recurringNetPerPeriod;
  final List<ForecastPoint> series;
}

/// Projects balances using non-recurring pace + explicit recurring cadence.
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
    );

    final nonRecurringDaily = _nonRecurringDailyNet(
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

    final recurringNetPerPeriod = recurringTxs.fold<double>(0, (sum, tx) {
      final signed = _signedMain(tx, mainCurrency, rates);
      return sum +
          normalizeToPeriod(signed, tx.recurrencePeriod, recurrence, asOf);
    });

    var balance = current;
    double? endOfMonthBalance;
    double? endOfYearBalance;
    double? endOfPeriodBalance;
    final series = <ForecastPoint>[ForecastPoint(date: asOf, balance: balance)];
    var nextSample = recurrence.addTo(asOf);

    var day = asOf;
    while (day.isBefore(simEnd)) {
      day = day.add(const Duration(days: 1));
      balance += nonRecurringDaily;

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

    // Ensure final horizon point exists.
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

    final daysInMonth = DateTime(asOf.year, asOf.month + 1, 0).day;
    final monthlyNet = nonRecurringDaily * daysInMonth +
        normalizeToPeriod(
          recurringNetPerPeriod,
          recurrence,
          RecurrencePeriod.monthly,
          asOf,
        );

    final clipped = [
      for (final p in series)
        if (!p.date.isAfter(horizonEnd)) p,
    ];

    return BudgetForecastSummary(
      endOfMonthBalance: endOfMonthBalance ?? current,
      endOfPeriodBalance: endOfPeriodBalance ?? clipped.last.balance,
      // Never fall back to horizon/sim end — that mislabeled "year" as period.
      endOfYearBalance: endOfYearBalance ?? endOfMonthBalance ?? current,
      monthlyNet: monthlyNet,
      dailyNet: monthlyNet / daysInMonth,
      recurringNetPerPeriod: recurringNetPerPeriod,
      series: _downsample(clipped, maxPoints: 180),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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

  static double _nonRecurringDailyNet({
    required List<MoneyTransaction> transactions,
    required List<BudgetCategory> budgets,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    required DateTime asOf,
  }) {
    final monthKey = MoneyMath.monthKey(asOf);
    final nonRecurring = transactions.where((t) => !t.isRecurring).toList();
    final income = MoneyMath.incomeInMonthMain(
      transactions: nonRecurring,
      monthKeyValue: monthKey,
      mainCurrency: mainCurrency,
      rates: rates,
    );
    final expense = MoneyMath.expenseInMonthMain(
      transactions: nonRecurring,
      monthKeyValue: monthKey,
      mainCurrency: mainCurrency,
      rates: rates,
    );
    final dayOfMonth = asOf.day.clamp(1, 31);
    final daysInMonth = DateTime(asOf.year, asOf.month + 1, 0).day;
    final allocated = MoneyMath.totalBudgetAllocated(
      budgets: budgets,
      monthKeyValue: monthKey,
    );

    double monthlyIncome;
    double monthlyExpense;
    if (income > 0 || expense > 0) {
      monthlyIncome = income / dayOfMonth * daysInMonth;
      monthlyExpense = expense / dayOfMonth * daysInMonth;
      if (allocated > 0 && dayOfMonth <= 7) {
        monthlyExpense = (monthlyExpense + allocated) / 2;
      }
    } else if (allocated > 0) {
      monthlyIncome = 0;
      monthlyExpense = allocated;
    } else {
      monthlyIncome = 0;
      monthlyExpense = 0;
    }
    return (monthlyIncome - monthlyExpense) / daysInMonth;
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
