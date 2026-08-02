import 'package:csv/csv.dart';

import '../models/models.dart';
import 'money_math.dart';
import 'recurrence_period.dart';

class CsvFullExportResult {
  const CsvFullExportResult({required this.csvBody, required this.fileName});

  final String csvBody;
  final String fileName;
}

class CsvFullImportResult {
  const CsvFullImportResult({
    required this.snapshot,
    required this.warnings,
  });

  final FinanceSnapshot snapshot;
  final List<String> warnings;
}

/// Multi-section CSV pack for moving all Zentho data between devices/tools.
///
/// Format:
/// ```
/// # zentho_export_v1
/// # exported_at,<iso>
///
/// [settings]
/// ...
/// [profiles]
/// ...
/// [accounts]
/// ...
/// [categories]
/// ...
/// [transactions]
/// ...
/// [budgets]
/// ...
/// [goals]
/// ...
/// [rates]
/// ...
/// [ledger]          # export-only, denormalized for spreadsheet debugging
/// [account_balances]# export-only
/// ```
abstract final class CsvDataExchange {
  static const formatMarker = '# zentho_export_v1';
  static const importSections = {
    'settings',
    'profiles',
    'accounts',
    'categories',
    'transactions',
    'budgets',
    'goals',
    'rates',
  };

  static bool looksLikeFullExport(String csvBody) {
    final trimmed = csvBody.trimLeft();
    if (trimmed.startsWith(formatMarker)) return true;
    return RegExp(r'^\[settings\]\s*$', multiLine: true).hasMatch(csvBody);
  }

  static CsvFullExportResult exportSnapshot(
    FinanceSnapshot snapshot, {
    DateTime? exportedAt,
  }) {
    final at = (exportedAt ?? DateTime.now().toUtc()).toIso8601String();
    final buffer = StringBuffer()
      ..writeln(formatMarker)
      ..writeln('# exported_at,$at')
      ..writeln('# main_currency,${snapshot.settings.mainCurrency}')
      ..writeln(
        '# tip,Import this file via Settings → Import CSV to replace all data. '
        '[ledger] and [account_balances] are ignored on import.',
      )
      ..writeln();

    void writeSection(String name, List<String> headers, List<List<dynamic>> rows) {
      buffer.writeln('[$name]');
      buffer.writeln(_encode([headers, ...rows]));
      buffer.writeln();
    }

    writeSection(
      'settings',
      const [
        'mainCurrency',
        'activeProfileId',
        'onboardingComplete',
        'showPrivate',
        'showShared',
        'householdCloudId',
        'householdInviteKey',
        'householdUpdatedAt',
      ],
      [
        [
          snapshot.settings.mainCurrency,
          snapshot.settings.activeProfileId,
          snapshot.settings.onboardingComplete,
          snapshot.settings.showPrivate,
          snapshot.settings.showShared,
          snapshot.settings.householdCloudId ?? '',
          snapshot.settings.householdInviteKey ?? '',
          snapshot.settings.householdUpdatedAt?.toIso8601String() ?? '',
        ],
      ],
    );

    writeSection(
      'profiles',
      const ['id', 'name', 'colorHex'],
      [
        for (final p in snapshot.profiles) [p.id, p.name, p.colorHex],
      ],
    );

    writeSection(
      'accounts',
      const [
        'id',
        'name',
        'type',
        'currencyCode',
        'openingBalance',
        'ownerProfileId',
        'visibility',
        'includeInNetWorth',
        'archived',
      ],
      [
        for (final a in snapshot.accounts)
          [
            a.id,
            a.name,
            a.type.name,
            a.currencyCode,
            a.openingBalance,
            a.ownerProfileId,
            a.visibility.name,
            a.includeInNetWorth,
            a.archived,
          ],
      ],
    );

    writeSection(
      'categories',
      const ['id', 'name', 'iconName', 'colorHex', 'isIncome', 'isSystem'],
      [
        for (final c in snapshot.categories)
          [c.id, c.name, c.iconName, c.colorHex, c.isIncome, c.isSystem],
      ],
    );

    final accountName = {for (final a in snapshot.accounts) a.id: a.name};
    final categoryName = {for (final c in snapshot.categories) c.id: c.name};

    writeSection(
      'transactions',
      const [
        'id',
        'date',
        'amount',
        'type',
        'currencyCode',
        'accountId',
        'accountName',
        'categoryId',
        'categoryName',
        'ownerProfileId',
        'visibility',
        'note',
        'transferAccountId',
        'exchangeRateToMain',
        'isRecurring',
        'recurringLabel',
        'recurrencePeriod',
      ],
      [
        for (final t in snapshot.transactions)
          [
            t.id,
            t.date.toIso8601String(),
            t.amount,
            t.type.name,
            t.currencyCode,
            t.accountId,
            accountName[t.accountId] ?? '',
            t.categoryId ?? '',
            t.categoryId == null ? '' : (categoryName[t.categoryId] ?? ''),
            t.ownerProfileId,
            t.visibility.name,
            t.note,
            t.transferAccountId ?? '',
            t.exchangeRateToMain ?? '',
            t.isRecurring,
            t.recurringLabel ?? '',
            t.recurrencePeriod.name,
          ],
      ],
    );

    writeSection(
      'budgets',
      const [
        'id',
        'categoryId',
        'categoryName',
        'monthKey',
        'allocated',
        'visibility',
        'ownerProfileId',
        'rollover',
      ],
      [
        for (final b in snapshot.budgets)
          [
            b.id,
            b.categoryId,
            categoryName[b.categoryId] ?? '',
            b.monthKey,
            b.allocated,
            b.visibility.name,
            b.ownerProfileId,
            b.rollover,
          ],
      ],
    );

    writeSection(
      'goals',
      const [
        'id',
        'name',
        'targetAmount',
        'currentAmount',
        'currencyCode',
        'ownerProfileId',
        'visibility',
        'status',
        'targetDate',
      ],
      [
        for (final g in snapshot.goals)
          [
            g.id,
            g.name,
            g.targetAmount,
            g.currentAmount,
            g.currencyCode,
            g.ownerProfileId,
            g.visibility.name,
            g.status.name,
            g.targetDate?.toIso8601String() ?? '',
          ],
      ],
    );

    writeSection(
      'rates',
      const ['code', 'rateToMain', 'updatedAt'],
      [
        for (final r in snapshot.rates)
          [r.code, r.rateToMain, r.updatedAt?.toIso8601String() ?? ''],
      ],
    );

    // Export-only debug sheets for spreadsheet analysis.
    final main = snapshot.settings.mainCurrency;
    writeSection(
      'ledger',
      const [
        'date',
        'type',
        'amount',
        'currencyCode',
        'rateToMain',
        'amountInMain',
        'signedAmountInMain',
        'accountName',
        'categoryName',
        'visibility',
        'ownerProfileId',
        'note',
        'isRecurring',
        'recurrencePeriod',
        'transactionId',
      ],
      [
        for (final t in snapshot.transactions)
          _ledgerRow(
            t,
            mainCurrency: main,
            rates: snapshot.rates,
            accountName: accountName,
            categoryName: categoryName,
          ),
      ],
    );

    writeSection(
      'account_balances',
      const [
        'accountId',
        'accountName',
        'currencyCode',
        'openingBalance',
        'balanceNative',
        'balanceInMain',
        'includeInNetWorth',
        'archived',
        'visibility',
      ],
      [
        for (final a in snapshot.accounts)
          [
            a.id,
            a.name,
            a.currencyCode,
            a.openingBalance,
            MoneyMath.balanceNativeForAccount(
              account: a,
              transactions: snapshot.transactions,
              mainCurrency: main,
              rates: snapshot.rates,
            ),
            MoneyMath.balanceForAccount(
              account: a,
              transactions: snapshot.transactions,
              mainCurrency: main,
              rates: snapshot.rates,
            ),
            a.includeInNetWorth,
            a.archived,
            a.visibility.name,
          ],
      ],
    );

    final stamp = at.replaceAll(':', '').replaceAll('-', '').split('.').first;
    return CsvFullExportResult(
      csvBody: buffer.toString(),
      fileName: 'zentho_export_$stamp.csv',
    );
  }

  static CsvFullImportResult importSnapshot(String csvBody) {
    final sections = _parseSections(csvBody);
    final warnings = <String>[];

    for (final required in const [
      'settings',
      'profiles',
      'accounts',
      'categories',
    ]) {
      if (!sections.containsKey(required)) {
        throw FormatException('Missing required section [$required]');
      }
    }

    final settingsRows = _rowsOf(sections['settings']!);
    if (settingsRows.isEmpty) {
      throw const FormatException('[settings] has no data row');
    }
    final settings = _parseSettings(settingsRows.first);

    final profiles = [
      for (final row in _rowsOf(sections['profiles']!)) _parseProfile(row),
    ];
    if (profiles.isEmpty) {
      throw const FormatException('[profiles] must include at least one profile');
    }
    if (!profiles.any((p) => p.id == settings.activeProfileId)) {
      warnings.add(
        'activeProfileId ${settings.activeProfileId} missing; '
        'using ${profiles.first.id}',
      );
    }

    final accounts = [
      for (final row in _rowsOf(sections['accounts']!)) _parseAccount(row),
    ];
    final categories = [
      for (final row in _rowsOf(sections['categories']!)) _parseCategory(row),
    ];

    final transactions = [
      for (final row in _rowsOf(sections['transactions'] ?? const []))
        _parseTransaction(row),
    ]..sort((a, b) => b.date.compareTo(a.date));

    final budgets = [
      for (final row in _rowsOf(sections['budgets'] ?? const []))
        _parseBudget(row),
    ];
    final goals = [
      for (final row in _rowsOf(sections['goals'] ?? const [])) _parseGoal(row),
    ];
    final rates = [
      for (final row in _rowsOf(sections['rates'] ?? const [])) _parseRate(row),
    ];

    final resolvedSettings = profiles.any((p) => p.id == settings.activeProfileId)
        ? settings
        : settings.copyWith(activeProfileId: profiles.first.id);

    return CsvFullImportResult(
      snapshot: FinanceSnapshot(
        settings: resolvedSettings,
        profiles: profiles,
        accounts: accounts,
        categories: categories,
        transactions: transactions,
        budgets: budgets,
        goals: goals,
        rates: rates,
      ),
      warnings: warnings,
    );
  }

  static List<dynamic> _ledgerRow(
    MoneyTransaction t, {
    required String mainCurrency,
    required List<CurrencyRate> rates,
    required Map<String, String> accountName,
    required Map<String, String> categoryName,
  }) {
    final rate = MoneyMath.rateFor(
      t.currencyCode,
      mainCurrency,
      rates,
      overrideRate: t.exchangeRateToMain,
    );
    final inMain = MoneyMath.toMain(
      amount: t.amount,
      currencyCode: t.currencyCode,
      mainCurrency: mainCurrency,
      rates: rates,
      overrideRate: t.exchangeRateToMain,
    );
    final signed = switch (t.type) {
      TransactionType.income => inMain,
      TransactionType.expense => -inMain,
      TransactionType.transfer => 0.0,
    };
    return [
      t.date.toIso8601String(),
      t.type.name,
      t.amount,
      t.currencyCode,
      rate,
      inMain,
      signed,
      accountName[t.accountId] ?? t.accountId,
      t.categoryId == null ? '' : (categoryName[t.categoryId] ?? t.categoryId!),
      t.visibility.name,
      t.ownerProfileId,
      t.note,
      t.isRecurring,
      t.recurrencePeriod.name,
      t.id,
    ];
  }

  static String _encode(List<List<dynamic>> rows) {
    return csv.encode(
      rows
          .map(
            (row) => row
                .map((cell) => cell == null ? '' : '$cell')
                .toList(growable: false),
          )
          .toList(growable: false),
    );
  }

  static Map<String, List<List<String>>> _parseSections(String body) {
    final lines = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final sections = <String, List<String>>{};
    String? current;
    final currentLines = <String>[];

    void flush() {
      final name = current;
      if (name == null) return;
      sections[name] = [...currentLines];
      currentLines.clear();
    }

    final headerRe = RegExp(r'^\[([a-zA-Z0-9_]+)\]\s*$');
    for (final line in lines) {
      final match = headerRe.firstMatch(line.trim());
      if (match != null) {
        flush();
        current = match.group(1)!.toLowerCase();
        continue;
      }
      if (current == null) continue;
      if (line.trim().startsWith('#') && !line.contains(',')) continue;
      currentLines.add(line);
    }
    flush();

    final decoded = <String, List<List<String>>>{};
    for (final entry in sections.entries) {
      final chunk = entry.value.join('\n').trim();
      if (chunk.isEmpty) {
        decoded[entry.key] = const [];
        continue;
      }
      final rows = csv
          .decode(chunk)
          .map((row) => row.map((cell) => '$cell'.trim()).toList())
          .toList();
      decoded[entry.key] = rows;
    }
    return decoded;
  }

  static List<Map<String, String>> _rowsOf(List<List<String>> table) {
    if (table.isEmpty) return const [];
    final header = table.first.map((e) => e.trim()).toList();
    final out = <Map<String, String>>[];
    for (var i = 1; i < table.length; i++) {
      final row = table[i];
      if (row.every((c) => c.trim().isEmpty)) continue;
      final map = <String, String>{};
      for (var c = 0; c < header.length; c++) {
        map[header[c]] = c < row.length ? row[c] : '';
      }
      out.add(map);
    }
    return out;
  }

  static String _req(Map<String, String> row, String key) {
    final value = row[key]?.trim() ?? '';
    if (value.isEmpty) {
      throw FormatException('Missing required field "$key"');
    }
    return value;
  }

  static bool _bool(String? raw, {bool fallback = false}) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    final v = raw.trim().toLowerCase();
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
    throw FormatException('Invalid boolean: $raw');
  }

  static double _double(String? raw, {double fallback = 0}) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    return double.parse(raw.trim());
  }

  static int _int(String? raw, {int fallback = 0}) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    final text = raw.trim();
    if (text.startsWith('0x') || text.startsWith('0X')) {
      return int.parse(text.substring(2), radix: 16);
    }
    return int.parse(text);
  }

  static AppSettings _parseSettings(Map<String, String> row) {
    final cloudId = row['householdCloudId']?.trim();
    final inviteKey = row['householdInviteKey']?.trim();
    final updatedRaw = row['householdUpdatedAt']?.trim();
    return AppSettings(
      mainCurrency: _req(row, 'mainCurrency').toUpperCase(),
      activeProfileId: _req(row, 'activeProfileId'),
      onboardingComplete: _bool(row['onboardingComplete']),
      showPrivate: _bool(row['showPrivate'], fallback: true),
      showShared: _bool(row['showShared'], fallback: true),
      householdCloudId:
          (cloudId == null || cloudId.isEmpty) ? null : cloudId,
      householdInviteKey:
          (inviteKey == null || inviteKey.isEmpty) ? null : inviteKey,
      householdUpdatedAt: (updatedRaw == null || updatedRaw.isEmpty)
          ? null
          : DateTime.tryParse(updatedRaw)?.toUtc(),
    );
  }

  static HouseholdProfile _parseProfile(Map<String, String> row) {
    return HouseholdProfile(
      id: _req(row, 'id'),
      name: _req(row, 'name'),
      colorHex: _int(row['colorHex'], fallback: 0xFF0B6E6E),
    );
  }

  static Account _parseAccount(Map<String, String> row) {
    return Account(
      id: _req(row, 'id'),
      name: _req(row, 'name'),
      type: AccountType.values.byName(_req(row, 'type').toLowerCase()),
      currencyCode: _req(row, 'currencyCode').toUpperCase(),
      openingBalance: _double(row['openingBalance']),
      ownerProfileId: _req(row, 'ownerProfileId'),
      visibility:
          VisibilityScope.values.byName(_req(row, 'visibility').toLowerCase()),
      includeInNetWorth: _bool(row['includeInNetWorth'], fallback: true),
      archived: _bool(row['archived']),
    );
  }

  static SpendCategory _parseCategory(Map<String, String> row) {
    return SpendCategory(
      id: _req(row, 'id'),
      name: _req(row, 'name'),
      iconName: row['iconName']?.trim().isNotEmpty == true
          ? row['iconName']!.trim()
          : 'category',
      colorHex: _int(row['colorHex'], fallback: 0xFF0B6E6E),
      isIncome: _bool(row['isIncome']),
      isSystem: _bool(row['isSystem']),
    );
  }

  static MoneyTransaction _parseTransaction(Map<String, String> row) {
    final categoryId = row['categoryId']?.trim();
    final transferAccountId = row['transferAccountId']?.trim();
    final recurringLabel = row['recurringLabel']?.trim();
    final rateRaw = row['exchangeRateToMain']?.trim();
    return MoneyTransaction(
      id: _req(row, 'id'),
      type: TransactionType.values.byName(_req(row, 'type').toLowerCase()),
      amount: _double(row['amount']).abs(),
      currencyCode: _req(row, 'currencyCode').toUpperCase(),
      accountId: _req(row, 'accountId'),
      categoryId: (categoryId == null || categoryId.isEmpty) ? null : categoryId,
      date: DateTime.parse(_req(row, 'date')),
      ownerProfileId: _req(row, 'ownerProfileId'),
      visibility:
          VisibilityScope.values.byName(_req(row, 'visibility').toLowerCase()),
      note: row['note']?.trim() ?? '',
      transferAccountId:
          (transferAccountId == null || transferAccountId.isEmpty)
              ? null
              : transferAccountId,
      exchangeRateToMain:
          (rateRaw == null || rateRaw.isEmpty) ? null : double.parse(rateRaw),
      isRecurring: _bool(row['isRecurring']),
      recurringLabel:
          (recurringLabel == null || recurringLabel.isEmpty)
              ? null
              : recurringLabel,
      recurrencePeriod: RecurrencePeriod.tryParse(row['recurrencePeriod']),
    );
  }

  static BudgetCategory _parseBudget(Map<String, String> row) {
    return BudgetCategory(
      id: _req(row, 'id'),
      categoryId: _req(row, 'categoryId'),
      monthKey: _req(row, 'monthKey'),
      allocated: _double(row['allocated']),
      visibility:
          VisibilityScope.values.byName(_req(row, 'visibility').toLowerCase()),
      ownerProfileId: _req(row, 'ownerProfileId'),
      rollover: _bool(row['rollover'], fallback: true),
    );
  }

  static SavingsGoal _parseGoal(Map<String, String> row) {
    final targetDate = row['targetDate']?.trim();
    return SavingsGoal(
      id: _req(row, 'id'),
      name: _req(row, 'name'),
      targetAmount: _double(row['targetAmount']),
      currentAmount: _double(row['currentAmount']),
      currencyCode: _req(row, 'currencyCode').toUpperCase(),
      ownerProfileId: _req(row, 'ownerProfileId'),
      visibility:
          VisibilityScope.values.byName(_req(row, 'visibility').toLowerCase()),
      status: GoalStatus.values.byName(
        (row['status']?.trim().isNotEmpty == true
                ? row['status']!
                : 'active')
            .toLowerCase(),
      ),
      targetDate:
          (targetDate == null || targetDate.isEmpty)
              ? null
              : DateTime.parse(targetDate),
    );
  }

  static CurrencyRate _parseRate(Map<String, String> row) {
    final updated = row['updatedAt']?.trim();
    return CurrencyRate(
      code: _req(row, 'code').toUpperCase(),
      rateToMain: _double(row['rateToMain'], fallback: 1),
      updatedAt:
          (updated == null || updated.isEmpty) ? null : DateTime.parse(updated),
    );
  }
}
