/// Signed-in Google / Firebase user. Household invite links are not identity.
class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
  });

  final String uid;
  final String? email;
  final String? displayName;

  /// Best label for Settings (email when present).
  String get label {
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) return mail;
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return uid;
  }
}

/// Identity for personal ledger sync. Not used for household invite links.
abstract class AuthService {
  AuthUser? get currentUser;

  /// False when Firebase is not initialized (placeholders / tests).
  bool get isAvailable;

  Stream<AuthUser?> authStateChanges();

  Future<AuthUser> signInWithGoogle();

  Future<void> signOut();
}

/// Default: unsigned-in, fully local. Used by tests and when Firebase is off.
class SignedOutAuthService implements AuthService {
  const SignedOutAuthService();

  @override
  AuthUser? get currentUser => null;

  @override
  bool get isAvailable => false;

  @override
  Stream<AuthUser?> authStateChanges() => const Stream.empty();

  @override
  Future<AuthUser> signInWithGoogle() {
    throw StateError(
      'Online accounts are not configured. Add the Firebase web config to '
      'lib/firebase_options.dart.',
    );
  }

  @override
  Future<void> signOut() async {}
}
