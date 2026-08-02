import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/app.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/features/shell/app_shell.dart';
import 'package:zentho/widgets/responsive.dart';

class MemoryStoreRepo extends FinanceRepository {
  MemoryStoreRepo() : super();

  Future<void> seedReady() async {
    final you = HouseholdProfile.create('You');
    profiles = [you];
    settings = AppSettings(
      mainCurrency: 'USD',
      activeProfileId: you.id,
      onboardingComplete: true,
    );
    rates = [const CurrencyRate(code: 'USD', rateToMain: 1)];
    categories = [
      SpendCategory.create(
        name: 'Groceries',
        iconName: 'cart',
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
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
        openingBalance: 1000,
      ),
    ];
    transactions = [];
    budgets = [];
    goals = [];
    loading = false;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('phone layout shows bottom navigation', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Available to spend'), findsOneWidget);
  });

  testWidgets('desktop layout uses navigation rail', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(Responsive.of(tester.element(find.byType(AppShell))),
        AppBreakpoint.desktop);
  });

  testWidgets('onboarding appears when incomplete', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FinanceRepository(refreshRatesOnInit: false);
    await repo.init();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: repo,
        child: const ZenthoApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('household ledger'), findsOneWidget);
    expect(find.text('Enter Zentho'), findsOneWidget);
  });
}
