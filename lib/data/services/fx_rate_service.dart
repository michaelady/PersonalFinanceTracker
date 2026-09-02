import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/models.dart';
import '../../domain/services/supported_currencies.dart';

class FxRefreshResult {
  const FxRefreshResult({
    required this.rates,
    required this.source,
    required this.fetchedAt,
  });

  final List<CurrencyRate> rates;
  final String source;
  final DateTime fetchedAt;
}

/// Fetches live FX rates. Offline-safe: callers catch failures.
class FxRateService {
  FxRateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _codes = SupportedCurrencies.codes;

  /// Returns rates as rateToMain for [mainCurrency]
  /// (1 unit of code = rateToMain units of main).
  Future<FxRefreshResult> fetchRates({required String mainCurrency}) async {
    FxRefreshResult? primary;
    try {
      primary = await _fetchFrankfurter(mainCurrency);
      if (_coversSupported(primary.rates)) return primary;
    } catch (_) {
      primary = null;
    }

    try {
      final secondary = await _fetchOpenErApi(mainCurrency);
      if (primary == null) return secondary;
      return _mergePreferPrimary(primary, secondary);
    } catch (_) {
      if (primary != null) return primary;
      rethrow;
    }
  }

  static bool _coversSupported(List<CurrencyRate> rates) {
    final codes = rates.map((r) => r.code).toSet();
    return SupportedCurrencies.codes.every(codes.contains);
  }

  static FxRefreshResult _mergePreferPrimary(
    FxRefreshResult primary,
    FxRefreshResult secondary,
  ) {
    final byCode = {for (final r in secondary.rates) r.code: r};
    for (final r in primary.rates) {
      byCode[r.code] = r;
    }
    return FxRefreshResult(
      rates: [
        for (final code in SupportedCurrencies.codes)
          if (byCode.containsKey(code)) byCode[code]!,
      ],
      source: '${primary.source}+${secondary.source}',
      fetchedAt: primary.fetchedAt,
    );
  }

  Future<FxRefreshResult> _fetchFrankfurter(String mainCurrency) async {
    final symbols = _codes.where((c) => c != mainCurrency).join(',');
    final uri = Uri.parse(
      'https://api.frankfurter.dev/v1/latest?base=$mainCurrency&symbols=$symbols',
    );
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Frankfurter HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rawRates = (json['rates'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    );
    final now = DateTime.now().toUtc();
    // Frankfurter returns units of foreign per 1 main.
    // rateToMain = 1 / that value.
    final rates = <CurrencyRate>[
      CurrencyRate(code: mainCurrency, rateToMain: 1, updatedAt: now),
      for (final code in _codes)
        if (code != mainCurrency && rawRates.containsKey(code))
          CurrencyRate(
            code: code,
            rateToMain: 1 / rawRates[code]!,
            updatedAt: now,
          ),
    ];
    return FxRefreshResult(
      rates: rates,
      source: 'Frankfurter',
      fetchedAt: now,
    );
  }

  Future<FxRefreshResult> _fetchOpenErApi(String mainCurrency) async {
    final uri = Uri.parse('https://open.er-api.com/v6/latest/$mainCurrency');
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('open.er-api HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['result'] != 'success') {
      throw StateError('open.er-api failed');
    }
    final rawRates = (json['rates'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, (v as num).toDouble()),
    );
    final now = DateTime.now().toUtc();
    final rates = <CurrencyRate>[
      CurrencyRate(code: mainCurrency, rateToMain: 1, updatedAt: now),
      for (final code in _codes)
        if (code != mainCurrency && rawRates.containsKey(code))
          CurrencyRate(
            code: code,
            rateToMain: 1 / rawRates[code]!,
            updatedAt: now,
          ),
    ];
    return FxRefreshResult(
      rates: rates,
      source: 'open.er-api',
      fetchedAt: now,
    );
  }

  /// Offline seed rates relative to [mainCurrency], using USD cross rates.
  static List<CurrencyRate> defaultRatesFor(String mainCurrency) {
    final usd = SupportedCurrencies.usdDefaults;
    final mainInUsd = usd[mainCurrency] ?? 1.0;
    final now = DateTime.now().toUtc();
    return [
      for (final code in SupportedCurrencies.codes)
        CurrencyRate(
          code: code,
          rateToMain: code == mainCurrency
              ? 1
              : (usd[code] ?? 1) / mainInUsd,
          updatedAt: now,
        ),
    ];
  }
}
