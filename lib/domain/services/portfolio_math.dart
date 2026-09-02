import '../models/models.dart';
import 'money_math.dart';

enum QuoteHistoryRange {
  oneMonth('1mo', Duration(days: 32), '1M'),
  threeMonths('3mo', Duration(days: 96), '3M'),
  oneYear('1y', Duration(days: 370), '1Y');

  const QuoteHistoryRange(this.key, this.lookback, this.chartLabel);
  final String key;
  final Duration lookback;
  final String chartLabel;
}

class HoldingValuation {
  const HoldingValuation({
    required this.holding,
    required this.costNative,
    required this.costMain,
    required this.quoteCurrency,
    this.lastPrice,
    this.quotedAt,
    this.quoteSource,
    this.marketNative,
    this.marketMain,
    this.unrealizedPlMain,
    this.unrealizedPlPercent,
    this.dayChangeMain,
    this.dayChangePercent,
    this.allocationPercent = 0,
  });

  final InvestmentHolding holding;
  final double costNative;
  final double costMain;
  final String quoteCurrency;
  final double? lastPrice;
  final DateTime? quotedAt;
  final String? quoteSource;
  final double? marketNative;
  final double? marketMain;
  final double? unrealizedPlMain;
  final double? unrealizedPlPercent;
  final double? dayChangeMain;
  final double? dayChangePercent;
  final double allocationPercent;

  /// Market value when a quote exists, otherwise cost — used for net worth.
  double get valueForNetWorthMain => marketMain ?? costMain;

  HoldingValuation withAllocation(double percent) {
    return HoldingValuation(
      holding: holding,
      costNative: costNative,
      costMain: costMain,
      quoteCurrency: quoteCurrency,
      lastPrice: lastPrice,
      quotedAt: quotedAt,
      quoteSource: quoteSource,
      marketNative: marketNative,
      marketMain: marketMain,
      unrealizedPlMain: unrealizedPlMain,
      unrealizedPlPercent: unrealizedPlPercent,
      dayChangeMain: dayChangeMain,
      dayChangePercent: dayChangePercent,
      allocationPercent: percent,
    );
  }
}

class PortfolioTotals {
  const PortfolioTotals({
    required this.holdings,
    required this.costMain,
    required this.marketMain,
    required this.netWorthMain,
    this.unrealizedPlMain,
    this.unrealizedPlPercent,
    this.dayChangeMain,
    this.quotedAt,
    this.quoteSource,
    this.usedCachedQuotes = false,
  });

  final List<HoldingValuation> holdings;
  final double costMain;
  final double marketMain;
  final double netWorthMain;
  final double? unrealizedPlMain;
  final double? unrealizedPlPercent;
  final double? dayChangeMain;
  final DateTime? quotedAt;
  final String? quoteSource;
  final bool usedCachedQuotes;
}

/// Pure portfolio calculations — unit-tested, no Flutter / network.
abstract final class PortfolioMath {
  static const quoteCacheTtl = Duration(minutes: 5);

  static bool quoteIsFresh(DateTime fetchedAt, {DateTime? now}) {
    final t = now ?? DateTime.now().toUtc();
    return t.difference(fetchedAt.toUtc()) <= quoteCacheTtl;
  }

  static double _rate(
    String currencyCode,
    String mainCurrency,
    List<CurrencyRate> rates,
  ) {
    if (currencyCode == mainCurrency) return 1;
    final match = rates.where((r) => r.code == currencyCode);
    if (match.isEmpty) return 1;
    return match.first.rateToMain;
  }

  static double toMain(
    double amount,
    String currencyCode,
    String mainCurrency,
    List<CurrencyRate> rates,
  ) {
    return amount * _rate(currencyCode, mainCurrency, rates);
  }

  static CachedQuote? quoteFor(
    InvestmentHolding holding,
    Map<String, CachedQuote> quotes,
  ) {
    return quotes[holding.ticker.toUpperCase()];
  }

  static HoldingValuation valueHolding({
    required InvestmentHolding holding,
    required Map<String, CachedQuote> quotes,
    required String mainCurrency,
    required List<CurrencyRate> rates,
  }) {
    final quote = quoteFor(holding, quotes);
    final costNative = holding.shares * holding.averageCostPerShare;
    final costMain = toMain(
      costNative,
      holding.currencyCode,
      mainCurrency,
      rates,
    );
    if (quote == null) {
      return HoldingValuation(
        holding: holding,
        costNative: costNative,
        costMain: costMain,
        quoteCurrency: holding.currencyCode,
      );
    }

    final marketNative = holding.shares * quote.price;
    final marketMain = toMain(
      marketNative,
      quote.currency,
      mainCurrency,
      rates,
    );
    final pl = marketMain - costMain;
    final plPct = costMain == 0 ? null : (pl / costMain) * 100;

    double? dayChangeNative;
    if (quote.previousClose != null) {
      dayChangeNative = holding.shares * (quote.price - quote.previousClose!);
    } else if (quote.changePercent != null) {
      final denom = 1 + (quote.changePercent! / 100);
      if (denom != 0) {
        final previous = quote.price / denom;
        dayChangeNative = holding.shares * (quote.price - previous);
      }
    }

    return HoldingValuation(
      holding: holding,
      costNative: costNative,
      costMain: costMain,
      quoteCurrency: quote.currency,
      lastPrice: quote.price,
      quotedAt: quote.fetchedAt,
      quoteSource: quote.source,
      marketNative: marketNative,
      marketMain: marketMain,
      unrealizedPlMain: pl,
      unrealizedPlPercent: plPct,
      dayChangeMain: dayChangeNative == null
          ? null
          : toMain(dayChangeNative, quote.currency, mainCurrency, rates),
      dayChangePercent: quote.changePercent,
    );
  }

  static PortfolioTotals summarize({
    required List<InvestmentHolding> holdings,
    required Map<String, CachedQuote> quotes,
    required String mainCurrency,
    required List<CurrencyRate> rates,
  }) {
    final valued = [
      for (final h in holdings)
        valueHolding(
          holding: h,
          quotes: quotes,
          mainCurrency: mainCurrency,
          rates: rates,
        ),
    ];

    final cost = valued.fold<double>(0, (s, v) => s + v.costMain);
    var marketKnown = 0.0;
    var hasMarket = false;
    var netWorth = 0.0;
    var day = 0.0;
    var hasDay = false;
    DateTime? latestQuote;
    String? source;

    for (final v in valued) {
      netWorth += v.valueForNetWorthMain;
      if (v.marketMain != null) {
        marketKnown += v.marketMain!;
        hasMarket = true;
      }
      if (v.dayChangeMain != null) {
        day += v.dayChangeMain!;
        hasDay = true;
      }
      if (v.quotedAt != null &&
          (latestQuote == null || v.quotedAt!.isAfter(latestQuote))) {
        latestQuote = v.quotedAt;
        source = v.quoteSource;
      }
    }

    final market = hasMarket ? marketKnown : cost;
    final pl = hasMarket ? market - cost : null;
    final plPct = (pl == null || cost == 0) ? null : (pl / cost) * 100;
    final totalForAlloc = valued.fold<double>(
      0,
      (s, v) => s + v.valueForNetWorthMain,
    );
    final withAlloc = [
      for (final v in valued)
        v.withAllocation(
          totalForAlloc <= 0
              ? 0
              : (v.valueForNetWorthMain / totalForAlloc) * 100,
        ),
    ]..sort(
        (a, b) => b.valueForNetWorthMain.compareTo(a.valueForNetWorthMain),
      );

    return PortfolioTotals(
      holdings: withAlloc,
      costMain: cost,
      marketMain: market,
      netWorthMain: netWorth,
      unrealizedPlMain: pl,
      unrealizedPlPercent: plPct,
      dayChangeMain: hasDay ? day : null,
      quotedAt: latestQuote,
      quoteSource: source,
      usedCachedQuotes: quotes.isNotEmpty,
    );
  }

  /// Holdings flagged [InvestmentHolding.includeInNetWorth], using last
  /// price when cached and cost otherwise.
  static double includedMarketValueMain({
    required List<InvestmentHolding> holdings,
    required Map<String, CachedQuote> quotes,
    required String mainCurrency,
    required List<CurrencyRate> rates,
  }) {
    return summarize(
      holdings: holdings.where((h) => h.includeInNetWorth).toList(),
      quotes: quotes,
      mainCurrency: mainCurrency,
      rates: rates,
    ).netWorthMain;
  }

  /// Daily closes stored on the quote, including a longer series sliced down.
  /// Does not invent a previous-close → last-price pair.
  static List<PricePoint> storedHistoryForRange(
    CachedQuote? quote,
    QuoteHistoryRange range, {
    DateTime? now,
  }) {
    if (quote == null) return const [];
    final points = quote.history[range.key];
    if (points != null && points.length >= 2) return points;
    final asOf = now ?? DateTime.now().toUtc();
    // A longer series can fill a shorter window.
    if (range != QuoteHistoryRange.oneYear) {
      final longer = quote.history[QuoteHistoryRange.oneYear.key];
      if (longer != null && longer.isNotEmpty) {
        final cut = asOf.subtract(range.lookback);
        final sliced = longer.where((p) => !p.date.isBefore(cut)).toList();
        if (sliced.length >= 2) return sliced;
      }
    }
    if (range == QuoteHistoryRange.oneMonth) {
      final q3 = quote.history[QuoteHistoryRange.threeMonths.key];
      if (q3 != null && q3.isNotEmpty) {
        final cut = asOf.subtract(range.lookback);
        final sliced = q3.where((p) => !p.date.isBefore(cut)).toList();
        if (sliced.length >= 2) return sliced;
      }
    }
    if (points != null && points.isNotEmpty) return points;
    return const [];
  }

  /// When daily history is missing, plot last session close vs last price.
  static List<PricePoint> twoPointFromQuote(
    CachedQuote quote, {
    DateTime? now,
  }) {
    final prev = quote.previousClose;
    if (prev == null || prev <= 0 || quote.price <= 0) return const [];
    final end = (now ?? quote.fetchedAt).toUtc();
    return [
      PricePoint(date: end.subtract(const Duration(days: 1)), close: prev),
      PricePoint(date: end, close: quote.price),
    ];
  }

  static bool usesLastCloseFallback(
    CachedQuote? quote,
    QuoteHistoryRange range, {
    DateTime? now,
  }) {
    if (quote == null) return false;
    return storedHistoryForRange(quote, range, now: now).length < 2 &&
        twoPointFromQuote(quote, now: now).length >= 2;
  }

  /// True when every quoted holding in [holdings] is using the two-point
  /// previous-close fallback rather than a daily series.
  static bool chartUsesLastCloseFallback({
    required List<InvestmentHolding> holdings,
    required Map<String, CachedQuote> quotes,
    required QuoteHistoryRange range,
    DateTime? now,
  }) {
    var any = false;
    for (final h in holdings) {
      final quote = quoteFor(h, quotes);
      if (quote == null) continue;
      any = true;
      if (!usesLastCloseFallback(quote, range, now: now)) return false;
    }
    return any;
  }

  static DateTime? historyFetchedAtForRange(
    CachedQuote quote,
    QuoteHistoryRange range,
  ) {
    final direct = quote.historyFetchedAt[range.key];
    if (direct != null) return direct;
    final year = quote.historyFetchedAt[QuoteHistoryRange.oneYear.key];
    if (year != null && range != QuoteHistoryRange.oneYear) return year;
    if (range == QuoteHistoryRange.oneMonth) {
      return quote.historyFetchedAt[QuoteHistoryRange.threeMonths.key];
    }
    return null;
  }

  static List<PricePoint> historyForRange(
    CachedQuote? quote,
    QuoteHistoryRange range, {
    DateTime? now,
  }) {
    final stored = storedHistoryForRange(quote, range, now: now);
    if (stored.length >= 2) return stored;
    if (quote == null) return stored;
    final fallback = twoPointFromQuote(quote, now: now);
    if (fallback.length >= 2) return fallback;
    return stored;
  }

  /// Lots that feed the performance chart. `null` [selectedHoldingId] is the
  /// full visible book; otherwise only that holding (empty if it is gone).
  static List<InvestmentHolding> holdingsForChart({
    required List<InvestmentHolding> visible,
    String? selectedHoldingId,
  }) {
    if (selectedHoldingId == null) return visible;
    return [
      for (final h in visible)
        if (h.id == selectedHoldingId) h,
    ];
  }

  /// Portfolio (or single holding) market value in main currency over time.
  /// Uses current FX rates as a bridge — not historical FX.
  static List<PricePoint> performanceSeries({
    required List<InvestmentHolding> holdings,
    required Map<String, CachedQuote> quotes,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    required QuoteHistoryRange range,
  }) {
    if (holdings.isEmpty) return const [];

    final seriesByTicker = <String, List<PricePoint>>{};
    final dates = <DateTime>{};
    for (final h in holdings) {
      final points = historyForRange(quoteFor(h, quotes), range);
      if (points.isEmpty) continue;
      seriesByTicker[h.ticker] = points;
      dates.addAll(points.map((p) => p.date));
    }
    if (dates.isEmpty) return const [];

    final ordered = dates.toList()..sort();
    final lastClose = <String, double>{};
    final out = <PricePoint>[];
    var dateIndex = {
      for (final e in seriesByTicker.entries) e.key: 0,
    };

    for (final day in ordered) {
      for (final h in holdings) {
        final series = seriesByTicker[h.ticker];
        if (series == null) continue;
        var i = dateIndex[h.ticker]!;
        while (i < series.length && !series[i].date.isAfter(day)) {
          lastClose[h.ticker] = series[i].close;
          i++;
        }
        dateIndex[h.ticker] = i;
      }
      var total = 0.0;
      var any = false;
      for (final h in holdings) {
        final close = lastClose[h.ticker];
        if (close == null) continue;
        final quote = quoteFor(h, quotes);
        final currency = quote?.currency ?? h.currencyCode;
        total += toMain(h.shares * close, currency, mainCurrency, rates);
        any = true;
      }
      if (any) {
        out.add(PricePoint(date: day, close: total));
      }
    }
    return out;
  }

  /// Re-export so tests can use the same FX helper as the rest of Zentho.
  static double convertHoldingAmount({
    required double amount,
    required String fromCurrency,
    required String mainCurrency,
    required List<CurrencyRate> rates,
  }) {
    return MoneyMath.toMain(
      amount: amount,
      currencyCode: fromCurrency,
      mainCurrency: mainCurrency,
      rates: rates,
    );
  }
}
