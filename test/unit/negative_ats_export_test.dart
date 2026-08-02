import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/domain/services/csv_data_exchange.dart';
import 'package:zentho/domain/services/money_math.dart';

void main() {
  final snapshot = CsvDataExchange.importSnapshot(
    File('test/fixtures/zentho_export_negative_ats.csv').readAsStringSync(),
  ).snapshot;

  // Match the export's visibility: showPrivate=false, showShared=true.
  final visible = snapshot.transactions.where((tx) {
    if (tx.visibility.name == 'shared') return true;
    return false;
  }).toList();

  test('booked August income is zero because salary is dated July', () {
    final booked = MoneyMath.incomeInMonthMain(
      transactions: visible,
      monthKeyValue: '2026-08',
      mainCurrency: 'CHF',
      rates: snapshot.rates,
    );
    expect(booked, 0);
  });

  test('available to spend includes July recurring salary for August', () {
    final available = MoneyMath.availableToSpend(
      transactions: visible,
      budgets: snapshot.budgets,
      monthKeyValue: '2026-08',
      mainCurrency: 'CHF',
      rates: snapshot.rates,
    );

    // Expected: recurring salary 9453 − August shared groceries 86.4
    // (private streaming hidden by showPrivate=false).
    expect(available, closeTo(9453 - 86.4, 0.01));
    expect(available, greaterThan(0));
  });

  test('effective August income surfaces the recurring salary', () {
    final income = MoneyMath.incomeInMonthMain(
      transactions: visible,
      monthKeyValue: '2026-08',
      mainCurrency: 'CHF',
      rates: snapshot.rates,
      includeExpectedRecurring: true,
    );
    expect(income, closeTo(9453, 0.01));
  });
}
