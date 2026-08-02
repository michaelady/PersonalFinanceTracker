import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../branding/zentho_logo.dart';
import '../../data/repositories/finance_repository.dart';
import '../../domain/models/models.dart';
import '../../domain/services/csv_data_exchange.dart';
import '../../theme/zentho_colors.dart';
import '../../widgets/responsive.dart';
import '../accounts/accounts_screen.dart';
import '../bills/bill_scan_flow.dart';
import '../reports/reports_screen.dart';
import '../user/user_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<FinanceRepository>();
    final settings = repo.settings;

    return AtmosphereBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Settings')),
        body: AppScaffoldBody(
          child: ListView(
            children: [
              const ZenthoWordmark(showTagline: true, compact: true),
              const SizedBox(height: 24),
              Text('Household', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: const Text('User & sharing'),
                subtitle: Text(
                  settings.householdSharingEnabled
                      ? 'Household sharing on · manage invite link'
                      : 'Profile, invite link, clear all data',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserScreen()),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: settings.activeProfileId,
                decoration: const InputDecoration(labelText: 'Active profile'),
                items: [
                  for (final p in repo.profiles)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (id) {
                  if (id != null) repo.setActiveProfile(id);
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show shared'),
                value: settings.showShared,
                activeThumbColor: ZenthoColors.tealDeep,
                onChanged: (v) => repo.setVisibilityFilters(showShared: v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show private'),
                value: settings.showPrivate,
                activeThumbColor: ZenthoColors.private,
                onChanged: (v) => repo.setVisibilityFilters(showPrivate: v),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _addProfile(context, repo),
                child: const Text('Add household profile'),
              ),
              const SizedBox(height: 24),
              Text('Currency', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: settings.mainCurrency,
                decoration: const InputDecoration(labelText: 'Main currency'),
                items: [
                  for (final r in repo.rates)
                    DropdownMenuItem(value: r.code, child: Text(r.code)),
                ],
                onChanged: (code) {
                  if (code != null) repo.setMainCurrency(code);
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  repo.ratesRefreshing
                      ? 'Refreshing exchange rates…'
                      : 'Rates (1 unit → ${settings.mainCurrency})',
                ),
                subtitle: Text(
                  [
                    if (repo.ratesSource != null) 'Source: ${repo.ratesSource}',
                    if (repo.ratesUpdatedAt != null)
                      'Updated: ${repo.ratesUpdatedAt!.toLocal()}',
                    if (repo.ratesError != null) repo.ratesError!,
                    'Includes CHF & RON. Editable offline.',
                  ].join('\n'),
                ),
                trailing: IconButton(
                  tooltip: 'Refresh online',
                  onPressed: repo.ratesRefreshing
                      ? null
                      : () => repo.refreshRatesOnline(),
                  icon: repo.ratesRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync_outlined),
                ),
              ),
              const SizedBox(height: 8),
              ...repo.rates.map(
                (rate) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(rate.code),
                  subtitle: Text(rate.rateToMain.toStringAsFixed(6)),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editRate(context, repo, rate),
                ),
              ),
              const SizedBox(height: 16),
              Text('Data', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Accounts'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountsScreen()),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insights_outlined),
                title: const Text('Reports'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsScreen()),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export all data (CSV)'),
                subtitle: const Text(
                  'Full backup plus ledger/balances sheets for spreadsheet debugging',
                ),
                onTap: () => _exportCsv(context, repo),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Import CSV'),
                subtitle: const Text(
                  'Full Zentho export (replaces all) or bank CSV '
                  '(date,amount,type,category,account,…)',
                ),
                onTap: () => _importCsv(context, repo),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('Scan bill or invoice'),
                subtitle: const Text(
                  'Photo or paste text, then add categorized expenses',
                ),
                onTap: () => BillScanFlow.start(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever_outlined,
                    color: Colors.red.shade700),
                title: const Text('Clear all data'),
                subtitle: const Text(
                  'Wipe this device and return to setup',
                ),
                onTap: () => _clearAll(context, repo),
              ),
              const SizedBox(height: 24),
              Text(
                'Offline-first · share household by invite link · '
                'investments roadmap ready',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _clearAll(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text(
          'This permanently removes all Zentho data on this device and '
          'returns you to setup. Export a CSV first if you might need it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repo.clearAllData();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All data cleared')),
    );
  }

  Future<void> _addProfile(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add profile'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (ok == true && controller.text.trim().isNotEmpty) {
      await repo.addProfile(controller.text.trim());
    }
    controller.dispose();
  }

  Future<void> _editRate(
    BuildContext context,
    FinanceRepository repo,
    CurrencyRate rate,
  ) async {
    final controller =
        TextEditingController(text: rate.rateToMain.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rate for ${rate.code}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '1 ${rate.code} in ${repo.settings.mainCurrency}',
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
      final value = double.tryParse(controller.text.trim());
      if (value != null && value > 0) {
        await repo.upsertRate(
          CurrencyRate(
            code: rate.code,
            rateToMain: value,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }
    controller.dispose();
  }

  Future<void> _exportCsv(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    try {
      final exported = repo.exportFullCsv();
      final bytes = utf8.encode(exported.csvBody);
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Export Zentho data',
        fileName: exported.fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(bytes),
      );
      if (!context.mounted) return;
      if (savedPath == null) {
        await Clipboard.setData(ClipboardData(text: exported.csvBody));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export copied to clipboard (save canceled)'),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${exported.fileName}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _importCsv(
    BuildContext context,
    FinanceRepository repo,
  ) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (result == null) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read CSV bytes')),
          );
        }
        return;
      }
      final csvBody = utf8.decode(bytes, allowMalformed: true);

      if (CsvDataExchange.looksLikeFullExport(csvBody)) {
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace all data?'),
            content: const Text(
              'This file is a full Zentho export. Importing it will replace '
              'settings, profiles, accounts, categories, transactions, '
              'budgets, goals, and rates.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }

      final importResult = await repo.importCsv(csvBody);
      if (!context.mounted) return;
      if (importResult.isFullReplace) {
        final warningCount = importResult.full?.warnings.length ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              warningCount == 0
                  ? 'Full data import complete'
                  : 'Full data import complete ($warningCount warning'
                      '${warningCount == 1 ? '' : 's'})',
            ),
          ),
        );
      } else {
        final tx = importResult.transactions!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${tx.transactions.length} transaction'
              '${tx.transactions.length == 1 ? '' : 's'}, '
              'skipped ${tx.skippedRows}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }
}
