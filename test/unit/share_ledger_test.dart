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
  const rates = [CurrencyRate(code: 'USD', rateToMain: 1)];

  InvestmentHolding lot({
    double shares = 0,
    double cost = 0,
    String ticker = 'AAPL',
  }) {
    return InvestmentHolding.create(
      ticker: ticker,
      displayName: ticker,
      shares: shares,
      averageCostPerShare: cost,
      currencyCode: 'USD',
      ownerProfileId: 'p1',
      visibility: VisibilityScope.shared,
    );
  }

  ShareTransaction tx({
    required InvestmentHolding holding,
    required ShareTransactionType type,
    required DateTime date,
    double shares = 0,
    double price = 0,
    double amount = 0,
    double fee = 0,
    String id = '',
  }) {
    final created = ShareTransaction.create(
      holdingId: holding.id,
      type: type,
      date: date,
      shares: shares,
      pricePerShare: price,
      amount: amount,
      fee: fee,
    );
    if (id.isEmpty) return created;
    return ShareTransaction(
      id: id,
      holdingId: holding.id,
      type: type,
      date: date,
      shares: shares,
      pricePerShare: price,
      amount: amount,
      fee: fee,
    );
  }

  group('Share ledger application', () {
    test('empty ledger uses the static holding snapshot', () {
      final holding = lot(shares: 10, cost: 50);
      final pos = PortfolioMath.positionFor(holding: holding);
      expect(pos.shares, 10);
      expect(pos.averageCostPerShare, 50);
      expect(pos.costNative, 500);
      expect(pos.realizedPlNative, 0);
    });

    test('buys raise quantity and average cost', () {
      final holding = lot();
      final pos = PortfolioMath.positionFor(
        holding: holding,
        transactions: [
          tx(
            holding: holding,
            type: ShareTransactionType.buy,
            date: DateTime.utc(2026, 1, 1),
            shares: 10,
            price: 100,
          ),
          tx(
            holding: holding,
            type: ShareTransactionType.buy,
            date: DateTime.utc(2026, 2, 1),
            shares: 10,
            price: 120,
          ),
        ],
      );
      expect(pos.shares, closeTo(20, 0.0001));
      expect(pos.averageCostPerShare, closeTo(110, 0.0001));
      expect(pos.costNative, closeTo(2200, 0.0001));
      expect(pos.investedNative, closeTo(2200, 0.0001));
    });

    test('partial sell realizes P/L and leaves remaining cost basis', () {
      final holding = lot();
      final pos = PortfolioMath.positionFor(
        holding: holding,
        transactions: [
          tx(
            holding: holding,
            type: ShareTransactionType.buy,
            date: DateTime.utc(2026, 1, 1),
            shares: 10,
            price: 100,
          ),
          tx(
            holding: holding,
            type: ShareTransactionType.sell,
            date: DateTime.utc(2026, 3, 1),
            shares: 4,
            price: 130,
          ),
        ],
      );
      // Sold 4 @ 130 vs avg 100 → realized 120; 6 remain @ 100
      expect(pos.shares, closeTo(6, 0.0001));
      expect(pos.averageCostPerShare, closeTo(100, 0.0001));
      expect(pos.costNative, closeTo(600, 0.0001));
      expect(pos.realizedPlNative, closeTo(120, 0.0001));
    });

    test('full sell zeros the position and keeps realized P/L', () {
      final holding = lot();
      final pos = PortfolioMath.positionFor(
        holding: holding,
        transactions: [
          tx(
            holding: holding,
            type: ShareTransactionType.buy,
            date: DateTime.utc(2026, 1, 1),
            shares: 2,
            price: 50,
          ),
          tx(
            holding: holding,
            type: ShareTransactionType.sell,
            date: DateTime.utc(2026, 2, 1),
            shares: 2,
            price: 80,
          ),
        ],
      );
      expect(pos.shares, 0);
      expect(pos.costNative, 0);
      expect(pos.realizedPlNative, closeTo(60, 0.0001));
    });

    test('sell commission reduces realized P/L', () {
      final holding = lot();
      final pos = PortfolioMath.positionFor(
        holding: holding,
        transactions: [
          tx(
            holding: holding,
            type: ShareTransactionType.buy,
            date: DateTime.utc(2026, 1, 1),
            shares: 10,
            price: 10,
            fee: 5,
          ),
          tx(
            holding: holding,
            type: ShareTransactionType.sell,
            date: DateTime.utc(2026, 2, 1),
            shares: 10,
            price: 12,
            fee: 5,
          ),
        ],
      );
      // Cost 105; proceeds 120-5=115; realized 10
      expect(pos.shares, 0);
      expect(pos.realizedPlNative, closeTo(10, 0.0001));
    });

    test('dividends are cash income and do not change quantity', () {
      final holding = lot();
      final pos = PortfolioMath.positionFor(
        holding: holding,
        transactions: [
          tx(
            holding: holding,
            type: ShareTransactionType.buy,
            date: DateTime.utc(2026, 1, 1),
            shares: 8,
            price: 25,
          ),
          tx(
            holding: holding,
            type: ShareTransactionType.dividend,
            date: DateTime.utc(2026, 2, 1),
            amount: 12,
          ),
        ],
      );
      expect(pos.shares, closeTo(8, 0.0001));
      expect(pos.costNative, closeTo(200, 0.0001));
      expect(pos.dividendNative, closeTo(12, 0.0001));
      expect(pos.realizedPlNative, 0);
    });

    test('standalone fee adds to remaining cost basis', () {
      final holding = lot();
      final pos = PortfolioMath.positionFor(
        holding: holding,
        transactions: [
          tx(
            holding: holding,
            type: ShareTransactionType.buy,
            date: DateTime.utc(2026, 1, 1),
            shares: 10,
            price: 10,
          ),
          tx(
            holding: holding,
            type: ShareTransactionType.fee,
            date: DateTime.utc(2026, 1, 2),
            amount: 5,
          ),
        ],
      );
      expect(pos.shares, 10);
      expect(pos.costNative, closeTo(105, 0.0001));
      expect(pos.averageCostPerShare, closeTo(10.5, 0.0001));
    });

    test('2-for-1 split doubles shares and halves average cost', () {
      final holding = lot();
      final pos = PortfolioMath.positionFor(
        holding: holding,
        transactions: [
          tx(
            holding: holding,
            type: ShareTransactionType.buy,
            date: DateTime.utc(2026, 1, 1),
            shares: 5,
            price: 200,
          ),
          tx(
            holding: holding,
            type: ShareTransactionType.split,
            date: DateTime.utc(2026, 2, 1),
            shares: 2,
          ),
        ],
      );
      expect(pos.shares, closeTo(10, 0.0001));
      expect(pos.averageCostPerShare, closeTo(100, 0.0001));
      expect(pos.costNative, closeTo(1000, 0.0001));
    });

    test('strict mode rejects selling more shares than held', () {
      final holding = lot();
      expect(
        () => PortfolioMath.positionFor(
          holding: holding,
          transactions: [
            tx(
              holding: holding,
              type: ShareTransactionType.buy,
              date: DateTime.utc(2026, 1, 1),
              shares: 2,
              price: 10,
            ),
            tx(
              holding: holding,
              type: ShareTransactionType.sell,
              date: DateTime.utc(2026, 2, 1),
              shares: 5,
              price: 12,
            ),
          ],
          strict: true,
        ),
        throwsA(isA<ShareLedgerException>()),
      );
      expect(
        PortfolioMath.validateShareLedger(
          holding: holding,
          transactions: [
            tx(
              holding: holding,
              type: ShareTransactionType.buy,
              date: DateTime.utc(2026, 1, 1),
              shares: 2,
              price: 10,
            ),
            tx(
              holding: holding,
              type: ShareTransactionType.sell,
              date: DateTime.utc(2026, 2, 1),
              shares: 5,
              price: 12,
            ),
          ],
        ),
        contains('Cannot sell'),
      );
    });

    test('strict mode rejects zero and negative quantities', () {
      final holding = lot();
      expect(
        PortfolioMath.validateShareLedger(
          holding: holding,
          transactions: [
            tx(
              holding: holding,
              type: ShareTransactionType.buy,
              date: DateTime.utc(2026, 1, 1),
              shares: 0,
              price: 10,
            ),
          ],
        ),
        contains('positive'),
      );
      expect(
        PortfolioMath.validateShareLedger(
          holding: holding,
          transactions: [
            tx(
              holding: holding,
              type: ShareTransactionType.sell,
              date: DateTime.utc(2026, 1, 1),
              shares: 1,
              price: 10,
            ),
          ],
        ),
        contains('empty position'),
      );
    });
  });

  group('Portfolio performance from transactions', () {
    test('unrealized uses remaining shares vs last price', () {
      final holding = lot();
      final txs = [
        tx(
          holding: holding,
          type: ShareTransactionType.buy,
          date: DateTime.utc(2026, 1, 1),
          shares: 10,
          price: 100,
        ),
        tx(
          holding: holding,
          type: ShareTransactionType.sell,
          date: DateTime.utc(2026, 2, 1),
          shares: 4,
          price: 130,
        ),
      ];
      final totals = PortfolioMath.summarize(
        holdings: [holding],
        shareTransactions: txs,
        quotes: {
          'AAPL': CachedQuote(
            symbol: 'AAPL',
            price: 140,
            currency: 'USD',
            fetchedAt: DateTime.utc(2026, 9, 1),
            source: 'test',
          ),
        },
        mainCurrency: 'USD',
        rates: rates,
      );
      // Remaining 6 @ cost 600, market 840, unrealized 240, realized 120
      expect(totals.holdings.single.holding.shares, closeTo(6, 0.0001));
      expect(totals.costMain, closeTo(600, 0.0001));
      expect(totals.marketMain, closeTo(840, 0.0001));
      expect(totals.unrealizedPlMain, closeTo(240, 0.0001));
      expect(totals.realizedPlMain, closeTo(120, 0.0001));
      expect(totals.totalPlMain, closeTo(360, 0.0001));
    });

    test('performance series uses quantity on each history date', () {
      final holding = lot();
      final txs = [
        tx(
          holding: holding,
          type: ShareTransactionType.buy,
          date: DateTime.utc(2026, 8, 1),
          shares: 2,
          price: 100,
        ),
        tx(
          holding: holding,
          type: ShareTransactionType.buy,
          date: DateTime.utc(2026, 8, 3),
          shares: 2,
          price: 110,
        ),
      ];
      final series = PortfolioMath.performanceSeries(
        holdings: [holding],
        shareTransactions: txs,
        quotes: {
          'AAPL': CachedQuote(
            symbol: 'AAPL',
            price: 120,
            currency: 'USD',
            fetchedAt: DateTime.utc(2026, 9, 1),
            source: 'test',
            history: {
              '1mo': [
                PricePoint(date: DateTime.utc(2026, 8, 1), close: 100),
                PricePoint(date: DateTime.utc(2026, 8, 2), close: 110),
                PricePoint(date: DateTime.utc(2026, 8, 3), close: 120),
              ],
            },
          ),
        },
        mainCurrency: 'USD',
        rates: rates,
        range: QuoteHistoryRange.oneMonth,
      );
      expect(series, hasLength(3));
      expect(series[0].close, closeTo(200, 0.01)); // 2 * 100
      expect(series[1].close, closeTo(220, 0.01)); // 2 * 110
      expect(series[2].close, closeTo(480, 0.01)); // 4 * 120
    });
  });

  group('FinanceRepository share transactions', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    Future<FinanceRepository> readyRepo() async {
      SharedPreferences.setMockInitialValues({});
      final repo = FinanceRepository(
        refreshRatesOnInit: false,
        quoteClient: _ThrowingQuoteClient(),
      );
      await repo.init();
      repo.settings = repo.settings.copyWith(onboardingComplete: true);
      repo.rates = rates;
      repo.quotes = {
        'AAPL': CachedQuote(
          symbol: 'AAPL',
          price: 150,
          currency: 'USD',
          fetchedAt: DateTime.utc(2026, 9, 1),
          source: 'cache',
        ),
      };
      return repo;
    }

    test('add/edit/delete transactions recompute holdings and P/L', () async {
      final repo = await readyRepo();
      final error = await repo.addShareTransactionForTicker(
        ticker: 'AAPL',
        displayName: 'Apple',
        currencyCode: 'USD',
        visibility: VisibilityScope.shared,
        type: ShareTransactionType.buy,
        date: DateTime.utc(2026, 1, 1),
        shares: 10,
        pricePerShare: 100,
      );
      expect(error, isNull);
      expect(repo.holdings, hasLength(1));
      expect(repo.holdings.single.shares, closeTo(10, 0.0001));
      expect(repo.holdings.single.averageCostPerShare, closeTo(100, 0.0001));
      expect(repo.portfolio.marketMain, closeTo(1500, 0.0001));
      expect(repo.portfolio.unrealizedPlMain, closeTo(500, 0.0001));

      final sellError = await repo.addShareTransaction(
        ShareTransaction.create(
          holdingId: repo.holdings.single.id,
          type: ShareTransactionType.sell,
          date: DateTime.utc(2026, 2, 1),
          shares: 4,
          pricePerShare: 130,
        ),
      );
      expect(sellError, isNull);
      expect(repo.holdings.single.shares, closeTo(6, 0.0001));
      expect(repo.portfolio.realizedPlMain, closeTo(120, 0.0001));
      expect(repo.portfolio.marketMain, closeTo(900, 0.0001));

      final sell = repo.shareTransactions
          .firstWhere((t) => t.type == ShareTransactionType.sell);
      expect(
        await repo.updateShareTransaction(sell.copyWith(shares: 2)),
        isNull,
      );
      expect(repo.holdings.single.shares, closeTo(8, 0.0001));
      expect(repo.portfolio.realizedPlMain, closeTo(60, 0.0001));

      expect(await repo.deleteShareTransaction(sell.id), isNull);
      expect(repo.holdings.single.shares, closeTo(10, 0.0001));
      expect(repo.portfolio.realizedPlMain, 0);
    });

    test('rejects an oversell and leaves the ledger unchanged', () async {
      final repo = await readyRepo();
      await repo.addShareTransactionForTicker(
        ticker: 'AAPL',
        displayName: 'Apple',
        currencyCode: 'USD',
        visibility: VisibilityScope.shared,
        type: ShareTransactionType.buy,
        date: DateTime.utc(2026, 1, 1),
        shares: 2,
        pricePerShare: 100,
      );
      final before = [...repo.shareTransactions];
      final error = await repo.addShareTransaction(
        ShareTransaction.create(
          holdingId: repo.holdings.single.id,
          type: ShareTransactionType.sell,
          date: DateTime.utc(2026, 2, 1),
          shares: 5,
          pricePerShare: 120,
        ),
      );
      expect(error, isNotNull);
      expect(repo.shareTransactions, before);
      expect(repo.holdings.single.shares, closeTo(2, 0.0001));
    });

    test('snapshot round-trips share transactions through JSON', () async {
      final repo = await readyRepo();
      await repo.addShareTransactionForTicker(
        ticker: 'AAPL',
        displayName: 'Apple',
        currencyCode: 'USD',
        visibility: VisibilityScope.shared,
        type: ShareTransactionType.buy,
        date: DateTime.utc(2026, 1, 1),
        shares: 3,
        pricePerShare: 40,
      );
      final restored = FinanceSnapshot.fromJson(repo.snapshot.toJson());
      expect(restored.shareTransactions, hasLength(1));
      expect(restored.shareTransactions.single.shares, 3);
      expect(restored.holdings.single.ticker, 'AAPL');
    });
  });
}
