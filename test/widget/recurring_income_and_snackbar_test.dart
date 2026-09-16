import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/budget_forecast.dart';
import 'package:zentho/domain/services/recurrence_period.dart';
import 'package:zentho/features/shell/app_shell.dart';
import 'package:zentho/widgets/zentho_snackbar.dart';

class MemoryStoreRepo extends FinanceRepository {
  MemoryStoreRepo() : super(refreshRatesOnInit: false);

  Future<void> seedReady() async {
    final you = HouseholdProfile.create('You');
    profiles = [you];
    settings = AppSettings(
      mainCurrency: 'CHF',
      activeProfileId: you.id,
      onboardingComplete: true,
    );
    rates = [const CurrencyRate(code: 'CHF', rateToMain: 1)];
    categories = [
      SpendCategory.create(
        name: 'Housing',
        iconName: 'home',
        colorHex: 1,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Salary',
        iconName: 'pay',
        colorHex: 1,
        isIncome: true,
        isSystem: true,
      ),
    ];
    accounts = [
      Account.create(
        name: 'UBS (CHF)',
        type: AccountType.checking,
        currencyCode: 'CHF',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
        openingBalance: 1000,
      ),
    ];
    transactions = [];
    loading = false;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpApp(WidgetTester tester, MemoryStoreRepo repo) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openNewTransaction(WidgetTester tester) async {
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add manually'));
    await tester.pumpAndSettle();
    expect(find.text('New transaction'), findsOneWidget);
  }

  testWidgets('Undo snackbar auto-dismisses after 30 seconds', (tester) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              messenger = ScaffoldMessenger.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    messenger.showSnackBar(
      undoSnackBar(message: 'Transaction saved', onUndo: () {}),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Transaction saved'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // Well past the default 4 s: still there, as requested (30 s window).
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Transaction saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Transaction saved'), findsNothing);
  });

  testWidgets('plain SnackBar with an action would persist (why we override)',
      (tester) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              messenger = ScaffoldMessenger.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    messenger.showSnackBar(
      SnackBar(
        content: const Text('sticky'),
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('sticky'), findsOneWidget);
    messenger.clearSnackBars();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'income marked recurring in the editor feeds assumed monthly income',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();
    await pumpApp(tester, repo);
    await openNewTransaction(tester);

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(
      find.text('Recurring income (salary, pension, rent received)'),
      findsOneWidget,
    );
    expect(find.text('Recurring bill / subscription'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('transaction-amount')),
      '3048.50',
    );
    await tester.ensureVisible(find.byKey(const Key('transaction-recurring')));
    await tester.tap(find.byKey(const Key('transaction-recurring')));
    await tester.pumpAndSettle();
    expect(find.text('Paid every'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('transaction-save')));
    await tester.tap(find.byKey(const Key('transaction-save')));
    await tester.pumpAndSettle();

    final saved = repo.transactions.single;
    expect(saved.type, TransactionType.income);
    expect(saved.isRecurring, isTrue);
    expect(saved.recurrencePeriod, RecurrencePeriod.monthly);

    final summary = BudgetForecast.project(
      accounts: repo.visibleAccounts,
      transactions: repo.visibleTransactions,
      budgets: const [],
      mainCurrency: 'CHF',
      rates: repo.rates,
      horizon: ForecastHorizon.y1,
    );
    expect(summary.recurringIncomeMonthly, closeTo(3048.50, 0.01));
    expect(summary.monthlyNet, closeTo(3048.50, 0.01));

    // Snackbar offers Undo and then leaves on its own.
    expect(find.text('Transaction saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('Transaction saved'), findsNothing);
  });

  testWidgets('Budgets explains zero assumed income when income is unmarked',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();
    final salary = repo.categories.firstWhere((c) => c.isIncome);
    final housing = repo.categories.firstWhere((c) => !c.isIncome);
    final now = DateTime.now();
    repo.transactions = [
      MoneyTransaction.create(
        type: TransactionType.income,
        amount: 3000,
        currencyCode: 'CHF',
        accountId: repo.accounts.first.id,
        categoryId: salary.id,
        date: DateTime(now.year, now.month, 1),
        ownerProfileId: repo.settings.activeProfileId,
        visibility: VisibilityScope.shared,
      ),
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 3000,
        currencyCode: 'CHF',
        accountId: repo.accounts.first.id,
        categoryId: housing.id,
        date: DateTime(now.year, now.month, 1),
        ownerProfileId: repo.settings.activeProfileId,
        visibility: VisibilityScope.shared,
      ),
    ];
    await pumpApp(tester, repo);
    await tester.tap(find.text('Budgets'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('budgets-income-hint')), findsOneWidget);

    // Mark the salary recurring: the hint goes away and income is assumed.
    repo.transactions = [
      repo.transactions.first.copyWith(
        isRecurring: true,
        recurringLabel: 'Salary',
        recurrencePeriod: RecurrencePeriod.monthly,
      ),
      repo.transactions.last,
    ];
    repo.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('budgets-income-hint')), findsNothing);
  });
}
