import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/features/shell/app_shell.dart';

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

  Future<void> openNewTransaction(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add manually'));
    await tester.pumpAndSettle();
    expect(find.text('New transaction'), findsOneWidget);
  }

  Future<void> pumpApp(WidgetTester tester, MemoryStoreRepo repo) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('invalid amount abc shows error and does not persist',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();
    await pumpApp(tester, repo);
    await openNewTransaction(tester);

    await tester.enterText(find.byKey(const Key('transaction-amount')), 'abc');
    await tester.ensureVisible(find.byKey(const Key('transaction-save')));
    await tester.tap(find.byKey(const Key('transaction-save')));
    await tester.pump();

    expect(find.text('Enter an amount greater than 0'), findsOneWidget);
    expect(find.text('New transaction'), findsOneWidget);
    expect(repo.transactions, isEmpty);
  });

  testWidgets('empty amount shows error and does not persist', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();
    await pumpApp(tester, repo);
    await openNewTransaction(tester);

    await tester.ensureVisible(find.byKey(const Key('transaction-save')));
    await tester.tap(find.byKey(const Key('transaction-save')));
    await tester.pump();

    expect(find.text('Enter an amount greater than 0'), findsOneWidget);
    expect(find.text('New transaction'), findsOneWidget);
    expect(repo.transactions, isEmpty);
  });

  testWidgets('zero amount shows error and does not persist', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();
    await pumpApp(tester, repo);
    await openNewTransaction(tester);

    await tester.enterText(find.byKey(const Key('transaction-amount')), '0');
    await tester.ensureVisible(find.byKey(const Key('transaction-save')));
    await tester.tap(find.byKey(const Key('transaction-save')));
    await tester.pump();

    expect(find.text('Enter an amount greater than 0'), findsOneWidget);
    expect(find.text('New transaction'), findsOneWidget);
    expect(repo.transactions, isEmpty);
  });
}
