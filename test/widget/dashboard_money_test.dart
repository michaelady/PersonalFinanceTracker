import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/features/reports/reports_screen.dart';
import 'package:zentho/features/shell/app_shell.dart';
import 'package:zentho/widgets/money_text.dart';

class MemoryStoreRepo extends FinanceRepository {
  MemoryStoreRepo() : super(refreshRatesOnInit: false);

  late SpendCategory groceries;
  late SpendCategory salary;
  late Account checking;
  late HouseholdProfile you;

  Future<void> seedHousehold() async {
    you = HouseholdProfile.create('You');
    profiles = [you, HouseholdProfile.create('Partner')];
    settings = AppSettings(
      mainCurrency: 'USD',
      activeProfileId: you.id,
      onboardingComplete: true,
      showShared: true,
      showPrivate: true,
    );
    rates = const [
      CurrencyRate(code: 'USD', rateToMain: 1),
      CurrencyRate(code: 'EUR', rateToMain: 1.1),
    ];
    groceries = SpendCategory.create(
      name: 'Groceries',
      iconName: 'cart',
      colorHex: 1,
      isIncome: false,
      isSystem: true,
    );
    salary = SpendCategory.create(
      name: 'Salary',
      iconName: 'pay',
      colorHex: 1,
      isIncome: true,
      isSystem: true,
    );
    categories = [groceries, salary];
    checking = Account.create(
      name: 'Checking',
      type: AccountType.checking,
      currencyCode: 'USD',
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
      openingBalance: 1000,
    );
    accounts = [checking];
    final now = DateTime.now();
    transactions = [
      MoneyTransaction.create(
        type: TransactionType.income,
        amount: 3000,
        currencyCode: 'USD',
        accountId: checking.id,
        categoryId: salary.id,
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
        date: DateTime(now.year, now.month, 1),
      ),
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 100,
        currencyCode: 'USD',
        accountId: checking.id,
        categoryId: groceries.id,
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
        date: DateTime(now.year, now.month, 4),
        note: 'Market',
      ),
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 50,
        currencyCode: 'EUR',
        accountId: checking.id,
        categoryId: groceries.id,
        ownerProfileId: you.id,
        visibility: VisibilityScope.private,
        date: DateTime(now.year, now.month, 5),
        note: 'Private shop',
      ),
    ];
    budgets = [
      BudgetCategory.create(
        categoryId: groceries.id,
        monthKey:
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}',
        allocated: 400,
        visibility: VisibilityScope.shared,
        ownerProfileId: you.id,
      ),
    ];
    goals = [
      SavingsGoal.create(
        name: 'Emergency fund',
        targetAmount: 1000,
        currentAmount: 250,
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

  testWidgets('dashboard available-to-spend matches income minus expenses',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHousehold();

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    // First frame — must not be a 0→target tween leftover (live flicker).
    await tester.pump();

    expect(find.text('Available to spend'), findsOneWidget);
    // 3000 − 100 − 50 EUR×1.1 = 2845
    expect(repo.availableToSpend(), closeTo(2845, 0.01));

    final hero = tester.widget<MoneyText>(find.byType(MoneyText).first);
    expect(hero.amount, closeTo(repo.availableToSpend(), 0.01));
    expect(hero.amount, isNot(closeTo(0, 1)));
  });

  testWidgets('Home ATS matches Reports cash flow immediately after save',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHousehold();

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();

    await repo.addTransaction(
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 200,
        currencyCode: 'USD',
        accountId: repo.checking.id,
        categoryId: repo.groceries.id,
        ownerProfileId: repo.you.id,
        visibility: VisibilityScope.shared,
        date: DateTime.now(),
        note: 'Housing stand-in',
      ),
    );
    await tester.pump();

    final homeAts = tester.widget<MoneyText>(find.byType(MoneyText).first);
    expect(homeAts.amount, closeTo(repo.availableToSpend(), 0.01));

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pump();

    final cashFlow = tester
        .widgetList<MoneyText>(find.byType(MoneyText))
        .firstWhere((w) => w.emphasize);
    expect(cashFlow.amount, closeTo(homeAts.amount, 0.01));
    expect(cashFlow.amount, closeTo(repo.availableToSpend(), 0.01));
  });

  testWidgets('hiding private spend raises available to spend', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHousehold();

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    final withPrivate = repo.availableToSpend();
    await repo.setVisibilityFilters(showPrivate: false);
    await tester.pumpAndSettle();

    final sharedOnly = repo.availableToSpend();
    expect(sharedOnly, closeTo(withPrivate + 55, 0.01));
    expect(sharedOnly, closeTo(2900, 0.01));
  });

  testWidgets('goals screen shows progress toward the target', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHousehold();

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();

    expect(find.text('Emergency fund'), findsOneWidget);
    expect(repo.visibleGoals.single.progress, closeTo(0.25, 0.0001));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('reports cash flow is booked income minus booked spend',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHousehold();

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Spend by category'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    final cashFlow = tester
        .widgetList<MoneyText>(find.byType(MoneyText))
        .firstWhere((w) => w.emphasize);
    expect(cashFlow.amount, closeTo(repo.availableToSpend(), 0.01));
  });

  testWidgets('recent activity shows native currency and main equivalent',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHousehold();
    repo.settings = repo.settings.copyWith(mainCurrency: 'USD');

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();

    final amounts = tester.widgetList<MoneyText>(find.byType(MoneyText)).toList();
    expect(amounts.any((w) => w.currencyCode == 'EUR'), isTrue);
    expect(
      amounts.any(
        (w) =>
            w.currencyCode == 'USD' &&
            w.signed &&
            (w.amount + 55).abs() < 0.01,
      ),
      isTrue,
    );
  });
}
