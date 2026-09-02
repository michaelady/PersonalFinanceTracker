import 'dart:async';
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

/// Compile-time Finnhub key from `--dart-define=FINNHUB_API_KEY=...`.
/// Empty when the define is omitted. Never commit a real key.
const bakedFinnhubApiKey = String.fromEnvironment(
  'FINNHUB_API_KEY',
  defaultValue: '',
);

/// User-saved token wins; otherwise the compile-time baked key.
String? resolveFinnhubToken({
  String? userToken,
  String bakedToken = bakedFinnhubApiKey,
}) {
  final user = userToken?.trim();
  if (user != null && user.isNotEmpty) return user;
  final baked = bakedToken.trim();
  if (baked.isNotEmpty) return baked;
  return null;
}

/// Builds a Finnhub client only when a non-empty token is available.
FinnhubQuoteClient? createFinnhubQuoteClient({
  String? userToken,
  String bakedToken = bakedFinnhubApiKey,
  http.Client? client,
}) {
  final token = resolveFinnhubToken(
    userToken: userToken,
    bakedToken: bakedToken,
  );
  if (token == null) return null;
  return FinnhubQuoteClient(token: token, client: client);
}

/// Compile-time Alpha Vantage key from `--dart-define=ALPHAVANTAGE_API_KEY=...`.
/// Empty when the define is omitted. Never commit a real key.
const bakedAlphaVantageApiKey = String.fromEnvironment(
  'ALPHAVANTAGE_API_KEY',
  defaultValue: '',
);

/// User-saved token wins; otherwise the compile-time baked key.
String? resolveAlphaVantageApiKey({
  String? userToken,
  String bakedToken = bakedAlphaVantageApiKey,
}) {
  final user = userToken?.trim();
  if (user != null && user.isNotEmpty) return user;
  final baked = bakedToken.trim();
  if (baked.isNotEmpty) return baked;
  return null;
}

/// Builds an Alpha Vantage history client only when a non-empty key is available.
AlphaVantageHistoryClient? createAlphaVantageHistoryClient({
  String? userToken,
  String bakedToken = bakedAlphaVantageApiKey,
  http.Client? client,
}) {
  final token = resolveAlphaVantageApiKey(
    userToken: userToken,
    bakedToken: bakedToken,
  );
  if (token == null) return null;
  return AlphaVantageHistoryClient(apiKey: token, client: client);
}

/// Free-tier Alpha Vantage throttle kind parsed from `Note` / `Information`.
enum AlphaVantageThrottle {
  none,
  perMinute,
  dailyQuota,
}

/// CORS-open daily history (TIME_SERIES_DAILY). Used on web after Yahoo fails
/// and Finnhub candles are unavailable on the free plan. Not used for last price.
///
/// Free keys only get `outputsize=compact` (~100 trading days). `full` (20y) is
/// premium-only. One compact series is cached and sliced for 1M/3M/1Y.
class AlphaVantageHistoryClient {
  AlphaVantageHistoryClient({
    required this.apiKey,
    http.Client? client,
    this.premium = false,
    this.minRequestGap = defaultMinRequestGap,
  }) : _client = client ?? http.Client();

  /// Free plan: 5 history calls per minute. Space HTTP starts by 12s.
  static const defaultMinRequestGap = Duration(seconds: 12);

  final String apiKey;
  final http.Client _client;

  /// When true, request `outputsize=full`. Default compact for free keys.
  final bool premium;
  final Duration minRequestGap;
  final Map<String, _CachedDaily> _cache = {};
  final Map<String, Future<List<PricePoint>>> _inflight = {};
  DateTime? _lastRequestAt;
  Future<void>? _requestChain;
  DateTime? _dailyQuotaAt;

  /// One compact daily series per ticker (~100 trading days). Reused across
  /// 1M/3M/1Y — 1Y plots whatever compact returned, not a claimed 370-day pull.
  Future<List<PricePoint>> fetchDailyHistory(String symbol) {
    final ticker = symbol.trim().toUpperCase();
    final cached = _cache[ticker];
    if (cached != null && PortfolioMath.quoteIsFresh(cached.at)) {
      return Future.value(cached.points);
    }
    final pending = _inflight[ticker];
    if (pending != null) return pending;
    final future = _downloadDailyHistory(ticker);
    _inflight[ticker] = future;
    return future.whenComplete(() => _inflight.remove(ticker));
  }

  Future<List<PricePoint>> _downloadDailyHistory(String ticker) async {
    _throwIfDailyQuotaBlocked();
    await _awaitRequestGap();
    _throwIfDailyQuotaBlocked();
    final uri = Uri.https('www.alphavantage.co', '/query', {
      'function': 'TIME_SERIES_DAILY',
      'symbol': ticker,
      'outputsize': premium ? 'full' : 'compact',
      'apikey': apiKey,
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw StateError('Alpha Vantage HTTP ${res.statusCode} for $ticker');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final blocked = json['Note'] ?? json['Information'] ?? json['Error Message'];
    if (blocked != null) {
      final text = blocked.toString();
      if (classifyThrottle(text) == AlphaVantageThrottle.dailyQuota) {
        _dailyQuotaAt = DateTime.now().toUtc();
      }
      throw StateError('Alpha Vantage: $text');
    }
    // Compact (~100 sessions) is enough to slice 1M/3M; keep the whole series
    // for 1Y rather than trimming as if we downloaded 370 calendar days.
    final points = parseDailySeries(json);
    if (points.length < 2) {
      throw StateError('Alpha Vantage returned no daily history for $ticker');
    }
    _cache[ticker] = _CachedDaily(DateTime.now().toUtc(), points);
    return points;
  }

  void _throwIfDailyQuotaBlocked() {
    final at = _dailyQuotaAt;
    if (at != null && PortfolioMath.quoteIsFresh(at)) {
      throw StateError('Alpha Vantage: daily quota exhausted');
    }
  }

  /// Serialize history GETs and space them by [minRequestGap] (5/min).
  Future<void> _awaitRequestGap() async {
    final starter = Completer<void>();
    final previous = _requestChain;
    _requestChain = starter.future;
    try {
      if (previous != null) {
        await previous;
      }
      final last = _lastRequestAt;
      if (last != null && minRequestGap > Duration.zero) {
        final wait = minRequestGap - DateTime.now().difference(last);
        if (wait > Duration.zero) {
          await Future<void>.delayed(wait);
        }
      }
      _lastRequestAt = DateTime.now();
    } finally {
      starter.complete();
    }
  }

  /// Per-minute throttle must not be cached as empty history. Daily quota can.
  static AlphaVantageThrottle classifyThrottle(String message) {
    final t = message.toLowerCase();
    final perMinute = t.contains('per minute');
    final daily25 = t.contains('25 requests per day') ||
        t.contains('25 request per day') ||
        t.contains('25 api requests per day');
    final dailyWords = t.contains('daily rate limit') ||
        t.contains('daily quota') ||
        t.contains('requests per day') ||
        t.contains('calls per day');
    if (perMinute) return AlphaVantageThrottle.perMinute;
    if (daily25 || dailyWords) return AlphaVantageThrottle.dailyQuota;
    return AlphaVantageThrottle.none;
  }

  static bool isPerMinuteThrottleError(Object error) {
    final text = error is StateError ? error.message : error.toString();
    return classifyThrottle(text) == AlphaVantageThrottle.perMinute;
  }

  static List<PricePoint> parseDailySeries(
    Map<String, dynamic> json, {
    Duration? keep,
    DateTime? now,
  }) {
    final blocked = json['Note'] ?? json['Information'] ?? json['Error Message'];
    if (blocked != null) {
      throw StateError('Alpha Vantage: $blocked');
    }
    final series = json['Time Series (Daily)'] as Map<String, dynamic>?;
    if (series == null || series.isEmpty) return const [];
    final out = <PricePoint>[];
    for (final entry in series.entries) {
      final date = _parseUtcDate(entry.key);
      final close = _parseClose(entry.value);
      if (date == null || close == null) continue;
      out.add(PricePoint(date: date, close: close));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    if (keep == null) return out;
    final cut = (now ?? DateTime.now()).toUtc().subtract(keep);
    return out.where((p) => !p.date.isBefore(cut)).toList();
  }

  static DateTime? _parseUtcDate(String raw) {
    final parts = raw.split('-');
    if (parts.length < 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime.utc(y, m, d);
  }

  static double? _parseClose(dynamic raw) {
    if (raw is Map) {
      final value = raw['4. close'] ?? raw['4. Close'] ?? raw['close'];
      return _parseClose(value);
    }
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }
}

class _CachedDaily {
  const _CachedDaily(this.at, this.points);
  final DateTime at;
  final List<PricePoint> points;
}

/// Finnhub quote + candle. Token is user-provided (local only) or a
/// compile-time `--dart-define=FINNHUB_API_KEY` baked into a release build.
class FinnhubQuoteClient implements QuoteClient {
  FinnhubQuoteClient({
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String token;
  final http.Client _client;
  bool _candlesUnavailableOnPlan = false;

  /// Free Finnhub tokens can quote but not candles (HTTP 403).
  bool get candlesUnavailableOnPlan => _candlesUnavailableOnPlan;

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
    if (_candlesUnavailableOnPlan) return const [];
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
      if (isCandleAccessDenied(res.statusCode, res.body)) {
        // Quotes work on the free plan; candles do not. Not an offline failure.
        _candlesUnavailableOnPlan = true;
        return const [];
      }
      if (res.statusCode != 200) return const [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return parseCandle(json);
    } catch (_) {
      return const [];
    }
  }

  static bool isCandleAccessDenied(int statusCode, [String? body]) {
    if (statusCode == 401 || statusCode == 403) return true;
    final text = body ?? '';
    return text.contains("You don't have access to this resource");
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

/// Try Yahoo first (native Android/Windows). On failure, Finnhub quote (and
/// candles when the plan allows). If candles are missing, Alpha Vantage daily
/// history is the CORS-open web fallback. Never uses a CORS proxy.
class CompositeQuoteClient implements QuoteClient {
  CompositeQuoteClient({
    required this.yahoo,
    this.finnhub,
    this.alphaVantage,
  });

  /// Yahoo plus optional Finnhub / Alpha Vantage. User-saved tokens override
  /// compile-time baked keys.
  factory CompositeQuoteClient.fromTokens({
    required QuoteClient yahoo,
    String? userToken,
    String bakedToken = bakedFinnhubApiKey,
    String? alphaVantageUserToken,
    String alphaVantageBakedToken = bakedAlphaVantageApiKey,
    http.Client? httpClient,
  }) {
    return CompositeQuoteClient(
      yahoo: yahoo,
      finnhub: createFinnhubQuoteClient(
        userToken: userToken,
        bakedToken: bakedToken,
        client: httpClient,
      ),
      alphaVantage: createAlphaVantageHistoryClient(
        userToken: alphaVantageUserToken,
        bakedToken: alphaVantageBakedToken,
        client: httpClient,
      ),
    );
  }

  final QuoteClient yahoo;
  final QuoteClient? finnhub;
  final AlphaVantageHistoryClient? alphaVantage;

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
      final QuoteBundle bundle;
      try {
        bundle = await fallback.fetchChart(symbol, range: range);
      } catch (finnhubError) {
        throw StateError(
          'Yahoo failed ($yahooError); Finnhub failed ($finnhubError)',
        );
      }
      return _attachDailyHistory(bundle, symbol, range);
    }
  }

  /// Finnhub last price is kept. Empty / 403 candles get Alpha Vantage daily
  /// closes when a key is available (one compact series, sliced for 1M/3M).
  Future<QuoteBundle> _attachDailyHistory(
    QuoteBundle bundle,
    String symbol,
    QuoteHistoryRange range,
  ) async {
    if (bundle.history.length >= 2) return bundle;
    final av = alphaVantage;
    if (av == null) return bundle;
    try {
      final year = await av.fetchDailyHistory(symbol);
      final at = DateTime.now().toUtc();
      var quote = bundle.quote.copyWith(
        history: {
          ...bundle.quote.history,
          QuoteHistoryRange.oneYear.key: year,
        },
        historyFetchedAt: {
          ...bundle.quote.historyFetchedAt,
          QuoteHistoryRange.oneYear.key: at,
        },
      );
      final sliced = PortfolioMath.storedHistoryForRange(quote, range);
      if (sliced.length < 2) return bundle;
      quote = quote.copyWith(
        history: {
          ...quote.history,
          range.key: sliced,
        },
        historyFetchedAt: {
          ...quote.historyFetchedAt,
          range.key: at,
        },
      );
      return QuoteBundle(quote: quote, history: sliced, range: range);
    } catch (error) {
      if (AlphaVantageHistoryClient.isPerMinuteThrottleError(error)) {
        // Do not stamp empty history as a successful miss — retry after the
        // 12s spacing window. Daily-quota errors keep Finnhub's stamp.
        final fetched = Map<String, DateTime>.from(bundle.quote.historyFetchedAt)
          ..remove(range.key);
        return QuoteBundle(
          quote: bundle.quote.copyWith(historyFetchedAt: fetched),
          history: bundle.history,
          range: range,
        );
      }
      return bundle;
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
