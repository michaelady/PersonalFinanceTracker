import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'identity_toolkit_client.dart';

class AuthSessionStore {
  static const prefsKey = 'zentho_auth_session_v1';

  Future<IdentityToolkitSession?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return null;
      return IdentityToolkitSession.fromStored(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(IdentityToolkitSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}
