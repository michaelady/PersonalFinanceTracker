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

class ShareLedgerException implements Exception {
  const ShareLedgerException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Average-cost lot after applying [ShareTransaction]s in date order.
///
/// Buys raise quantity and cost basis (price × shares + fee). Sells reduce
/// quantity at the current average cost and realize P/L (proceeds − cost of
/// shares sold − fee). Dividends are cash income (not a cost-basis change).
/// Standalone fees add to remaining cost basis, or reduce realized P/L when
/// the position is flat. Splits multiply quantity and leave cost basis as-is.
class SharePosition {
  const SharePosition({
    required this.shares,
    required this.averageCostPerShare,
    required this.costNative,
    required this.realizedPlNative,
    required this.dividendNative,
    required this.investedNative,
    required this.proceedsNative,
  });

  final double shares;
  final double averageCostPerShare;
  final double costNative;
  final double realizedPlNative;
  final double dividendNative;
  final double investedNative;
  final double proceedsNative;

  double get totalRealizedNative => realizedPlNative + dividendNative;

  factory SharePosition.fromHolding(InvestmentHolding holding) {
    final shares = holding.shares;
    final avg = holding.averageCostPerShare;
    final cost = shares * avg;
    return SharePosition(
      shares: shares,
      averageCostPerShare: avg,
      costNative: cost,
      realizedPlNative: 0,
      dividendNative: 0,
      investedNative: cost,
      proceedsNative: 0,
    );
  }
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
    this.realizedPlMain = 0,
    this.dividendMain = 0,
    this.investedMain = 0,
    this.totalPlMain,
    this.totalPlPercent,
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
  final double realizedPlMain;
  final double dividendMain;
  final double investedMain;
  final double? totalPlMain;
  final double? totalPlPercent;

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
      realizedPlMain: realizedPlMain,
      dividendMain: dividendMain,
      investedMain: investedMain,
      totalPlMain: totalPlMain,
      totalPlPercent: totalPlPercent,
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
    this.realizedPlMain = 0,
    this.dividendMain = 0,
    this.investedMain = 0,
    this.totalPlMain,
    this.totalPlPercent,
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
  final double realizedPlMain;
  final double dividendMain;
  final double investedMain;
  final double? totalPlMain;
  final double? totalPlPercent;
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

  static const qtyEpsilon = 1e-10;

  static List<ShareTransaction> transactionsForHolding(
    String holdingId,
    List<ShareTransaction> transactions,
  ) {
    final out = [
      for (final t in transactions)
        if (t.holdingId == holdingId) t,
    ]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
      });
    return out;
  }

  static ShareTransaction openingBuyFor(
    InvestmentHolding holding, {
    DateTime? date,
    String notes = 'Opening position',
  }) {
    return ShareTransaction.create(
      holdingId: holding.id,
      type: ShareTransactionType.buy,
      date: date ?? DateTime.now(),
      shares: holding.shares,
      pricePerShare: holding.averageCostPerShare,
      notes: notes,
    );
  }

  /// Chronological average-cost application. When [strict] is true, invalid
  /// quantities throw [ShareLedgerException]; otherwise sells are clamped to
  /// shares held so stored ledgers still display.
  static SharePosition positionFor({
    required InvestmentHolding holding,
    List<ShareTransaction> transactions = const [],
    DateTime? asOf,
    bool strict = false,
  }) {
    final txs = [
      for (final t in transactionsForHolding(holding.id, transactions))
        if (asOf == null || !t.date.isAfter(asOf)) t,
    ];
    if (txs.isEmpty) return SharePosition.fromHolding(holding);

    var quantity = 0.0;
    var costBasis = 0.0;
    var realized = 0.0;
    var dividends = 0.0;
    var invested = 0.0;
    var proceeds = 0.0;

    void zeroIfFlat() {
      if (quantity.abs() <= qtyEpsilon) {
        quantity = 0;
        costBasis = 0;
      }
    }

    for (final tx in txs) {
      switch (tx.type) {
        case ShareTransactionType.buy:
          if (tx.shares <= 0) {
            if (strict) {
              throw const ShareLedgerException('Buy quantity must be positive');
            }
            break;
          }
          if (tx.pricePerShare < 0) {
            if (strict) {
              throw const ShareLedgerException('Buy price cannot be negative');
            }
            break;
          }
          final buyCost = tx.shares * tx.pricePerShare + tx.fee;
          quantity += tx.shares;
          costBasis += buyCost;
          invested += buyCost;
        case ShareTransactionType.sell:
          if (tx.shares <= 0) {
            if (strict) {
              throw const ShareLedgerException(
                'Sell quantity must be positive',
              );
            }
            break;
          }
          if (tx.pricePerShare < 0) {
            if (strict) {
              throw const ShareLedgerException('Sell price cannot be negative');
            }
            break;
          }
          if (quantity <= qtyEpsilon) {
            if (strict) {
              throw const ShareLedgerException(
                'Cannot sell shares from an empty position',
              );
            }
            break;
          }
          var sold = tx.shares;
          if (sold > quantity + qtyEpsilon) {
            if (strict) {
              throw ShareLedgerException(
                'Cannot sell ${_trimQty(sold)} shares; only ${_trimQty(quantity)} held',
              );
            }
            sold = quantity;
          }
          final avg = costBasis / quantity;
          final soldCost = avg * sold;
          final saleProceeds = sold * tx.pricePerShare - tx.fee;
          realized += saleProceeds - soldCost;
          proceeds += saleProceeds;
          quantity -= sold;
          costBasis -= soldCost;
          zeroIfFlat();
        case ShareTransactionType.dividend:
          if (tx.amount < 0) {
            if (strict) {
              throw const ShareLedgerException(
                'Dividend amount cannot be negative',
              );
            }
            break;
          }
          dividends += tx.amount;
        case ShareTransactionType.fee:
          if (tx.amount <= 0) {
            if (strict) {
              throw const ShareLedgerException('Fee amount must be positive');
            }
            break;
          }
          if (quantity > qtyEpsilon) {
            costBasis += tx.amount;
            invested += tx.amount;
          } else {
            realized -= tx.amount;
          }
        case ShareTransactionType.split:
          if (tx.shares <= 0) {
            if (strict) {
              throw const ShareLedgerException(
                'Split ratio must be greater than zero',
              );
            }
            break;
          }
          quantity *= tx.shares;
          zeroIfFlat();
      }
    }

    zeroIfFlat();
    final avg = quantity <= qtyEpsilon ? 0.0 : costBasis / quantity;
    return SharePosition(
      shares: quantity,
      averageCostPerShare: avg,
      costNative: costBasis,
      realizedPlNative: realized,
      dividendNative: dividends,
      investedNative: invested,
      proceedsNative: proceeds,
    );
  }

  static String? validateShareLedger({
    required InvestmentHolding holding,
    required List<ShareTransaction> transactions,
  }) {
    try {
      positionFor(
        holding: holding,
        transactions: transactions,
        strict: true,
      );
      return null;
    } on ShareLedgerException catch (e) {
      return e.message;
    }
  }

  static InvestmentHolding holdingWithLedger(
    InvestmentHolding holding,
    List<ShareTransaction> transactions,
  ) {
    final position = positionFor(holding: holding, transactions: transactions);
    return holding.copyWith(
      shares: position.shares,
      averageCostPerShare: position.averageCostPerShare,
    );
  }

  static List<InvestmentHolding> holdingsWithLedger(
    List<InvestmentHolding> holdings,
    List<ShareTransaction> transactions,
  ) {
    return [
      for (final h in holdings) holdingWithLedger(h, transactions),
    ];
  }

  static double sharesOnDate({
    required InvestmentHolding holding,
    required DateTime asOf,
    List<ShareTransaction> transactions = const [],
  }) {
    return positionFor(
      holding: holding,
      transactions: transactions,
      asOf: asOf,
    ).shares;
  }

  static String _trimQty(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(4);
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
    SharePosition? position,
    List<ShareTransaction> shareTransactions = const [],
  }) {
    final pos = position ??
        positionFor(holding: holding, transactions: shareTransactions);
    final lot = holding.copyWith(
      shares: pos.shares,
      averageCostPerShare: pos.averageCostPerShare,
    );
    final quote = quoteFor(holding, quotes);
    final costNative = pos.costNative;
    final costMain = toMain(
      costNative,
      holding.currencyCode,
      mainCurrency,
      rates,
    );
    final realizedMain = toMain(
      pos.realizedPlNative,
      holding.currencyCode,
      mainCurrency,
      rates,
    );
    final dividendMain = toMain(
      pos.dividendNative,
      holding.currencyCode,
      mainCurrency,
      rates,
    );
    final investedMain = toMain(
      pos.investedNative,
      holding.currencyCode,
      mainCurrency,
      rates,
    );

    HoldingValuation finish({
      required String quoteCurrency,
      double? lastPrice,
      DateTime? quotedAt,
      String? quoteSource,
      double? marketNative,
      double? marketMain,
      double? unrealizedPlMain,
      double? unrealizedPlPercent,
      double? dayChangeMain,
      double? dayChangePercent,
    }) {
      final totalPl = (unrealizedPlMain ?? 0) + realizedMain + dividendMain;
      final totalPct =
          investedMain == 0 ? null : (totalPl / investedMain) * 100;
      return HoldingValuation(
        holding: lot,
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
        realizedPlMain: realizedMain,
        dividendMain: dividendMain,
        investedMain: investedMain,
        totalPlMain: totalPl,
        totalPlPercent: totalPct,
      );
    }

    if (quote == null) {
      return finish(
        quoteCurrency: holding.currencyCode,
        unrealizedPlMain: pos.shares.abs() <= qtyEpsilon ? 0 : null,
      );
    }

    final marketNative = pos.shares * quote.price;
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
      dayChangeNative = pos.shares * (quote.price - quote.previousClose!);
    } else if (quote.changePercent != null) {
      final denom = 1 + (quote.changePercent! / 100);
      if (denom != 0) {
        final previous = quote.price / denom;
        dayChangeNative = pos.shares * (quote.price - previous);
      }
    }

    return finish(
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
    List<ShareTransaction> shareTransactions = const [],
  }) {
    final valued = [
      for (final h in holdings)
        valueHolding(
          holding: h,
          quotes: quotes,
          mainCurrency: mainCurrency,
          rates: rates,
          shareTransactions: shareTransactions,
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
    var realized = 0.0;
    var dividends = 0.0;
    var invested = 0.0;

    for (final v in valued) {
      netWorth += v.valueForNetWorthMain;
      realized += v.realizedPlMain;
      dividends += v.dividendMain;
      invested += v.investedMain;
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
    final totalPl = (pl ?? 0) + realized + dividends;
    final totalPct = invested == 0 ? null : (totalPl / invested) * 100;
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
      realizedPlMain: realized,
      dividendMain: dividends,
      investedMain: invested,
      totalPlMain: totalPl,
      totalPlPercent: totalPct,
    );
  }

  /// Holdings flagged [InvestmentHolding.includeInNetWorth], using last
  /// price when cached and cost otherwise.
  static double includedMarketValueMain({
    required List<InvestmentHolding> holdings,
    required Map<String, CachedQuote> quotes,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    List<ShareTransaction> shareTransactions = const [],
  }) {
    return summarize(
      holdings: holdings.where((h) => h.includeInNetWorth).toList(),
      quotes: quotes,
      mainCurrency: mainCurrency,
      rates: rates,
      shareTransactions: shareTransactions,
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

  /// UTC calendar day so Yahoo session timestamps and daily midnights align.
  static DateTime calendarDayUtc(DateTime date) {
    final utc = date.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  /// Inclusive end of [date]'s UTC calendar day, so a daily close includes
  /// buys booked later that session (not only those at midnight).
  static DateTime endOfCalendarDayUtc(DateTime date) {
    final day = calendarDayUtc(date);
    return DateTime.utc(day.year, day.month, day.day, 23, 59, 59, 999);
  }

  /// Portfolio (or single holding) market value in main currency over time.
  /// Uses current FX rates as a bridge — not historical FX. Share quantity on
  /// each day comes from the transaction ledger when present.
  ///
  /// The series starts on the first day with a real, complete market value —
  /// leading zeros, dummy 0 closes, and days that only price a subset of the
  /// book are dropped so the Y axis scales around the holding, not a spike
  /// up from one ticker's first bar.
  static List<PricePoint> performanceSeries({
    required List<InvestmentHolding> holdings,
    required Map<String, CachedQuote> quotes,
    required String mainCurrency,
    required List<CurrencyRate> rates,
    required QuoteHistoryRange range,
    List<ShareTransaction> shareTransactions = const [],
  }) {
    if (holdings.isEmpty) return const [];

    final seriesByTicker = <String, List<PricePoint>>{};
    final dates = <DateTime>{};
    for (final h in holdings) {
      final points = [
        ...historyForRange(quoteFor(h, quotes), range),
      ]..sort((a, b) => a.date.compareTo(b.date));
      if (points.isEmpty) continue;
      seriesByTicker[h.ticker] = points;
      dates.addAll(points.map((p) => calendarDayUtc(p.date)));
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
        while (i < series.length &&
            !calendarDayUtc(series[i].date).isAfter(day)) {
          final close = series[i].close;
          if (close > 0) lastClose[h.ticker] = close;
          i++;
        }
        dateIndex[h.ticker] = i;
      }
      var total = 0.0;
      var any = false;
      var incomplete = false;
      final asOf = endOfCalendarDayUtc(day);
      for (final h in holdings) {
        final shares = sharesOnDate(
          holding: h,
          asOf: asOf,
          transactions: shareTransactions,
        );
        if (shares.abs() <= qtyEpsilon) continue;
        final close = lastClose[h.ticker];
        if (close == null || close <= 0) {
          // A held lot whose daily history has not started yet would
          // understate the book (first-day spike from ~10K to the real
          // ~100K). Two-point previous-close fallbacks must not block
          // earlier days — they only have yesterday + today.
          final quote = quoteFor(h, quotes);
          if (seriesByTicker.containsKey(h.ticker) &&
              !usesLastCloseFallback(quote, range)) {
            incomplete = true;
            break;
          }
          continue;
        }
        final quote = quoteFor(h, quotes);
        final currency = quote?.currency ?? h.currencyCode;
        total += toMain(shares * close, currency, mainCurrency, rates);
        any = true;
      }
      if (!incomplete && any) {
        out.add(PricePoint(date: day, close: total));
      }
    }
    final start = out.indexWhere((p) => p.close > qtyEpsilon);
    if (start < 0) return const [];
    return start == 0 ? out : out.sublist(start);
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
