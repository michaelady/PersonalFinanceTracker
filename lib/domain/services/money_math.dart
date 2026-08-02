import '../models/models.dart';

/// Pure finance calculations — unit-tested, no Flutter dependencies.
abstract final class MoneyMath {
  static String monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  static double rateFor(
    String currencyCode,
    String mainCurrency,
    List<CurrencyRate> rates, {
    double? overrideRate,
  }) {
    if (currencyCode == mainCurrency) return 1;
    if (overrideRate != null) return overrideRate;
    final match = rates.where((r) => r.code == currencyCode);
    if (match.isEmpty) {
      throw StateError('Missing exchange rate for $currencyCode');
    }
    return match.first.rateToMain;
  }

  static double toMain({
    required double amount,
    required String currencyCode,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    double? overrideRate,
  }) {
    return amount *
        rateFor(currencyCode, mainCurrency, rates, overrideRate: overrideRate);
  }

  static bool isVisible({
    required VisibilityScope visibility,
    required String ownerProfileId,
    required String activeProfileId,
    required bool showShared,
    required bool showPrivate,
  }) {
    if (visibility == VisibilityScope.shared) return showShared;
    return showPrivate && ownerProfileId == activeProfileId;
  }

  static Iterable<T> filterVisible<T>({
    required Iterable<T> items,
    required VisibilityScope Function(T) visibilityOf,
    required String Function(T) ownerOf,
    required String activeProfileId,
    required bool showShared,
    required bool showPrivate,
  }) {
    return items.where(
      (item) => isVisible(
        visibility: visibilityOf(item),
        ownerProfileId: ownerOf(item),
        activeProfileId: activeProfileId,
        showShared: showShared,
        showPrivate: showPrivate,
      ),
    );
  }

  /// Opening balance + incomes − expenses ± transfers, in the account's currency.
  ///
  /// Foreign-currency transactions are converted via [mainCurrency] as a bridge.
  /// Optional [asOf] excludes transactions dated after that day (inclusive cut-off
  /// uses calendar date only).
  static double balanceNativeForAccount({
    required Account account,
    required List<MoneyTransaction> transactions,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    DateTime? asOf,
  }) {
    var balanceNative = account.openingBalance;
    final asOfDay = asOf == null
        ? null
        : DateTime(asOf.year, asOf.month, asOf.day);

    for (final tx in transactions) {
      if (asOfDay != null) {
        final txDay = DateTime(tx.date.year, tx.date.month, tx.date.day);
        if (txDay.isAfter(asOfDay)) continue;
      }

      final touchesAccount =
          tx.accountId == account.id || tx.transferAccountId == account.id;
      if (!touchesAccount) continue;

      final amountInAccountCurrency = tx.currencyCode == account.currencyCode
          ? tx.amount
          : toMain(
                amount: tx.amount,
                currencyCode: tx.currencyCode,
                mainCurrency: mainCurrency,
                rates: rates,
                overrideRate: tx.exchangeRateToMain,
              ) /
              rateFor(account.currencyCode, mainCurrency, rates);

      switch (tx.type) {
        case TransactionType.income:
          if (tx.accountId == account.id) {
            balanceNative += amountInAccountCurrency;
          }
        case TransactionType.expense:
          if (tx.accountId == account.id) {
            balanceNative -= amountInAccountCurrency;
          }
        case TransactionType.transfer:
          if (tx.accountId == account.id) {
            balanceNative -= amountInAccountCurrency;
          }
          if (tx.transferAccountId == account.id) {
            balanceNative += amountInAccountCurrency;
          }
      }
    }

    return balanceNative;
  }

  /// Opening balance + incomes − expenses ± transfers, converted to main currency.
  static double balanceForAccount({
    required Account account,
    required List<MoneyTransaction> transactions,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    DateTime? asOf,
  }) {
    final native = balanceNativeForAccount(
      account: account,
      transactions: transactions,
      mainCurrency: mainCurrency,
      rates: rates,
      asOf: asOf,
    );
    return toMain(
      amount: native,
      currencyCode: account.currencyCode,
      mainCurrency: mainCurrency,
      rates: rates,
    );
  }

  static double netWorthMain({
    required List<Account> accounts,
    required List<MoneyTransaction> transactions,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    DateTime? asOf,
  }) {
    return accounts
        .where((a) => !a.archived && a.includeInNetWorth)
        .fold<double>(
          0,
          (sum, account) =>
              sum +
              balanceForAccount(
                account: account,
                transactions: transactions,
                mainCurrency: mainCurrency,
                rates: rates,
                asOf: asOf,
              ),
        );
  }

  static double spentInCategoryMain({
    required String categoryId,
    required String monthKeyValue,
    required List<MoneyTransaction> transactions,
    required String mainCurrency,
    required List<CurrencyRate> rates,
  }) {
    return transactions
        .where(
          (tx) =>
              tx.type == TransactionType.expense &&
              tx.categoryId == categoryId &&
              monthKey(tx.date) == monthKeyValue,
        )
        .fold<double>(
          0,
          (sum, tx) =>
              sum +
              toMain(
                amount: tx.amount,
                currencyCode: tx.currencyCode,
                mainCurrency: mainCurrency,
                rates: rates,
                overrideRate: tx.exchangeRateToMain,
              ),
        );
  }

  static double totalBudgetAllocated({
    required List<BudgetCategory> budgets,
    required String monthKeyValue,
  }) {
    return budgets
        .where((b) => b.monthKey == monthKeyValue)
        .fold<double>(0, (sum, b) => sum + b.allocated);
  }

  static double incomeInMonthMain({
    required List<MoneyTransaction> transactions,
    required String monthKeyValue,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    bool includeExpectedRecurring = false,
  }) {
    final booked = transactions
        .where(
          (tx) =>
              tx.type == TransactionType.income &&
              monthKey(tx.date) == monthKeyValue,
        )
        .fold<double>(
          0,
          (sum, tx) =>
              sum +
              toMain(
                amount: tx.amount,
                currencyCode: tx.currencyCode,
                mainCurrency: mainCurrency,
                rates: rates,
                overrideRate: tx.exchangeRateToMain,
              ),
        );
    if (!includeExpectedRecurring) return booked;
    return booked +
        _expectedRecurringNotYetBooked(
          transactions: transactions,
          type: TransactionType.income,
          monthKeyValue: monthKeyValue,
          mainCurrency: mainCurrency,
          rates: rates,
        );
  }

  static double expenseInMonthMain({
    required List<MoneyTransaction> transactions,
    required String monthKeyValue,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    bool includeExpectedRecurring = false,
  }) {
    final booked = transactions
        .where(
          (tx) =>
              tx.type == TransactionType.expense &&
              monthKey(tx.date) == monthKeyValue,
        )
        .fold<double>(
          0,
          (sum, tx) =>
              sum +
              toMain(
                amount: tx.amount,
                currencyCode: tx.currencyCode,
                mainCurrency: mainCurrency,
                rates: rates,
                overrideRate: tx.exchangeRateToMain,
              ),
        );
    if (!includeExpectedRecurring) return booked;
    return booked +
        _expectedRecurringNotYetBooked(
          transactions: transactions,
          type: TransactionType.expense,
          monthKeyValue: monthKeyValue,
          mainCurrency: mainCurrency,
          rates: rates,
        );
  }

  /// Recurring series key so July salary and its August occurrence match.
  static String recurringSeriesKey(MoneyTransaction tx) {
    final label = tx.recurringLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return '${tx.type.name}|label|$label';
    }
    return [
      tx.type.name,
      tx.categoryId ?? '',
      tx.amount.toString(),
      tx.currencyCode,
      tx.recurrencePeriod.name,
    ].join('|');
  }

  /// Monthly-equivalent amount for recurring items of [type] that have no
  /// booking in [monthKeyValue] yet (e.g. salary last booked in July).
  static double _expectedRecurringNotYetBooked({
    required List<MoneyTransaction> transactions,
    required TransactionType type,
    required String monthKeyValue,
    required String mainCurrency,
    required List<CurrencyRate> rates,
  }) {
    final recurring = transactions
        .where((tx) => tx.isRecurring && tx.type == type)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final bookedKeys = <String>{
      for (final tx in transactions)
        if (tx.type == type && monthKey(tx.date) == monthKeyValue)
          recurringSeriesKey(tx),
    };

    final seen = <String>{};
    var extra = 0.0;
    for (final tx in recurring) {
      final key = recurringSeriesKey(tx);
      if (!seen.add(key)) continue; // latest template only
      if (bookedKeys.contains(key)) continue;
      final main = toMain(
        amount: tx.amount,
        currencyCode: tx.currencyCode,
        mainCurrency: mainCurrency,
        rates: rates,
        overrideRate: tx.exchangeRateToMain,
      );
      extra += tx.recurrencePeriod.toMonthly(main);
    }
    return extra;
  }

  /// Hybrid available-to-spend for the month.
  ///
  /// Intended envelope view:
  ///   remaining budgets + unallocated income − unbudgeted spending
  /// which simplifies to income − expenses (overspend is counted once).
  ///
  /// Income/expenses include expected recurring items for the month when the
  /// last booking is in another month (e.g. July salary still counts in August).
  ///
  /// Earlier builds also subtracted a global "overspend vs allocated" term,
  /// which double-counted category overspend and understated available cash.
  static double availableToSpend({
    required List<MoneyTransaction> transactions,
    required List<BudgetCategory> budgets,
    required String monthKeyValue,
    required String mainCurrency,
    required List<CurrencyRate> rates,
  }) {
    final income = incomeInMonthMain(
      transactions: transactions,
      monthKeyValue: monthKeyValue,
      mainCurrency: mainCurrency,
      rates: rates,
      includeExpectedRecurring: true,
    );
    final spent = expenseInMonthMain(
      transactions: transactions,
      monthKeyValue: monthKeyValue,
      mainCurrency: mainCurrency,
      rates: rates,
      includeExpectedRecurring: true,
    );

    // Keep the envelope breakdown explicit so budget overspend / unbudgeted
    // spend stay auditable in tests without changing the result.
    final monthBudgets =
        budgets.where((b) => b.monthKey == monthKeyValue).toList();
    final allocated = monthBudgets.fold<double>(0, (sum, b) => sum + b.allocated);
    final budgetedCategoryIds = monthBudgets.map((b) => b.categoryId).toSet();
    final spentBudgeted = transactions
        .where(
          (tx) =>
              tx.type == TransactionType.expense &&
              monthKey(tx.date) == monthKeyValue &&
              tx.categoryId != null &&
              budgetedCategoryIds.contains(tx.categoryId),
        )
        .fold<double>(
          0,
          (sum, tx) =>
              sum +
              toMain(
                amount: tx.amount,
                currencyCode: tx.currencyCode,
                mainCurrency: mainCurrency,
                rates: rates,
                overrideRate: tx.exchangeRateToMain,
              ),
        );
    // Expected recurring expenses in budgeted categories also consume budget.
    final expectedBudgetedRecurring = _expectedRecurringNotYetBooked(
      transactions: transactions.where((tx) {
        return tx.categoryId != null &&
            budgetedCategoryIds.contains(tx.categoryId);
      }).toList(),
      type: TransactionType.expense,
      monthKeyValue: monthKeyValue,
      mainCurrency: mainCurrency,
      rates: rates,
    );
    final spentBudgetedTotal = spentBudgeted + expectedBudgetedRecurring;
    final remainingBudgets = allocated - spentBudgetedTotal;
    final unallocatedIncome = income - allocated;
    final unbudgetedSpending = spent - spentBudgetedTotal;
    return remainingBudgets + unallocatedIncome - unbudgetedSpending;
  }

  static List<MoneyTransaction> recurringCandidates(
    List<MoneyTransaction> transactions,
  ) {
    return transactions.where((tx) => tx.isRecurring).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }
}
