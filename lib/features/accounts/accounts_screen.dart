import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../branding/zentho_logo.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/money_math.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/money_text.dart';
import '../../widgets/responsive.dart';
import '../../widgets/visibility_chip.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final accounts = repo.visibleAccounts;

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Accounts'),
          actions: [
            IconButton(
              onPressed: () => _editAccount(context, repo),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: AppScaffoldBody(
          child: accounts.isEmpty
              ? const Center(child: Text('No accounts yet.'))
              : ListView.separated(
                  itemCount: accounts.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final account = accounts[index];
                    final balance = MoneyMath.balanceForAccount(
                      account: account,
                      transactions: repo.visibleTransactions,
                      mainCurrency: repo.settings.mainCurrency,
                      rates: repo.rates,
                    );
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(account.name),
                      subtitle: Text(
                        '${account.type.name} · ${account.currencyCode}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(
                            balance,
                            currencyCode: repo.settings.mainCurrency,
                          ),
                          const SizedBox(height: 4),
                          VisibilityChip(account.visibility),
                        ],
                      ),
                      onTap: () =>
                          _editAccount(context, repo, existing: account),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _editAccount(
    BuildContext context,
    FinanceRepository repo, {
    Account? existing,
  }) async {
    final isEditing = existing != null;
    final name = TextEditingController(text: existing?.name ?? '');
    final balance = TextEditingController(
      text: (existing?.openingBalance ?? 0).toString(),
    );
    var type = existing?.type ?? AccountType.checking;
    var currency = existing?.currencyCode ?? repo.settings.mainCurrency;
    var visibility = existing?.visibility ?? VisibilityScope.shared;
    const currencies = ['USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD'];

    final ok = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(isEditing ? 'Edit account' : 'Add account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountType>(
                  // ignore: deprecated_member_use
                  value: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    for (final t in AccountType.values)
                      DropdownMenuItem(value: t, child: Text(t.name)),
                  ],
                  onChanged: (v) => setLocal(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [
                    for (final c in currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setLocal(() => currency = v ?? currency),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: balance,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Opening balance'),
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
                      setLocal(() => visibility = v ?? visibility),
                ),
              ],
            ),
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
      final opening = double.tryParse(balance.text.trim()) ?? 0;
      if (isEditing) {
        await repo.updateAccount(
          existing.copyWith(
            name: name.text.trim(),
            type: type,
            currencyCode: currency,
            openingBalance: opening,
            visibility: visibility,
          ),
        );
      } else {
        await repo.addAccount(
          Account.create(
            name: name.text.trim(),
            type: type,
            currencyCode: currency,
            ownerProfileId: repo.settings.activeProfileId,
            visibility: visibility,
            openingBalance: opening,
          ),
        );
      }
    } else if (ok == 'delete' && isEditing) {
      await repo.deleteAccount(existing.id);
    }
    name.dispose();
    balance.dispose();
  }
}
