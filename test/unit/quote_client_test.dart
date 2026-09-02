import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zentho/data/services/quote_client.dart';
import 'package:zentho/domain/services/portfolio_math.dart';

void main() {
  final yahooChart = {
    'chart': {
      'result': [
        {
          'meta': {
            'currency': 'USD',
            'symbol': 'AAPL',
            'regularMarketPrice': 325.13,
            'regularMarketChangePercent': 1.25,
            'chartPreviousClose': 321.12,
          },
          'timestamp': [1725148800, 1725235200],
          'indicators': {
            'quote': [
              {
                'close': [320.0, 325.13],
              },
            ],
          },
        },
      ],
      'error': null,
    },
  };

  test('Yahoo chart parser reads price, currency, and history', () {
    final bundle = YahooQuoteClient.parseChart(
      yahooChart,
      ticker: 'AAPL',
      range: QuoteHistoryRange.oneMonth,
      fetchedAt: DateTime.utc(2026, 9, 2),
    );
    expect(bundle.quote.price, closeTo(325.13, 0.0001));
    expect(bundle.quote.currency, 'USD');
    expect(bundle.quote.changePercent, closeTo(1.25, 0.0001));
    expect(bundle.quote.previousClose, closeTo(321.12, 0.0001));
    expect(bundle.quote.source, 'yahoo');
    expect(bundle.history, hasLength(2));
    expect(bundle.history.last.close, closeTo(325.13, 0.0001));
  });

  test('Yahoo search parser maps quote results', () {
    final results = YahooQuoteClient.parseSearch({
      'quotes': [
        {
          'symbol': 'AAPL',
          'shortname': 'Apple Inc.',
          'quoteType': 'EQUITY',
          'exchDisp': 'NASDAQ',
        },
      ],
    });
    expect(results, hasLength(1));
    expect(results.first.symbol, 'AAPL');
    expect(results.first.name, 'Apple Inc.');
    expect(results.first.exchange, 'NASDAQ');
  });

  test('Yahoo client uses v8 chart and a browser User-Agent', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(jsonEncode(yahooChart), 200);
    });
    final yahoo = YahooQuoteClient(client: client);
    final bundle = await yahoo.fetchChart('aapl');
    expect(seen.url.host, 'query1.finance.yahoo.com');
    expect(seen.url.path, '/v8/finance/chart/AAPL');
    expect(seen.url.queryParameters['interval'], '1d');
    expect(seen.url.queryParameters['range'], '1mo');
    expect(seen.headers['User-Agent'], contains('Mozilla'));
    expect(bundle.quote.price, closeTo(325.13, 0.0001));
  });

  test('Finnhub parser reads quote and candles', () {
    final quote = FinnhubQuoteClient.parseQuote(
      {'c': 325.13, 'd': 4.01, 'dp': 1.25, 'pc': 321.12},
      ticker: 'AAPL',
      fetchedAt: DateTime.utc(2026, 9, 2),
    );
    expect(quote.source, 'finnhub');
    expect(quote.price, closeTo(325.13, 0.0001));
    expect(quote.changePercent, closeTo(1.25, 0.0001));
    expect(
      FinnhubQuoteClient.parseCandle({
        's': 'ok',
        'c': [320.0, 325.13],
        't': [1725148800, 1725235200],
      }),
      hasLength(2),
    );
  });

  test('composite client falls back to Finnhub after Yahoo network failure', () async {
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        throw http.ClientException('Failed to fetch', request.url);
      }
      if (request.url.path.contains('/quote')) {
        return http.Response(
          jsonEncode({'c': 325.13, 'dp': 1.25, 'pc': 321.12}),
          200,
        );
      }
      if (request.url.path.contains('/candle')) {
        return http.Response(
          jsonEncode({
            's': 'ok',
            'c': [325.13],
            't': [1725235200],
          }),
          200,
        );
      }
      fail('Unexpected ${request.url}');
    });

    final composite = CompositeQuoteClient(
      yahoo: YahooQuoteClient(client: client),
      finnhub: FinnhubQuoteClient(token: 'user-local-only', client: client),
    );
    final bundle = await composite.fetchChart('AAPL');
    expect(bundle.quote.source, 'finnhub');
    expect(bundle.quote.price, closeTo(325.13, 0.0001));
  });

  test('composite client does not call Finnhub when Yahoo succeeds', () async {
    var finnhubHits = 0;
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        return http.Response(jsonEncode(yahooChart), 200);
      }
      finnhubHits++;
      return http.Response('nope', 500);
    });
    final composite = CompositeQuoteClient(
      yahoo: YahooQuoteClient(client: client),
      finnhub: FinnhubQuoteClient(token: 'unused', client: client),
    );
    final bundle = await composite.fetchChart('AAPL');
    expect(bundle.quote.source, 'yahoo');
    expect(finnhubHits, 0);
  });

  test('composite client without Finnhub token surfaces Yahoo failure', () async {
    final client = MockClient((request) async {
      throw http.ClientException('Failed to fetch', request.url);
    });
    final composite = CompositeQuoteClient(
      yahoo: YahooQuoteClient(client: client),
    );
    expect(
      () => composite.fetchChart('AAPL'),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('empty baked key does not construct a Finnhub client', () {
    expect(
      createFinnhubQuoteClient(userToken: null, bakedToken: ''),
      isNull,
    );
    expect(
      createFinnhubQuoteClient(userToken: '  ', bakedToken: '   '),
      isNull,
    );
    final composite = CompositeQuoteClient.fromTokens(
      yahoo: YahooQuoteClient(),
      userToken: null,
      bakedToken: '',
    );
    expect(composite.finnhub, isNull);
  });

  test('baked key constructs Finnhub fallback when user has no token', () {
    final client = createFinnhubQuoteClient(
      userToken: null,
      bakedToken: 'baked-test-key',
    );
    expect(client, isA<FinnhubQuoteClient>());
    expect(client!.token, 'baked-test-key');

    final composite = CompositeQuoteClient.fromTokens(
      yahoo: YahooQuoteClient(),
      userToken: null,
      bakedToken: 'baked-test-key',
    );
    expect(composite.finnhub, isA<FinnhubQuoteClient>());
    expect((composite.finnhub! as FinnhubQuoteClient).token, 'baked-test-key');
  });

  test('user-saved token overrides baked Finnhub key', () {
    final client = createFinnhubQuoteClient(
      userToken: '  user-test-key  ',
      bakedToken: 'baked-test-key',
    );
    expect(client, isA<FinnhubQuoteClient>());
    expect(client!.token, 'user-test-key');

    final emptyUserFallsBack = createFinnhubQuoteClient(
      userToken: '',
      bakedToken: 'baked-test-key',
    );
    expect(emptyUserFallsBack!.token, 'baked-test-key');
  });

  test('baked Finnhub key is used after Yahoo failure', () async {
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        throw http.ClientException('Failed to fetch', request.url);
      }
      if (request.url.path.contains('/quote')) {
        expect(request.url.queryParameters['token'], 'baked-test-key');
        return http.Response(
          jsonEncode({'c': 325.13, 'dp': 1.25, 'pc': 321.12}),
          200,
        );
      }
      if (request.url.path.contains('/candle')) {
        return http.Response(
          jsonEncode({
            's': 'ok',
            'c': [325.13],
            't': [1725235200],
          }),
          200,
        );
      }
      fail('Unexpected ${request.url}');
    });

    final composite = CompositeQuoteClient.fromTokens(
      yahoo: YahooQuoteClient(client: client),
      userToken: null,
      bakedToken: 'baked-test-key',
      httpClient: client,
    );
    final bundle = await composite.fetchChart('AAPL');
    expect(bundle.quote.source, 'finnhub');
    expect(bundle.quote.price, closeTo(325.13, 0.0001));
  });

  test('Finnhub candle 403 is access-denied, not offline', () {
    expect(
      FinnhubQuoteClient.isCandleAccessDenied(
        403,
        '{"error":"You don\'t have access to this resource."}',
      ),
      isTrue,
    );
    expect(FinnhubQuoteClient.isCandleAccessDenied(200, '{"s":"ok"}'), isFalse);
  });

  test('Finnhub candle 403 keeps the quote and does not throw', () async {
    final client = MockClient((request) async {
      if (request.url.path.contains('/quote')) {
        return http.Response(
          jsonEncode({'c': 132.27, 'dp': 1.1, 'pc': 130.0}),
          200,
        );
      }
      if (request.url.path.contains('/candle')) {
        return http.Response(
          '{"error":"You don\'t have access to this resource."}',
          403,
        );
      }
      fail('Unexpected ${request.url}');
    });
    final finnhub = FinnhubQuoteClient(token: 'free-token', client: client);
    final bundle = await finnhub.fetchChart('SMTC');
    expect(bundle.quote.source, 'finnhub');
    expect(bundle.quote.price, closeTo(132.27, 0.0001));
    expect(bundle.quote.previousClose, closeTo(130, 0.0001));
    expect(bundle.history, isEmpty);
    expect(finnhub.candlesUnavailableOnPlan, isTrue);
  });

  test('Alpha Vantage parser reads daily closes oldest-first and trims to 1y',
      () {
    final points = AlphaVantageHistoryClient.parseDailySeries(
      {
        'Time Series (Daily)': {
          '2026-09-02': {'4. close': '132.27'},
          '2026-08-03': {'4. close': '110.00'},
          '2024-01-02': {'4. close': '1.00'},
        },
      },
      keep: QuoteHistoryRange.oneYear.lookback,
      now: DateTime.utc(2026, 9, 2),
    );
    expect(points, hasLength(2));
    expect(points.first.date, DateTime.utc(2026, 8, 3));
    expect(points.first.close, closeTo(110, 0.0001));
    expect(points.last.close, closeTo(132.27, 0.0001));
  });

  test('Alpha Vantage rate-limit Note is not treated as history', () {
    expect(
      () => AlphaVantageHistoryClient.parseDailySeries(
        {'Note': 'Thank you for using Alpha Vantage!'},
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('Finnhub candle 403 then Alpha Vantage history is used', () async {
    final now = DateTime.now().toUtc();
    final avBody = _alphaVantageDaily({
      _ymd(now.subtract(const Duration(days: 20))): '110.00',
      _ymd(now.subtract(const Duration(days: 10))): '120.00',
      _ymd(now.subtract(const Duration(days: 1))): '130.00',
      _ymd(now): '132.27',
    });
    var avHits = 0;
    var candleHits = 0;
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        throw http.ClientException('Failed to fetch', request.url);
      }
      if (request.url.host.contains('alphavantage')) {
        avHits++;
        expect(request.url.path, '/query');
        expect(request.url.queryParameters['function'], 'TIME_SERIES_DAILY');
        expect(request.url.queryParameters['symbol'], 'SMTC');
        expect(request.url.queryParameters['outputsize'], 'full');
        expect(request.url.queryParameters['apikey'], 'test-av-key');
        return http.Response(jsonEncode(avBody), 200);
      }
      if (request.url.path.contains('/quote')) {
        return http.Response(
          jsonEncode({'c': 132.27, 'dp': 1.1, 'pc': 130.0}),
          200,
        );
      }
      if (request.url.path.contains('/candle')) {
        candleHits++;
        return http.Response(
          '{"error":"You don\'t have access to this resource."}',
          403,
        );
      }
      fail('Unexpected ${request.url}');
    });

    final composite = CompositeQuoteClient(
      yahoo: YahooQuoteClient(client: client),
      finnhub: FinnhubQuoteClient(token: 'free-token', client: client),
      alphaVantage:
          AlphaVantageHistoryClient(apiKey: 'test-av-key', client: client),
    );
    final bundle = await composite.fetchChart('SMTC');
    expect(bundle.quote.source, 'finnhub');
    expect(bundle.quote.price, closeTo(132.27, 0.0001));
    expect(bundle.history.length, greaterThanOrEqualTo(2));
    expect(bundle.history.last.close, closeTo(132.27, 0.0001));
    expect(bundle.quote.history[QuoteHistoryRange.oneYear.key], isNotEmpty);
    expect(avHits, 1);
    expect(candleHits, 1);
    expect(
      PortfolioMath.usesLastCloseFallback(
        bundle.quote,
        QuoteHistoryRange.oneMonth,
      ),
      isFalse,
    );

    final yearBundle = await composite.fetchChart(
      'SMTC',
      range: QuoteHistoryRange.oneYear,
    );
    expect(avHits, 1);
    expect(yearBundle.history.length, greaterThanOrEqualTo(2));
    expect(candleHits, 1);
  });

  test('Yahoo success does not call Alpha Vantage', () async {
    var avHits = 0;
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        return http.Response(jsonEncode(yahooChart), 200);
      }
      avHits++;
      return http.Response('nope', 500);
    });
    final composite = CompositeQuoteClient(
      yahoo: YahooQuoteClient(client: client),
      finnhub: FinnhubQuoteClient(token: 'unused', client: client),
      alphaVantage:
          AlphaVantageHistoryClient(apiKey: 'test-av-key', client: client),
    );
    final bundle = await composite.fetchChart('AAPL');
    expect(bundle.quote.source, 'yahoo');
    expect(avHits, 0);
  });

  test('empty baked Alpha Vantage key does not construct a client', () {
    expect(
      createAlphaVantageHistoryClient(userToken: null, bakedToken: ''),
      isNull,
    );
    final composite = CompositeQuoteClient.fromTokens(
      yahoo: YahooQuoteClient(),
      userToken: null,
      bakedToken: '',
      alphaVantageUserToken: null,
      alphaVantageBakedToken: '',
    );
    expect(composite.alphaVantage, isNull);
  });

  test('user-saved Alpha Vantage key overrides baked key', () {
    final client = createAlphaVantageHistoryClient(
      userToken: '  user-av-key  ',
      bakedToken: 'baked-av-key',
    );
    expect(client, isA<AlphaVantageHistoryClient>());
    expect(client!.apiKey, 'user-av-key');
  });
}

String _ymd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

Map<String, dynamic> _alphaVantageDaily(Map<String, String> closesByDate) {
  return {
    'Meta Data': {'2. Symbol': 'SMTC'},
    'Time Series (Daily)': {
      for (final e in closesByDate.entries) e.key: {'4. close': e.value},
    },
  };
}
