import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/data/services/quote_client.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/portfolio_math.dart';

class _ThrowingQuoteClient implements QuoteClient {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('net worth adds holding market value from cached quotes without network',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = FinanceRepository(
      refreshRatesOnInit: false,
      quoteClient: _ThrowingQuoteClient(),
    );
    await repo.init();
    final you = repo.profiles.first;
    repo.settings = repo.settings.copyWith(onboardingComplete: true);
    repo.rates = const [
      CurrencyRate(code: 'USD', rateToMain: 1),
      CurrencyRate(code: 'EUR', rateToMain: 1.1),
    ];
    repo.accounts = [
      Account.create(
        name: 'Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
        openingBalance: 1000,
      ),
    ];
    repo.holdings = [
      InvestmentHolding.create(
        ticker: 'AAPL',
        displayName: 'Apple',
        shares: 2,
        averageCostPerShare: 100,
        currencyCode: 'USD',
        ownerProfileId: you.id,
        visibility: VisibilityScope.shared,
      ),
    ];
    repo.quotes = {
      'AAPL': CachedQuote(
        symbol: 'AAPL',
        price: 150,
        currency: 'USD',
        fetchedAt: DateTime.utc(2026, 9, 1),
        source: 'cache',
      ),
    };

    // Accounts 1000 + 2 * 150 = 1300
    expect(repo.netWorth, closeTo(1300, 0.0001));
  });

  test('FinanceSnapshot loads legacy JSON without a holdings key', () {
    final you = HouseholdProfile.create('You');
    final json = FinanceSnapshot(
      settings: AppSettings(
        mainCurrency: 'USD',
        activeProfileId: you.id,
        onboardingComplete: true,
      ),
      profiles: [you],
      accounts: const [],
      categories: const [],
      transactions: const [],
      budgets: const [],
      goals: const [],
      rates: const [CurrencyRate(code: 'USD', rateToMain: 1)],
    ).toJson()
      ..remove('holdings');

    final restored = FinanceSnapshot.fromJson(json);
    expect(restored.holdings, isEmpty);
  });
}
