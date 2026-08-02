import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/budget_forecast.dart';
import '../../domain/services/money_math.dart';
import '../../domain/services/recurrence_period.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/responsive.dart';
import '../../widgets/visibility_chip.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  ForecastHorizon _horizon = ForecastHorizon.y1;
  RecurrencePeriod _recurrence = RecurrencePeriod.monthly;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final month = MoneyMath.monthKey(DateTime.now());
    final budgets =
        repo.visibleBudgets.where((b) => b.monthKey == month).toList();
    final expenseCategories =
        repo.categories.where((c) => !c.isIncome).toList();
    final forecast = BudgetForecast.project(
      accounts: repo.visibleAccounts,
      transactions: repo.visibleTransactions,
      budgets: budgets,
      mainCurrency: repo.settings.mainCurrency,
      rates: repo.rates,
      horizon: _horizon,
      recurrence: _recurrence,
    );

    return AppScaffoldBody(
      child: ListView(
        children: [
          Text('Budgets', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Tap a budget to edit. Forecasts use recurring bills, your budgets, '
            'and typical unbudgeted one-offs from recent months.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _PredictionCards(
            currency: repo.settings.mainCurrency,
            endOfMonth: forecast.endOfMonthBalance,
            endOfPeriod: forecast.endOfPeriodBalance,
            periodLabel: _horizon.label,
            endOfYear: forecast.endOfYearBalance,
            monthlyNet: forecast.monthlyNet,
            recurringIncome: forecast.recurringIncomeMonthly,
            plannedExpenses: forecast.plannedExpensesMonthly,
            highSavingsRate: forecast.highSavingsRate,
          ),
          const SizedBox(height: 20),
          Text(
            'Total prediction',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ForecastHorizon>(
            // ignore: deprecated_member_use
            value: _horizon,
            decoration: const InputDecoration(
              labelText: 'Prediction period',
            ),
            items: [
              for (final h in ForecastHorizon.values)
                DropdownMenuItem(value: h, child: Text(h.label)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _horizon = v);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<RecurrencePeriod>(
            // ignore: deprecated_member_use
            value: _recurrence,
            decoration: const InputDecoration(
              labelText: 'Recurrence',
              helperText:
                  'Chart sampling + how recurring amounts are normalized in the summary',
            ),
            items: [
              for (final p in RecurrencePeriod.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _recurrence = v);
            },
          ),
          const SizedBox(height: 12),
          _ForecastChart(
            series: forecast.series,
            currency: repo.settings.mainCurrency,
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: () =>
                  _editBudget(context, repo, expenseCategories, month),
              child: const Text('Set category budget'),
            ),
          ),
          const SizedBox(height: 20),
          if (budgets.isEmpty)
            Text(
              'No budgets this month yet.',
              style: Theme.of(context).textTheme.bodyLarge,
            )
          else
            ...budgets.map((budget) {
              final category = repo.categories
                  .firstWhere((c) => c.id == budget.categoryId);
              final spent = MoneyMath.spentInCategoryMain(
                categoryId: budget.categoryId,
                monthKeyValue: month,
                transactions: repo.visibleTransactions,
                mainCurrency: repo.settings.mainCurrency,
                rates: repo.rates,
              );
              final progress =
                  budget.allocated <= 0 ? 0.0 : (spent / budget.allocated);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _editBudget(
                  context,
                  repo,
                  expenseCategories,
                  month,
                  existing: budget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              category.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          VisibilityChip(budget.visibility),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0, 1),
                          minHeight: 10,
                          backgroundColor: ZenthoColors.line,
                          color: progress > 1
                              ? ZenthoColors.coral
                              : ZenthoColors.teal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          MoneyText(
                            spent,
                            currencyCode: repo.settings.mainCurrency,
                          ),
                          Text(
                            ' of ',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          MoneyText(
                            budget.allocated,
                            currencyCode: repo.settings.mainCurrency,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _editBudget(
    BuildContext context,
    FinanceRepository repo,
    List<SpendCategory> categories,
    String month, {
    BudgetCategory? existing,
  }) async {
    if (categories.isEmpty) return;
    final isEditing = existing != null;
    var categoryId = existing?.categoryId ?? categories.first.id;
    final amountController = TextEditingController(
      text: (existing?.allocated ?? 100).toString(),
    );
    var visibility = existing?.visibility ?? VisibilityScope.shared;

    final ok = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(isEditing ? 'Edit budget' : 'Category budget'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) =>
                    setLocal(() => categoryId = v ?? categoryId),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Allocated (${repo.settings.mainCurrency})',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<VisibilityScope>(
                // ignore: deprecated_member_use
                value: visibility,
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
                    setLocal(() => visibility = v ?? VisibilityScope.shared),
              ),
            ],
          ),
          actions: [
            if (isEditing)
              TextButton(
                onPressed: () => Navigator.pop(context, 'delete'),
                child: Text(
                  'Delete',
                  style: TextStyle(color: ZenthoColors.coral),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok == 'save') {
      final amount = double.tryParse(amountController.text.trim()) ?? 0;
      if (isEditing) {
        await repo.upsertBudget(
          existing.copyWith(
            categoryId: categoryId,
            allocated: amount,
            visibility: visibility,
          ),
        );
      } else {
        await repo.upsertBudget(
          BudgetCategory.create(
            categoryId: categoryId,
            monthKey: month,
            allocated: amount,
            visibility: visibility,
            ownerProfileId: repo.settings.activeProfileId,
          ),
        );
      }
    } else if (ok == 'delete' && isEditing) {
      await repo.deleteBudget(existing.id);
    }
    amountController.dispose();
  }
}

class _PredictionCards extends StatelessWidget {
  const _PredictionCards({
    required this.currency,
    required this.endOfMonth,
    required this.endOfPeriod,
    required this.periodLabel,
    required this.endOfYear,
    required this.monthlyNet,
    required this.recurringIncome,
    required this.plannedExpenses,
    required this.highSavingsRate,
  });

  final String currency;
  final double endOfMonth;
  final double endOfPeriod;
  final String periodLabel;
  final double endOfYear;
  final double monthlyNet;
  final double recurringIncome;
  final double plannedExpenses;
  final bool highSavingsRate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _PredictTile(
                label: 'End of month',
                child: MoneyText(endOfMonth, currencyCode: currency),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PredictTile(
                label: 'End of period ($periodLabel)',
                child: MoneyText(endOfPeriod, currencyCode: currency),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PredictTile(
          label: 'End of calendar year',
          child: MoneyText(endOfYear, currencyCode: currency),
        ),
        const SizedBox(height: 8),
        _PredictTile(
          label: 'Assumed monthly income',
          child: MoneyText(recurringIncome, currencyCode: currency, signed: true),
        ),
        const SizedBox(height: 8),
        _PredictTile(
          label: 'Assumed monthly expenses',
          child: MoneyText(-plannedExpenses, currencyCode: currency, signed: true),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Recurring bills + category budgets + typical unbudgeted one-offs',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ZenthoColors.inkMuted,
                ),
          ),
        ),
        const SizedBox(height: 8),
        _PredictTile(
          label: 'Projected monthly net',
          child: MoneyText(monthlyNet, currencyCode: currency, signed: true),
        ),
        if (highSavingsRate) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ZenthoColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ZenthoColors.amber.withValues(alpha: 0.4)),
            ),
            child: Text(
              'Savings rate looks high from the data entered. If this feels '
              'too optimistic, add missing recurring expenses or budgets '
              '(dining, transport, fun, etc.).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

class _PredictTile extends StatelessWidget {
  const _PredictTile({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: ZenthoColors.line),
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.55),
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

class _ForecastChart extends StatelessWidget {
  const _ForecastChart({required this.series, required this.currency});

  final List<ForecastPoint> series;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (series.length < 2) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('Not enough data to chart yet.')),
      );
    }

    final minY = series.map((e) => e.balance).reduce((a, b) => a < b ? a : b);
    final maxY = series.map((e) => e.balance).reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.12).clamp(1.0, double.infinity);
    final format = DateFormat.yMMMd();

    return Container(
      height: 240,
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
      decoration: BoxDecoration(
        border: Border.all(color: ZenthoColors.line),
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.45),
      ),
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
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
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                interval: (series.length / 3).clamp(1, series.length).toDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= series.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      format.format(series[i].date),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '$currency ${s.y.toStringAsFixed(0)}\n${format.format(series[s.x.toInt()].date)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < series.length; i++)
                  FlSpot(i.toDouble(), series[i].balance),
              ],
              isCurved: true,
              color: ZenthoColors.tealDeep,
              barWidth: 3,
              dotData: FlDotData(show: series.length <= 14),
              belowBarData: BarAreaData(
                show: true,
                color: ZenthoColors.tealSoft.withValues(alpha: 0.18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
