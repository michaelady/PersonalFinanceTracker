import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/models.dart';
import '../../domain/services/portfolio_math.dart';

class TickerSearchResult {
  const TickerSearchResult({
    required this.symbol,
    required this.name,
    this.typeLabel,
    this.exchange,
  });

  final String symbol;
  final String name;
  final String? typeLabel;
  final String? exchange;
}

class QuoteBundle {
  const QuoteBundle({
    required this.quote,
    this.history = const [],
    this.range,
  });

  final CachedQuote quote;
  final List<PricePoint> history;
  final QuoteHistoryRange? range;
}

/// Market-data source. Implementations must not require a committed API key.
abstract class QuoteClient {
  Future<QuoteBundle> fetchChart(
    String symbol, {
    QuoteHistoryRange range = QuoteHistoryRange.oneMonth,
  });

  Future<List<TickerSearchResult>> search(String query);
}

/// Unofficial Yahoo Finance v8 chart + v1 search. No API key.
///
/// `/v7/finance/quote` is intentionally unused (429 / crumb auth).
class YahooQuoteClient implements QuoteClient {
  YahooQuoteClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const _headers = {
    'User-Agent': _userAgent,
    'Accept': 'application/json,text/plain,*/*',
  };

  @override
  Future<QuoteBundle> fetchChart(
    String symbol, {
    QuoteHistoryRange range = QuoteHistoryRange.oneMonth,
  }) async {
    final ticker = symbol.trim().toUpperCase();
    final uri = Uri.https(
      'query1.finance.yahoo.com',
      '/v8/finance/chart/$ticker',
      {'interval': '1d', 'range': range.key},
    );
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Yahoo chart HTTP ${response.statusCode} for $ticker');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseChart(json, ticker: ticker, range: range);
  }

  @override
  Future<List<TickerSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.https(
      'query1.finance.yahoo.com',
      '/v1/finance/search',
      {
        'q': q,
        'quotesCount': '8',
        'newsCount': '0',
        'listsCount': '0',
      },
    );
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Yahoo search HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseSearch(json);
  }

  static QuoteBundle parseChart(
    Map<String, dynamic> json, {
    required String ticker,
    required QuoteHistoryRange range,
    DateTime? fetchedAt,
  }) {
    final chart = json['chart'] as Map<String, dynamic>?;
    final error = chart?['error'];
    if (error != null) {
      throw StateError('Yahoo chart error for $ticker: $error');
    }
    final results = chart?['result'] as List?;
    if (results == null || results.isEmpty) {
      throw StateError('Yahoo chart empty for $ticker');
    }
    final result = results.first as Map<String, dynamic>;
    final meta = result['meta'] as Map<String, dynamic>? ?? const {};
    final price = (meta['regularMarketPrice'] as num?)?.toDouble();
    if (price == null) {
      throw StateError('Yahoo chart missing regularMarketPrice for $ticker');
    }
    final currency = (meta['currency'] as String?)?.toUpperCase() ?? 'USD';
    final changePct = (meta['regularMarketChangePercent'] as num?)?.toDouble();
    final previous = (meta['chartPreviousClose'] as num?)?.toDouble() ??
        (meta['previousClose'] as num?)?.toDouble();

    final timestamps = (result['timestamp'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const <int>[];
    final indicators = result['indicators'] as Map<String, dynamic>?;
    final quoteList = indicators?['quote'] as List?;
    final closes = quoteList != null && quoteList.isNotEmpty
        ? ((quoteList.first as Map<String, dynamic>)['close'] as List?)
        : null;
    final history = <PricePoint>[];
    if (closes != null) {
      final n = timestamps.length < closes.length ? timestamps.length : closes.length;
      for (var i = 0; i < n; i++) {
        final close = closes[i];
        if (close is num) {
          history.add(
            PricePoint(
              date: DateTime.fromMillisecondsSinceEpoch(
                timestamps[i] * 1000,
                isUtc: true,
              ),
              close: close.toDouble(),
            ),
          );
        }
      }
    }

    final at = fetchedAt ?? DateTime.now().toUtc();
    final quote = CachedQuote(
      symbol: (meta['symbol'] as String?)?.toUpperCase() ?? ticker,
      price: price,
      currency: currency,
      fetchedAt: at,
      source: 'yahoo',
      changePercent: changePct,
      previousClose: previous,
      history: {range.key: history},
      historyFetchedAt: {range.key: at},
    );
    return QuoteBundle(quote: quote, history: history, range: range);
  }

  static List<TickerSearchResult> parseSearch(Map<String, dynamic> json) {
    final quotes = json['quotes'] as List? ?? const [];
    final out = <TickerSearchResult>[];
    for (final raw in quotes) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final symbol = (map['symbol'] as String?)?.trim();
      if (symbol == null || symbol.isEmpty) continue;
      final name = (map['shortname'] as String?)?.trim() ??
          (map['longname'] as String?)?.trim() ??
          symbol;
      out.add(
        TickerSearchResult(
          symbol: symbol.toUpperCase(),
          name: name,
          typeLabel: map['quoteType'] as String? ?? map['typeDisp'] as String?,
          exchange: map['exchDisp'] as String? ?? map['exchange'] as String?,
        ),
      );
    }
    return out;
  }
}

/// Finnhub quote + candle. Requires a **user-provided** free token (local only).
class FinnhubQuoteClient implements QuoteClient {
  FinnhubQuoteClient({
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String token;
  final http.Client _client;

  @override
  Future<QuoteBundle> fetchChart(
    String symbol, {
    QuoteHistoryRange range = QuoteHistoryRange.oneMonth,
  }) async {
    final ticker = symbol.trim().toUpperCase();
    final quoteUri = Uri.https('finnhub.io', '/api/v1/quote', {
      'symbol': ticker,
      'token': token,
    });
    final quoteRes = await _client
        .get(quoteUri)
        .timeout(const Duration(seconds: 10));
    if (quoteRes.statusCode != 200) {
      throw StateError('Finnhub quote HTTP ${quoteRes.statusCode} for $ticker');
    }
    final quoteJson = jsonDecode(quoteRes.body) as Map<String, dynamic>;
    final parsed = parseQuote(quoteJson, ticker: ticker);
    final history = await _fetchCandle(ticker, range);
    final at = parsed.fetchedAt;
    return QuoteBundle(
      quote: parsed.copyWith(
        history: {range.key: history},
        historyFetchedAt: {range.key: at},
      ),
      history: history,
      range: range,
    );
  }

  Future<List<PricePoint>> _fetchCandle(
    String ticker,
    QuoteHistoryRange range,
  ) async {
    final to = DateTime.now().toUtc();
    final from = to.subtract(range.lookback);
    final uri = Uri.https('finnhub.io', '/api/v1/stock/candle', {
      'symbol': ticker,
      'resolution': 'D',
      'from': '${from.millisecondsSinceEpoch ~/ 1000}',
      'to': '${to.millisecondsSinceEpoch ~/ 1000}',
      'token': token,
    });
    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return parseCandle(json);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<TickerSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.https('finnhub.io', '/api/v1/search', {
      'q': q,
      'token': token,
    });
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Finnhub search HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseSearch(json);
  }

  static CachedQuote parseQuote(
    Map<String, dynamic> json, {
    required String ticker,
    String currency = 'USD',
    DateTime? fetchedAt,
  }) {
    final price = (json['c'] as num?)?.toDouble() ?? 0;
    final previous = (json['pc'] as num?)?.toDouble();
    final changePct = (json['dp'] as num?)?.toDouble();
    if (price == 0 && (previous == null || previous == 0)) {
      throw StateError('Finnhub returned no price for $ticker');
    }
    final at = fetchedAt ?? DateTime.now().toUtc();
    return CachedQuote(
      symbol: ticker,
      price: price,
      currency: currency,
      fetchedAt: at,
      source: 'finnhub',
      changePercent: changePct,
      previousClose: previous,
    );
  }

  static List<PricePoint> parseCandle(Map<String, dynamic> json) {
    if (json['s'] != 'ok') return const [];
    final closes = json['c'] as List? ?? const [];
    final times = json['t'] as List? ?? const [];
    final n = closes.length < times.length ? closes.length : times.length;
    final out = <PricePoint>[];
    for (var i = 0; i < n; i++) {
      final close = closes[i];
      final t = times[i];
      if (close is num && t is num) {
        out.add(
          PricePoint(
            date: DateTime.fromMillisecondsSinceEpoch(
              t.toInt() * 1000,
              isUtc: true,
            ),
            close: close.toDouble(),
          ),
        );
      }
    }
    return out;
  }

  static List<TickerSearchResult> parseSearch(Map<String, dynamic> json) {
    final result = json['result'] as List? ?? const [];
    final out = <TickerSearchResult>[];
    for (final raw in result.take(8)) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final symbol = (map['symbol'] as String?)?.trim() ??
          (map['displaySymbol'] as String?)?.trim();
      if (symbol == null || symbol.isEmpty) continue;
      out.add(
        TickerSearchResult(
          symbol: symbol.toUpperCase(),
          name: (map['description'] as String?)?.trim().isNotEmpty == true
              ? map['description'] as String
              : symbol,
          typeLabel: map['type'] as String?,
        ),
      );
    }
    return out;
  }
}

/// Try Yahoo first (native Android/Windows). On failure, Finnhub if a token
/// was provided. Never uses a CORS proxy.
class CompositeQuoteClient implements QuoteClient {
  CompositeQuoteClient({
    required this.yahoo,
    this.finnhub,
  });

  final QuoteClient yahoo;
  final QuoteClient? finnhub;

  @override
  Future<QuoteBundle> fetchChart(
    String symbol, {
    QuoteHistoryRange range = QuoteHistoryRange.oneMonth,
  }) async {
    try {
      return await yahoo.fetchChart(symbol, range: range);
    } catch (yahooError) {
      final fallback = finnhub;
      if (fallback == null) rethrow;
      try {
        return await fallback.fetchChart(symbol, range: range);
      } catch (finnhubError) {
        throw StateError(
          'Yahoo failed ($yahooError); Finnhub failed ($finnhubError)',
        );
      }
    }
  }

  @override
  Future<List<TickerSearchResult>> search(String query) async {
    try {
      final results = await yahoo.search(query);
      if (results.isNotEmpty) return results;
      final fallback = finnhub;
      if (fallback == null) return results;
      return await fallback.search(query);
    } catch (_) {
      final fallback = finnhub;
      if (fallback == null) rethrow;
      return await fallback.search(query);
    }
  }
}
