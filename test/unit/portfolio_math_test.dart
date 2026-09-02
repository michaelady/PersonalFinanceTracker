import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/portfolio_math.dart';

void main() {
  const rates = [
    CurrencyRate(code: 'USD', rateToMain: 1),
    CurrencyRate(code: 'EUR', rateToMain: 1.1),
  ];

  InvestmentHolding lot({
    required String ticker,
    required double shares,
    required double cost,
    String currency = 'USD',
    bool includeInNetWorth = true,
  }) {
    return InvestmentHolding.create(
      ticker: ticker,
      displayName: ticker,
      shares: shares,
      averageCostPerShare: cost,
      currencyCode: currency,
      ownerProfileId: 'p1',
      visibility: VisibilityScope.shared,
      includeInNetWorth: includeInNetWorth,
    );
  }

  CachedQuote quote({
    required String symbol,
    required double price,
    String currency = 'USD',
    double? changePercent,
    double? previousClose,
  }) {
    return CachedQuote(
      symbol: symbol,
      price: price,
      currency: currency,
      fetchedAt: DateTime.utc(2026, 9, 2, 12),
      source: 'test',
      changePercent: changePercent,
      previousClose: previousClose,
    );
  }

  group('PortfolioMath', () {
    test('unrealized P/L in dollars and percent', () {
      final holding = lot(ticker: 'AAPL', shares: 10, cost: 100);
      final totals = PortfolioMath.summarize(
        holdings: [holding],
        quotes: {
          'AAPL': quote(symbol: 'AAPL', price: 110),
        },
        mainCurrency: 'USD',
        rates: rates,
      );
      expect(totals.costMain, closeTo(1000, 0.0001));
      expect(totals.marketMain, closeTo(1100, 0.0001));
      expect(totals.unrealizedPlMain, closeTo(100, 0.0001));
      expect(totals.unrealizedPlPercent, closeTo(10, 0.0001));
      expect(totals.holdings.single.unrealizedPlPercent, closeTo(10, 0.0001));
    });

    test('allocation percent by holding market value', () {
      final aapl = lot(ticker: 'AAPL', shares: 10, cost: 50);
      final vwce = lot(ticker: 'VWCE.DE', shares: 5, cost: 80, currency: 'EUR');
      final totals = PortfolioMath.summarize(
        holdings: [aapl, vwce],
        quotes: {
          'AAPL': quote(symbol: 'AAPL', price: 100),
          'VWCE.DE': quote(symbol: 'VWCE.DE', price: 80, currency: 'EUR'),
        },
        mainCurrency: 'USD',
        rates: rates,
      );
      // AAPL 1000 USD; VWCE 400 EUR → 440 USD; total 1440
      expect(totals.marketMain, closeTo(1440, 0.01));
      final byTicker = {
        for (final v in totals.holdings) v.holding.ticker: v.allocationPercent,
      };
      expect(byTicker['AAPL'], closeTo(1000 / 1440 * 100, 0.01));
      expect(byTicker['VWCE.DE'], closeTo(440 / 1440 * 100, 0.01));
    });

    test('converts a foreign-currency holding into main via existing FX rates', () {
      final holding = lot(
        ticker: 'VWCE.DE',
        shares: 2,
        cost: 100,
        currency: 'EUR',
      );
      final valued = PortfolioMath.valueHolding(
        holding: holding,
        quotes: {
          'VWCE.DE': quote(symbol: 'VWCE.DE', price: 120, currency: 'EUR'),
        },
        mainCurrency: 'USD',
        rates: rates,
      );
      // cost 200 EUR → 220 USD; market 240 EUR → 264 USD; P/L 44
      expect(valued.costMain, closeTo(220, 0.0001));
      expect(valued.marketMain, closeTo(264, 0.0001));
      expect(valued.unrealizedPlMain, closeTo(44, 0.0001));
      expect(
        PortfolioMath.convertHoldingAmount(
          amount: 240,
          fromCurrency: 'EUR',
          mainCurrency: 'USD',
          rates: rates,
        ),
        closeTo(264, 0.0001),
      );
    });

    test('portfolio totals include day change from previous close', () {
      final holding = lot(ticker: 'AAPL', shares: 10, cost: 100);
      final totals = PortfolioMath.summarize(
        holdings: [holding],
        quotes: {
          'AAPL': quote(
            symbol: 'AAPL',
            price: 110,
            previousClose: 100,
            changePercent: 10,
          ),
        },
        mainCurrency: 'USD',
        rates: rates,
      );
      expect(totals.dayChangeMain, closeTo(100, 0.0001));
      expect(totals.marketMain, closeTo(1100, 0.0001));
    });

    test('uses cost when a quote is missing and respects includeInNetWorth', () {
      final counted = lot(ticker: 'AAPL', shares: 2, cost: 50);
      final excluded = lot(
        ticker: 'MSFT',
        shares: 10,
        cost: 400,
        includeInNetWorth: false,
      );
      final included = PortfolioMath.includedMarketValueMain(
        holdings: [counted, excluded],
        quotes: const {},
        mainCurrency: 'USD',
        rates: rates,
      );
      expect(included, closeTo(100, 0.0001));
    });

    test('builds a portfolio performance series from mocked history', () {
      final aapl = lot(ticker: 'AAPL', shares: 2, cost: 100);
      final vwce = lot(ticker: 'VWCE.DE', shares: 1, cost: 50, currency: 'EUR');
      final quotes = {
        'AAPL': quote(symbol: 'AAPL', price: 120).copyWith(
          history: {
            '1mo': [
              PricePoint(date: DateTime.utc(2026, 8, 1), close: 100),
              PricePoint(date: DateTime.utc(2026, 8, 2), close: 110),
            ],
          },
        ),
        'VWCE.DE': quote(symbol: 'VWCE.DE', price: 60, currency: 'EUR').copyWith(
          history: {
            '1mo': [
              PricePoint(date: DateTime.utc(2026, 8, 1), close: 50),
              PricePoint(date: DateTime.utc(2026, 8, 3), close: 55),
            ],
          },
        ),
      };
      final series = PortfolioMath.performanceSeries(
        holdings: [aapl, vwce],
        quotes: quotes,
        mainCurrency: 'USD',
        rates: rates,
        range: QuoteHistoryRange.oneMonth,
      );
      expect(series, hasLength(3));
      // Aug 1: 2*100 USD + 1*50 EUR*1.1 = 200 + 55 = 255
      expect(series[0].close, closeTo(255, 0.01));
      // Aug 2: AAPL 220 + VWCE last 55 = 275
      expect(series[1].close, closeTo(275, 0.01));
      // Aug 3: AAPL last 220 + VWCE 55*1.1 = 220 + 60.5 = 280.5
      expect(series[2].close, closeTo(280.5, 0.01));
    });

    test('holdingsForChart selects the full book or a single lot', () {
      final aapl = lot(ticker: 'AAPL', shares: 2, cost: 100);
      final vwce = lot(ticker: 'VWCE.DE', shares: 1, cost: 50, currency: 'EUR');
      expect(
        PortfolioMath.holdingsForChart(
          visible: [aapl, vwce],
          selectedHoldingId: null,
        ),
        [aapl, vwce],
      );
      expect(
        PortfolioMath.holdingsForChart(
          visible: [aapl, vwce],
          selectedHoldingId: aapl.id,
        ),
        [aapl],
      );
      expect(
        PortfolioMath.holdingsForChart(
          visible: [aapl, vwce],
          selectedHoldingId: 'missing',
        ),
        isEmpty,
      );
    });

    test('selecting one holding changes the performance series vs the portfolio',
        () {
      final aapl = lot(ticker: 'AAPL', shares: 2, cost: 100);
      final vwce = lot(ticker: 'VWCE.DE', shares: 1, cost: 50, currency: 'EUR');
      final quotes = {
        'AAPL': quote(symbol: 'AAPL', price: 120).copyWith(
          history: {
            '1mo': [
              PricePoint(date: DateTime.utc(2026, 8, 1), close: 100),
              PricePoint(date: DateTime.utc(2026, 8, 2), close: 110),
            ],
          },
        ),
        'VWCE.DE': quote(symbol: 'VWCE.DE', price: 60, currency: 'EUR').copyWith(
          history: {
            '1mo': [
              PricePoint(date: DateTime.utc(2026, 8, 1), close: 50),
              PricePoint(date: DateTime.utc(2026, 8, 3), close: 55),
            ],
          },
        ),
      };

      List<PricePoint> seriesFor(String? selectedId) {
        return PortfolioMath.performanceSeries(
          holdings: PortfolioMath.holdingsForChart(
            visible: [aapl, vwce],
            selectedHoldingId: selectedId,
          ),
          quotes: quotes,
          mainCurrency: 'USD',
          rates: rates,
          range: QuoteHistoryRange.oneMonth,
        );
      }

      final portfolio = seriesFor(null);
      final appleOnly = seriesFor(aapl.id);
      expect(portfolio, hasLength(3));
      expect(appleOnly, hasLength(2));
      expect(appleOnly.first.close, closeTo(200, 0.01));
      expect(appleOnly.last.close, closeTo(220, 0.01));
      expect(appleOnly.last.close, isNot(closeTo(portfolio.last.close, 0.01)));
    });
  });
}
