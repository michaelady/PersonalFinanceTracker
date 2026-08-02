import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zentho/data/services/fx_rate_service.dart';

void main() {
  test('parses Frankfurter rates into rateToMain', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.frankfurter.dev');
      return http.Response(
        jsonEncode({
          'amount': 1.0,
          'base': 'USD',
          'date': '2026-08-02',
          'rates': {
            'EUR': 0.87,
            'CHF': 0.81,
            'RON': 4.56,
            'GBP': 0.74,
            'JPY': 160.0,
            'CAD': 1.40,
            'AUD': 1.42,
          },
        }),
        200,
      );
    });

    final service = FxRateService(client: client);
    final result = await service.fetchRates(mainCurrency: 'USD');
    expect(result.source, 'Frankfurter');
    expect(result.rates.firstWhere((r) => r.code == 'USD').rateToMain, 1);
    expect(
      result.rates.firstWhere((r) => r.code == 'CHF').rateToMain,
      closeTo(1 / 0.81, 0.0001),
    );
    expect(
      result.rates.firstWhere((r) => r.code == 'RON').rateToMain,
      closeTo(1 / 4.56, 0.0001),
    );
  });

  test('falls back to open.er-api when Frankfurter fails', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (request.url.host.contains('frankfurter')) {
        return http.Response('nope', 500);
      }
      return http.Response(
        jsonEncode({
          'result': 'success',
          'rates': {
            'USD': 1,
            'EUR': 0.87,
            'CHF': 0.81,
            'RON': 4.56,
            'GBP': 0.74,
            'JPY': 160.0,
            'CAD': 1.40,
            'AUD': 1.42,
          },
        }),
        200,
      );
    });

    final service = FxRateService(client: client);
    final result = await service.fetchRates(mainCurrency: 'USD');
    expect(calls, 2);
    expect(result.source, 'open.er-api');
    expect(result.rates.any((r) => r.code == 'CHF'), isTrue);
  });
}
