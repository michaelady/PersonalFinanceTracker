import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/responsive.dart';
import '../../widgets/visibility_chip.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  static Future<void> showAddSheet(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    if (repo.accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an account first in Settings.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: const _AddTransactionForm(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final items = repo.visibleTransactions;

    return AppScaffoldBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Activity', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Shared household spend and your private entries.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'No activity yet.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = items[index];
                      final category = repo.categories
                          .where((c) => c.id == tx.categoryId)
                          .firstOrNull;
                      final account = repo.accounts
                          .where((a) => a.id == tx.accountId)
                          .firstOrNull;
                      final signed = tx.type == TransactionType.expense
                          ? -tx.amount
                          : tx.amount;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(category?.name ?? 'Transfer'),
                        subtitle: Text(
                          [
                            account?.name ?? 'Account',
                            if (tx.note.isNotEmpty) tx.note,
                            if (tx.isRecurring)
                              tx.recurringLabel ?? 'Recurring',
                          ].join(' · '),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            MoneyText(
                              signed,
                              currencyCode: tx.currencyCode,
                              signed: true,
                            ),
                            const SizedBox(height: 4),
                            VisibilityChip(tx.visibility),
                          ],
                        ),
                        onLongPress: () async {
                          await repo.deleteTransaction(tx.id);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AddTransactionForm extends StatefulWidget {
  const _AddTransactionForm();

  @override
  State<_AddTransactionForm> createState() => _AddTransactionFormState();
}

class _AddTransactionFormState extends State<_AddTransactionForm> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  TransactionType _type = TransactionType.expense;
  VisibilityScope _visibility = VisibilityScope.shared;
  String? _accountId;
  String? _categoryId;
  bool _recurring = false;
  late String _currency;

  @override
  void initState() {
    super.initState();
    final repo = context.read<FinanceRepository>();
    _accountId = repo.accounts.first.id;
    _currency = repo.accounts.first.currencyCode;
    final cats = repo.categories.where((c) => !c.isIncome).toList();
    _categoryId = cats.isEmpty ? null : cats.first.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final categories = repo.categories
        .where(
          (c) => _type == TransactionType.income ? c.isIncome : !c.isIncome,
        )
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New transaction',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          SegmentedButton<TransactionType>(
            segments: const [
              ButtonSegment(
                value: TransactionType.expense,
                label: Text('Expense'),
              ),
              ButtonSegment(
                value: TransactionType.income,
                label: Text('Income'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) {
              setState(() {
                _type = s.first;
                final cats = repo.categories
                    .where(
                      (c) => _type == TransactionType.income
                          ? c.isIncome
                          : !c.isIncome,
                    )
                    .toList();
                _categoryId = cats.isEmpty ? null : cats.first.id;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _accountId,
            decoration: const InputDecoration(labelText: 'Account'),
            items: [
              for (final a in repo.accounts)
                DropdownMenuItem(value: a.id, child: Text(a.name)),
            ],
            onChanged: (v) {
              setState(() {
                _accountId = v;
                final account =
                    repo.accounts.firstWhere((a) => a.id == v);
                _currency = account.currencyCode;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _categoryId,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
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
                setState(() => _visibility = v ?? VisibilityScope.shared),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Recurring / subscription'),
            value: _recurring,
            activeThumbColor: ZenthoColors.tealDeep,
            onChanged: (v) => setState(() => _recurring = v),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(_amount.text.trim());
              if (amount == null ||
                  amount <= 0 ||
                  _accountId == null ||
                  _categoryId == null) {
                return;
              }
              await repo.addTransaction(
                MoneyTransaction.create(
                  type: _type,
                  amount: amount,
                  currencyCode: _currency,
                  accountId: _accountId!,
                  categoryId: _categoryId,
                  ownerProfileId: repo.settings.activeProfileId,
                  visibility: _visibility,
                  note: _note.text.trim(),
                  isRecurring: _recurring,
                  recurringLabel: _recurring ? _note.text.trim() : null,
                ),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
