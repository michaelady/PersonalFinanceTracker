import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../branding/zentho_logo.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/money_math.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/responsive.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final month = MoneyMath.monthKey(DateTime.now());
    final currency = repo.settings.mainCurrency;
    final byCategory = <String, double>{};

    for (final tx in repo.visibleTransactions.where(
      (t) =>
          t.type == TransactionType.expense &&
          MoneyMath.monthKey(t.date) == month,
    )) {
      final key = tx.categoryId ?? 'other';
      byCategory[key] = (byCategory[key] ?? 0) +
          MoneyMath.toMain(
            amount: tx.amount,
            currencyCode: tx.currencyCode,
            mainCurrency: currency,
            rates: repo.rates,
            overrideRate: tx.exchangeRateToMain,
          );
    }

    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (s, e) => s + e.value);

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Reports')),
        body: AppScaffoldBody(
          child: ListView(
            children: [
              Text(
                'Spend by category',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Month $month · totals in $currency',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (entries.isEmpty)
                const Text('No expenses to chart yet.')
              else ...[
                SizedBox(
                  height: 220,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 48,
                      sections: [
                        for (var i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: entries[i].value,
                            title: total == 0
                                ? ''
                                : '${((entries[i].value / total) * 100).round()}%',
                            radius: 56,
                            color: _colorAt(i),
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...entries.map((e) {
                  final category = repo.categories
                      .where((c) => c.id == e.key)
                      .firstOrNull;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(category?.name ?? 'Other'),
                    trailing: MoneyText(e.value, currencyCode: currency),
                  );
                }),
              ],
              const SizedBox(height: 24),
              Text(
                'Cash flow',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              MoneyText(
                MoneyMath.incomeInMonthMain(
                      transactions: repo.visibleTransactions,
                      monthKeyValue: month,
                      mainCurrency: currency,
                      rates: repo.rates,
                    ) -
                    MoneyMath.expenseInMonthMain(
                      transactions: repo.visibleTransactions,
                      monthKeyValue: month,
                      mainCurrency: currency,
                      rates: repo.rates,
                    ),
                currencyCode: currency,
                signed: true,
                emphasize: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorAt(int i) {
    const colors = [
      ZenthoColors.tealDeep,
      ZenthoColors.tealSoft,
      ZenthoColors.amber,
      ZenthoColors.coral,
      ZenthoColors.sage,
      ZenthoColors.private,
    ];
    return colors[i % colors.length];
  }
}
