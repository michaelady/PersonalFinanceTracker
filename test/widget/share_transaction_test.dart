import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/data/services/quote_client.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/portfolio_math.dart';
import 'package:zentho/features/investments/investments_screen.dart';

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

  Future<void> seedEmptyPortfolio() async {
    you = HouseholdProfile.create('You');
    profiles = [you];
    settings = AppSettings(
      mainCurrency: 'USD',
      activeProfileId: you.id,
      onboardingComplete: true,
    );
    rates = const [CurrencyRate(code: 'USD', rateToMain: 1)];
    holdings = [];
    shareTransactions = [];
    quotes = {
      'AAPL': CachedQuote(
        symbol: 'AAPL',
        price: 150,
        currency: 'USD',
        fetchedAt: DateTime.utc(2026, 9, 1),
        source: 'test',
      ),
    };
    loading = false;
    notifyListeners();
  }

  @override
  Future<void> refreshQuotes({
    Iterable<String>? symbols,
    QuoteHistoryRange range = QuoteHistoryRange.oneMonth,
    bool force = false,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpInvestments(
    WidgetTester tester,
    MemoryStoreRepo repo,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
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

  testWidgets('user can add a buy from the investments screen', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedEmptyPortfolio();
    await pumpInvestments(tester, repo);

    expect(find.text('No holdings yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-share-transaction')));
    await tester.pumpAndSettle();

    expect(find.text('Add transaction'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('share-tx-ticker')),
      'AAPL',
    );
    await tester.enterText(
      find.byKey(const Key('share-tx-shares')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('share-tx-price')),
      '100',
    );
    await tester.tap(find.byKey(const Key('share-tx-save')));
    await tester.pumpAndSettle();

    expect(repo.holdings, hasLength(1));
    expect(repo.holdings.single.ticker, 'AAPL');
    expect(repo.holdings.single.shares, closeTo(10, 0.0001));
    expect(repo.shareTransactions.single.type, ShareTransactionType.buy);
    expect(find.text('No holdings yet'), findsNothing);
    expect(find.textContaining('AAPL'), findsWidgets);
    expect(repo.portfolio.marketMain, closeTo(1500, 0.0001));
    expect(repo.portfolio.unrealizedPlMain, closeTo(500, 0.0001));
  });

  testWidgets('listed share transaction opens the editor', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedEmptyPortfolio();
    await repo.addShareTransactionForTicker(
      ticker: 'AAPL',
      displayName: 'Apple',
      currencyCode: 'USD',
      visibility: VisibilityScope.shared,
      type: ShareTransactionType.buy,
      date: DateTime.utc(2026, 1, 1),
      shares: 4,
      pricePerShare: 90,
    );
    await pumpInvestments(tester, repo);

    final tx = repo.shareTransactions.single;
    await tester.ensureVisible(find.byKey(ValueKey('share-tx-${tx.id}')));
    await tester.tap(find.byKey(ValueKey('share-tx-${tx.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Edit transaction'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Invest screen has a Yahoo CSV import action', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedEmptyPortfolio();
    await pumpInvestments(tester, repo);

    expect(find.byKey(const Key('import-yahoo-lots')), findsOneWidget);
    expect(find.text('Import Yahoo CSV'), findsOneWidget);
  });

  testWidgets('sample Yahoo CSV import produces holdings', (tester) async {
    final repo = MemoryStoreRepo();
    await repo.seedEmptyPortfolio();
    const sample = '''
Symbol,Current Price,Date,Time,Change,Open,High,Low,Volume,Trade Date,Purchase Price,Quantity,Commission,High Limit,Low Limit,Comment,Transaction Type
RKLB,63.1,2026/09/02,16:00 EDT,0.56,62.29,63.52,61.45,1,20250303,20.33,25.0,3.03,,,,BUY
VAN.F,174.54,2026/09/02,16:41 CEST,-0.96,173.6,176.04,171.96,231,20251020,102.0,5.0,4.0,,,,BUY
''';
    final result = await repo.importYahooLots(
      sample,
      refreshQuotesAfter: false,
    );
    expect(result.imported, 2);
    expect(result.createdHoldings, 2);
    await pumpInvestments(tester, repo);

    expect(find.text('No holdings yet'), findsNothing);
    expect(find.textContaining('RKLB'), findsWidgets);
    expect(find.textContaining('VAN.F'), findsWidgets);
    expect(
      repo.holdings.singleWhere((h) => h.ticker == 'RKLB').shares,
      closeTo(25, 0.0001),
    );
  });
}
