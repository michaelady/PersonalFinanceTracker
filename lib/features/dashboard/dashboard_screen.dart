import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/money_math.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/responsive.dart';
import '../../widgets/visibility_chip.dart';
import '../transactions/transactions_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final available = repo.availableToSpend();
    final currency = repo.settings.mainCurrency;
    final month = MoneyMath.monthKey(DateTime.now());
    final income = MoneyMath.incomeInMonthMain(
      transactions: repo.visibleTransactions,
      monthKeyValue: month,
      mainCurrency: currency,
      rates: repo.rates,
      includeExpectedRecurring: true,
    );
    final expense = MoneyMath.expenseInMonthMain(
      transactions: repo.visibleTransactions,
      monthKeyValue: month,
      mainCurrency: currency,
      rates: repo.rates,
      includeExpectedRecurring: true,
    );
    final recurring = MoneyMath.recurringCandidates(repo.visibleTransactions);
    final recent = repo.visibleTransactions.take(5).toList();

    return AppScaffoldBody(
      child: ListView(
        children: [
          Text(
            'Available to spend',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: ZenthoColors.inkMuted),
          ),
          const SizedBox(height: 6),
          MoneyText(available, currencyCode: currency, emphasize: true),
          const SizedBox(height: 8),
          Text(
            'This month’s calm number — income minus expenses, including '
            'recurring items even if last booked in another month.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _HeroFlowChart(income: income, expense: expense, currency: currency),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Net worth',
                  child: MoneyText(repo.netWorth, currencyCode: currency),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricTile(
                  label: 'Recurring',
                  child: Text(
                    '${recurring.length} tracked',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Recent activity',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            Text(
              'No transactions yet. Add one from Activity.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...recent.map((tx) => _TxRow(tx: tx, repo: repo)),
          const SizedBox(height: 20),
          Text('Investments', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _InvestmentsPreview(repo: repo, currency: currency),
        ],
      ),
    );
  }
}

class _HeroFlowChart extends StatelessWidget {
  const _HeroFlowChart({
    required this.income,
    required this.expense,
    required this.currency,
  });

  final double income;
  final double expense;
  final String currency;

  String _compact(double value) {
    final compact = NumberFormat.compact().format(value.abs());
    return '$currency $compact';
  }

  @override
  Widget build(BuildContext context) {
    final maxY = [income, expense, 1.0].reduce((a, b) => a > b ? a : b) * 1.2;
    final interval = maxY / 4;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 236,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: ZenthoColors.line.withValues(alpha: 0.7),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: interval,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    meta: meta,
                    space: 4,
                    child: Text(
                      NumberFormat.compact().format(value),
                      style: labelStyle,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final isIncome = value.round() == 0;
                  final label = isIncome ? 'Income' : 'Spend';
                  final amount = isIncome ? income : expense;
                  return SideTitleWidget(
                    meta: meta,
                    space: 8,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(_compact(amount), style: labelStyle),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final isIncome = group.x == 0;
                return BarTooltipItem(
                  '${isIncome ? 'Income' : 'Spend'}\n${_compact(rod.toY)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          barGroups: [
            BarChartGroupData(
              x: 0,
              barRods: [
                BarChartRodData(
                  toY: income,
                  width: 42,
                  borderRadius: BorderRadius.circular(12),
                  color: ZenthoColors.teal,
                ),
              ],
            ),
            BarChartGroupData(
              x: 1,
              barRods: [
                BarChartRodData(
                  toY: expense,
                  width: 42,
                  borderRadius: BorderRadius.circular(12),
                  color: ZenthoColors.amber,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: ZenthoColors.line.withValues(alpha: 0.9)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx, required this.repo});

  final MoneyTransaction tx;
  final FinanceRepository repo;

  @override
  Widget build(BuildContext context) {
    final category = repo.categories
        .where((c) => c.id == tx.categoryId)
        .firstOrNull;
    final inMain = MoneyMath.toMain(
      amount: tx.amount,
      currencyCode: tx.currencyCode,
      mainCurrency: repo.settings.mainCurrency,
      rates: repo.rates,
      overrideRate: tx.exchangeRateToMain,
    );
    final signedNative = tx.type == TransactionType.expense
        ? -tx.amount
        : tx.amount;
    final signedMain = tx.type == TransactionType.expense ? -inMain : inMain;
    final foreign = tx.currencyCode != repo.settings.mainCurrency;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => TransactionsScreen.showEditor(context, repo, existing: tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: ZenthoColors.mint,
              child: Icon(
                tx.type == TransactionType.income
                    ? Icons.south_west
                    : Icons.north_east,
                color: ZenthoColors.tealDeep,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category?.name ?? tx.note.ifEmpty('Transaction'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      VisibilityChip(tx.visibility),
                      if (tx.isRecurring) ...[
                        const SizedBox(width: 8),
                        Text(
                          tx.recurringLabel ?? 'Recurring',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(
                  signedNative,
                  currencyCode: tx.currencyCode,
                  signed: true,
                ),
                if (foreign) ...[
                  const SizedBox(height: 2),
                  MoneyText(
                    signedMain,
                    currencyCode: repo.settings.mainCurrency,
                    signed: true,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}

class _InvestmentsPreview extends StatelessWidget {
  const _InvestmentsPreview({required this.repo, required this.currency});

  final FinanceRepository repo;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final portfolio = repo.portfolio;
    final empty = repo.visibleHoldings.isEmpty;
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
      child: empty
          ? Text(
              'Add lots on the Invest tab. Market value (or last cached quote) '
              'rolls into net worth above.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${repo.visibleHoldings.length} holding'
                  '${repo.visibleHoldings.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                MoneyText(portfolio.marketMain, currencyCode: currency),
                if (portfolio.unrealizedPlMain != null) ...[
                  const SizedBox(height: 4),
                  MoneyText(
                    portfolio.unrealizedPlMain!,
                    currencyCode: currency,
                    signed: true,
                  ),
                ],
                if (portfolio.realizedPlMain != 0 ||
                    portfolio.dividendMain != 0) ...[
                  const SizedBox(height: 4),
                  MoneyText(
                    portfolio.realizedPlMain + portfolio.dividendMain,
                    currencyCode: currency,
                    signed: true,
                  ),
                ],
              ],
            ),
    );
  }
}
