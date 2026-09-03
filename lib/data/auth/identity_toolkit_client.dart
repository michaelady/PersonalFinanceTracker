import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../firebase_options.dart';
import 'auth_service.dart';

/// Firebase Auth REST (Identity Toolkit) so Android can sign in without a
/// native Firebase Android app id. Using the web `appId` with the Android
/// Firebase Auth SDK returns `INVALID_APP_ID`.
class IdentityToolkitClient {
  IdentityToolkitClient({
    http.Client? httpClient,
    String? apiKey,
    this.authHandlerUrl = DefaultFirebaseOptions.authHandlerUrl,
  })  : _http = httpClient ?? http.Client(),
        _apiKey = apiKey ?? DefaultFirebaseOptions.web.apiKey;

  final http.Client _http;
  final String _apiKey;
  final String authHandlerUrl;

  Uri get _signInWithIdp => Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=$_apiKey',
      );

  Uri get _createAuthUri => Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:createAuthUri?key=$_apiKey',
      );

  Uri get _refresh => Uri.parse(
        'https://securetoken.googleapis.com/v1/token?key=$_apiKey',
      );

  /// Google authorization URL for the project’s web OAuth client.
  Future<String> createGoogleAuthUri({String identifier = 'user@gmail.com'}) async {
    final json = await _postJson(_createAuthUri, {
      'identifier': identifier,
      'continueUri': authHandlerUrl,
      'providerId': 'google.com',
    });
    final uri = json['authUri'] as String?;
    if (uri == null || uri.isEmpty) {
      throw StateError('Google sign-in did not return an auth URL');
    }
    return uri;
  }

  Future<IdentityToolkitSession> signInWithGoogleIdToken(String idToken) async {
    final json = await _postJson(_signInWithIdp, {
      'requestUri': authHandlerUrl,
      'postBody': 'id_token=$idToken&providerId=google.com',
      'returnSecureToken': true,
      'returnIdpCredential': true,
    });
    return IdentityToolkitSession.fromJson(json);
  }

  Future<IdentityToolkitSession> refresh(String refreshToken) async {
    final response = await _http.post(
      _refresh,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );
    final json = _decode(response);
    final idToken = json['id_token'] as String? ?? json['idToken'] as String?;
    final newRefresh =
        json['refresh_token'] as String? ?? json['refreshToken'] as String?;
    final uid = json['user_id'] as String? ?? json['userId'] as String?;
    final expiresIn = json['expires_in'] as String? ?? json['expiresIn'] as String?;
    if (idToken == null || idToken.isEmpty || uid == null || uid.isEmpty) {
      throw StateError('Could not refresh the signed-in session');
    }
    return IdentityToolkitSession(
      uid: uid,
      idToken: idToken,
      refreshToken: newRefresh ?? refreshToken,
      expiresAt: _expiry(expiresIn),
    );
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final response = await _http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected auth response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_errorMessage(decoded));
    }
    return decoded;
  }

  static String _errorMessage(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is Map && error['message'] is String) {
      return error['message'] as String;
    }
    return 'Sign-in failed';
  }

  static DateTime _expiry(String? expiresIn) {
    final seconds = int.tryParse(expiresIn ?? '') ?? 3600;
    return DateTime.now().toUtc().add(Duration(seconds: seconds - 60));
  }
}

class IdentityToolkitSession {
  const IdentityToolkitSession({
    required this.uid,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
    this.email,
    this.displayName,
  });

  final String uid;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String? email;
  final String? displayName;

  AuthUser get user => AuthUser(
        uid: uid,
        email: email,
        displayName: displayName,
      );

  bool get isExpired => !DateTime.now().toUtc().isBefore(expiresAt);

  IdentityToolkitSession copyWith({
    String? uid,
    String? idToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? email,
    String? displayName,
  }) {
    return IdentityToolkitSession(
      uid: uid ?? this.uid,
      idToken: idToken ?? this.idToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
    );
  }

  factory IdentityToolkitSession.fromJson(Map<String, dynamic> json) {
    final uid = json['localId'] as String? ?? json['userId'] as String?;
    final idToken = json['idToken'] as String?;
    final refresh = json['refreshToken'] as String?;
    if (uid == null || uid.isEmpty || idToken == null || refresh == null) {
      throw StateError('Sign-in did not return a session');
    }
    return IdentityToolkitSession(
      uid: uid,
      idToken: idToken,
      refreshToken: refresh,
      expiresAt: IdentityToolkitClient._expiry(json['expiresIn'] as String?),
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'idToken': idToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        'email': email,
        'displayName': displayName,
      };

  factory IdentityToolkitSession.fromStored(Map<String, dynamic> json) {
    return IdentityToolkitSession(
      uid: json['uid'] as String,
      idToken: json['idToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
    );
  }
}

/// Pulls a Google `id_token` out of the Firebase Auth handler redirect.
String? googleIdTokenFromRedirect(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (!uri.path.contains('/__/auth/handler')) return null;
  final raw = uri.fragment.isNotEmpty ? uri.fragment : uri.query;
  if (raw.isEmpty) return null;
  final params = Uri.splitQueryString(raw);
  final error = params['error'];
  if (error != null && error.isNotEmpty) {
    final description = params['error_description'] ?? error;
    throw StateError('Google sign-in failed: $description');
  }
  final token = params['id_token'];
  if (token == null || token.isEmpty) return null;
  return token;
}
