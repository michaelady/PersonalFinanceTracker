import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/models.dart';

/// Offline-first JSON persistence via SharedPreferences (works on Android, Windows, Web).
class LocalStore {
  static const _prefsKey = 'zentho_finance_snapshot_v1';
  static const _quotesKey = 'zentho_quote_cache_v1';
  static const _finnhubKey = 'zentho_finnhub_token_v1';
  static const _alphaVantageKey = 'zentho_alphavantage_token_v1';
  static const _twelveDataKey = 'zentho_twelvedata_token_v1';

  Future<FinanceSnapshot?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      return FinanceSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(FinanceSnapshot snapshot) async {
    final raw = jsonEncode(snapshot.toJson());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, raw);
  }

  Future<Map<String, CachedQuote>> loadQuotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_quotesKey);
      if (raw == null) return {};
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in json.entries)
          e.key.toUpperCase(): CachedQuote.fromJson(
            e.value as Map<String, dynamic>,
          ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> saveQuotes(Map<String, CachedQuote> quotes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _quotesKey,
      jsonEncode({
        for (final e in quotes.entries) e.key.toUpperCase(): e.value.toJson(),
      }),
    );
  }

  Future<String?> loadFinnhubToken() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_finnhubKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> saveFinnhubToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_finnhubKey);
    } else {
      await prefs.setString(_finnhubKey, trimmed);
    }
  }

  Future<String?> loadAlphaVantageToken() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_alphaVantageKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> saveAlphaVantageToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_alphaVantageKey);
    } else {
      await prefs.setString(_alphaVantageKey, trimmed);
    }
  }

  Future<String?> loadTwelveDataToken() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_twelveDataKey)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> saveTwelveDataToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_twelveDataKey);
    } else {
      await prefs.setString(_twelveDataKey, trimmed);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await prefs.remove(_quotesKey);
    await prefs.remove(_finnhubKey);
    await prefs.remove(_alphaVantageKey);
    await prefs.remove(_twelveDataKey);
  }
}
