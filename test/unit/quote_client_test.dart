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
}
