import '../models/models.dart';
import 'money_math.dart';
import 'supported_currencies.dart';

class ParsedBillLine {
  const ParsedBillLine({
    required this.description,
    required this.amount,
    required this.categoryName,
    this.currencyCode,
  });

  final String description;
  final double amount;
  final String categoryName;
  final String? currencyCode;
}

class ParsedBill {
  const ParsedBill({
    required this.merchant,
    required this.total,
    required this.currencyCode,
    required this.date,
    required this.lines,
    required this.rawText,
    required this.suggestedCategoryName,
    this.printedTotal,
  });

  final String merchant;
  final double total;
  final String currencyCode;
  final DateTime date;
  final List<ParsedBillLine> lines;
  final String rawText;
  final String suggestedCategoryName;

  /// Labeled TOTAL / amount due from the receipt, when OCR found one.
  /// Null means no printed total was detected (do not treat [total] as gospel).
  final double? printedTotal;

  double get itemsSum => lines.fold<double>(0, (s, l) => s + l.amount);

  /// Printed TOTAL minus line-item sum, rounded to the currency minor unit.
  /// Null when no labeled TOTAL was found.
  double? get printedTotalDelta {
    if (printedTotal == null || printedTotal! <= 0) return null;
    final printed = MoneyMath.roundToMinorUnits(printedTotal!, currencyCode);
    final sum = MoneyMath.roundToMinorUnits(itemsSum, currencyCode);
    return MoneyMath.roundToMinorUnits(printed - sum, currencyCode);
  }

  bool get printedTotalMismatches {
    final delta = printedTotalDelta;
    return delta != null && delta.abs() >= 0.005;
  }
}

/// Heuristic bill/invoice text parser + category suggestions.
abstract final class BillParser {
  static const _categoryKeywords = <String, List<String>>{
    'Groceries': [
      'grocery',
      'market',
      'supermarket',
      'aldi',
      'lidl',
      'migros',
      'coop',
      'walmart',
      'tesco',
      'carrefour',
      'rewe',
      'spar',
    ],
    'Dining': [
      'restaurant',
      'ristorante',
      'trattoria',
      'osteria',
      'pizzeria',
      'brasserie',
      'cafe',
      'coffee',
      'espresso',
      'cappuccino',
      'latte',
      'pizza',
      'burger',
      'bistro',
      'diner',
      'mcdonald',
      'starbucks',
      'takeaway',
      'delivery',
    ],
    'Transport': [
      'uber',
      'lyft',
      'taxi',
      'fuel',
      'petrol',
      'diesel',
      'gas station',
      'parking',
      'train',
      'bus',
      'flight',
      'airline',
    ],
    'Subscriptions': [
      'netflix',
      'spotify',
      'subscription',
      'membership',
      'prime',
      'adobe',
      'microsoft 365',
    ],
    'Health': [
      'pharmacy',
      'clinic',
      'hospital',
      'dental',
      'doctor',
      'apotheke',
      'medical',
    ],
    'Housing': [
      'rent',
      'landlord',
      'mortgage',
      'utilities',
      'electric',
      'water bill',
      'internet',
      'insurance',
    ],
    'Fun': [
      'cinema',
      'theater',
      'concert',
      'game',
      'steam',
      'ticket',
      'museum',
    ],
  };

  static ParsedBill parse(
    String rawText, {
    required String fallbackCurrency,
    DateTime? now,
  }) {
    final text = rawText.replaceAll('\r', '\n');
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final currency = _detectCurrency(text) ?? fallbackCurrency;
    final printedTotal = _detectLabeledTotal(text);
    final total =
        printedTotal ?? _detectTotal(text) ?? _largestAmount(text) ?? 0;
    final date = _detectDate(text) ?? (now ?? DateTime.now());
    final merchant = _detectMerchant(lines) ?? 'Scanned bill';
    final category = suggestCategory('$merchant\n$text');

    final itemLines = <ParsedBillLine>[];
    final amountPattern = RegExp(
      r'^(.*?)[:\s]+(?:CHF|EUR|USD|GBP|RON|CAD|AUD|JPY|\$|€|£)?\s*(-?\d+[.,]\d{2})\s*$',
      caseSensitive: false,
    );
    for (final line in lines) {
      final m = amountPattern.firstMatch(line);
      if (m == null) continue;
      final desc = m.group(1)!.trim();
      final amount = _parseAmount(m.group(2)!);
      if (amount == null || amount <= 0) continue;
      if (_looksLikeTotalLabel(desc)) continue;
      itemLines.add(
        ParsedBillLine(
          description: desc.isEmpty ? 'Item' : desc,
          amount: amount,
          categoryName: suggestCategory(desc, fallback: category),
          currencyCode: currency,
        ),
      );
    }

    // If no line items, create one expense for the total.
    if (itemLines.isEmpty && total > 0) {
      itemLines.add(
        ParsedBillLine(
          description: merchant,
          amount: total,
          categoryName: category,
          currencyCode: currency,
        ),
      );
    }

    return ParsedBill(
      merchant: merchant,
      total: total > 0
          ? total
          : itemLines.fold<double>(0, (s, l) => s + l.amount),
      printedTotal: printedTotal,
      currencyCode: currency,
      date: date,
      lines: itemLines,
      rawText: text,
      suggestedCategoryName: category,
    );
  }

  static String suggestCategory(String haystack, {String? fallback}) {
    final lower = haystack.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return fallback ?? 'Fun';
  }

  static String? _detectCurrency(String text) {
    final upper = text.toUpperCase();
    for (final code in SupportedCurrencies.codes) {
      if (RegExp('\\b$code\\b').hasMatch(upper)) return code;
    }
    if (text.contains('€')) return 'EUR';
    if (text.contains('£')) return 'GBP';
    if (text.contains('\$')) return 'USD';
    if (text.contains('₣') || upper.contains('SFR')) return 'CHF';
    return null;
  }

  static final _labeledTotalPattern = RegExp(
    r'(?:total|amount due|balance due|grand total|summe|total ttc|zu zahlen)\s*[:\-]?\s*(?:CHF|EUR|USD|GBP|RON|CAD|AUD|JPY|\$|€|£)?\s*(-?\d+[.,]\d{2})',
    caseSensitive: false,
  );

  /// TOTAL / amount-due printed on the receipt (not an inferred largest line).
  static double? _detectLabeledTotal(String text) {
    final matches = _labeledTotalPattern.allMatches(text).toList();
    if (matches.isEmpty) return null;
    final amount = _parseAmount(matches.last.group(1)!);
    if (amount != null && amount > 0) return amount;
    return null;
  }

  static double? _detectTotal(String text) {
    final labeled = _detectLabeledTotal(text);
    if (labeled != null) return labeled;
    final pattern = RegExp(
      r'(?:CHF|EUR|USD|GBP|RON|CAD|AUD|JPY|\$|€|£)\s*(-?\d+[.,]\d{2})\s*(?:total)?',
      caseSensitive: false,
    );
    final matches = pattern.allMatches(text).toList();
    if (matches.isEmpty) return null;
    final amount = _parseAmount(matches.last.group(1)!);
    if (amount != null && amount > 0) return amount;
    return null;
  }

  static double? _largestAmount(String text) {
    final amounts = RegExp(r'(?<!\d)(\d+[.,]\d{2})(?!\d)')
        .allMatches(text)
        .map((m) => _parseAmount(m.group(1)!))
        .whereType<double>()
        .where((a) => a > 0)
        .toList();
    if (amounts.isEmpty) return null;
    amounts.sort();
    return amounts.last;
  }

  static DateTime? _detectDate(String text) {
    final patterns = [
      RegExp(r'\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b'),
      RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b'),
    ];
    for (final pattern in patterns) {
      final m = pattern.firstMatch(text);
      if (m == null) continue;
      try {
        if (pattern == patterns.first) {
          return DateTime(
            int.parse(m.group(1)!),
            int.parse(m.group(2)!),
            int.parse(m.group(3)!),
          );
        }
        var year = int.parse(m.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(
          year,
          int.parse(m.group(2)!),
          int.parse(m.group(1)!),
        );
      } catch (_) {}
    }
    return null;
  }

  static String? _detectMerchant(List<String> lines) {
    for (final line in lines.take(8)) {
      if (line.length < 3) continue;
      if (RegExp(r'^\d').hasMatch(line)) continue;
      if (_looksLikeTotalLabel(line)) continue;
      if (RegExp(r'invoice|receipt|bill|tax|vat|date', caseSensitive: false)
          .hasMatch(line)) {
        continue;
      }
      return line.length > 48 ? line.substring(0, 48) : line;
    }
    return null;
  }

  static bool _looksLikeTotalLabel(String value) {
    final lower = value.toLowerCase();
    return lower.contains('total') ||
        lower.contains('amount due') ||
        lower.contains('balance') ||
        lower.contains('summe') ||
        lower.contains('zu zahlen');
  }

  static double? _parseAmount(String raw) {
    var cleaned = raw.trim();
    if (cleaned.contains(',') && cleaned.contains('.')) {
      if (cleaned.lastIndexOf(',') > cleaned.lastIndexOf('.')) {
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      } else {
        cleaned = cleaned.replaceAll(',', '');
      }
    } else if (cleaned.contains(',')) {
      cleaned = cleaned.replaceAll(',', '.');
    }
    return double.tryParse(cleaned);
  }

  static String? resolveCategoryId(
    String categoryName,
    List<SpendCategory> categories,
  ) {
    final match = categories.where(
      (c) => !c.isIncome && c.name.toLowerCase() == categoryName.toLowerCase(),
    );
    if (match.isNotEmpty) return match.first.id;
    final fun = categories.where((c) => !c.isIncome && c.name == 'Fun');
    return fun.isEmpty ? categories.where((c) => !c.isIncome).firstOrNull?.id : fun.first.id;
  }
}
