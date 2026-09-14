import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/data/services/quote_client.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/portfolio_math.dart';

class _MixedBookQuoteClient implements QuoteClient {
  final calls = <String>[];

  @override
  Future<QuoteBundle> fetchChart(
    String symbol, {
    QuoteHistoryRange range = QuoteHistoryRange.oneMonth,
  }) async {
    final ticker = symbol.trim().toUpperCase();
    calls.add(ticker);
    if (ticker == 'VTI') {
      return QuoteBundle(
        quote: CachedQuote(
          symbol: 'VTI',
          price: 262.97,
          currency: 'USD',
          fetchedAt: DateTime.now().toUtc(),
          source: 'finnhub',
          previousClose: 261.50,
          changePercent: 0.56,
        ),
        range: range,
      );
    }
    if (ticker == 'NESN.SW') {
      throw QuoteUnavailable(
        symbol: 'NESN.SW',
        skippedYahoo: true,
        finnhubError: StateError('Finnhub quote HTTP 403 for NESN.SW'),
      );
    }
    throw StateError('unexpected $symbol');
  }

  @override
  Future<List<TickerSearchResult>> search(String query) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<FinanceRepository> seededRepo(_MixedBookQuoteClient quotes) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FinanceRepository(
      refreshRatesOnInit: false,
      quoteClient: quotes,
    );
    await repo.init();
    final you = repo.profiles.first;
    repo.settings = repo.settings.copyWith(onboardingComplete: true);
    repo.rates = const [
      CurrencyRate(code: 'USD', rateToMain: 1),
      CurrencyRate(code: 'CHF', rateToMain: 1.1),
    ];
    repo.holdings = [
      InvestmentHolding.create(
        ticker: 'VTI',
        displayName: 'Vanguard Total Stock',
        shares: 10,
        averageCostPerShare: 250,
        currencyCode: 'USD',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
      ),
      InvestmentHolding.create(
        ticker: 'NESN.SW',
        displayName: 'Nestle',
        shares: 5,
        averageCostPerShare: 80,
        currencyCode: 'CHF',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
      ),
    ];
    repo.quotes = {
      'VTI': CachedQuote(
        symbol: 'VTI',
        price: 200,
        currency: 'USD',
        fetchedAt: DateTime.utc(2026, 9, 1),
        source: 'finnhub',
        previousClose: 199,
      ),
      'NESN.SW': CachedQuote(
        symbol: 'NESN.SW',
        price: 80,
        currency: 'CHF',
        fetchedAt: DateTime.utc(2026, 9, 1),
        source: 'finnhub',
        previousClose: 81,
      ),
    };
    return repo;
  }

  test('US lot refreshes while Swiss Finnhub 403 keeps saved price', () async {
    final client = _MixedBookQuoteClient();
    final repo = await seededRepo(client);
    await repo.refreshQuotes(force: true);

    expect(client.calls, ['VTI', 'NESN.SW']);
    expect(repo.quotes['VTI']!.price, closeTo(262.97, 0.0001));
    expect(repo.quotes['VTI']!.previousClose, closeTo(261.50, 0.0001));
    expect(repo.quotes['VTI']!.source, 'finnhub');
    expect(repo.quotes['NESN.SW']!.price, closeTo(80, 0.0001));
    expect(repo.quotesError, contains('Could not refresh NESN.SW'));
    expect(repo.quotesError, contains('Browser CORS blocks Yahoo'));
    expect(repo.quotesError, contains('SIX Swiss'));
    expect(repo.quotesError, isNot(contains('query1.finance.yahoo.com')));
    expect(
      repo.quotesError,
      isNot(contains('Could not refresh quotes —')),
    );
  });

  test('fresh US cache plus Swiss 403 names NESN.SW, not the whole book',
      () async {
    final client = _MixedBookQuoteClient();
    final repo = await seededRepo(client);
    repo.quotes = {
      ...repo.quotes,
      'VTI': repo.quotes['VTI']!.copyWith(
        fetchedAt: DateTime.now().toUtc(),
        historyFetchedAt: {
          QuoteHistoryRange.oneMonth.key: DateTime.now().toUtc(),
        },
      ),
    };
    await repo.refreshQuotes();

    expect(client.calls, ['NESN.SW']);
    expect(repo.quotes['VTI']!.price, closeTo(200, 0.0001));
    expect(repo.quotesError, contains('Could not refresh NESN.SW'));
    expect(repo.quotesError, contains('Browser CORS blocks Yahoo'));
    expect(
      repo.quotesError,
      isNot(contains('Could not refresh quotes —')),
    );
  });
}
