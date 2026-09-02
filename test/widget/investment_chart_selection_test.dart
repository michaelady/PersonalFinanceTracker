import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/data/services/quote_client.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/portfolio_math.dart';
import 'package:zentho/features/investments/investments_screen.dart';
import 'package:zentho/widgets/money_text.dart';

class _NoNetworkQuoteClient implements QuoteClient {
  @override
  Future<QuoteBundle> fetchChart(
    String symbol, {
    QuoteHistoryRange range = QuoteHistoryRange.oneMonth,
  }) {
    throw StateError('network should not be used in this test');
  }

  @override
  Future<List<TickerSearchResult>> search(String query) async => const [];
}

class MemoryStoreRepo extends FinanceRepository {
  MemoryStoreRepo()
      : super(
          refreshRatesOnInit: false,
          quoteClient: _NoNetworkQuoteClient(),
        );

  late HouseholdProfile you;
  late InvestmentHolding apple;
  late InvestmentHolding microsoft;

  Future<void> seedHoldings({bool withHistory = true}) async {
    you = HouseholdProfile.create('You');
    profiles = [you];
    settings = AppSettings(
      mainCurrency: 'USD',
      activeProfileId: you.id,
      onboardingComplete: true,
    );
    rates = const [CurrencyRate(code: 'USD', rateToMain: 1)];
    apple = InvestmentHolding.create(
      ticker: 'AAPL',
      displayName: 'Apple',
      shares: 2,
      averageCostPerShare: 100,
      currencyCode: 'USD',
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
    );
    microsoft = InvestmentHolding.create(
      ticker: 'MSFT',
      displayName: 'Microsoft',
      shares: 1,
      averageCostPerShare: 50,
      currencyCode: 'USD',
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
    );
    holdings = [apple, microsoft];
    final now = DateTime.now().toUtc();
    quotes = {
      'AAPL': CachedQuote(
        symbol: 'AAPL',
        price: 120,
        currency: 'USD',
        fetchedAt: now,
        source: 'test',
        history: withHistory
            ? {
                '1mo': [
                  PricePoint(date: DateTime.utc(2026, 8, 1), close: 100),
                  PricePoint(date: DateTime.utc(2026, 8, 2), close: 110),
                  PricePoint(date: DateTime.utc(2026, 8, 3), close: 120),
                ],
              }
            : const {},
        historyFetchedAt: {'1mo': now},
      ),
      'MSFT': CachedQuote(
        symbol: 'MSFT',
        price: 80,
        currency: 'USD',
        fetchedAt: now,
        source: 'test',
        history: withHistory
            ? {
                '1mo': [
                  PricePoint(date: DateTime.utc(2026, 8, 1), close: 50),
                  PricePoint(date: DateTime.utc(2026, 8, 2), close: 50),
                  PricePoint(date: DateTime.utc(2026, 8, 3), close: 80),
                ],
              }
            : const {},
        historyFetchedAt: {'1mo': now},
      ),
    };
    loading = false;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpInvestments(WidgetTester tester, MemoryStoreRepo repo) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: Scaffold(body: InvestmentsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  double latestChartValue(WidgetTester tester) {
    return tester
        .widget<MoneyText>(find.byKey(const Key('chart-latest')))
        .amount;
  }

  String? dropdownValue(WidgetTester tester) {
    return tester
        .widget<DropdownButton<String?>>(
          find.byKey(const Key('chart-holding-dropdown')),
        )
        .value;
  }

  testWidgets('defaults to the full-portfolio series', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHoldings();
    await pumpInvestments(tester, repo);

    expect(find.text('1M'), findsOneWidget);
    expect(find.text('3M'), findsOneWidget);
    expect(find.text('1Y'), findsOneWidget);
    expect(find.text('Whole portfolio market value'), findsOneWidget);
    expect(find.byKey(const Key('performance-chart')), findsOneWidget);
    expect(dropdownValue(tester), isNull);
    expect(latestChartValue(tester), closeTo(320, 0.01));
    expect(find.text('Edit holding'), findsNothing);
  });

  testWidgets('tapping a holding plots that position instead of opening edit',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHoldings();
    await pumpInvestments(tester, repo);

    await tester.ensureVisible(find.byKey(ValueKey('holding-${repo.apple.id}')));
    await tester.tap(find.byKey(ValueKey('holding-${repo.apple.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Edit holding'), findsNothing);
    expect(dropdownValue(tester), repo.apple.id);
    expect(find.text('Apple · AAPL'), findsOneWidget);
    expect(latestChartValue(tester), closeTo(240, 0.01));
    expect(find.byKey(const Key('chart-show-portfolio')), findsOneWidget);
  });

  testWidgets('tapping the same holding again returns to the portfolio chart',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHoldings();
    await pumpInvestments(tester, repo);

    final appleTile = find.byKey(ValueKey('holding-${repo.apple.id}'));
    await tester.ensureVisible(appleTile);
    await tester.tap(appleTile);
    await tester.pumpAndSettle();
    expect(latestChartValue(tester), closeTo(240, 0.01));

    await tester.ensureVisible(appleTile);
    await tester.tap(appleTile);
    await tester.pumpAndSettle();

    expect(dropdownValue(tester), isNull);
    expect(find.text('Whole portfolio market value'), findsOneWidget);
    expect(latestChartValue(tester), closeTo(320, 0.01));
  });

  testWidgets('Portfolio control restores the full-book series', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHoldings();
    await pumpInvestments(tester, repo);

    await tester.ensureVisible(find.byKey(ValueKey('holding-${repo.apple.id}')));
    await tester.tap(find.byKey(ValueKey('holding-${repo.apple.id}')));
    await tester.pumpAndSettle();
    expect(latestChartValue(tester), closeTo(240, 0.01));

    await tester.tap(find.byKey(const Key('chart-show-portfolio')));
    await tester.pumpAndSettle();

    expect(dropdownValue(tester), isNull);
    expect(latestChartValue(tester), closeTo(320, 0.01));
  });

  testWidgets('allocation row can select the same holding series',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHoldings();
    await pumpInvestments(tester, repo);

    await tester.ensureVisible(
      find.byKey(ValueKey('allocation-${repo.microsoft.id}')),
    );
    await tester.tap(find.byKey(ValueKey('allocation-${repo.microsoft.id}')));
    await tester.pumpAndSettle();

    expect(dropdownValue(tester), repo.microsoft.id);
    expect(latestChartValue(tester), closeTo(80, 0.01));
  });

  testWidgets('edit icon still opens the holding editor', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHoldings();
    await pumpInvestments(tester, repo);

    await tester.ensureVisible(
      find.byKey(ValueKey('edit-holding-${repo.apple.id}')),
    );
    await tester.tap(find.byKey(ValueKey('edit-holding-${repo.apple.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Edit holding'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(dropdownValue(tester), isNull);
    expect(latestChartValue(tester), closeTo(320, 0.01));
  });

  testWidgets('long-press still opens the holding editor', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHoldings();
    await pumpInvestments(tester, repo);

    await tester.ensureVisible(find.byKey(ValueKey('holding-${repo.apple.id}')));
    await tester.longPress(find.byKey(ValueKey('holding-${repo.apple.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Edit holding'), findsOneWidget);
    expect(dropdownValue(tester), isNull);
  });

  testWidgets('empty history shows an empty state instead of a chart',
      (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedHoldings(withHistory: false);
    await pumpInvestments(tester, repo);

    expect(find.byKey(const Key('performance-empty')), findsOneWidget);
    expect(find.byKey(const Key('performance-chart')), findsNothing);
    expect(
      find.text('No history yet for this range. Pull to refresh when online.'),
      findsOneWidget,
    );
  });
}
