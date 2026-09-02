import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/data/services/quote_client.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/csv_data_exchange.dart';
import 'package:zentho/domain/services/portfolio_math.dart';
import 'package:zentho/domain/services/yahoo_lots_csv.dart';

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
  final fixture =
      File('test/fixtures/yahoo_finance_lots.csv').readAsStringSync();

  group('YahooLotsCsv.parse', () {
    test('detects the Yahoo lots header and not other CSV formats', () {
      expect(YahooLotsCsv.looksLike(fixture), isTrue);
      expect(
        YahooLotsCsv.looksLike(
          'date,amount,type,category,account,note,currency,visibility\n'
          '2026-08-01,42.5,expense,Groceries,Checking,Market,USD,shared\n',
        ),
        isFalse,
      );
      expect(
        CsvDataExchange.looksLikeFullExport(fixture),
        isFalse,
      );
    });

    test('parses the real export: 43 lots, BUY/SELL counts, empty commission',
        () {
      final parsed = YahooLotsCsv.parse(fixture);
      expect(parsed.errors, isEmpty);
      expect(parsed.lots, hasLength(43));
      expect(parsed.buyCount, 40);
      expect(parsed.sellCount, 3);
      expect(
        parsed.lots.every((l) => l.date == DateTime(l.date.year, l.date.month, l.date.day)),
        isTrue,
      );
      expect(parsed.lots.first.date.isBefore(parsed.lots.last.date), isTrue);

      final emptyCommission = parsed.lots.where((l) => l.fee == 0).toList();
      expect(
        emptyCommission.any(
          (l) =>
              l.symbol == 'SPCE' &&
              l.shares == 8 &&
              l.date == DateTime(2025, 6, 6),
        ),
        isTrue,
      );
      expect(
        emptyCommission.any(
          (l) =>
              l.symbol == 'AMD' &&
              l.shares == 6 &&
              l.date == DateTime(2025, 5, 5),
        ),
        isTrue,
      );
    });

    test('skips bad rows without throwing', () {
      const csv = '''
Symbol,Current Price,Date,Time,Change,Open,High,Low,Volume,Trade Date,Purchase Price,Quantity,Commission,High Limit,Low Limit,Comment,Transaction Type
AAPL,1,2026/09/02,16:00 EDT,0,1,1,1,1,20260101,10,2,0,,,,BUY
,1,2026/09/02,16:00 EDT,0,1,1,1,1,20260101,10,2,0,,,,BUY
MSFT,1,2026/09/02,16:00 EDT,0,1,1,1,1,20260101,10,,0,,,,BUY
NVDA,1,2026/09/02,16:00 EDT,0,1,1,1,1,20260101,10,2,0,,,,HOLD
''';
      final parsed = YahooLotsCsv.parse(csv);
      expect(parsed.lots, hasLength(1));
      expect(parsed.lots.single.symbol, 'AAPL');
      expect(parsed.skippedRows, 3);
      expect(parsed.errors, hasLength(3));
    });
  });

  group('Yahoo lots import', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    Future<FinanceRepository> readyRepo() async {
      SharedPreferences.setMockInitialValues({});
      final repo = FinanceRepository(
        refreshRatesOnInit: false,
        quoteClient: _ThrowingQuoteClient(),
      );
      await repo.init();
      repo.settings = repo.settings.copyWith(onboardingComplete: true);
      repo.rates = const [
        CurrencyRate(code: 'USD', rateToMain: 1),
        CurrencyRate(code: 'EUR', rateToMain: 1.1),
        CurrencyRate(code: 'CHF', rateToMain: 1.2),
      ];
      return repo;
    }

    Map<String, double> netShares(FinanceRepository repo) {
      return {
        for (final h in repo.holdings) h.ticker: h.shares,
      };
    }

    test('import applies lots oldest-first and matches expected net quantities',
        () async {
      final repo = await readyRepo();
      final outcome = await repo.importCsv(
        fixture,
        refreshQuotesAfter: false,
      );
      expect(outcome.yahooLots, isNotNull);
      expect(outcome.yahooLots!.imported, 43);
      expect(outcome.yahooLots!.skippedDuplicates, 0);
      expect(outcome.transactions, isNull);

      // Average-cost ledger, chronological (export is newest-first).
      // RKLB: buys 20+25+5+10+11+9+10+12+2+4+60 = 168 minus sell 49 = 119
      // MSFT: buys 2+3+3+2+3+2+1+2 = 18 minus sell 9 = 9
      // SMTC: 37 − 36 = 1; SPCE: 300+24+8 = 332
      const expected = {
        'SMTC': 1.0,
        'SPCX': 34.0,
        'MRVL': 4.0,
        'SMCI': 10.0,
        'VAN.F': 5.0,
        'ADCT': 20.0,
        'SPCE': 332.0,
        'RKLB': 119.0,
        'INTC': 23.0,
        'APGN.SW': 2.0,
        'MSFT': 9.0,
        'AMD': 21.0,
      };
      expect(netShares(repo).keys.toSet(), expected.keys.toSet());
      expected.forEach((ticker, shares) {
        expect(netShares(repo)[ticker], closeTo(shares, 0.0001), reason: ticker);
      });
      expect(repo.shareTransactions, hasLength(43));
      expect(repo.holdings, hasLength(12));

      final van = repo.holdings.firstWhere((h) => h.ticker == 'VAN.F');
      expect(van.currencyCode, 'EUR');
      final swiss = repo.holdings.firstWhere((h) => h.ticker == 'APGN.SW');
      expect(swiss.currencyCode, 'CHF');

      final rklb = repo.holdings.firstWhere((h) => h.ticker == 'RKLB');
      final rklbPos = PortfolioMath.positionFor(
        holding: rklb,
        transactions: repo.shareTransactions,
      );
      expect(rklbPos.shares, closeTo(119, 0.0001));
      expect(rklbPos.realizedPlNative, isNot(0));
    });

    test('second import of the same file skips every lot', () async {
      final repo = await readyRepo();
      await repo.importYahooLots(fixture, refreshQuotesAfter: false);
      final again = await repo.importYahooLots(
        fixture,
        refreshQuotesAfter: false,
      );
      expect(again.imported, 0);
      expect(again.skippedDuplicates, 43);
      expect(repo.shareTransactions, hasLength(43));
      expect(netShares(repo)['RKLB'], 119);
    });

    test('maps onto an existing ticker instead of creating a second holding',
        () async {
      final repo = await readyRepo();
      await repo.addHolding(
        InvestmentHolding.create(
          ticker: 'MSFT',
          displayName: 'Microsoft',
          shares: 0,
          averageCostPerShare: 0,
          currencyCode: 'USD',
          ownerProfileId: repo.settings.activeProfileId,
          visibility: VisibilityScope.shared,
        ),
      );
      final beforeId = repo.holdings.singleWhere((h) => h.ticker == 'MSFT').id;
      final result = await repo.importYahooLots(
        fixture,
        refreshQuotesAfter: false,
      );
      expect(result.createdHoldings, 11);
      expect(
        repo.holdings.where((h) => h.ticker == 'MSFT'),
        hasLength(1),
      );
      expect(
        repo.holdings.singleWhere((h) => h.ticker == 'MSFT').id,
        beforeId,
      );
      expect(
        repo.holdings.singleWhere((h) => h.ticker == 'MSFT').shares,
        closeTo(9, 0.0001),
      );
    });
  });
}
