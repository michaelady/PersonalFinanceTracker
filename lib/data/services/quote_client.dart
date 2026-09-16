import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/models.dart';
import '../../domain/services/portfolio_math.dart';
import '../../domain/services/yahoo_lots_csv.dart';


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
      {
        'interval': '1d',
        // Always pull a year so 1M/3M/1Y are sliced from local history.
        'range': QuoteHistoryRange.oneYear.key,
      },
    );
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Yahoo chart HTTP ${response.statusCode} for $ticker');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final parsed = parseChart(
      json,
      ticker: ticker,
      range: QuoteHistoryRange.oneYear,
    );
    final sliced = PortfolioMath.storedHistoryForRange(parsed.quote, range);
    return QuoteBundle(
      quote: parsed.quote,
      history: sliced.length >= 2 ? sliced : parsed.history,
      range: range,
    );
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
    final changePct = _metaNum(meta, 'regularMarketChangePercent') ??
        _metaNum(meta, 'fulldayChangePercent');

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
        if (close is num && close.toDouble() > 0) {
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
    // `chartPreviousClose` is the first bar of `range` (e.g. ~1 month ago on
    // 1mo), not yesterday. Using it as "day" previous close flips the sign
    // whenever the book is up over the range and down today.
    final previous = sessionPreviousCloseFromMeta(
      meta,
      price: price,
      history: history,
      fetchedAt: at,
    );
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

  /// Yesterday / last regular session close from a v8 chart payload.
  ///
  /// Never returns `chartPreviousClose` — that field is the close before the
  /// requested chart range, so a 1mo fetch yields ~last month, not last session.
  static double? sessionPreviousCloseFromMeta(
    Map<String, dynamic> meta, {
    required double price,
    List<PricePoint> history = const [],
    DateTime? fetchedAt,
  }) {
    final regularPrev = _metaNum(meta, 'regularMarketPreviousClose');
    if (regularPrev != null && regularPrev > 0) return regularPrev;

    final chartPrev = _metaNum(meta, 'chartPreviousClose');
    final listedPrev = _metaNum(meta, 'previousClose');
    if (listedPrev != null &&
        listedPrev > 0 &&
        (chartPrev == null ||
            !PortfolioMath.nearlySamePrice(listedPrev, chartPrev))) {
      return listedPrev;
    }

    final change =
        _metaNum(meta, 'regularMarketChange') ?? _metaNum(meta, 'fulldayChange');
    if (change != null) {
      final implied = price - change;
      if (implied > 0) return implied;
    }

    final pct = _metaNum(meta, 'regularMarketChangePercent') ??
        _metaNum(meta, 'fulldayChangePercent');
    final fromPct = PortfolioMath.previousCloseFromChangePercent(price, pct);
    if (fromPct != null) return fromPct;

    return PortfolioMath.previousCloseFromHistory(
      CachedQuote(
        symbol: (meta['symbol'] as String?)?.toUpperCase() ?? '',
        price: price,
        currency: 'USD',
        fetchedAt: fetchedAt ?? DateTime.now().toUtc(),
        source: 'yahoo',
        history: {
          if (history.length >= 2) QuoteHistoryRange.oneMonth.key: history,
        },
      ),
      now: fetchedAt,
    );
  }

  static double? _metaNum(Map<String, dynamic> meta, String key) {
    final value = meta[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
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
/// and Finnhub candles (or the quote itself) are unavailable. Last two daily
/// closes can fill last price + previous close when Finnhub returns 403.
///
/// Free keys only get `outputsize=compact` (~100 trading days). `full` (20y) is
/// premium-only. One compact series is cached and sliced for 1M/3M/1Y.
class AlphaVantageHistoryClient {
  AlphaVantageHistoryClient({
    required this.apiKey,
    http.Client? client,
    this.premium = false,
    this.minRequestGap = defaultMinRequestGap,
    DateTime Function()? clock,
    Future<void> Function(Duration duration)? delay,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now,
        _delay = delay ?? ((d) => Future<void>.delayed(d));

  /// Free plan: 5 history calls per minute. Space HTTP starts by 12s.
  static const defaultMinRequestGap = Duration(seconds: 12);

  /// Yahoo/Finnhub suffix → Alpha Vantage `TIME_SERIES_DAILY` suffix.
  ///
  /// Free Finnhub often 403s these (US quotes only). AV uses different
  /// exchange codes than Yahoo:
  /// - TSX `.TO` → `.TRT` (SHOP.TRT)
  /// - TSXV `.V` → `.TRV`
  /// - SIX Swiss `.SW` → `.SWI` (NESN.SWI)
  /// - LSE `.L` → `.LON`
  /// - Euronext Amsterdam `.AS` → `.AMS`
  ///
  /// Unlisted suffixes stay as-is (Twelve Data still uses the Yahoo form).
  static const yahooToAlphaVantageSuffix = {
    '.TO': '.TRT',
    '.SW': '.SWI',
    '.AS': '.AMS',
    '.L': '.LON',
    '.V': '.TRV',
  };

  static String symbolFor(String yahooOrFinnhub) {
    final s = yahooOrFinnhub.trim().toUpperCase();
    final suffixes = yahooToAlphaVantageSuffix.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final yahoo in suffixes) {
      if (s.endsWith(yahoo) && s.length > yahoo.length) {
        return '${s.substring(0, s.length - yahoo.length)}'
            '${yahooToAlphaVantageSuffix[yahoo]}';
      }
    }
    return s;
  }

  final String apiKey;
  final http.Client _client;

  /// When true, request `outputsize=full`. Default compact for free keys.
  final bool premium;
  final Duration minRequestGap;
  final DateTime Function() _clock;
  final Future<void> Function(Duration duration) _delay;
  final Map<String, _CachedDaily> _cache = {};
  final Map<String, Future<List<PricePoint>>> _inflight = {};
  DateTime? _lastRequestAt;
  Future<void>? _requestChain;
  DateTime? _dailyQuotaAt;

  /// One compact daily series per ticker (~100 trading days). Reused across
  /// 1M/3M. For 1Y, [fetchWeeklyHistory] is merged in so the year is covered
  /// on a free key (compact daily is only ~5 months).
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
    // Compact (~100 sessions) is enough to slice 1M/3M. Keep every bar so a
    // later weekly merge can fill the rest of the year.
    final points = parseDailySeries(json);
    if (points.length < 2) {
      throw StateError('Alpha Vantage returned no daily history for $ticker');
    }
    _cache[ticker] = _CachedDaily(DateTime.now().toUtc(), points);
    return points;
  }

  /// Compact weekly closes (~100 weeks). Combined with daily compact this
  /// covers a 1Y chart without `outputsize=full`.
  Future<List<PricePoint>> fetchWeeklyHistory(String symbol) {
    final ticker = 'W:${symbol.trim().toUpperCase()}';
    final cached = _cache[ticker];
    if (cached != null && PortfolioMath.quoteIsFresh(cached.at)) {
      return Future.value(cached.points);
    }
    final pending = _inflight[ticker];
    if (pending != null) return pending;
    final future = _downloadWeeklyHistory(symbol.trim().toUpperCase());
    _inflight[ticker] = future;
    return future.whenComplete(() => _inflight.remove(ticker));
  }

  Future<List<PricePoint>> _downloadWeeklyHistory(String ticker) async {
    _throwIfDailyQuotaBlocked();
    await _awaitRequestGap();
    _throwIfDailyQuotaBlocked();
    final uri = Uri.https('www.alphavantage.co', '/query', {
      'function': 'TIME_SERIES_WEEKLY',
      'symbol': ticker,
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
    final points = parseWeeklySeries(json);
    if (points.length < 2) {
      throw StateError('Alpha Vantage returned no weekly history for $ticker');
    }
    _cache['W:$ticker'] = _CachedDaily(DateTime.now().toUtc(), points);
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
        final wait = minRequestGap - _clock().difference(last);
        if (wait > Duration.zero) {
          await _delay(wait);
        }
      }
      _lastRequestAt = _clock();
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
      if (date == null || close == null || close <= 0) continue;
      out.add(PricePoint(date: date, close: close));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    if (keep == null) return out;
    final cut = (now ?? DateTime.now()).toUtc().subtract(keep);
    return out.where((p) => !p.date.isBefore(cut)).toList();
  }

  static List<PricePoint> parseWeeklySeries(
    Map<String, dynamic> json, {
    Duration? keep,
    DateTime? now,
  }) {
    final blocked = json['Note'] ?? json['Information'] ?? json['Error Message'];
    if (blocked != null) {
      throw StateError('Alpha Vantage: $blocked');
    }
    final series = json['Weekly Time Series'] as Map<String, dynamic>?;
    if (series == null || series.isEmpty) return const [];
    final out = <PricePoint>[];
    for (final entry in series.entries) {
      final date = _parseUtcDate(entry.key);
      final close = _parseClose(entry.value);
      if (date == null || close == null || close <= 0) continue;
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

/// Compile-time Twelve Data key from `--dart-define=TWELVEDATA_API_KEY=...`.
/// Empty when the define is omitted. Never commit a real key.
const bakedTwelveDataApiKey = String.fromEnvironment(
  'TWELVEDATA_API_KEY',
  defaultValue: '',
);

/// User-saved token wins; otherwise the compile-time baked key.
String? resolveTwelveDataApiKey({
  String? userToken,
  String bakedToken = bakedTwelveDataApiKey,
}) {
  final user = userToken?.trim();
  if (user != null && user.isNotEmpty) return user;
  final baked = bakedToken.trim();
  if (baked.isNotEmpty) return baked;
  return null;
}

/// Builds a Twelve Data history client only when a non-empty key is available.
TwelveDataHistoryClient? createTwelveDataHistoryClient({
  String? userToken,
  String bakedToken = bakedTwelveDataApiKey,
  http.Client? client,
}) {
  final token = resolveTwelveDataApiKey(
    userToken: userToken,
    bakedToken: bakedToken,
  );
  if (token == null) return null;
  return TwelveDataHistoryClient(apiKey: token, client: client);
}

/// CORS-open daily history (`time_series`, `interval=1day`). Used on web after
/// Yahoo fails and Finnhub candles are unavailable. Not used for last price
/// when Finnhub's quote works.
///
/// Free plan is 8 requests/minute. HTTP starts are spaced by 8s. One series
/// (`outputsize=365`) is cached locally and sliced for 1M/3M/1Y.
class TwelveDataHistoryClient {
  TwelveDataHistoryClient({
    required this.apiKey,
    http.Client? client,
    this.minRequestGap = defaultMinRequestGap,
    DateTime Function()? clock,
    Future<void> Function(Duration duration)? delay,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now,
        _delay = delay ?? ((d) => Future<void>.delayed(d));

  /// Free plan: 8 history calls per minute. Space HTTP starts by 8s.
  static const defaultMinRequestGap = Duration(seconds: 8);

  final String apiKey;
  final http.Client _client;
  final Duration minRequestGap;
  final DateTime Function() _clock;
  final Future<void> Function(Duration duration) _delay;
  final Map<String, _CachedDaily> _cache = {};
  final Map<String, Future<List<PricePoint>>> _inflight = {};
  DateTime? _lastRequestAt;
  Future<void>? _requestChain;

  /// Trading days in a year, plus a few extra for holidays.
  static const yearOutputSize = '365';

  /// One daily series per ticker (~1 year). Reused across 1M/3M/1Y.
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
    await _awaitRequestGap();
    final uri = Uri.https('api.twelvedata.com', '/time_series', {
      'symbol': ticker,
      'interval': '1day',
      'outputsize': yearOutputSize,
      'apikey': apiKey,
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode == 401) {
      throw StateError('Twelve Data HTTP 401 for $ticker');
    }
    if (res.statusCode != 200) {
      throw StateError('Twelve Data HTTP ${res.statusCode} for $ticker');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final points = parseTimeSeries(json);
    if (points.length < 2) {
      throw StateError('Twelve Data returned no daily history for $ticker');
    }
    _cache[ticker] = _CachedDaily(DateTime.now().toUtc(), points);
    return points;
  }

  /// Serialize history GETs and space them by [minRequestGap] (8/min).
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
        final wait = minRequestGap - _clock().difference(last);
        if (wait > Duration.zero) {
          await _delay(wait);
        }
      }
      _lastRequestAt = _clock();
    } finally {
      starter.complete();
    }
  }

  /// `values[]` with `datetime` + `close`. `status=error` is no history.
  static List<PricePoint> parseTimeSeries(Map<String, dynamic> json) {
    if (json['status'] == 'error') return const [];
    final values = json['values'] as List?;
    if (values == null || values.isEmpty) return const [];
    final out = <PricePoint>[];
    for (final raw in values) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final date = _parseUtcDate(map['datetime']?.toString() ?? '');
      final close = _parseClose(map['close']);
      if (date == null || close == null || close <= 0) continue;
      out.add(PricePoint(date: date, close: close));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  static DateTime? _parseUtcDate(String raw) {
    final datePart = raw.trim().split(RegExp(r'[ T]')).first;
    final parts = datePart.split('-');
    if (parts.length < 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime.utc(y, m, d);
  }

  static double? _parseClose(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }
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
    final history = await _fetchCandle(ticker);
    final at = parsed.fetchedAt;
    return QuoteBundle(
      quote: parsed.copyWith(
        history: {
          if (history.length >= 2) QuoteHistoryRange.oneYear.key: history,
        },
        historyFetchedAt: {
          if (history.length >= 2) QuoteHistoryRange.oneYear.key: at,
        },
      ),
      history: history,
      range: range,
    );
  }

  Future<List<PricePoint>> _fetchCandle(String ticker) async {
    if (_candlesUnavailableOnPlan) return const [];
    final to = DateTime.now().toUtc();
    final from = to.subtract(QuoteHistoryRange.oneYear.lookback);
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
    final change = (json['d'] as num?)?.toDouble();
    final listedPrev = (json['pc'] as num?)?.toDouble();
    final changePct = (json['dp'] as num?)?.toDouble();
    if (price == 0 && (listedPrev == null || listedPrev == 0)) {
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
      previousClose: sessionPreviousCloseFromQuote(
        price: price,
        previousClose: listedPrev,
        change: change,
        changePercent: changePct,
      ),
    );
  }

  /// Finnhub `pc` is yesterday. Fall back to `c − d`, then percent-implied.
  /// Never uses a daily series (those may be Alpha Vantage / Yahoo 1M).
  static double? sessionPreviousCloseFromQuote({
    required double price,
    double? previousClose,
    double? change,
    double? changePercent,
  }) {
    if (previousClose != null && previousClose > 0) return previousClose;
    if (change != null) {
      final implied = price - change;
      if (implied > 0) return implied;
    }
    return PortfolioMath.previousCloseFromChangePercent(price, changePercent);
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
      if (close is num && t is num && close.toDouble() > 0) {
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

/// Keep daily history across refetches. Same-day bars from [bundle] win;
/// a shorter vendor series must not wipe a longer local year.
CachedQuote mergeFetchedQuote(CachedQuote? previous, QuoteBundle bundle) {
  final next = bundle.quote;
  if (previous == null) return next;
  if (previous.source != next.source) {
    // Keep the longer local year when only the last-price vendor flipped.
    final mergedHistory = <String, List<PricePoint>>{
      ...previous.history,
    };
    for (final e in next.history.entries) {
      mergedHistory[e.key] = PortfolioMath.mergePricePoints(
        mergedHistory[e.key] ?? const [],
        e.value,
      );
    }
    final fetched = {
      ...previous.historyFetchedAt,
      ...next.historyFetchedAt,
    };
    return next.copyWith(history: mergedHistory, historyFetchedAt: fetched);
  }
  final history = <String, List<PricePoint>>{...previous.history};
  for (final e in next.history.entries) {
    history[e.key] = PortfolioMath.mergePricePoints(
      history[e.key] ?? const [],
      e.value,
    );
  }
  final fetched = {...previous.historyFetchedAt, ...next.historyFetchedAt};
  final range = bundle.range;
  // A per-minute Alpha Vantage miss omits this range's stamp so retries are
  // not blocked for the whole quote TTL. Do not resurrect a previous stamp.
  if (range != null &&
      !next.historyFetchedAt.containsKey(range.key) &&
      (next.history[range.key]?.length ?? 0) < 2) {
    fetched.remove(range.key);
  }
  return next.copyWith(history: history, historyFetchedAt: fetched);
}

/// Thrown when every quote vendor failed for a ticker. [toString] is safe to
/// show on the Invest card (no Yahoo URL dump).
class QuoteUnavailable implements Exception {
  const QuoteUnavailable({
    required this.symbol,
    this.skippedYahoo = false,
    this.yahooError,
    this.finnhubError,
  });

  final String symbol;
  final bool skippedYahoo;
  final Object? yahooError;
  final Object? finnhubError;

  static bool isTorontoListing(String symbol) {
    final s = symbol.trim().toUpperCase();
    return s.endsWith('.TO') || s.endsWith('.V');
  }

  static bool isSwissListing(String symbol) {
    return symbol.trim().toUpperCase().endsWith('.SW');
  }

  /// Dotted Yahoo/Finnhub tickers (`.TO`, `.SW`, `.L`, …). Free Finnhub is
  /// US-only and typically 403s these.
  static bool isNonUsListing(String symbol) {
    final s = symbol.trim().toUpperCase();
    final dot = s.lastIndexOf('.');
    return dot > 0 && dot < s.length - 1;
  }

  /// Exchange name for Finnhub 403 copy when the suffix is a known package.
  static String? finnhubPackageLabel(String symbol) {
    final s = symbol.trim().toUpperCase();
    if (isTorontoListing(s)) return 'TSX';
    if (isSwissListing(s)) return 'SIX Swiss';
    if (s.endsWith('.L')) return 'LSE';
    if (s.endsWith('.AS')) return 'Euronext Amsterdam';
    return null;
  }

  static bool isYahooBrowserBlock(Object? error) {
    if (error == null) return false;
    final t = error.toString();
    return t.contains('Failed to fetch') &&
        (t.contains('yahoo') || t.contains('finance.yahoo.com'));
  }

  static bool isFinnhubQuoteForbidden(Object? error) {
    if (error == null) return false;
    return error.toString().contains('Finnhub quote HTTP 403');
  }

  /// Compact, user-facing copy for the portfolio card. Never names vendors,
  /// HTTP codes, or URLs — those belong in logs, not the GUI.
  static String shortMessage(Object error) {
    if (error is QuoteUnavailable) return error.toString();
    if (isFinnhubQuoteForbidden(error)) {
      return 'Live quotes for non-US listings are not included in the free '
          'market-data plan.';
    }
    return 'Live quotes are not available right now.';
  }

  @override
  String toString() {
    if (isFinnhubQuoteForbidden(finnhubError)) {
      final label = finnhubPackageLabel(symbol);
      if (label != null) {
        return 'Live quotes for $symbol ($label) are not included in the '
            'free market-data plan.';
      }
      if (isNonUsListing(symbol)) {
        return 'Live quotes for $symbol are not included in the free '
            'market-data plan (non-US listing).';
      }
    }
    return 'Live quotes for $symbol are not available right now.';
  }
}

/// Try Yahoo first (native Android/Windows). On failure, Finnhub quote (and
/// 1Y candles when the plan allows). If candles are missing, Twelve Data
/// daily (365 bars) is tried, then Alpha Vantage compact daily merged with
/// weekly so a free key can still fill a year. Never uses a CORS proxy.
class CompositeQuoteClient implements QuoteClient {
  CompositeQuoteClient({
    required this.yahoo,
    this.finnhub,
    this.alphaVantage,
    this.twelveData,
    this.skipYahoo = false,
  });

  /// Yahoo plus optional Finnhub / Alpha Vantage / Twelve Data. User-saved
  /// tokens override compile-time baked keys.
  factory CompositeQuoteClient.fromTokens({
    required QuoteClient yahoo,
    String? userToken,
    String bakedToken = bakedFinnhubApiKey,
    String? alphaVantageUserToken,
    String alphaVantageBakedToken = bakedAlphaVantageApiKey,
    String? twelveDataUserToken,
    String twelveDataBakedToken = bakedTwelveDataApiKey,
    http.Client? httpClient,
    bool skipYahoo = false,
  }) {
    return CompositeQuoteClient(
      yahoo: yahoo,
      skipYahoo: skipYahoo,
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
      twelveData: createTwelveDataHistoryClient(
        userToken: twelveDataUserToken,
        bakedToken: twelveDataBakedToken,
        client: httpClient,
      ),
    );
  }

  final QuoteClient yahoo;

  /// When true (GitHub Pages / Flutter web), do not call Yahoo. The v8 chart
  /// host sends no CORS headers; the browser surfaces `ClientException:
  /// Failed to fetch`. There is no Pages setting that can fix Yahoo's
  /// response, and this app does not use a CORS proxy.
  final bool skipYahoo;
  final QuoteClient? finnhub;
  final AlphaVantageHistoryClient? alphaVantage;
  final TwelveDataHistoryClient? twelveData;

  @override
  Future<QuoteBundle> fetchChart(
    String symbol, {
    QuoteHistoryRange range = QuoteHistoryRange.oneMonth,
  }) async {
    Object? yahooError;
    if (!skipYahoo) {
      try {
        return await yahoo.fetchChart(symbol, range: range);
      } catch (error) {
        yahooError = error;
      }
    }
    final fallback = finnhub;
    if (fallback != null) {
      try {
        final bundle = await fallback.fetchChart(symbol, range: range);
        return await _attachDailyHistory(bundle, symbol, range);
      } catch (finnhubError) {
        final daily = await _lastPriceFromDailyHistory(symbol, range);
        if (daily != null) return daily;
        throw QuoteUnavailable(
          symbol: symbol,
          skippedYahoo: skipYahoo,
          yahooError: yahooError,
          finnhubError: finnhubError,
        );
      }
    }
    final daily = await _lastPriceFromDailyHistory(symbol, range);
    if (daily != null) return daily;
    if (yahooError != null) throw yahooError;
    throw QuoteUnavailable(symbol: symbol, skippedYahoo: skipYahoo);
  }

  /// Finnhub last price is kept. Empty / 403 candles get a year of daily
  /// closes from Twelve Data, then Alpha Vantage daily (+ weekly when compact
  /// daily is shorter than 1Y).
  Future<QuoteBundle> _attachDailyHistory(
    QuoteBundle bundle,
    String symbol,
    QuoteHistoryRange range,
  ) async {
    if (PortfolioMath.historyCoversRange(
      bundle.quote,
      QuoteHistoryRange.oneYear,
    )) {
      return _withSlicedDailyHistory(
        bundle,
        range,
        bundle.quote.history[QuoteHistoryRange.oneYear.key] ?? bundle.history,
      );
    }

    var avPerMinute = false;
    List<PricePoint>? best = bundle.history.length >= 2 ? bundle.history : null;

    final td = twelveData;
    if (td != null) {
      try {
        final points = await td.fetchDailyHistory(symbol);
        if (_isLongerSeries(points, best)) best = points;
      } catch (_) {
        // Twelve Data 401 / status=error / empty series: try Alpha Vantage.
      }
    }

    if (!PortfolioMath.seriesCoversLookback(
      best ?? const [],
      QuoteHistoryRange.oneYear.lookback,
    )) {
      final av = alphaVantage;
      if (av != null) {
        try {
          final daily = await av.fetchDailyHistory(
            AlphaVantageHistoryClient.symbolFor(symbol),
          );
          var merged = daily;
          if (!PortfolioMath.seriesCoversLookback(
            daily,
            QuoteHistoryRange.oneYear.lookback,
          )) {
            try {
              final weekly = await av.fetchWeeklyHistory(
                AlphaVantageHistoryClient.symbolFor(symbol),
              );
              merged = PortfolioMath.mergeWeeklyBeforeDaily(weekly, daily);
            } catch (error) {
              if (AlphaVantageHistoryClient.isPerMinuteThrottleError(error)) {
                avPerMinute = true;
              }
            }
          }
          if (_isLongerSeries(merged, best)) best = merged;
        } catch (error) {
          if (AlphaVantageHistoryClient.isPerMinuteThrottleError(error)) {
            avPerMinute = true;
          }
        }
      }
    }

    if (best != null && best.length >= 2) {
      return _withSlicedDailyHistory(bundle, range, best);
    }

    final attemptedAt = DateTime.now().toUtc();
    if (avPerMinute) {
      // Do not stamp empty history as a successful miss — retry after the
      // 12s spacing window. Daily-quota errors keep Finnhub's stamp.
      final fetched = Map<String, DateTime>.from(bundle.quote.historyFetchedAt)
        ..remove(range.key)
        ..remove(QuoteHistoryRange.oneYear.key);
      return QuoteBundle(
        quote: bundle.quote.copyWith(historyFetchedAt: fetched),
        history: bundle.history,
        range: range,
      );
    }
    return QuoteBundle(
      quote: bundle.quote.copyWith(
        historyFetchedAt: {
          ...bundle.quote.historyFetchedAt,
          QuoteHistoryRange.oneYear.key: attemptedAt,
          range.key: attemptedAt,
        },
      ),
      history: bundle.history,
      range: range,
    );
  }

  static bool _isLongerSeries(List<PricePoint> candidate, List<PricePoint>? best) {
    if (candidate.length < 2) return false;
    if (best == null || best.length < 2) return true;
    final candSpan = candidate.last.date.difference(candidate.first.date);
    final bestSpan = best.last.date.difference(best.first.date);
    return candSpan > bestSpan ||
        (candSpan == bestSpan && candidate.length > best.length);
  }

  /// Last completed daily close as last price when Finnhub's quote 403s
  /// (typical for `.TO` / `.SW` on a free key). Not a live Yahoo session.
  Future<QuoteBundle?> _lastPriceFromDailyHistory(
    String symbol,
    QuoteHistoryRange range,
  ) async {
    final ticker = symbol.trim().toUpperCase();
    QuoteBundle? best;

    void consider(QuoteBundle? bundle) {
      if (bundle == null) return;
      if (best == null) {
        best = bundle;
        return;
      }
      final cand =
          bundle.quote.history[QuoteHistoryRange.oneYear.key] ?? bundle.history;
      final prev =
          best!.quote.history[QuoteHistoryRange.oneYear.key] ?? best!.history;
      if (_isLongerSeries(cand, prev)) best = bundle;
    }

    final td = twelveData;
    if (td != null) {
      try {
        consider(
          _quoteFromDailyCloses(
            ticker: ticker,
            range: range,
            year: await td.fetchDailyHistory(ticker),
            source: 'twelvedata',
          ),
        );
      } catch (_) {}
    }

    final av = alphaVantage;
    if (av != null &&
        !PortfolioMath.historyCoversRange(
          best?.quote,
          QuoteHistoryRange.oneYear,
        )) {
      try {
        final daily = await av.fetchDailyHistory(
          AlphaVantageHistoryClient.symbolFor(ticker),
        );
        var year = daily;
        if (!PortfolioMath.seriesCoversLookback(
          daily,
          QuoteHistoryRange.oneYear.lookback,
        )) {
          try {
            final weekly = await av.fetchWeeklyHistory(
              AlphaVantageHistoryClient.symbolFor(ticker),
            );
            year = PortfolioMath.mergeWeeklyBeforeDaily(weekly, daily);
          } catch (_) {}
        }
        consider(
          _quoteFromDailyCloses(
            ticker: ticker,
            range: range,
            year: year,
            source: 'alphavantage',
          ),
        );
      } catch (_) {}
    }
    return best;
  }

  QuoteBundle? _quoteFromDailyCloses({
    required String ticker,
    required QuoteHistoryRange range,
    required List<PricePoint> year,
    required String source,
  }) {
    if (year.length < 2) return null;
    final last = year.last;
    final prior = year[year.length - 2];
    if (last.close <= 0 || prior.close <= 0) return null;
    final at = DateTime.now().toUtc();
    final quote = CachedQuote(
      symbol: ticker,
      price: last.close,
      currency: YahooLotsCsv.currencyForSymbol(ticker, 'USD'),
      fetchedAt: at,
      source: source,
      previousClose: prior.close,
      changePercent: ((last.close - prior.close) / prior.close) * 100,
      history: {QuoteHistoryRange.oneYear.key: year},
      historyFetchedAt: {QuoteHistoryRange.oneYear.key: at},
    );
    return _withSlicedDailyHistory(
      QuoteBundle(
        quote: quote,
        history: year,
        range: QuoteHistoryRange.oneYear,
      ),
      range,
      year,
    );
  }

  QuoteBundle _withSlicedDailyHistory(
    QuoteBundle bundle,
    QuoteHistoryRange range,
    List<PricePoint> year,
  ) {
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
  }

  @override
  Future<List<TickerSearchResult>> search(String query) async {
    if (!skipYahoo) {
      try {
        final results = await yahoo.search(query);
        if (results.isNotEmpty) return results;
      } catch (_) {}
    }
    final fallback = finnhub;
    if (fallback != null) return await fallback.search(query);
    if (skipYahoo) return const [];
    return await yahoo.search(query);
  }
}
