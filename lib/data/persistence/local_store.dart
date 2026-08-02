import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/models.dart';

/// Offline-first JSON persistence via SharedPreferences (works on Android, Windows, Web).
class LocalStore {
  static const _prefsKey = 'zentho_finance_snapshot_v1';

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
}
