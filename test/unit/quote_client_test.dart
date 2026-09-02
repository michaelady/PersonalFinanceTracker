import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zentho/data/services/quote_client.dart';
import 'package:zentho/domain/models/models.dart';
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

  test('Alpha Vantage Information and Error Message are not history', () {
    expect(
      () => AlphaVantageHistoryClient.parseDailySeries({
        'Information':
            'Thank you for using Alpha Vantage! Our standard API rate limit is 25 requests per day and 5 requests per minute.',
      }),
      throwsA(isA<StateError>()),
    );
    expect(
      () => AlphaVantageHistoryClient.parseDailySeries({
        'Error Message': 'Invalid API call.',
      }),
      throwsA(isA<StateError>()),
    );
  });

  test('Time Series (Daily) parses when Meta Data includes Information', () {
    final points = AlphaVantageHistoryClient.parseDailySeries({
      'Meta Data': {
        '1. Information': 'Daily Prices (open, high, low, close) and Volumes',
        '2. Symbol': 'IBM',
        '4. Output Size': 'Compact',
      },
      'Time Series (Daily)': {
        '2026-09-02': {'4. close': '10.00'},
        '2026-09-01': {'4. close': '9.00'},
      },
    });
    expect(points, hasLength(2));
    expect(points.first.close, closeTo(9, 0.0001));
    expect(points.last.close, closeTo(10, 0.0001));
  });

  test('compact daily series slices to 1M without requiring outputsize=full',
      () {
    final now = DateTime.utc(2026, 9, 2);
    final closes = <String, String>{};
    for (var i = 0; i < 8; i++) {
      closes[_ymd(now.subtract(Duration(days: i * 5)))] = '${100 + i}.00';
    }
    final points = AlphaVantageHistoryClient.parseDailySeries(
      _alphaVantageDaily(closes),
      now: now,
    );
    expect(points.length, 8);
    final quote = CachedQuote(
      symbol: 'SMTC',
      price: 100,
      currency: 'USD',
      fetchedAt: now,
      source: 'finnhub',
      history: {QuoteHistoryRange.oneYear.key: points},
      historyFetchedAt: {QuoteHistoryRange.oneYear.key: now},
    );
    final month = PortfolioMath.storedHistoryForRange(
      quote,
      QuoteHistoryRange.oneMonth,
      now: now,
    );
    expect(month.length, greaterThanOrEqualTo(2));
    expect(
      month.every(
        (p) => !p.date
            .isBefore(now.subtract(QuoteHistoryRange.oneMonth.lookback)),
      ),
      isTrue,
    );
    expect(
      PortfolioMath.usesLastCloseFallback(
        quote,
        QuoteHistoryRange.oneMonth,
        now: now,
      ),
      isFalse,
    );
    final year = PortfolioMath.storedHistoryForRange(
      quote,
      QuoteHistoryRange.oneYear,
      now: now,
    );
    expect(year, hasLength(8));
    expect(year.length, isNot(370));
  });

  test('classifies per-minute vs daily Alpha Vantage throttle messages', () {
    expect(
      AlphaVantageHistoryClient.classifyThrottle(
        'Thank you for using Alpha Vantage! Our standard API call frequency is 5 calls per minute and 500 calls per day.',
      ),
      AlphaVantageThrottle.perMinute,
    );
    expect(
      AlphaVantageHistoryClient.classifyThrottle(
        'Thank you for using Alpha Vantage! Our standard API rate limit is 25 requests per day and 5 requests per minute.',
      ),
      AlphaVantageThrottle.perMinute,
    );
    expect(
      AlphaVantageHistoryClient.classifyThrottle(
        'Thank you for using Alpha Vantage! Our standard API rate limit is 25 requests per day. Please subscribe to remove all daily rate limits.',
      ),
      AlphaVantageThrottle.dailyQuota,
    );
    expect(
      AlphaVantageHistoryClient.classifyThrottle('Invalid API call.'),
      AlphaVantageThrottle.none,
    );
    expect(
      AlphaVantageHistoryClient.defaultMinRequestGap,
      const Duration(seconds: 12),
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
        expect(request.url.queryParameters['outputsize'], 'compact');
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

  test('Alpha Vantage history URL uses compact unless premium is set', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode(_alphaVantageDaily({
          '2026-09-01': '10.00',
          '2026-09-02': '11.00',
        })),
        200,
      );
    });
    final av = AlphaVantageHistoryClient(
      apiKey: 'test-av-key',
      client: client,
      minRequestGap: Duration.zero,
    );
    await av.fetchDailyHistory('IBM');
    expect(seen.url.queryParameters['outputsize'], 'compact');
    expect(seen.url.queryParameters['function'], 'TIME_SERIES_DAILY');
    expect(seen.url.queryParameters.containsKey('apikey'), isTrue);

    late http.Request premiumSeen;
    final premiumClient = MockClient((request) async {
      premiumSeen = request;
      return http.Response(
        jsonEncode(_alphaVantageDaily({
          '2026-09-01': '10.00',
          '2026-09-02': '11.00',
        })),
        200,
      );
    });
    await AlphaVantageHistoryClient(
      apiKey: 'test-av-key',
      client: premiumClient,
      premium: true,
      minRequestGap: Duration.zero,
    ).fetchDailyHistory('IBM');
    expect(premiumSeen.url.queryParameters['outputsize'], 'full');
  });

  test('per-minute Information does not stamp empty history as a miss',
      () async {
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        throw http.ClientException('Failed to fetch', request.url);
      }
      if (request.url.host.contains('alphavantage')) {
        return http.Response(
          jsonEncode({
            'Information':
                'Thank you for using Alpha Vantage! Our standard API rate limit is 25 requests per day and 5 requests per minute.',
          }),
          200,
        );
      }
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
    final composite = CompositeQuoteClient(
      yahoo: YahooQuoteClient(client: client),
      finnhub: FinnhubQuoteClient(token: 'free-token', client: client),
      alphaVantage: AlphaVantageHistoryClient(
        apiKey: 'test-av-key',
        client: client,
        minRequestGap: Duration.zero,
      ),
    );
    final bundle = await composite.fetchChart('SMTC');
    expect(bundle.quote.source, 'finnhub');
    expect(bundle.history, isEmpty);
    expect(
      bundle.quote.historyFetchedAt[QuoteHistoryRange.oneMonth.key],
      isNull,
    );
  });

  test('daily-quota Information stays stamped and skips a second ticker HTTP',
      () async {
    var avHits = 0;
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        throw http.ClientException('Failed to fetch', request.url);
      }
      if (request.url.host.contains('alphavantage')) {
        avHits++;
        return http.Response(
          jsonEncode({
            'Information':
                'Thank you for using Alpha Vantage! Our standard API rate limit is 25 requests per day. Please subscribe to remove all daily rate limits.',
          }),
          200,
        );
      }
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
    final av = AlphaVantageHistoryClient(
      apiKey: 'test-av-key',
      client: client,
      minRequestGap: Duration.zero,
    );
    final composite = CompositeQuoteClient(
      yahoo: YahooQuoteClient(client: client),
      finnhub: FinnhubQuoteClient(token: 'free-token', client: client),
      alphaVantage: av,
    );
    final first = await composite.fetchChart('SMTC');
    expect(
      first.quote.historyFetchedAt[QuoteHistoryRange.oneMonth.key],
      isNotNull,
    );
    expect(avHits, 1);
    final second = await composite.fetchChart('AAPL');
    expect(avHits, 1);
    expect(
      second.quote.historyFetchedAt[QuoteHistoryRange.oneMonth.key],
      isNotNull,
    );
  });

  test('Alpha Vantage spaces history fetches for different tickers', () async {
    final clock = _FakeClock(DateTime.utc(2026, 9, 2, 12));
    final startedAt = <DateTime>[];
    final client = MockClient((request) async {
      startedAt.add(clock.now());
      final symbol = request.url.queryParameters['symbol']!;
      return http.Response(
        jsonEncode(_alphaVantageDaily({
          '2026-09-01': '10.00',
          '2026-09-02': symbol == 'AAPL' ? '11.00' : '12.00',
        })),
        200,
      );
    });
    final av = AlphaVantageHistoryClient(
      apiKey: 'test-av-key',
      client: client,
      minRequestGap: const Duration(milliseconds: 40),
      clock: clock.now,
      delay: clock.delay,
    );
    await av.fetchDailyHistory('AAPL');
    await av.fetchDailyHistory('MSFT');
    expect(startedAt, hasLength(2));
    expect(
      startedAt[1].difference(startedAt[0]) >= const Duration(milliseconds: 40),
      isTrue,
    );
  });

  test('Twelve Data parser reads demo-like AAPL values oldest-first', () {
    final points = TwelveDataHistoryClient.parseTimeSeries({
      'meta': {'symbol': 'AAPL', 'interval': '1day'},
      'values': [
        {'datetime': '2026-09-02', 'close': '132.27'},
        {'datetime': '2026-08-03 15:59:00', 'close': '110.00'},
        {'datetime': '2026-07-01', 'close': '100.50'},
      ],
      'status': 'ok',
    });
    expect(points, hasLength(3));
    expect(points.first.date, DateTime.utc(2026, 7, 1));
    expect(points.first.close, closeTo(100.50, 0.0001));
    expect(points.last.close, closeTo(132.27, 0.0001));
  });

  test('Twelve Data 401 and status=error are no history', () async {
    expect(
      TwelveDataHistoryClient.parseTimeSeries({
        'code': 401,
        'message': 'Invalid API key.',
        'status': 'error',
      }),
      isEmpty,
    );
    expect(
      TwelveDataHistoryClient.parseTimeSeries({
        'code': 400,
        'message': '**symbol** or **figi** parameter is missing or invalid.',
        'status': 'error',
      }),
      isEmpty,
    );

    final unauthorized = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'code': 401,
          'message': 'Invalid API key.',
          'status': 'error',
        }),
        401,
      );
    });
    expect(
      () => TwelveDataHistoryClient(
        apiKey: 'test-td-key',
        client: unauthorized,
        minRequestGap: Duration.zero,
      ).fetchDailyHistory('SMTC'),
      throwsA(isA<StateError>()),
    );

    final unknown = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'code': 400,
          'message': '**symbol** or **figi** parameter is missing or invalid.',
          'status': 'error',
        }),
        200,
      );
    });
    expect(
      () => TwelveDataHistoryClient(
        apiKey: 'test-td-key',
        client: unknown,
        minRequestGap: Duration.zero,
      ).fetchDailyHistory('UNKNOWN'),
      throwsA(isA<StateError>()),
    );
  });

  test('Twelve Data history URL uses interval=1day and outputsize=100',
      () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode(_twelveDataDaily('AAPL', {
          '2026-09-01': '10.00',
          '2026-09-02': '11.00',
        })),
        200,
      );
    });
    await TwelveDataHistoryClient(
      apiKey: 'test-td-key',
      client: client,
      minRequestGap: Duration.zero,
    ).fetchDailyHistory('aapl');
    expect(seen.url.host, 'api.twelvedata.com');
    expect(seen.url.path, '/time_series');
    expect(seen.url.queryParameters['symbol'], 'AAPL');
    expect(seen.url.queryParameters['interval'], '1day');
    expect(seen.url.queryParameters['outputsize'], '100');
    expect(seen.url.queryParameters['apikey'], 'test-td-key');
    expect(
      TwelveDataHistoryClient.defaultMinRequestGap,
      const Duration(seconds: 8),
    );
  });

  test('empty baked Twelve Data key does not construct a client', () {
    expect(
      createTwelveDataHistoryClient(userToken: null, bakedToken: ''),
      isNull,
    );
    expect(
      createTwelveDataHistoryClient(userToken: '  ', bakedToken: '   '),
      isNull,
    );
    final composite = CompositeQuoteClient.fromTokens(
      yahoo: YahooQuoteClient(),
      userToken: null,
      bakedToken: '',
      alphaVantageUserToken: null,
      alphaVantageBakedToken: '',
      twelveDataUserToken: null,
      twelveDataBakedToken: '',
    );
    expect(composite.twelveData, isNull);
  });

  test('user-saved Twelve Data key overrides baked key', () {
    final client = createTwelveDataHistoryClient(
      userToken: '  user-td-key  ',
      bakedToken: 'baked-td-key',
    );
    expect(client, isA<TwelveDataHistoryClient>());
    expect(client!.apiKey, 'user-td-key');

    final emptyUserFallsBack = createTwelveDataHistoryClient(
      userToken: '',
      bakedToken: 'baked-td-key',
    );
    expect(emptyUserFallsBack!.apiKey, 'baked-td-key');
  });

  test(
      'Finnhub candle 403 and Alpha Vantage Information then Twelve Data history',
      () async {
    final now = DateTime.now().toUtc();
    final tdBody = _twelveDataDaily('SMTC', {
      _ymd(now.subtract(const Duration(days: 20))): '110.00',
      _ymd(now.subtract(const Duration(days: 10))): '120.00',
      _ymd(now.subtract(const Duration(days: 1))): '130.00',
      _ymd(now): '132.27',
    });
    var avHits = 0;
    var tdHits = 0;
    var candleHits = 0;
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        throw http.ClientException('Failed to fetch', request.url);
      }
      if (request.url.host.contains('alphavantage')) {
        avHits++;
        return http.Response(
          jsonEncode({
            'Information':
                'This is a premium endpoint. Please subscribe to any of the premium plans.',
          }),
          200,
        );
      }
      if (request.url.host.contains('twelvedata')) {
        tdHits++;
        expect(request.url.path, '/time_series');
        expect(request.url.queryParameters['interval'], '1day');
        expect(request.url.queryParameters['outputsize'], '100');
        expect(request.url.queryParameters['symbol'], 'SMTC');
        expect(request.url.queryParameters['apikey'], 'test-td-key');
        return http.Response(jsonEncode(tdBody), 200);
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
      alphaVantage: AlphaVantageHistoryClient(
        apiKey: 'test-av-key',
        client: client,
        minRequestGap: Duration.zero,
      ),
      twelveData: TwelveDataHistoryClient(
        apiKey: 'test-td-key',
        client: client,
        minRequestGap: Duration.zero,
      ),
    );
    final bundle = await composite.fetchChart('SMTC');
    expect(bundle.quote.source, 'finnhub');
    expect(bundle.quote.price, closeTo(132.27, 0.0001));
    expect(bundle.history.length, greaterThanOrEqualTo(2));
    expect(bundle.history.last.close, closeTo(132.27, 0.0001));
    expect(bundle.quote.history[QuoteHistoryRange.oneYear.key], isNotEmpty);
    expect(avHits, 1);
    expect(tdHits, 1);
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
    expect(tdHits, 1);
    expect(yearBundle.history.length, greaterThanOrEqualTo(2));
    expect(candleHits, 1);
  });

  test('Yahoo success does not call Twelve Data', () async {
    var tdHits = 0;
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        return http.Response(jsonEncode(yahooChart), 200);
      }
      tdHits++;
      return http.Response('nope', 500);
    });
    final composite = CompositeQuoteClient(
      yahoo: YahooQuoteClient(client: client),
      finnhub: FinnhubQuoteClient(token: 'unused', client: client),
      twelveData: TwelveDataHistoryClient(
        apiKey: 'test-td-key',
        client: client,
        minRequestGap: Duration.zero,
      ),
    );
    final bundle = await composite.fetchChart('AAPL');
    expect(bundle.quote.source, 'yahoo');
    expect(tdHits, 0);
  });

  test('Alpha Vantage success does not call Twelve Data', () async {
    final now = DateTime.now().toUtc();
    var tdHits = 0;
    final client = MockClient((request) async {
      if (request.url.host.contains('yahoo')) {
        throw http.ClientException('Failed to fetch', request.url);
      }
      if (request.url.host.contains('alphavantage')) {
        return http.Response(
          jsonEncode(_alphaVantageDaily({
            _ymd(now.subtract(const Duration(days: 10))): '120.00',
            _ymd(now): '132.27',
          })),
          200,
        );
      }
      if (request.url.host.contains('twelvedata')) {
        tdHits++;
        return http.Response('nope', 500);
      }
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
    final composite = CompositeQuoteClient(
      yahoo: YahooQuoteClient(client: client),
      finnhub: FinnhubQuoteClient(token: 'free-token', client: client),
      alphaVantage: AlphaVantageHistoryClient(
        apiKey: 'test-av-key',
        client: client,
        minRequestGap: Duration.zero,
      ),
      twelveData: TwelveDataHistoryClient(
        apiKey: 'test-td-key',
        client: client,
        minRequestGap: Duration.zero,
      ),
    );
    final bundle = await composite.fetchChart('SMTC');
    expect(bundle.history.length, greaterThanOrEqualTo(2));
    expect(tdHits, 0);
  });

  test('Twelve Data spaces history fetches for different tickers', () async {
    final clock = _FakeClock(DateTime.utc(2026, 9, 2, 12));
    final startedAt = <DateTime>[];
    final client = MockClient((request) async {
      startedAt.add(clock.now());
      final symbol = request.url.queryParameters['symbol']!;
      return http.Response(
        jsonEncode(_twelveDataDaily(symbol, {
          '2026-09-01': '10.00',
          '2026-09-02': symbol == 'AAPL' ? '11.00' : '12.00',
        })),
        200,
      );
    });
    final td = TwelveDataHistoryClient(
      apiKey: 'test-td-key',
      client: client,
      minRequestGap: const Duration(milliseconds: 40),
      clock: clock.now,
      delay: clock.delay,
    );
    await td.fetchDailyHistory('AAPL');
    await td.fetchDailyHistory('MSFT');
    expect(startedAt, hasLength(2));
    expect(
      startedAt[1].difference(startedAt[0]) >= const Duration(milliseconds: 40),
      isTrue,
    );
  });

  test('Twelve Data cache key trims ticker whitespace', () async {
    var hits = 0;
    final client = MockClient((request) async {
      hits++;
      final symbol = request.url.queryParameters['symbol']!;
      expect(symbol, 'AAPL');
      return http.Response(
        jsonEncode(_twelveDataDaily(symbol, {
          '2026-09-01': '10.00',
          '2026-09-02': '11.00',
        })),
        200,
      );
    });
    final td = TwelveDataHistoryClient(
      apiKey: 'test-td-key',
      client: client,
      minRequestGap: Duration.zero,
    );
    await td.fetchDailyHistory(' aapl ');
    await td.fetchDailyHistory('AAPL');
    expect(hits, 1);
  });
}

class _FakeClock {
  _FakeClock(this._now);

  DateTime _now;

  DateTime now() => _now;

  Future<void> delay(Duration duration) async {
    _now = _now.add(duration);
  }
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

Map<String, dynamic> _twelveDataDaily(
  String symbol,
  Map<String, String> closesByDate,
) {
  final newestFirst = closesByDate.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return {
    'meta': {'symbol': symbol, 'interval': '1day'},
    'values': [
      for (final e in newestFirst) {'datetime': e.key, 'close': e.value},
    ],
    'status': 'ok',
  };
}
