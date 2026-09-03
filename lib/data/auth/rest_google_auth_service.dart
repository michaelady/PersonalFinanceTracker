import 'dart:async';

import 'auth_service.dart';
import 'auth_session_store.dart';
import 'identity_toolkit_client.dart';

/// Supplies a Google ID token (plugin or in-app OAuth).
abstract class GoogleIdTokenSource {
  Future<String> getIdToken();

  Future<void> signOut();
}

/// Google → Identity Toolkit REST. Used on Android where the Firebase Auth
/// SDK rejects the web `appId` with `INVALID_APP_ID`.
class RestGoogleAuthService implements AuthService {
  RestGoogleAuthService({
    required IdentityToolkitClient this._toolkit,
    required GoogleIdTokenSource this._tokenSource,
    AuthSessionStore? sessions,
  }) : _sessions = sessions ?? AuthSessionStore();

  final IdentityToolkitClient _toolkit;
  final GoogleIdTokenSource _tokenSource;
  final AuthSessionStore _sessions;
  final _controller = StreamController<AuthUser?>.broadcast();

  IdentityToolkitSession? _session;

  @override
  bool get isAvailable => true;

  @override
  AuthUser? get currentUser => _session?.user;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  Future<void> restore() async {
    final stored = await _sessions.load();
    if (stored == null) return;
    try {
      _session = stored.isExpired
          ? await _toolkit.refresh(stored.refreshToken)
          : stored;
      if (_session!.isExpired) {
        _session = await _toolkit.refresh(_session!.refreshToken);
      }
      _session = _session!.copyWith(
        email: _session!.email ?? stored.email,
        displayName: _session!.displayName ?? stored.displayName,
      );
      await _sessions.save(_session!);
      _controller.add(currentUser);
    } catch (_) {
      await _sessions.clear();
      _session = null;
    }
  }

  Future<String> idToken() async {
    var session = _session;
    if (session == null) {
      throw StateError('Not signed in');
    }
    if (session.isExpired) {
      session = await _toolkit.refresh(session.refreshToken);
      session = session.copyWith(
        email: session.email ?? _session?.email,
        displayName: session.displayName ?? _session?.displayName,
      );
      _session = session;
      await _sessions.save(session);
    }
    return session.idToken;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    final googleIdToken = await _tokenSource.getIdToken();
    final session = await _toolkit.signInWithGoogleIdToken(googleIdToken);
    _session = session;
    await _sessions.save(session);
    _controller.add(session.user);
    return session.user;
  }

  @override
  Future<void> signOut() async {
    try {
      await _tokenSource.signOut();
    } catch (_) {
      // Plugin / webview session may already be gone.
    }
    _session = null;
    await _sessions.clear();
    _controller.add(null);
  }
}
