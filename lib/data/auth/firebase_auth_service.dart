import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_service.dart';

/// Google sign-in via Firebase Auth.
///
/// Web (GitHub Pages) uses [FirebaseAuth.signInWithPopup]. Android uses the
/// `google_sign_in` plugin, then falls back to [FirebaseAuth.signInWithProvider]
/// so Windows still compiles without a native Google Sign-In plugin.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  var _googleInitialized = false;

  @override
  bool get isAvailable => Firebase.apps.isNotEmpty;

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> authStateChanges() =>
      _auth.authStateChanges().map(_map);

  @override
  Future<AuthUser> signInWithGoogle() async {
    if (!isAvailable) {
      throw StateError(
        'Online accounts are not configured. Add the Firebase web config to '
        'lib/firebase_options.dart.',
      );
    }

    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..setCustomParameters({'prompt': 'select_account'});

    final UserCredential cred;
    if (kIsWeb) {
      cred = await _auth.signInWithPopup(provider);
    } else {
      cred = await _signInNative(provider);
    }

    final user = cred.user;
    if (user == null) {
      throw StateError('Google sign-in was cancelled');
    }
    return _map(user)!;
  }

  Future<UserCredential> _signInNative(GoogleAuthProvider provider) async {
    try {
      if (!_googleInitialized) {
        await _googleSignIn.initialize();
        _googleInitialized = true;
      }
      final account = await _googleSignIn.authenticate(
        scopeHint: const ['email'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw StateError('Google sign-in did not return an ID token');
      }
      return _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
    } catch (_) {
      // Windows (and any host without the plugin) uses Firebase's provider flow.
      return _auth.signInWithProvider(provider);
    }
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Plugin may be missing on Windows.
      }
    }
    await _auth.signOut();
  }

  static AuthUser? _map(User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
    );
  }
}
