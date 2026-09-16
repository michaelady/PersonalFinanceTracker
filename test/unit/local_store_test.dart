import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/persistence/local_store.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/portfolio_math.dart';

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
    expect(prefs.getString('zentho_quote_cache_v3'), isNotNull);
    final loaded = await store.loadQuotes();
    expect(loaded['TSLA']!.previousClose, closeTo(365.44, 0.0001));
    expect(loaded['TSLA']!.source, 'finnhub');
  });

  test('quote cache v3 migrates v2 last prices and forces a year backfill',
      () async {
    final old = CachedQuote(
      symbol: 'VTI',
      price: 262.97,
      currency: 'USD',
      fetchedAt: DateTime.utc(2026, 9, 16, 12),
      source: 'finnhub',
      previousClose: 261.50,
      history: {
        '1y': [
          PricePoint(date: DateTime.utc(2026, 6, 12), close: 240),
          PricePoint(date: DateTime.utc(2026, 9, 16), close: 262.97),
        ],
      },
      historyFetchedAt: {'1y': DateTime.utc(2026, 9, 16, 12)},
    );
    SharedPreferences.setMockInitialValues({
      'zentho_quote_cache_v2': jsonEncode({'VTI': old.toJson()}),
    });
    final store = LocalStore();
    final loaded = await store.loadQuotes();
    expect(loaded['VTI']!.price, closeTo(262.97, 0.0001));
    expect(loaded['VTI']!.history['1y'], hasLength(2));
    expect(loaded['VTI']!.historyFetchedAt, isEmpty);
    expect(loaded['VTI']!.fetchedAt.year, 2000);
    expect(
      PortfolioMath.historyCoversRange(
        loaded['VTI'],
        QuoteHistoryRange.oneYear,
        now: DateTime.utc(2026, 9, 16),
      ),
      isFalse,
    );
  });

  test('snapshot with enum names from a newer app version still loads',
      () async {
    final you = HouseholdProfile.create('You');
    final account = Account.create(
      name: 'Main',
      type: AccountType.checking,
      currencyCode: 'USD',
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
      openingBalance: 10,
    );
    final tx = MoneyTransaction.create(
      type: TransactionType.expense,
      amount: 4,
      currencyCode: 'USD',
      accountId: account.id,
      date: DateTime(2026, 9, 1),
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
    );
    final goal = SavingsGoal.create(
      name: 'Trip',
      targetAmount: 100,
      currentAmount: 5,
      currencyCode: 'USD',
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
    );
    final snapshot = FinanceSnapshot(
      settings: AppSettings(
        mainCurrency: 'USD',
        activeProfileId: you.id,
        onboardingComplete: true,
      ),
      profiles: [you],
      accounts: [account],
      categories: const [],
      transactions: [tx],
      budgets: const [],
      goals: [goal],
      rates: const [CurrencyRate(code: 'USD', rateToMain: 1)],
      holdings: const [],
      shareTransactions: const [],
    );
    final json = snapshot.toJson();
    (json['accounts'] as List).first['type'] = 'crypto_wallet';
    (json['transactions'] as List).first['visibility'] = 'household';
    (json['goals'] as List).first['status'] = 'archived';
    SharedPreferences.setMockInitialValues({
      'zentho_finance_snapshot_v1': jsonEncode(json),
    });

    final loaded = await LocalStore().load();
    expect(loaded, isNotNull, reason: 'one unknown enum must not wipe data');
    expect(loaded!.accounts.single.type, AccountType.other);
    expect(loaded.accounts.single.openingBalance, 10);
    expect(loaded.transactions.single.visibility, VisibilityScope.private);
    expect(loaded.transactions.single.amount, 4);
    expect(loaded.goals.single.status, GoalStatus.active);
  });
}
