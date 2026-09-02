import 'package:csv/csv.dart';

import '../models/models.dart';
import 'supported_currencies.dart';

/// One Yahoo Finance lots-export row, mapped onto a [ShareTransaction].
class YahooLotRow {
  const YahooLotRow({
    required this.id,
    required this.fingerprint,
    required this.symbol,
    required this.date,
    required this.type,
    required this.shares,
    required this.pricePerShare,
    required this.fee,
    this.comment = '',
    this.sourceRow = 0,
  });

  /// Stable id so the same file can be imported twice without duplicating.
  final String id;
  final String fingerprint;
  final String symbol;
  final DateTime date;
  final ShareTransactionType type;
  final double shares;
  final double pricePerShare;
  final double fee;
  final String comment;
  final int sourceRow;
}

class YahooLotsParseResult {
  const YahooLotsParseResult({
    required this.lots,
    required this.skippedRows,
    required this.errors,
  });

  final List<YahooLotRow> lots;
  final int skippedRows;
  final List<String> errors;

  int get buyCount =>
      lots.where((l) => l.type == ShareTransactionType.buy).length;
  int get sellCount =>
      lots.where((l) => l.type == ShareTransactionType.sell).length;
}

class YahooLotsImportResult {
  const YahooLotsImportResult({
    required this.imported,
    required this.skippedDuplicates,
    required this.skippedRows,
    required this.createdHoldings,
    required this.errors,
  });

  final int imported;
  final int skippedDuplicates;
  final int skippedRows;
  final int createdHoldings;
  final List<String> errors;

  String get summary {
    if (imported == 0 && skippedDuplicates > 0) {
      return 'No new lots — $skippedDuplicates already imported';
    }
    return 'Imported $imported lot'
        '${imported == 1 ? '' : 's'}'
        '${createdHoldings == 0 ? '' : ', $createdHoldings holding${createdHoldings == 1 ? '' : 's'}'}'
        ', skipped $skippedDuplicates duplicate'
        '${skippedDuplicates == 1 ? '' : 's'}'
        ', skipped $skippedRows bad row'
        '${skippedRows == 1 ? '' : 's'}';
  }
}

/// Yahoo Finance portfolio lots CSV
/// (`Symbol,…,Trade Date,Purchase Price,Quantity,Commission,…,Transaction Type`).
///
/// Quote snapshot columns (Current Price, Date, Time, OHLC, Volume) are ignored.
/// Lots are applied oldest-first; the export itself is newest-first.
abstract final class YahooLotsCsv {
  static const requiredHeaders = [
    'symbol',
    'trade date',
    'purchase price',
    'quantity',
    'transaction type',
  ];

  static bool looksLike(String csvBody) {
    final header = _headerLine(csvBody);
    if (header.isEmpty) return false;
    return header.contains('trade date') &&
        header.contains('purchase price') &&
        header.contains('transaction type') &&
        header.contains('symbol');
  }

  static YahooLotsParseResult parse(String csvBody) {
    final trimmed = _stripBom(csvBody).trim();
    if (trimmed.isEmpty) {
      return const YahooLotsParseResult(
        lots: [],
        skippedRows: 0,
        errors: ['CSV is empty'],
      );
    }

    final decoded = csv.decode(trimmed);
    final rows = [
      for (final row in decoded)
        [for (final cell in row) '${cell ?? ''}'],
    ];
    if (rows.isEmpty) {
      return const YahooLotsParseResult(
        lots: [],
        skippedRows: 0,
        errors: ['CSV is empty'],
      );
    }

    final header = [for (final h in rows.first) h.trim().toLowerCase()];
    final missing = [
      for (final key in requiredHeaders)
        if (!header.contains(key)) key,
    ];
    if (missing.isNotEmpty) {
      return YahooLotsParseResult(
        lots: const [],
        skippedRows: 0,
        errors: [
          'Missing required column: ${missing.join(', ')}',
        ],
      );
    }

    final idx = {for (var i = 0; i < header.length; i++) header[i]: i};
    final lots = <YahooLotRow>[];
    final errors = <String>[];
    var skipped = 0;
    final seen = <String>{};

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.every((cell) => cell.trim().isEmpty)) {
        skipped++;
        continue;
      }

      try {
        final lot = _parseRow(row, idx, r + 1);
        if (seen.contains(lot.fingerprint)) {
          skipped++;
          continue;
        }
        seen.add(lot.fingerprint);
        lots.add(lot);
      } catch (e) {
        skipped++;
        errors.add('Row ${r + 1}: $e');
      }
    }

    lots.sort(_compareLots);
    return YahooLotsParseResult(
      lots: lots,
      skippedRows: skipped,
      errors: errors,
    );
  }

  static String fingerprint({
    required String symbol,
    required DateTime date,
    required ShareTransactionType type,
    required double shares,
    required double price,
    required double fee,
  }) {
    return [
      symbol.trim().toUpperCase(),
      _ymd(date),
      type.name,
      _num(shares),
      _num(price),
      _num(fee),
    ].join('|');
  }

  static String currencyForSymbol(String symbol, String fallback) {
    final s = symbol.trim().toUpperCase();
    if (s.endsWith('.SW')) return _supported('CHF', fallback);
    if (s.endsWith('.L')) return _supported('GBP', fallback);
    if (s.endsWith('.T')) return _supported('JPY', fallback);
    if (s.endsWith('.TO') || s.endsWith('.V')) {
      return _supported('CAD', fallback);
    }
    if (s.endsWith('.AX')) return _supported('AUD', fallback);
    const euro = ['.F', '.DE', '.PA', '.AS', '.MI', '.MC', '.BR', '.HE', '.LS'];
    for (final suffix in euro) {
      if (s.endsWith(suffix)) return _supported('EUR', fallback);
    }
    return fallback;
  }

  static String _supported(String code, String fallback) {
    return SupportedCurrencies.codes.contains(code) ? code : fallback;
  }

  static int _compareLots(YahooLotRow a, YahooLotRow b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    final byType = a.type.index.compareTo(b.type.index);
    if (byType != 0) return byType;
    return a.symbol.compareTo(b.symbol);
  }

  static YahooLotRow _parseRow(
    List<String> row,
    Map<String, int> idx,
    int rowNumber,
  ) {
    String col(String key) {
      final i = idx[key];
      if (i == null || i >= row.length) return '';
      return row[i].trim();
    }

    final symbol = col('symbol').toUpperCase();
    if (symbol.isEmpty) {
      throw const FormatException('missing symbol');
    }

    final typeRaw = col('transaction type').toLowerCase();
    final type = switch (typeRaw) {
      'buy' => ShareTransactionType.buy,
      'sell' => ShareTransactionType.sell,
      _ => throw FormatException('unsupported transaction type "$typeRaw"'),
    };

    final shares = _parseNumber(col('quantity'), 'quantity');
    if (shares <= 0) {
      throw const FormatException('quantity must be positive');
    }
    final price = _parseNumber(col('purchase price'), 'purchase price');
    if (price < 0) {
      throw const FormatException('purchase price cannot be negative');
    }
    final feeRaw = col('commission');
    final fee = feeRaw.isEmpty ? 0.0 : _parseNumber(feeRaw, 'commission');
    if (fee < 0) {
      throw const FormatException('commission cannot be negative');
    }

    final date = _parseTradeDate(col('trade date'));
    final comment = col('comment');
    final fp = fingerprint(
      symbol: symbol,
      date: date,
      type: type,
      shares: shares,
      price: price,
      fee: fee,
    );
    return YahooLotRow(
      id: 'yahoo:$fp',
      fingerprint: fp,
      symbol: symbol,
      date: date,
      type: type,
      shares: shares,
      pricePerShare: price,
      fee: fee,
      comment: comment,
      sourceRow: rowNumber,
    );
  }

  static DateTime _parseTradeDate(String raw) {
    final compact = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (compact.length != 8) {
      throw FormatException('invalid trade date "$raw"');
    }
    final year = int.parse(compact.substring(0, 4));
    final month = int.parse(compact.substring(4, 6));
    final day = int.parse(compact.substring(6, 8));
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw FormatException('invalid trade date "$raw"');
    }
    return date;
  }

  static double _parseNumber(String raw, String label) {
    if (raw.isEmpty) {
      throw FormatException('missing $label');
    }
    final value = double.tryParse(raw);
    if (value == null) {
      throw FormatException('invalid $label "$raw"');
    }
    return value;
  }

  static String _ymd(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static String _num(double value) {
    if (value == 0) return '0';
    var text = value.toStringAsFixed(8);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    }
    return text;
  }

  static String _stripBom(String body) {
    if (body.startsWith('\uFEFF')) return body.substring(1);
    return body;
  }

  static String _headerLine(String csvBody) {
    final text = _stripBom(csvBody).trimLeft();
    if (text.isEmpty) return '';
    final end = text.indexOf(RegExp(r'\r?\n'));
    final line = end < 0 ? text : text.substring(0, end);
    return line.trim().toLowerCase();
  }
}
