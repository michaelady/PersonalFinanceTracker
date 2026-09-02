import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/csv_data_exchange.dart';
import 'package:zentho/domain/services/recurrence_period.dart';

void main() {
  group('CsvDataExchange', () {
    test('round-trips a full snapshot and keeps debug sheets export-only', () {
      final you = HouseholdProfile.create('You', colorHex: 0xFF0B6E6E);
      final account = Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'CHF',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
        openingBalance: 1000,
      );
      final groceries = SpendCategory.create(
        name: 'Groceries',
        iconName: 'cart',
        colorHex: 0xFF6FAE8F,
        isIncome: false,
        isSystem: true,
      );
      final salary = SpendCategory.create(
        name: 'Salary',
        iconName: 'payments',
        colorHex: 0xFF6FAE8F,
        isIncome: true,
        isSystem: true,
      );
      final expense = MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 42.5,
        currencyCode: 'EUR',
        accountId: account.id,
        categoryId: groceries.id,
        date: DateTime.utc(2026, 8, 1),
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
        note: 'Market',
        isRecurring: true,
        recurringLabel: 'Weekly shop',
        recurrencePeriod: RecurrencePeriod.weekly,
      );
      final income = MoneyTransaction.create(
        type: TransactionType.income,
        amount: 5000,
        currencyCode: 'CHF',
        accountId: account.id,
        categoryId: salary.id,
        date: DateTime.utc(2026, 8, 2),
        ownerProfileId: you.id,
        visibility: VisibilityScope.private,
        note: 'Pay',
      );
      final budget = BudgetCategory.create(
        categoryId: groceries.id,
        monthKey: '2026-08',
        allocated: 400,
        visibility: VisibilityScope.shared,
        ownerProfileId: you.id,
      );
      final goal = SavingsGoal.create(
        name: 'Emergency fund',
        targetAmount: 5000,
        currentAmount: 1200,
        currencyCode: 'EUR',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
      );
      final holding = InvestmentHolding.create(
        ticker: 'VWCE.DE',
        displayName: 'Vanguard FTSE All-World',
        shares: 12.5,
        averageCostPerShare: 110.2,
        currencyCode: 'EUR',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
        notes: 'ISA',
      );
      final shareTx = ShareTransaction.create(
        holdingId: holding.id,
        type: ShareTransactionType.buy,
        date: DateTime.utc(2026, 7, 1),
        shares: 12.5,
        pricePerShare: 110.2,
        notes: 'Opening position',
      );
      final snapshot = FinanceSnapshot(
        settings: AppSettings(
          mainCurrency: 'CHF',
          activeProfileId: you.id,
          onboardingComplete: true,
          showPrivate: true,
          showShared: false,
        ),
        profiles: [you],
        accounts: [account],
        categories: [groceries, salary],
        transactions: [expense, income],
        budgets: [budget],
        goals: [goal],
        holdings: [holding],
        shareTransactions: [shareTx],
        rates: const [
          CurrencyRate(code: 'CHF', rateToMain: 1),
          CurrencyRate(code: 'EUR', rateToMain: 0.93),
        ],
      );

      final exported = CsvDataExchange.exportSnapshot(
        snapshot,
        exportedAt: DateTime.utc(2026, 8, 2, 12),
      );

      expect(exported.csvBody, contains('# zentho_export_v1'));
      expect(exported.csvBody, contains('[ledger]'));
      expect(exported.csvBody, contains('[account_balances]'));
      expect(exported.csvBody, contains('amountInMain'));
      expect(CsvDataExchange.looksLikeFullExport(exported.csvBody), isTrue);

      final imported = CsvDataExchange.importSnapshot(exported.csvBody);
      expect(imported.snapshot.settings.mainCurrency, 'CHF');
      expect(imported.snapshot.settings.showShared, isFalse);
      expect(imported.snapshot.profiles, hasLength(1));
      expect(imported.snapshot.accounts.single.name, 'Checking');
      expect(imported.snapshot.categories, hasLength(2));
      expect(imported.snapshot.transactions, hasLength(2));
      expect(imported.snapshot.budgets.single.allocated, 400);
      expect(imported.snapshot.goals.single.currencyCode, 'EUR');
      expect(imported.snapshot.holdings.single.ticker, 'VWCE.DE');
      expect(imported.snapshot.holdings.single.shares, 12.5);
      expect(imported.snapshot.shareTransactions.single.type, ShareTransactionType.buy);
      expect(imported.snapshot.shareTransactions.single.shares, 12.5);
      expect(imported.snapshot.rates.where((r) => r.code == 'EUR').single.rateToMain, 0.93);

      final restoredExpense = imported.snapshot.transactions
          .firstWhere((t) => t.id == expense.id);
      expect(restoredExpense.amount, 42.5);
      expect(restoredExpense.currencyCode, 'EUR');
      expect(restoredExpense.isRecurring, isTrue);
      expect(restoredExpense.recurrencePeriod, RecurrencePeriod.weekly);
      expect(restoredExpense.note, 'Market');
    });

    test('rejects exports missing required sections', () {
      expect(
        () => CsvDataExchange.importSnapshot('[profiles]\nid,name\np1,You\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('does not treat bank transaction CSV as a full export', () {
      const bank = '''
date,amount,type,category,account,note,currency,visibility
2026-08-01,42.5,expense,Groceries,Checking,Market,USD,shared
''';
      expect(CsvDataExchange.looksLikeFullExport(bank), isFalse);
    });
  });
}
