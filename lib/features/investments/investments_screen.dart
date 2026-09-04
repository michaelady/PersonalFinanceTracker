import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../data/services/quote_client.dart';
import '../../domain/models/models.dart';
import '../../domain/services/portfolio_math.dart';
import '../../domain/services/supported_currencies.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/responsive.dart';
import '../../widgets/sheet_inset.dart';
import '../../widgets/visibility_chip.dart';

String performanceEmptyCopy({required bool hasLastPrice}) {
  if (hasLastPrice) {
    return 'No daily history for this range. Last price is still shown above.';
  }
  return 'No history yet for this range. Pull to refresh when online.';
}

String performanceTwoPointCaption(QuoteHistoryRange range) {
  return 'Last close vs last price — not a full ${range.chartLabel} history.';
}

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key});

  static Future<void> showEditor(
    BuildContext context,
    FinanceRepository repo, {
    InvestmentHolding? existing,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SheetInset(
        child: _HoldingEditor(existing: existing),
      ),
    );
  }

  static Future<void> showShareTransactionEditor(
    BuildContext context,
    FinanceRepository repo, {
    ShareTransaction? existing,
    InvestmentHolding? holding,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SheetInset(
        child: _ShareTransactionEditor(
          existing: existing,
          initialHolding: holding,
        ),
      ),
    );
  }

  static Future<void> importYahooLots(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read CSV bytes')),
          );
        }
        return;
      }
      final csvBody = utf8.decode(bytes, allowMalformed: true);
      final imported = await repo.importYahooLots(csvBody);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(imported.summary)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  QuoteHistoryRange _range = QuoteHistoryRange.oneMonth;
  String? _chartHoldingId;
  final _scrollController = ScrollController();
  final _chartKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FinanceRepository>().refreshQuotes();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRange(QuoteHistoryRange range) async {
    setState(() => _range = range);
    await context.read<FinanceRepository>().refreshQuotes(range: range);
  }

  void _setChartHolding(String? id) {
    setState(() => _chartHoldingId = id);
  }

  void _toggleChartHolding(String id) {
    _setChartHolding(_chartHoldingId == id ? null : id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chartKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    });
  }

  void _editHolding(FinanceRepository repo, InvestmentHolding holding) {
    InvestmentsScreen.showEditor(context, repo, existing: holding);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final portfolio = repo.portfolio;
    final currency = repo.settings.mainCurrency;
    final holdings = portfolio.holdings;
    final chartHoldingId = holdings.any((v) => v.holding.id == _chartHoldingId)
        ? _chartHoldingId
        : null;

    return AppScaffoldBody(
      child: RefreshIndicator(
        onRefresh: () => repo.refreshQuotes(force: true, range: _range),
        child: ListView(
          controller: _scrollController,
          children: [
            Text(
              'Investments',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Lots from your buy/sell history, with Yahoo Finance quotes '
              '(unofficial, delayed, not advice). Average-cost basis; '
              'realized P/L from sells + dividends; unrealized vs last price.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  key: const Key('add-share-transaction'),
                  onPressed: () => InvestmentsScreen.showShareTransactionEditor(
                    context,
                    repo,
                  ),
                  child: const Text('Add transaction'),
                ),
                FilledButton.tonal(
                  onPressed: () => InvestmentsScreen.showEditor(context, repo),
                  child: const Text('New holding'),
                ),
                FilledButton.tonal(
                  key: const Key('import-yahoo-lots'),
                  onPressed: () =>
                      InvestmentsScreen.importYahooLots(context, repo),
                  child: const Text('Import Yahoo CSV'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (repo.visibleHoldings.isEmpty)
              const _EmptyState()
            else ...[
              _TotalsCard(portfolio: portfolio, currency: currency, repo: repo),
              const SizedBox(height: 20),
              KeyedSubtree(
                key: _chartKey,
                child: _ChartBlock(
                  repo: repo,
                  range: _range,
                  chartHoldingId: chartHoldingId,
                  onRange: _onRange,
                  onSelectHolding: _setChartHolding,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Allocation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ...holdings.map(
                (v) => _AllocationRow(
                  valuation: v,
                  currency: currency,
                  selected: chartHoldingId == v.holding.id,
                  onTap: () => _toggleChartHolding(v.holding.id),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Holdings',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ...holdings.map(
                (v) => _HoldingTile(
                  valuation: v,
                  currency: currency,
                  selected: chartHoldingId == v.holding.id,
                  onTap: () => _toggleChartHolding(v.holding.id),
                  onEdit: () => _editHolding(repo, v.holding),
                  onAddTransaction: () =>
                      InvestmentsScreen.showShareTransactionEditor(
                    context,
                    repo,
                    holding: v.holding,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Transactions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (repo.visibleShareTransactions.isEmpty)
                Text(
                  'Record buys, sells, dividends, fees, and splits. Holdings '
                  'and P/L update from this list.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              else
                ...repo.visibleShareTransactions.map(
                  (tx) => _ShareTransactionTile(
                    tx: tx,
                    holding: repo.holdingById(tx.holdingId),
                    onTap: () => InvestmentsScreen.showShareTransactionEditor(
                      context,
                      repo,
                      existing: tx,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: ZenthoColors.line),
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.55),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No holdings yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Add a ticker, record share transactions, or import a Yahoo '
            'Finance lots CSV. Quantity, cost basis, and P/L are derived from '
            'the transaction list. Quotes come from Yahoo Finance — unofficial, '
            'delayed, and not investment advice.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Android and Windows fetch Yahoo directly. This website cannot, '
            'because Yahoo does not allow browser requests — it may already '
            'have a default Finnhub key, and a personal key in Settings still '
            'overrides it. Last successful prices stay on this device for offline use.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({
    required this.portfolio,
    required this.currency,
    required this.repo,
  });

  final PortfolioTotals portfolio;
  final String currency;
  final FinanceRepository repo;

  @override
  Widget build(BuildContext context) {
    final pl = portfolio.unrealizedPlMain;
    final asOf = portfolio.quotedAt;
    final source = _sourceLabel(portfolio.quoteSource ?? repo.quotesSource);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border.all(color: ZenthoColors.line),
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.7),
            ZenthoColors.mint.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Portfolio',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: ZenthoColors.inkMuted,
                    ),
              ),
              const Spacer(),
              if (repo.quotesRefreshing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  tooltip: 'Refresh quotes',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => repo.refreshQuotes(force: true),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          MoneyText(portfolio.marketMain, currencyCode: currency, emphasize: true),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _LabeledMoney(label: 'Cost', amount: portfolio.costMain, currency: currency),
              if (pl != null)
                _LabeledMoney(
                  label: portfolio.unrealizedPlPercent == null
                      ? 'Unrealized'
                      : 'Unrealized ${portfolio.unrealizedPlPercent!.toStringAsFixed(1)}%',
                  amount: pl,
                  currency: currency,
                  signed: true,
                ),
              if (portfolio.realizedPlMain != 0 || portfolio.dividendMain != 0)
                _LabeledMoney(
                  label: 'Realized',
                  amount: portfolio.realizedPlMain + portfolio.dividendMain,
                  currency: currency,
                  signed: true,
                ),
              if (portfolio.totalPlMain != null &&
                  (portfolio.realizedPlMain != 0 ||
                      portfolio.dividendMain != 0))
                _LabeledMoney(
                  label: portfolio.totalPlPercent == null
                      ? 'Total P/L'
                      : 'Total ${portfolio.totalPlPercent!.toStringAsFixed(1)}% vs invested',
                  amount: portfolio.totalPlMain!,
                  currency: currency,
                  signed: true,
                ),
              if (portfolio.dayChangeMain != null)
                _LabeledMoney(
                  label: 'Day',
                  amount: portfolio.dayChangeMain!,
                  currency: currency,
                  signed: true,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (asOf != null)
                'Last price ${DateFormat.MMMd().add_jm().format(asOf.toLocal())}',
              ?source,
              ?repo.quotesError,
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: repo.quotesError != null
                      ? ZenthoColors.coral
                      : ZenthoColors.inkMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _LabeledMoney extends StatelessWidget {
  const _LabeledMoney({
    required this.label,
    required this.amount,
    required this.currency,
    this.signed = false,
  });

  final String label;
  final double amount;
  final String currency;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        MoneyText(amount, currencyCode: currency, signed: signed),
      ],
    );
  }
}

class _ChartBlock extends StatelessWidget {
  const _ChartBlock({
    required this.repo,
    required this.range,
    required this.chartHoldingId,
    required this.onRange,
    required this.onSelectHolding,
  });

  final FinanceRepository repo;
  final QuoteHistoryRange range;
  final String? chartHoldingId;
  final ValueChanged<QuoteHistoryRange> onRange;
  final ValueChanged<String?> onSelectHolding;

  @override
  Widget build(BuildContext context) {
    final currency = repo.settings.mainCurrency;
    final selected = PortfolioMath.holdingsForChart(
      visible: repo.visibleHoldings,
      selectedHoldingId: chartHoldingId,
    );
    final selectedHolding = selected.length == 1 ? selected.single : null;
    final series = PortfolioMath.performanceSeries(
      holdings: selected,
      quotes: repo.quotes,
      mainCurrency: currency,
      rates: repo.rates,
      range: range,
      shareTransactions: repo.shareTransactions,
    );
    final twoPointFallback = PortfolioMath.chartUsesLastCloseFallback(
      holdings: selected,
      quotes: repo.quotes,
      range: range,
    );
    final hasLastPrice = selected.any((h) {
      final quote = repo.quotes[h.ticker.toUpperCase()];
      return quote != null && quote.price > 0;
    });
    final subtitle = selectedHolding == null
        ? 'Whole portfolio market value'
        : selectedHolding.displayName.isEmpty
            ? selectedHolding.ticker
            : '${selectedHolding.displayName} · ${selectedHolding.ticker}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Performance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    subtitle,
                    key: const Key('chart-subtitle'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (chartHoldingId != null)
              TextButton(
                key: const Key('chart-show-portfolio'),
                onPressed: () => onSelectHolding(null),
                child: const Text('Portfolio'),
              ),
            DropdownButton<String?>(
              key: const Key('chart-holding-dropdown'),
              // ignore: deprecated_member_use
              value: chartHoldingId,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem(value: null, child: Text('Portfolio')),
                for (final h in repo.visibleHoldings)
                  DropdownMenuItem(value: h.id, child: Text(h.ticker)),
              ],
              onChanged: onSelectHolding,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<QuoteHistoryRange>(
          segments: const [
            ButtonSegment(value: QuoteHistoryRange.oneMonth, label: Text('1M')),
            ButtonSegment(value: QuoteHistoryRange.threeMonths, label: Text('3M')),
            ButtonSegment(value: QuoteHistoryRange.oneYear, label: Text('1Y')),
          ],
          selected: {range},
          onSelectionChanged: (s) => onRange(s.first),
        ),
        const SizedBox(height: 12),
        if (series.length < 2)
          Container(
            key: const Key('performance-empty'),
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border.all(color: ZenthoColors.line),
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.45),
            ),
            child: Text(
              performanceEmptyCopy(hasLastPrice: hasLastPrice),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          _PerformanceChart(
            series: series,
            currency: currency,
            fallbackCaption: twoPointFallback
                ? performanceTwoPointCaption(range)
                : null,
          ),
      ],
    );
  }
}

class _PerformanceChart extends StatelessWidget {
  const _PerformanceChart({
    required this.series,
    required this.currency,
    this.fallbackCaption,
  });

  final List<PricePoint> series;
  final String currency;
  final String? fallbackCaption;

  @override
  Widget build(BuildContext context) {
    final last = series.last;
    final minClose =
        series.map((p) => p.close).reduce((a, b) => a < b ? a : b);
    final maxClose =
        series.map((p) => p.close).reduce((a, b) => a > b ? a : b);
    final span = (maxClose - minClose).abs();
    final pad = span < 1 ? 1.0 : span * 0.08;
    final dateFormat = DateFormat.MMMd();
    final moneyFormat = NumberFormat.currency(name: currency, symbol: '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            MoneyText(
              last.close,
              key: const Key('chart-latest'),
              currencyCode: currency,
            ),
            const SizedBox(width: 8),
            Text(
              dateFormat.format(last.date.toLocal()),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ZenthoColors.inkMuted,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          key: const Key('performance-chart'),
          height: 220,
          padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
          decoration: BoxDecoration(
            border: Border.all(color: ZenthoColors.line),
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: 0.45),
          ),
          child: LineChart(
            LineChartData(
              minY: minClose - pad,
              maxY: maxClose + pad,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: ZenthoColors.line.withValues(alpha: 0.7),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    getTitlesWidget: (value, _) => Text(
                      NumberFormat.compact().format(value),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval:
                        (series.length / 3).clamp(1, series.length).toDouble(),
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= series.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          dateFormat.format(series[i].date.toLocal()),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      if (s.spotIndex >= 0 && s.spotIndex < series.length)
                        LineTooltipItem(
                          '$currency ${moneyFormat.format(s.y).trim()}\n'
                          '${dateFormat.format(series[s.spotIndex].date.toLocal())}',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < series.length; i++)
                      FlSpot(i.toDouble(), series[i].close),
                  ],
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: ZenthoColors.tealDeep,
                  barWidth: 2.4,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: ZenthoColors.tealSoft.withValues(alpha: 0.18),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          fallbackCaption ?? 'Touch the line for value and date.',
          key: fallbackCaption == null ? null : const Key('chart-fallback-caption'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: ZenthoColors.inkMuted,
              ),
        ),
      ],
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({
    required this.valuation,
    required this.currency,
    required this.selected,
    required this.onTap,
  });

  final HoldingValuation valuation;
  final String currency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = valuation.allocationPercent.clamp(0, 100) / 100;
    return InkWell(
      key: ValueKey('allocation-${valuation.holding.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? ZenthoColors.mint.withValues(alpha: 0.7)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? ZenthoColors.tealDeep : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${valuation.holding.ticker} · ${valuation.allocationPercent.toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                MoneyText(
                  valuation.valueForNetWorthMain,
                  currencyCode: currency,
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct.toDouble(),
                minHeight: 8,
                backgroundColor: ZenthoColors.line,
                color: ZenthoColors.tealDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldingTile extends StatelessWidget {
  const _HoldingTile({
    required this.valuation,
    required this.currency,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onAddTransaction,
  });

  final HoldingValuation valuation;
  final String currency;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onAddTransaction;

  @override
  Widget build(BuildContext context) {
    final h = valuation.holding;
    final priceLabel = valuation.lastPrice == null
        ? 'No quote yet'
        : '${valuation.quoteCurrency} ${valuation.lastPrice!.toStringAsFixed(2)}';
    return InkWell(
      key: ValueKey('holding-${h.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onEdit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? ZenthoColors.mint.withValues(alpha: 0.7)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? ZenthoColors.tealDeep : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: ZenthoColors.mint,
              child: Text(
                h.ticker.length <= 2 ? h.ticker : h.ticker.substring(0, 2),
                style: const TextStyle(
                  color: ZenthoColors.tealDeep,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    h.displayName.isEmpty ? h.ticker : h.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${h.ticker} · ${_sharesLabel(h.shares)} sh · last $priceLabel',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  VisibilityChip(h.visibility),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(
                  valuation.valueForNetWorthMain,
                  currencyCode: currency,
                ),
                if (valuation.unrealizedPlMain != null)
                  MoneyText(
                    valuation.unrealizedPlMain!,
                    currencyCode: currency,
                    signed: true,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (valuation.realizedPlMain != 0 || valuation.dividendMain != 0)
                  Text(
                    'Realized ${_signedShort(valuation.realizedPlMain + valuation.dividendMain, currency)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ZenthoColors.inkMuted,
                        ),
                  ),
                if (valuation.unrealizedPlPercent != null)
                  Text(
                    '${valuation.unrealizedPlPercent!.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: (valuation.unrealizedPlMain ?? 0) < 0
                              ? ZenthoColors.coral
                              : ZenthoColors.tealDeep,
                        ),
                  ),
              ],
            ),
            IconButton(
              key: ValueKey('add-tx-${h.id}'),
              tooltip: 'Add transaction',
              visualDensity: VisualDensity.compact,
              onPressed: onAddTransaction,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              key: ValueKey('edit-holding-${h.id}'),
              tooltip: 'Edit holding',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

String _sharesLabel(double shares) {
  if (shares == shares.roundToDouble()) return shares.toStringAsFixed(0);
  return shares.toStringAsFixed(4);
}

String _signedShort(double amount, String currency) {
  final prefix = amount > 0
      ? '+'
      : amount < 0
          ? '−'
          : '';
  return '$prefix$currency ${amount.abs().toStringAsFixed(2)}';
}

String _shareTxTypeLabel(ShareTransactionType type) {
  return switch (type) {
    ShareTransactionType.buy => 'Buy',
    ShareTransactionType.sell => 'Sell',
    ShareTransactionType.dividend => 'Dividend',
    ShareTransactionType.fee => 'Fee',
    ShareTransactionType.split => 'Split',
  };
}

String? _sourceLabel(String? source) {
  return switch (source) {
    'yahoo' => 'Yahoo Finance',
    'finnhub' => 'Finnhub',
    'alphavantage' => 'Alpha Vantage',
    'twelvedata' => 'Twelve Data',
    null => null,
    _ => source,
  };
}

class _HoldingEditor extends StatefulWidget {
  const _HoldingEditor({this.existing});

  final InvestmentHolding? existing;

  @override
  State<_HoldingEditor> createState() => _HoldingEditorState();
}

class _HoldingEditorState extends State<_HoldingEditor> {
  late final TextEditingController _ticker;
  late final TextEditingController _name;
  late final TextEditingController _shares;
  late final TextEditingController _cost;
  late final TextEditingController _notes;
  late String _currency;
  late VisibilityScope _visibility;
  late bool _includeInNetWorth;
  String? _accountId;
  List<TickerSearchResult> _matches = [];
  Timer? _searchTimer;
  bool _searching = false;
  var _didInitCurrency = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _ticker = TextEditingController(text: existing?.ticker ?? '');
    _name = TextEditingController(text: existing?.displayName ?? '');
    _shares = TextEditingController(
      text: existing == null ? '' : _sharesLabel(existing.shares),
    );
    _cost = TextEditingController(
      text: existing == null ? '' : existing.averageCostPerShare.toString(),
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
    _currency = existing?.currencyCode ?? 'USD';
    _visibility = existing?.visibility ?? VisibilityScope.shared;
    _includeInNetWorth = existing?.includeInNetWorth ?? true;
    _accountId = existing?.accountId;
    _ticker.addListener(_onTickerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitCurrency) return;
    _didInitCurrency = true;
    if (widget.existing == null) {
      _currency = context.read<FinanceRepository>().settings.mainCurrency;
    }
  }

  void _onTickerChanged() {
    _searchTimer?.cancel();
    final q = _ticker.text.trim();
    if (q.isEmpty) {
      setState(() => _matches = []);
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final results =
          await context.read<FinanceRepository>().searchTickers(q);
      if (!mounted) return;
      setState(() {
        _matches = results;
        _searching = false;
      });
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _ticker.removeListener(_onTickerChanged);
    _ticker.dispose();
    _name.dispose();
    _shares.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final isEditing = widget.existing != null;
    final hasLedger = widget.existing != null &&
        repo.shareTransactions.any((t) => t.holdingId == widget.existing!.id);
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEditing ? 'Edit holding' : 'Add holding',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ticker,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Ticker',
                hintText: 'AAPL, VWCE.DE, BTC-USD',
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            if (_matches.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._matches.take(6).map(
                    (m) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.symbol),
                      subtitle: Text(
                        [
                          m.name,
                          if (m.exchange != null) m.exchange,
                          if (m.typeLabel != null) m.typeLabel,
                        ].join(' · '),
                      ),
                      onTap: () {
                        _ticker.text = m.symbol;
                        if (_name.text.trim().isEmpty ||
                            widget.existing == null) {
                          _name.text = m.name;
                        }
                        setState(() => _matches = []);
                      },
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 12),
            if (hasLedger) ...[
              Text(
                'Shares ${_sharesLabel(widget.existing!.shares)} · avg cost '
                '${widget.existing!.averageCostPerShare.toStringAsFixed(2)} '
                '${widget.existing!.currencyCode}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Quantity and average cost come from the transaction list. '
                'Add a buy or sell to change this lot.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ZenthoColors.inkMuted,
                    ),
              ),
            ] else ...[
              TextField(
                controller: _shares,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Shares'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Average cost per share',
                ),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: [
                for (final c in SupportedCurrencies.codes)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => _currency = v ?? _currency),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<VisibilityScope>(
              // ignore: deprecated_member_use
              value: _visibility,
              decoration: const InputDecoration(labelText: 'Visibility'),
              items: const [
                DropdownMenuItem(
                  value: VisibilityScope.shared,
                  child: Text('Shared'),
                ),
                DropdownMenuItem(
                  value: VisibilityScope.private,
                  child: Text('Private'),
                ),
              ],
              onChanged: (v) =>
                  setState(() => _visibility = v ?? _visibility),
            ),
            if (repo.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: _accountId,
                decoration: const InputDecoration(
                  labelText: 'Account (optional)',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final a in repo.visibleAccounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include in net worth'),
              subtitle: const Text(
                'Turn off if this lot is already counted in an account balance.',
              ),
              value: _includeInNetWorth,
              activeThumbColor: ZenthoColors.tealDeep,
              onChanged: (v) => setState(() => _includeInNetWorth = v),
            ),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (isEditing)
                  TextButton(
                    onPressed: () async {
                      await repo.deleteHolding(widget.existing!.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text(
                      'Delete',
                      style: TextStyle(color: ZenthoColors.coral),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _save(repo),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(FinanceRepository repo) async {
    final ticker = _ticker.text.trim().toUpperCase();
    final hasLedger = widget.existing != null &&
        repo.shareTransactions.any((t) => t.holdingId == widget.existing!.id);
    final shares = hasLedger
        ? widget.existing!.shares
        : double.tryParse(_shares.text.trim()) ?? 0;
    final cost = hasLedger
        ? widget.existing!.averageCostPerShare
        : double.tryParse(_cost.text.trim()) ?? 0;
    if (ticker.isEmpty || (!hasLedger && shares <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a ticker and shares')),
      );
      return;
    }
    final name = _name.text.trim().isEmpty ? ticker : _name.text.trim();
    if (widget.existing != null) {
      await repo.updateHolding(
        widget.existing!.copyWith(
          ticker: ticker,
          displayName: name,
          shares: shares,
          averageCostPerShare: cost,
          currencyCode: _currency,
          visibility: _visibility,
          accountId: _accountId,
          notes: _notes.text.trim(),
          includeInNetWorth: _includeInNetWorth,
        ),
      );
    } else {
      await repo.addHolding(
        InvestmentHolding.create(
          ticker: ticker,
          displayName: name,
          shares: shares,
          averageCostPerShare: cost,
          currencyCode: _currency,
          ownerProfileId: repo.settings.activeProfileId,
          visibility: _visibility,
          accountId: _accountId,
          notes: _notes.text.trim(),
          includeInNetWorth: _includeInNetWorth,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }
}

class _ShareTransactionTile extends StatelessWidget {
  const _ShareTransactionTile({
    required this.tx,
    required this.holding,
    required this.onTap,
  });

  final ShareTransaction tx;
  final InvestmentHolding? holding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ticker = holding?.ticker ?? 'Holding';
    final subtitle = switch (tx.type) {
      ShareTransactionType.buy || ShareTransactionType.sell => [
          '${_sharesLabel(tx.shares)} sh @ ${tx.pricePerShare.toStringAsFixed(2)}',
          if (tx.fee > 0) 'fee ${tx.fee.toStringAsFixed(2)}',
          DateFormat.yMMMd().format(tx.date),
          if (tx.notes.isNotEmpty) tx.notes,
        ].join(' · '),
      ShareTransactionType.dividend => [
          holding == null
              ? tx.amount.toStringAsFixed(2)
              : '${holding!.currencyCode} ${tx.amount.toStringAsFixed(2)}',
          DateFormat.yMMMd().format(tx.date),
          if (tx.notes.isNotEmpty) tx.notes,
        ].join(' · '),
      ShareTransactionType.fee => [
          holding == null
              ? tx.amount.toStringAsFixed(2)
              : '${holding!.currencyCode} ${tx.amount.toStringAsFixed(2)}',
          DateFormat.yMMMd().format(tx.date),
          if (tx.notes.isNotEmpty) tx.notes,
        ].join(' · '),
      ShareTransactionType.split => [
          '${_sharesLabel(tx.shares)}-for-1',
          DateFormat.yMMMd().format(tx.date),
          if (tx.notes.isNotEmpty) tx.notes,
        ].join(' · '),
    };
    return ListTile(
      key: ValueKey('share-tx-${tx.id}'),
      contentPadding: EdgeInsets.zero,
      title: Text('${_shareTxTypeLabel(tx.type)} · $ticker'),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class _ShareTransactionEditor extends StatefulWidget {
  const _ShareTransactionEditor({
    this.existing,
    this.initialHolding,
  });

  final ShareTransaction? existing;
  final InvestmentHolding? initialHolding;

  @override
  State<_ShareTransactionEditor> createState() =>
      _ShareTransactionEditorState();
}

class _ShareTransactionEditorState extends State<_ShareTransactionEditor> {
  late final TextEditingController _ticker;
  late final TextEditingController _name;
  late final TextEditingController _shares;
  late final TextEditingController _price;
  late final TextEditingController _amount;
  late final TextEditingController _fee;
  late final TextEditingController _notes;
  late ShareTransactionType _type;
  late DateTime _date;
  late String _currency;
  late VisibilityScope _visibility;
  String? _holdingId;
  String? _accountId;
  List<TickerSearchResult> _matches = [];
  Timer? _searchTimer;
  bool _searching = false;
  var _didInitCurrency = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final initial = widget.initialHolding;
    _type = existing?.type ?? ShareTransactionType.buy;
    _date = existing?.date ?? DateTime.now();
    _holdingId = existing?.holdingId ?? initial?.id;
    _ticker = TextEditingController(text: initial?.ticker ?? '');
    _name = TextEditingController(text: initial?.displayName ?? '');
    _shares = TextEditingController(
      text: existing == null || existing.shares == 0
          ? ''
          : _sharesLabel(existing.shares),
    );
    _price = TextEditingController(
      text: existing == null || existing.pricePerShare == 0
          ? ''
          : existing.pricePerShare.toString(),
    );
    _amount = TextEditingController(
      text: existing == null || existing.amount == 0
          ? ''
          : existing.amount.toString(),
    );
    _fee = TextEditingController(
      text: existing == null || existing.fee == 0 ? '' : existing.fee.toString(),
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
    _currency = initial?.currencyCode ?? 'USD';
    _visibility = initial?.visibility ?? VisibilityScope.shared;
    _accountId = initial?.accountId;
    _ticker.addListener(_onTickerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = context.read<FinanceRepository>();
    if (_holdingId != null) {
      final holding = repo.holdingById(_holdingId!);
      if (holding != null && _ticker.text.isEmpty) {
        _ticker.text = holding.ticker;
        if (_name.text.isEmpty) _name.text = holding.displayName;
        _currency = holding.currencyCode;
        _visibility = holding.visibility;
        _accountId = holding.accountId;
      }
    }
    if (_didInitCurrency) return;
    _didInitCurrency = true;
    if (widget.initialHolding == null && widget.existing == null) {
      _currency = repo.settings.mainCurrency;
    }
  }

  void _onTickerChanged() {
    if (_holdingId != null) return;
    _searchTimer?.cancel();
    final q = _ticker.text.trim();
    if (q.isEmpty) {
      setState(() => _matches = []);
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      final results = await context.read<FinanceRepository>().searchTickers(q);
      if (!mounted) return;
      setState(() {
        _matches = results;
        _searching = false;
      });
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _ticker.removeListener(_onTickerChanged);
    _ticker.dispose();
    _name.dispose();
    _shares.dispose();
    _price.dispose();
    _amount.dispose();
    _fee.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _needsShares =>
      _type == ShareTransactionType.buy ||
      _type == ShareTransactionType.sell ||
      _type == ShareTransactionType.split;

  bool get _needsPrice =>
      _type == ShareTransactionType.buy || _type == ShareTransactionType.sell;

  bool get _needsAmount =>
      _type == ShareTransactionType.dividend ||
      _type == ShareTransactionType.fee;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Edit transaction' : 'Add transaction',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ShareTransactionType>(
              key: const Key('share-tx-type'),
              // ignore: deprecated_member_use
              value: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final t in ShareTransactionType.values)
                  DropdownMenuItem(
                    value: t,
                    child: Text(_shareTxTypeLabel(t)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
            ),
            const SizedBox(height: 12),
            if (repo.holdings.isNotEmpty)
              DropdownButtonFormField<String?>(
                key: const Key('share-tx-holding'),
                // ignore: deprecated_member_use
                value: _holdingId,
                decoration: const InputDecoration(labelText: 'Holding'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('New ticker'),
                  ),
                  for (final h in repo.visibleHoldings)
                    DropdownMenuItem(
                      value: h.id,
                      child: Text(
                        h.displayName.isEmpty
                            ? h.ticker
                            : '${h.displayName} · ${h.ticker}',
                      ),
                    ),
                ],
                onChanged: _isEditing
                    ? null
                    : (v) {
                        setState(() {
                          _holdingId = v;
                          _matches = [];
                          if (v == null) return;
                          final h = repo.holdingById(v);
                          if (h == null) return;
                          _ticker.text = h.ticker;
                          _name.text = h.displayName;
                          _currency = h.currencyCode;
                          _visibility = h.visibility;
                          _accountId = h.accountId;
                        });
                      },
              ),
            if (_holdingId == null) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('share-tx-ticker'),
                controller: _ticker,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Ticker',
                  hintText: 'AAPL, VWCE.DE, BTC-USD',
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              if (_matches.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._matches.take(6).map(
                      (m) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.symbol),
                        subtitle: Text(
                          [
                            m.name,
                            if (m.exchange != null) m.exchange,
                            if (m.typeLabel != null) m.typeLabel,
                          ].join(' · '),
                        ),
                        onTap: () {
                          _ticker.text = m.symbol;
                          if (_name.text.trim().isEmpty) _name.text = m.name;
                          setState(() => _matches = []);
                        },
                      ),
                    ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: [
                  for (final c in SupportedCurrencies.codes)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _currency = v ?? _currency),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<VisibilityScope>(
                // ignore: deprecated_member_use
                value: _visibility,
                decoration: const InputDecoration(labelText: 'Visibility'),
                items: const [
                  DropdownMenuItem(
                    value: VisibilityScope.shared,
                    child: Text('Shared'),
                  ),
                  DropdownMenuItem(
                    value: VisibilityScope.private,
                    child: Text('Private'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _visibility = v ?? _visibility),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date'),
              subtitle: Text(DateFormat.yMMMd().format(_date)),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(1990),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            if (_needsShares) ...[
              TextField(
                key: const Key('share-tx-shares'),
                controller: _shares,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _type == ShareTransactionType.split
                      ? 'Split ratio'
                      : 'Shares',
                  hintText: _type == ShareTransactionType.split
                      ? '2 for a 2-for-1 split'
                      : null,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_needsPrice) ...[
              TextField(
                key: const Key('share-tx-price'),
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Price per share',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fee,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Commission / fee (optional)',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_needsAmount) ...[
              TextField(
                key: const Key('share-tx-amount'),
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _type == ShareTransactionType.dividend
                      ? 'Cash dividend'
                      : 'Fee amount',
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('share-tx-save'),
              onPressed: () => _save(repo),
              child: Text(_isEditing ? 'Save changes' : 'Save'),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final error = await repo.deleteShareTransaction(
                    widget.existing!.id,
                  );
                  if (!context.mounted) return;
                  if (error != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error)),
                    );
                    return;
                  }
                  Navigator.pop(context);
                },
                child: Text(
                  'Delete',
                  style: TextStyle(color: ZenthoColors.coral),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save(FinanceRepository repo) async {
    final shares = double.tryParse(_shares.text.trim()) ?? 0;
    final price = double.tryParse(_price.text.trim()) ?? 0;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final fee = double.tryParse(_fee.text.trim()) ?? 0;
    String? error;
    if (_isEditing) {
      error = await repo.updateShareTransaction(
        widget.existing!.copyWith(
          type: _type,
          date: _date,
          shares: shares,
          pricePerShare: price,
          amount: amount,
          fee: fee,
          notes: _notes.text.trim(),
        ),
      );
    } else {
      error = await repo.addShareTransactionForTicker(
        ticker: _ticker.text,
        displayName: _name.text,
        currencyCode: _currency,
        visibility: _visibility,
        accountId: _accountId,
        holdingId: _holdingId,
        type: _type,
        date: _date,
        shares: shares,
        pricePerShare: price,
        amount: amount,
        fee: fee,
        notes: _notes.text.trim(),
      );
    }
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context);
  }
}
