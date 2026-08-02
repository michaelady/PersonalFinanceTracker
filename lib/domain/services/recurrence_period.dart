/// How often a recurring cash flow repeats.
enum RecurrencePeriod {
  daily('Daily', 1),
  weekly('Weekly', 7),
  monthly('Monthly', 30),
  twoMonths('2 months', 60),
  quarter('Quarter', 90),
  year('Year', 365);

  const RecurrencePeriod(this.label, this.approxDays);
  final String label;
  final int approxDays;

  static RecurrencePeriod tryParse(String? raw) {
    if (raw == null) return RecurrencePeriod.monthly;
    return RecurrencePeriod.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => RecurrencePeriod.monthly,
    );
  }

  DateTime addTo(DateTime date) {
    switch (this) {
      case RecurrencePeriod.daily:
        return date.add(const Duration(days: 1));
      case RecurrencePeriod.weekly:
        return date.add(const Duration(days: 7));
      case RecurrencePeriod.monthly:
        return _addMonths(date, 1);
      case RecurrencePeriod.twoMonths:
        return _addMonths(date, 2);
      case RecurrencePeriod.quarter:
        return _addMonths(date, 3);
      case RecurrencePeriod.year:
        return _addMonths(date, 12);
    }
  }

  static DateTime _addMonths(DateTime date, int months) {
    final total = date.month - 1 + months;
    final year = date.year + total ~/ 12;
    final month = total % 12 + 1;
    final day = date.day.clamp(1, DateTime(year, month + 1, 0).day);
    return DateTime(year, month, day, date.hour, date.minute, date.second);
  }
}
