import 'package:csv/csv.dart';

import '../models/models.dart';
import 'csv_data_exchange.dart';
import 'yahoo_lots_csv.dart';

class CsvImportResult {
  const CsvImportResult({
    required this.transactions,
    required this.skippedRows,
    required this.errors,
  });

  final List<MoneyTransaction> transactions;
  final int skippedRows;
  final List<String> errors;
}

/// Result of Settings CSV import — either a full snapshot replace,
/// a bank-style transaction append, or a Yahoo Finance lots merge.
class CsvImportOutcome {
  const CsvImportOutcome._({
    required this.isFullReplace,
    this.transactions,
    this.full,
    this.yahooLots,
  });

  factory CsvImportOutcome.transactions(CsvImportResult result) {
    return CsvImportOutcome._(isFullReplace: false, transactions: result);
  }

  factory CsvImportOutcome.full(CsvFullImportResult result) {
    return CsvImportOutcome._(isFullReplace: true, full: result);
  }

  factory CsvImportOutcome.yahooLots(YahooLotsImportResult result) {
    return CsvImportOutcome._(isFullReplace: false, yahooLots: result);
  }

  final bool isFullReplace;
  final CsvImportResult? transactions;
  final CsvFullImportResult? full;
  final YahooLotsImportResult? yahooLots;
}

/// Expects headers: date,amount,type,category,account,note,currency,visibility
/// type: income|expense
/// visibility: shared|private (optional, default shared)
abstract final class CsvImportService {
  static CsvImportResult parse({
    required String csvBody,
    required List<Account> accounts,
    required List<SpendCategory> categories,
    required String ownerProfileId,
    required String defaultCurrency,
  }) {
    final decoded = csv.decode(csvBody.trim());
    final rows = decoded
        .map((row) => row.map((cell) => '$cell').toList())
        .toList();

    if (rows.isEmpty) {
      return const CsvImportResult(
        transactions: [],
        skippedRows: 0,
        errors: ['CSV is empty'],
      );
    }

    final header = rows.first.map((e) => e.trim().toLowerCase()).toList();
    final required = ['date', 'amount', 'type', 'category', 'account'];
    for (final key in required) {
      if (!header.contains(key)) {
        return CsvImportResult(
          transactions: const [],
          skippedRows: 0,
          errors: ['Missing required column: $key'],
        );
      }
    }

    final idx = {
      for (var i = 0; i < header.length; i++) header[i]: i,
    };

    final transactions = <MoneyTransaction>[];
    final errors = <String>[];
    var skipped = 0;

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.every((cell) => cell.trim().isEmpty)) {
        skipped++;
        continue;
      }

      try {
        final date = DateTime.parse(row[idx['date']!].trim());
        final amount = double.parse(row[idx['amount']!].trim());
        final typeName = row[idx['type']!].trim().toLowerCase();
        final type = TransactionType.values.byName(typeName);
        if (type == TransactionType.transfer) {
          throw FormatException('Transfer rows are not supported in CSV import');
        }

        final categoryName = row[idx['category']!].trim().toLowerCase();
        final accountName = row[idx['account']!].trim().toLowerCase();
        final note = idx.containsKey('note') ? row[idx['note']!].trim() : '';
        final currency = idx.containsKey('currency')
            ? row[idx['currency']!].trim().toUpperCase()
            : defaultCurrency;
        final visibilityName = idx.containsKey('visibility')
            ? row[idx['visibility']!].trim().toLowerCase()
            : 'shared';
        final visibility = VisibilityScope.values.byName(
          visibilityName.isEmpty ? 'shared' : visibilityName,
        );

        final account = accounts.firstWhere(
          (a) => a.name.toLowerCase() == accountName,
        );
        final category = categories.firstWhere(
          (c) =>
              c.name.toLowerCase() == categoryName &&
              c.isIncome == (type == TransactionType.income),
        );

        transactions.add(
          MoneyTransaction.create(
            type: type,
            amount: amount.abs(),
            currencyCode: currency.isEmpty ? defaultCurrency : currency,
            accountId: account.id,
            categoryId: category.id,
            date: date,
            ownerProfileId: ownerProfileId,
            visibility: visibility,
            note: note,
          ),
        );
      } catch (e) {
        skipped++;
        errors.add('Row ${r + 1}: $e');
      }
    }

    return CsvImportResult(
      transactions: transactions,
      skippedRows: skipped,
      errors: errors,
    );
  }
}
