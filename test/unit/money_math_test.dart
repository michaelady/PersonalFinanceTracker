import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/models/models.dart';
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
  });
}
