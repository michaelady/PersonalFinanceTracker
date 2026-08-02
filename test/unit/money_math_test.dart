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
