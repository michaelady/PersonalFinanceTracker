import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/money_math.dart';
import '../../domain/services/recurrence_period.dart';
import '../../domain/services/supported_currencies.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/responsive.dart';
import '../../widgets/sheet_inset.dart';
import '../../widgets/visibility_chip.dart';
import '../bills/bill_scan_flow.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  static Future<void> showAddSheet(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    await showEditor(context, repo);
  }

  static Future<void> showAddActions(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add manually'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan bill or invoice'),
              subtitle: const Text('Photo or paste text → auto-categorize'),
              onTap: () => Navigator.pop(context, 'scan'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'scan') {
      await BillScanFlow.start(context);
    } else {
      await showAddSheet(context, repo);
    }
  }

  static Future<void> showEditor(
    BuildContext context,
    FinanceRepository repo, {
    MoneyTransaction? existing,
  }) async {
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
      builder: (context) => SheetInset(
        child: _TransactionEditor(existing: existing),
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
            'Tap any item to edit. Shared household spend and your private entries.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: () => BillScanFlow.start(context),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan bill'),
            ),
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
                      final inMain = MoneyMath.toMain(
                        amount: tx.amount,
                        currencyCode: tx.currencyCode,
                        mainCurrency: repo.settings.mainCurrency,
                        rates: repo.rates,
                        overrideRate: tx.exchangeRateToMain,
                      );
                      final signedMain = tx.type == TransactionType.expense
                          ? -inMain
                          : inMain;
                      final foreign =
                          tx.currencyCode != repo.settings.mainCurrency;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(category?.name ?? 'Transfer'),
                        subtitle: Text(
                          [
                            account?.name ?? 'Account',
                            tx.currencyCode,
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
                            if (foreign)
                              MoneyText(
                                signedMain,
                                currencyCode: repo.settings.mainCurrency,
                                signed: true,
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              const SizedBox(height: 4),
                            VisibilityChip(tx.visibility),
                          ],
                        ),
                        onTap: () => showEditor(context, repo, existing: tx),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TransactionEditor extends StatefulWidget {
  const _TransactionEditor({this.existing});

  final MoneyTransaction? existing;

  @override
  State<_TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<_TransactionEditor> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late TransactionType _type;
  late VisibilityScope _visibility;
  String? _accountId;
  String? _categoryId;
  late bool _recurring;
  late RecurrencePeriod _recurrencePeriod;
  late String _currency;
  late DateTime _date;
  String? _amountError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final repo = context.read<FinanceRepository>();
    final existing = widget.existing;
    _type = existing?.type ?? TransactionType.expense;
    _visibility = existing?.visibility ?? VisibilityScope.shared;
    _accountId = existing?.accountId ?? repo.accounts.first.id;
    _currency = existing?.currencyCode ??
        repo.accounts
            .firstWhere(
              (a) => a.id == _accountId,
              orElse: () => repo.accounts.first,
            )
            .currencyCode;
    final cats = repo.categories
        .where(
          (c) => _type == TransactionType.income ? c.isIncome : !c.isIncome,
        )
        .toList();
    _categoryId = existing?.categoryId ?? (cats.isEmpty ? null : cats.first.id);
    _recurring = existing?.isRecurring ?? false;
    _recurrencePeriod =
        existing?.recurrencePeriod ?? RecurrencePeriod.monthly;
    _date = existing?.date ?? DateTime.now();
    _amount = TextEditingController(
      text: existing == null ? '' : existing.amount.toString(),
    );
    _note = TextEditingController(text: existing?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _validateAmount(String raw) {
    final amount = double.tryParse(raw.trim());
    if (amount == null || amount <= 0) {
      return 'Enter an amount greater than 0';
    }
    return null;
  }

  Future<void> _save(FinanceRepository repo) async {
    final error = _validateAmount(_amount.text);
    if (error != null) {
      setState(() => _amountError = error);
      return;
    }
    if (_accountId == null || _categoryId == null) {
      setState(() => _amountError = 'Choose an account and category');
      return;
    }
    final amount = double.parse(_amount.text.trim());

    final note = _note.text.trim();
    String? createdId;
    if (_isEditing) {
      await repo.updateTransaction(
        widget.existing!.copyWith(
          type: _type,
          amount: amount,
          currencyCode: _currency,
          accountId: _accountId,
          categoryId: _categoryId,
          date: _date,
          visibility: _visibility,
          note: note,
          isRecurring: _recurring,
          recurringLabel:
              _recurring ? (note.isEmpty ? 'Recurring' : note) : null,
          recurrencePeriod: _recurrencePeriod,
        ),
      );
    } else {
      final created = MoneyTransaction.create(
        type: _type,
        amount: amount,
        currencyCode: _currency,
        accountId: _accountId!,
        categoryId: _categoryId,
        date: _date,
        ownerProfileId: repo.settings.activeProfileId,
        visibility: _visibility,
        note: note,
        isRecurring: _recurring,
        recurringLabel:
            _recurring ? (note.isEmpty ? 'Recurring' : note) : null,
        recurrencePeriod: _recurrencePeriod,
      );
      await repo.addTransaction(created);
      createdId = created.id;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(_isEditing ? 'Transaction updated' : 'Transaction saved'),
        action: createdId == null
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () => repo.deleteTransaction(createdId!),
              ),
      ),
    );
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
          Text(
            _isEditing ? 'Edit transaction' : 'New transaction',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
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
                if (!cats.any((c) => c.id == _categoryId)) {
                  _categoryId = cats.isEmpty ? null : cats.first.id;
                }
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('transaction-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_amountError == null) return;
              setState(() => _amountError = _validateAmount(_amount.text));
            },
            decoration: InputDecoration(
              labelText: 'Amount',
              errorText: _amountError,
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    // ignore: deprecated_member_use
                    value: SupportedCurrencies.codes.contains(_currency)
                        ? _currency
                        : repo.settings.mainCurrency,
                    alignment: Alignment.centerRight,
                    items: [
                      for (final code in SupportedCurrencies.codes)
                        DropdownMenuItem(
                          value: code,
                          child: Text(
                            code,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: ZenthoColors.tealDeep,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                    ],
                    onChanged: (code) {
                      if (code != null) setState(() => _currency = code);
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: _accountId,
            decoration: const InputDecoration(labelText: 'Account'),
            items: [
              for (final a in repo.accounts)
                DropdownMenuItem(
                  value: a.id,
                  child: Text('${a.name} (${a.currencyCode})'),
                ),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: categories.any((c) => c.id == _categoryId)
                ? _categoryId
                : (categories.isEmpty ? null : categories.first.id),
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text(
              '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
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
          if (_recurring) ...[
            DropdownButtonFormField<RecurrencePeriod>(
              // ignore: deprecated_member_use
              value: _recurrencePeriod,
              decoration: const InputDecoration(labelText: 'Recurs every'),
              items: [
                for (final p in RecurrencePeriod.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _recurrencePeriod = v);
              },
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('transaction-save'),
            onPressed: () => _save(repo),
            child: Text(_isEditing ? 'Save changes' : 'Save'),
          ),
          if (_isEditing) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                await repo.deleteTransaction(widget.existing!.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(
                'Delete',
                style: TextStyle(color: ZenthoColors.coral),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
