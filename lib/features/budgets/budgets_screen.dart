import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/money_math.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/responsive.dart';
import '../../widgets/visibility_chip.dart';

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final month = MoneyMath.monthKey(DateTime.now());
    final budgets =
        repo.visibleBudgets.where((b) => b.monthKey == month).toList();
    final expenseCategories =
        repo.categories.where((c) => !c.isIncome).toList();

    return AppScaffoldBody(
      child: ListView(
        children: [
          Text('Budgets', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Tap a budget to edit. Hybrid envelopes for $month.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
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
