import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../branding/zentho_logo.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/money_math.dart';
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
              onPressed: () => _addAccount(context, repo),
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
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _addAccount(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    final name = TextEditingController();
    final balance = TextEditingController(text: '0');
    var type = AccountType.checking;
    var currency = repo.settings.mainCurrency;
    var visibility = VisibilityScope.shared;
    const currencies = ['USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD'];

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add account'),
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
                onChanged: (v) => type = v ?? type,
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
                onChanged: (v) => currency = v ?? currency,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balance,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Opening balance'),
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
                onChanged: (v) => visibility = v ?? visibility,
              ),
            ],
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

    if (ok == true && name.text.trim().isNotEmpty) {
      await repo.addAccount(
        Account.create(
          name: name.text.trim(),
          type: type,
          currencyCode: currency,
          ownerProfileId: repo.settings.activeProfileId,
          visibility: visibility,
          openingBalance: double.tryParse(balance.text.trim()) ?? 0,
        ),
      );
    }
    name.dispose();
    balance.dispose();
  }
}
