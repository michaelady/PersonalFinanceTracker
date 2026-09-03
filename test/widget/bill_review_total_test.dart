import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/bill_parser.dart';
import 'package:zentho/features/bills/bill_scan_flow.dart';

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
        name: 'Groceries',
        iconName: 'cart',
        colorHex: 1,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Dining',
        iconName: 'restaurant',
        colorHex: 1,
        isIncome: false,
        isSystem: true,
      ),
      SpendCategory.create(
        name: 'Fun',
        iconName: 'celebration',
        colorHex: 1,
        isIncome: false,
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

const _coopReceipt = '''
Coop Pronto
Date: 2026-09-03
Olive oil        CHF 12.90
Tomatoes         CHF 8.50
Cheese           CHF 4.20
Juice            CHF 6.40
Yogurt           CHF 3.00
Bread            CHF 2.50
Milk             CHF 4.80
Bananas          CHF 1.80
Apples           CHF 1.50
Carrots          CHF 1.25
TOTAL            CHF 47.85
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Review bill warns when checked lines do not match printed TOTAL',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedReady();
    final parsed = BillParser.parse(_coopReceipt, fallbackCurrency: 'CHF');
    expect(parsed.printedTotalMismatches, isTrue);

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: MaterialApp(home: BillReviewScreen(initial: parsed)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review bill'), findsOneWidget);
    expect(find.text('Add 10 expense(s)'), findsOneWidget);
    expect(find.byKey(const Key('bill-total-mismatch')), findsOneWidget);
    expect(find.textContaining('47.85'), findsWidgets);
    expect(find.textContaining('46.85'), findsWidgets);
    expect(find.textContaining('1.00'), findsWidgets);
    expect(find.textContaining('short'), findsWidgets);
    expect(find.text('Line items do not match the printed TOTAL'), findsOneWidget);
  });
}
