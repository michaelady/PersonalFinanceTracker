import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/persistence/local_store.dart';
import 'package:zentho/domain/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quote cache v2 ignores v1 Yahoo chartPreviousClose blobs', () async {
    SharedPreferences.setMockInitialValues({
      'zentho_quote_cache_v1': jsonEncode({
        'TSLA': CachedQuote(
          symbol: 'TSLA',
          price: 362.53,
          currency: 'USD',
          fetchedAt: DateTime.utc(2026, 9, 14, 16),
          source: 'yahoo',
          previousClose: 342.27,
        ).toJson(),
      }),
    });
    final store = LocalStore();
    expect(await store.loadQuotes(), isEmpty);

    await store.saveQuotes({
      'TSLA': CachedQuote(
        symbol: 'TSLA',
        price: 362.53,
        currency: 'USD',
        fetchedAt: DateTime.utc(2026, 9, 14, 17),
        source: 'finnhub',
        previousClose: 365.44,
      ),
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('zentho_quote_cache_v1'), isNull);
    expect(prefs.getString('zentho_quote_cache_v2'), isNotNull);
    final loaded = await store.loadQuotes();
    expect(loaded['TSLA']!.previousClose, closeTo(365.44, 0.0001));
    expect(loaded['TSLA']!.source, 'finnhub');
  });
}
