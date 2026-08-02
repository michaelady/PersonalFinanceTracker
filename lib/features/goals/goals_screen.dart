import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/supported_currencies.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/responsive.dart';
import '../../widgets/visibility_chip.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final goals = repo.visibleGoals;

    return AppScaffoldBody(
      child: ListView(
        children: [
          Text('Goals', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Tap a goal to edit. Savings targets for the household or just for you.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: () => _editGoal(context, repo),
              child: const Text('New goal'),
            ),
          ),
          const SizedBox(height: 20),
          if (goals.isEmpty)
            Text('No goals yet.', style: Theme.of(context).textTheme.bodyLarge)
          else
            ...goals.map((goal) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _editGoal(context, repo, existing: goal),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              goal.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          VisibilityChip(goal.visibility),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: goal.progress),
                        duration: const Duration(milliseconds: 500),
                        builder: (context, value, _) => ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 12,
                            backgroundColor: ZenthoColors.line,
                            color: ZenthoColors.tealDeep,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          MoneyText(
                            goal.currentAmount,
                            currencyCode: goal.currencyCode,
                          ),
                          Text(
                            ' / ',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          MoneyText(
                            goal.targetAmount,
                            currencyCode: goal.currencyCode,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _contribute(context, repo, goal),
                            child: const Text('Add progress'),
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

  Future<void> _editGoal(
    BuildContext context,
    FinanceRepository repo, {
    SavingsGoal? existing,
  }) async {
    final isEditing = existing != null;
    final name = TextEditingController(text: existing?.name ?? '');
    final target = TextEditingController(
      text: (existing?.targetAmount ?? 1000).toString(),
    );
    final current = TextEditingController(
      text: (existing?.currentAmount ?? 0).toString(),
    );
    var visibility = existing?.visibility ?? VisibilityScope.shared;
    var currencyCode =
        existing?.currencyCode ?? repo.settings.mainCurrency;

    final ok = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(isEditing ? 'Edit goal' : 'New savings goal'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: currencyCode,
                decoration: const InputDecoration(labelText: 'Currency'),
                items: [
                  for (final code in SupportedCurrencies.codes)
                    DropdownMenuItem(value: code, child: Text(code)),
                ],
                onChanged: (v) =>
                    setLocal(() => currencyCode = v ?? currencyCode),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: target,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Target ($currencyCode)',
                ),
              ),
              if (isEditing) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: current,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Current ($currencyCode)',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<VisibilityScope>(
                // ignore: deprecated_member_use
                value: visibility,
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

    if (ok == 'save' && name.text.trim().isNotEmpty) {
      final targetAmount = double.tryParse(target.text.trim()) ?? 0;
      if (isEditing) {
        await repo.updateGoal(
          existing.copyWith(
            name: name.text.trim(),
            targetAmount: targetAmount,
            currentAmount: double.tryParse(current.text.trim()) ??
                existing.currentAmount,
            currencyCode: currencyCode,
            visibility: visibility,
          ),
        );
      } else {
        await repo.addGoal(
          SavingsGoal.create(
            name: name.text.trim(),
            targetAmount: targetAmount,
            currencyCode: currencyCode,
            ownerProfileId: repo.settings.activeProfileId,
            visibility: visibility,
          ),
        );
      }
    } else if (ok == 'delete' && isEditing) {
      await repo.deleteGoal(existing.id);
    }
    name.dispose();
    target.dispose();
    current.dispose();
  }

  Future<void> _contribute(
    BuildContext context,
    FinanceRepository repo,
    SavingsGoal goal,
  ) async {
    final controller = TextEditingController(text: '50');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add to ${goal.name}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount (${goal.currencyCode})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final add = double.tryParse(controller.text.trim()) ?? 0;
      await repo.updateGoalProgress(goal.id, goal.currentAmount + add);
    }
    controller.dispose();
  }
}
