import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/recurrence_period.dart';
import 'package:zentho/domain/services/money_math.dart';

void main() {
  group('MoneyMath', () {
    final rates = [
      const CurrencyRate(code: 'USD', rateToMain: 1),
      const CurrencyRate(code: 'EUR', rateToMain: 1.1),
    ];

    test('converts foreign amounts into main currency', () {
      final main = MoneyMath.toMain(
        amount: 10,
        currencyCode: 'EUR',
        mainCurrency: 'USD',
        rates: rates,
      );
      expect(main, closeTo(11, 0.0001));
    });

    test('available to spend uses hybrid budget math', () {
      final owner = 'p1';
      final account = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: owner,
        visibility: VisibilityScope.shared,
      );
      final groceries = SpendCategory.create(
        name: 'Groceries',
        iconName: 'shop',
        colorHex: 1,
        isIncome: false,
      );
      final salary = SpendCategory.create(
        name: 'Salary',
        iconName: 'pay',
        colorHex: 1,
        isIncome: true,
      );
      final month = '2026-08';
      final transactions = [
        MoneyTransaction.create(
          type: TransactionType.income,
          amount: 3000,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: salary.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 1),
        ),
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 100,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: groceries.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 4),
        ),
      ];
      final budgets = [
        BudgetCategory.create(
          categoryId: groceries.id,
          monthKey: month,
          allocated: 400,
          visibility: VisibilityScope.shared,
          ownerProfileId: owner,
        ),
      ];

      final available = MoneyMath.availableToSpend(
        transactions: transactions,
        budgets: budgets,
        monthKeyValue: month,
        mainCurrency: 'USD',
        rates: rates,
      );

      // Remaining groceries 300 + unallocated income 2600 = 2900
      expect(available, closeTo(2900, 0.01));
    });

    test('available to spend does not double-count budget overspend', () {
      final owner = 'p1';
      final account = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: owner,
        visibility: VisibilityScope.shared,
      );
      final housing = SpendCategory.create(
        name: 'Housing',
        iconName: 'home',
        colorHex: 1,
        isIncome: false,
      );
      final salary = SpendCategory.create(
        name: 'Salary',
        iconName: 'pay',
        colorHex: 1,
        isIncome: true,
      );
      const month = '2026-08';
      final transactions = [
        MoneyTransaction.create(
          type: TransactionType.income,
          amount: 3000,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: salary.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 1),
        ),
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 500,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: housing.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 3),
        ),
      ];
      final budgets = [
        BudgetCategory.create(
          categoryId: housing.id,
          monthKey: month,
          allocated: 100,
          visibility: VisibilityScope.shared,
          ownerProfileId: owner,
        ),
      ];

      final available = MoneyMath.availableToSpend(
        transactions: transactions,
        budgets: budgets,
        monthKeyValue: month,
        mainCurrency: 'USD',
        rates: rates,
      );

      // income 3000 - spent 500 = 2500 (not 2400 from double-counted overspend)
      expect(available, closeTo(2500, 0.01));
    });

    test('available to spend subtracts unbudgeted expenses once', () {
      final owner = 'p1';
      final account = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: owner,
        visibility: VisibilityScope.shared,
      );
      final groceries = SpendCategory.create(
        name: 'Groceries',
        iconName: 'shop',
        colorHex: 1,
        isIncome: false,
      );
      final fun = SpendCategory.create(
        name: 'Fun',
        iconName: 'fun',
        colorHex: 1,
        isIncome: false,
      );
      final salary = SpendCategory.create(
        name: 'Salary',
        iconName: 'pay',
        colorHex: 1,
        isIncome: true,
      );
      const month = '2026-08';
      final transactions = [
        MoneyTransaction.create(
          type: TransactionType.income,
          amount: 3000,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: salary.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 1),
        ),
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 100,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: groceries.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 4),
        ),
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 200,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: fun.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 5),
        ),
      ];
      final budgets = [
        BudgetCategory.create(
          categoryId: groceries.id,
          monthKey: month,
          allocated: 400,
          visibility: VisibilityScope.shared,
          ownerProfileId: owner,
        ),
      ];

      final available = MoneyMath.availableToSpend(
        transactions: transactions,
        budgets: budgets,
        monthKeyValue: month,
        mainCurrency: 'USD',
        rates: rates,
      );

      // 300 remaining groceries + 2600 unallocated - 200 unbudgeted = 2700
      expect(available, closeTo(2700, 0.01));
    });

    test('mixed-currency account balance bridges via main currency', () {
      final account = Account.create(
        name: 'EU',
        type: AccountType.checking,
        currencyCode: 'EUR',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        openingBalance: 100,
      );
      final chfRates = [
        const CurrencyRate(code: 'CHF', rateToMain: 1),
        const CurrencyRate(code: 'EUR', rateToMain: 0.5),
      ];
      final tx = MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 10,
        currencyCode: 'CHF',
        accountId: account.id,
        categoryId: 'c',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
      );
      // 10 CHF → 10 main → 20 EUR at 0.5 CHF/EUR
      final native = MoneyMath.balanceNativeForAccount(
        account: account,
        transactions: [tx],
        mainCurrency: 'CHF',
        rates: chfRates,
      );
      expect(native, closeTo(80, 0.001));
      final mainBalance = MoneyMath.balanceForAccount(
        account: account,
        transactions: [tx],
        mainCurrency: 'CHF',
        rates: chfRates,
      );
      expect(mainBalance, closeTo(40, 0.001));
    });

    test('private visibility only for active profile', () {
      final visible = MoneyMath.isVisible(
        visibility: VisibilityScope.private,
        ownerProfileId: 'a',
        activeProfileId: 'a',
        showShared: true,
        showPrivate: true,
      );
      final hidden = MoneyMath.isVisible(
        visibility: VisibilityScope.private,
        ownerProfileId: 'a',
        activeProfileId: 'b',
        showShared: true,
        showPrivate: true,
      );
      expect(visible, isTrue);
      expect(hidden, isFalse);
    });

    test('account balance includes opening and expenses', () {
      final account = Account.create(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'USD',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        openingBalance: 100,
      );
      final tx = MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 25,
        currencyCode: 'USD',
        accountId: account.id,
        categoryId: 'c',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
      );
      final balance = MoneyMath.balanceForAccount(
        account: account,
        transactions: [tx],
        mainCurrency: 'USD',
        rates: rates,
      );
      expect(balance, closeTo(75, 0.001));
    });

    test('rounds converted amounts to the main currency minor unit', () {
      expect(MoneyMath.roundToMinorUnits(80.38704875, 'CHF'), 80.39);
      expect(MoneyMath.roundToMinorUnits(80.38704875, 'JPY'), 80);
      expect(MoneyMath.roundToMinorUnits(6.314, 'USD'), 6.31);

      final yenRates = [
        const CurrencyRate(code: 'USD', rateToMain: 1),
        const CurrencyRate(code: 'JPY', rateToMain: 0.006315),
      ];
      final yenToUsd = MoneyMath.toMain(
        amount: 1000,
        currencyCode: 'JPY',
        mainCurrency: 'USD',
        rates: yenRates,
      );
      // 1000 × 0.006315 = 6.315 → $6.32
      expect(yenToUsd, 6.32);

      final usdToYen = MoneyMath.toMain(
        amount: 10.50,
        currencyCode: 'USD',
        mainCurrency: 'JPY',
        rates: [
          const CurrencyRate(code: 'JPY', rateToMain: 1),
          const CurrencyRate(code: 'USD', rateToMain: 158.353127),
        ],
      );
      expect(usdToYen, 1663);
    });

    test('overrideRate wins over the live table for that transaction', () {
      final main = MoneyMath.toMain(
        amount: 10,
        currencyCode: 'EUR',
        mainCurrency: 'USD',
        rates: rates,
        overrideRate: 2.0,
      );
      expect(main, 20);
    });

    test('throws when a foreign rate is missing', () {
      expect(
        () => MoneyMath.toMain(
          amount: 10,
          currencyCode: 'GBP',
          mainCurrency: 'USD',
          rates: rates,
        ),
        throwsStateError,
      );
    });

    test('available to spend includes expected weekly subscription as monthly', () {
      final owner = 'p1';
      final account = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: owner,
        visibility: VisibilityScope.shared,
      );
      final salary = SpendCategory.create(
        name: 'Salary',
        iconName: 'pay',
        colorHex: 1,
        isIncome: true,
      );
      final subs = SpendCategory.create(
        name: 'Subscriptions',
        iconName: 'sub',
        colorHex: 1,
        isIncome: false,
      );
      const month = '2026-08';
      final transactions = [
        MoneyTransaction.create(
          type: TransactionType.income,
          amount: 3000,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: salary.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 1),
        ),
        MoneyTransaction.create(
          type: TransactionType.expense,
          amount: 10,
          currencyCode: 'USD',
          accountId: account.id,
          categoryId: subs.id,
          ownerProfileId: owner,
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 7, 20),
          isRecurring: true,
          recurringLabel: 'Stream',
          recurrencePeriod: RecurrencePeriod.weekly,
        ),
      ];

      final available = MoneyMath.availableToSpend(
        transactions: transactions,
        budgets: const [],
        monthKeyValue: month,
        mainCurrency: 'USD',
        rates: rates,
      );
      final weeklyMonthly = RecurrencePeriod.weekly.toMonthly(10);
      expect(available, closeTo(3000 - weeklyMonthly, 0.01));
    });

    test('shared vs private sums follow visibility filters', () {
      final you = 'you';
      final partner = 'partner';
      final account = Account.create(
        name: 'Joint',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: you,
        visibility: VisibilityScope.shared,
      );
      final cat = SpendCategory.create(
        name: 'Fun',
        iconName: 'fun',
        colorHex: 1,
        isIncome: false,
      );
      final shared = MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 40,
        currencyCode: 'USD',
        accountId: account.id,
        categoryId: cat.id,
        ownerProfileId: you,
        visibility: VisibilityScope.shared,
        date: DateTime(2026, 8, 2),
      );
      final yours = MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 25,
        currencyCode: 'USD',
        accountId: account.id,
        categoryId: cat.id,
        ownerProfileId: you,
        visibility: VisibilityScope.private,
        date: DateTime(2026, 8, 3),
      );
      final theirs = MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 99,
        currencyCode: 'USD',
        accountId: account.id,
        categoryId: cat.id,
        ownerProfileId: partner,
        visibility: VisibilityScope.private,
        date: DateTime(2026, 8, 4),
      );
      final all = [shared, yours, theirs];

      final visibleToYou = MoneyMath.filterVisible(
        items: all,
        visibilityOf: (t) => t.visibility,
        ownerOf: (t) => t.ownerProfileId,
        activeProfileId: you,
        showShared: true,
        showPrivate: true,
      ).toList();
      expect(
        MoneyMath.expenseInMonthMain(
          transactions: visibleToYou,
          monthKeyValue: '2026-08',
          mainCurrency: 'USD',
          rates: rates,
        ),
        closeTo(65, 0.01),
      );

      final sharedOnly = MoneyMath.filterVisible(
        items: all,
        visibilityOf: (t) => t.visibility,
        ownerOf: (t) => t.ownerProfileId,
        activeProfileId: you,
        showShared: true,
        showPrivate: false,
      ).toList();
      expect(
        MoneyMath.expenseInMonthMain(
          transactions: sharedOnly,
          monthKeyValue: '2026-08',
          mainCurrency: 'USD',
          rates: rates,
        ),
        closeTo(40, 0.01),
      );

      final partnerPrivate = MoneyMath.filterVisible(
        items: all,
        visibilityOf: (t) => t.visibility,
        ownerOf: (t) => t.ownerProfileId,
        activeProfileId: partner,
        showShared: false,
        showPrivate: true,
      ).toList();
      expect(
        MoneyMath.expenseInMonthMain(
          transactions: partnerPrivate,
          monthKeyValue: '2026-08',
          mainCurrency: 'USD',
          rates: rates,
        ),
        closeTo(99, 0.01),
      );
    });

    test('transfers conserve net worth and do not change available to spend', () {
      final checking = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        openingBalance: 500,
      );
      final savings = Account.create(
        name: 'Savings',
        type: AccountType.savings,
        currencyCode: 'EUR',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        openingBalance: 0,
      );
      final salary = SpendCategory.create(
        name: 'Salary',
        iconName: 'pay',
        colorHex: 1,
        isIncome: true,
      );
      final income = MoneyTransaction.create(
        type: TransactionType.income,
        amount: 200,
        currencyCode: 'USD',
        accountId: checking.id,
        categoryId: salary.id,
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        date: DateTime(2026, 8, 1),
      );
      final transfer = MoneyTransaction.create(
        type: TransactionType.transfer,
        amount: 50,
        currencyCode: 'USD',
        accountId: checking.id,
        transferAccountId: savings.id,
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        date: DateTime(2026, 8, 2),
      );

      final before = MoneyMath.netWorthMain(
        accounts: [checking, savings],
        transactions: [income],
        mainCurrency: 'USD',
        rates: rates,
      );
      final after = MoneyMath.netWorthMain(
        accounts: [checking, savings],
        transactions: [income, transfer],
        mainCurrency: 'USD',
        rates: rates,
      );
      expect(after, closeTo(before, 0.01));
      expect(after, closeTo(700, 0.01));

      final ats = MoneyMath.availableToSpend(
        transactions: [income, transfer],
        budgets: const [],
        monthKeyValue: '2026-08',
        mainCurrency: 'USD',
        rates: rates,
      );
      expect(ats, closeTo(200, 0.01));
    });

    test('net worth skips archived and opted-out accounts', () {
      final counted = Account.create(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'USD',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        openingBalance: 100,
      );
      final hidden = Account.create(
        name: 'Old',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        openingBalance: 999,
      ).copyWith(archived: true);
      final excluded = Account.create(
        name: 'House',
        type: AccountType.other,
        currencyCode: 'USD',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        openingBalance: 50000,
        includeInNetWorth: false,
      );
      expect(
        MoneyMath.netWorthMain(
          accounts: [counted, hidden, excluded],
          transactions: const [],
          mainCurrency: 'USD',
          rates: rates,
        ),
        closeTo(100, 0.01),
      );
    });

    test('as-of cutoff is inclusive of that calendar day', () {
      final account = Account.create(
        name: 'Cash',
        type: AccountType.cash,
        currencyCode: 'USD',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        openingBalance: 0,
      );
      final txs = [
        MoneyTransaction.create(
          type: TransactionType.income,
          amount: 10,
          currencyCode: 'USD',
          accountId: account.id,
          ownerProfileId: 'p',
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 2, 23, 59),
        ),
        MoneyTransaction.create(
          type: TransactionType.income,
          amount: 5,
          currencyCode: 'USD',
          accountId: account.id,
          ownerProfileId: 'p',
          visibility: VisibilityScope.shared,
          date: DateTime(2026, 8, 3),
        ),
      ];
      expect(
        MoneyMath.balanceForAccount(
          account: account,
          transactions: txs,
          mainCurrency: 'USD',
          rates: rates,
          asOf: DateTime(2026, 8, 2),
        ),
        closeTo(10, 0.01),
      );
    });

    test('budget totals only include the requested month', () {
      final groceries = SpendCategory.create(
        name: 'Groceries',
        iconName: 'shop',
        colorHex: 1,
        isIncome: false,
      );
      final budgets = [
        BudgetCategory.create(
          categoryId: groceries.id,
          monthKey: '2026-08',
          allocated: 400,
          visibility: VisibilityScope.shared,
          ownerProfileId: 'p',
        ),
        BudgetCategory.create(
          categoryId: groceries.id,
          monthKey: '2026-07',
          allocated: 350,
          visibility: VisibilityScope.shared,
          ownerProfileId: 'p',
        ),
      ];
      expect(
        MoneyMath.totalBudgetAllocated(
          budgets: budgets,
          monthKeyValue: '2026-08',
        ),
        400,
      );
    });

    test('latest recurring template is the most recent booking', () {
      final account = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
      );
      final salary = SpendCategory.create(
        name: 'Salary',
        iconName: 'pay',
        colorHex: 1,
        isIncome: true,
      );
      final july = MoneyTransaction.create(
        type: TransactionType.income,
        amount: 2800,
        currencyCode: 'USD',
        accountId: account.id,
        categoryId: salary.id,
        ownerProfileId: 'p',
        visibility: VisibilityScope.shared,
        date: DateTime(2026, 7, 1),
        isRecurring: true,
        recurringLabel: 'Salary',
      );
      final august = july.copyWith(
        date: DateTime(2026, 8, 1),
        amount: 3000,
      );
      final templates = MoneyMath.latestRecurringTemplates([july, august]);
      expect(templates, hasLength(1));
      expect(templates.single.amount, 3000);
    });
  });
}
