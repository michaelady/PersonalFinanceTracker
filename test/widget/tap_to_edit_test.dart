import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/features/shell/app_shell.dart';
import 'package:zentho/features/transactions/transactions_screen.dart';

class MemoryStoreRepo extends FinanceRepository {
  Future<void> seedReady() async {
    final you = HouseholdProfile.create('You');
    profiles = [you];
    settings = AppSettings(
      mainCurrency: 'USD',
      activeProfileId: you.id,
      onboardingComplete: true,
    );
    rates = [const CurrencyRate(code: 'USD', rateToMain: 1)];
    final groceries = SpendCategory.create(
      name: 'Groceries',
      iconName: 'cart',
      colorHex: 1,
      isIncome: false,
      isSystem: true,
    );
    final salary = SpendCategory.create(
      name: 'Salary',
      iconName: 'pay',
      colorHex: 1,
      isIncome: true,
      isSystem: true,
    );
    categories = [groceries, salary];
    final account = Account.create(
      name: 'Checking',
      type: AccountType.checking,
      currencyCode: 'USD',
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
      openingBalance: 1000,
    );
    accounts = [account];
    transactions = [
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 25,
        currencyCode: 'USD',
        accountId: account.id,
        categoryId: groceries.id,
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
        note: 'Apples',
      ),
    ];
    budgets = [
      BudgetCategory.create(
        categoryId: groceries.id,
        monthKey: '2026-08',
        allocated: 200,
        visibility: VisibilityScope.shared,
        ownerProfileId: you.id,
      ),
    ];
    goals = [
      SavingsGoal.create(
        name: 'Emergency fund',
        targetAmount: 1000,
        currentAmount: 100,
        currencyCode: 'USD',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
      ),
    ];
    loading = false;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tapping a transaction opens the edit sheet', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    // Open Activity tab
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionsScreen), findsOneWidget);
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    expect(find.text('Edit transaction'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('edit sheet Delete stays above the Android navigation inset',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.text('Delete')).bottom,
      lessThanOrEqualTo(900 - 48 + 0.5),
    );
  });

  testWidgets('repository updateTransaction persists field changes',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();
    final original = repo.transactions.first;
    await repo.updateTransaction(
      original.copyWith(amount: 99, note: 'Updated'),
    );
    expect(repo.transactions.first.amount, 99);
    expect(repo.transactions.first.note, 'Updated');
    expect(repo.transactions.first.id, original.id);
  });
}
