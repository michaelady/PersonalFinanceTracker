import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
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
            'Savings targets for the household or just for you.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: () => _addGoal(context, repo),
              child: const Text('New goal'),
            ),
          ),
          const SizedBox(height: 20),
          if (goals.isEmpty)
            Text('No goals yet.', style: Theme.of(context).textTheme.bodyLarge)
          else
            ...goals.map((goal) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
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
              );
            }),
        ],
      ),
    );
  }

  Future<void> _addGoal(BuildContext context, FinanceRepository repo) async {
    final name = TextEditingController();
    final target = TextEditingController(text: '1000');
    VisibilityScope visibility = VisibilityScope.shared;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New savings goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: target,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Target (${repo.settings.mainCurrency})',
              ),
            ),
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
              onChanged: (v) => visibility = v ?? VisibilityScope.shared,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok == true && name.text.trim().isNotEmpty) {
      await repo.addGoal(
        SavingsGoal.create(
          name: name.text.trim(),
          targetAmount: double.tryParse(target.text.trim()) ?? 0,
          currencyCode: repo.settings.mainCurrency,
          ownerProfileId: repo.settings.activeProfileId,
          visibility: visibility,
        ),
      );
    }
    name.dispose();
    target.dispose();
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
