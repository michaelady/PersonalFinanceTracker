import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../features/auth/google_oauth_web_view.dart';
import '../../firebase_options.dart';
import 'auth_service.dart';
import 'identity_toolkit_client.dart';
import 'rest_google_auth_service.dart';

/// Native Google Sign-In when Play services allow it; on Android the web
/// OAuth client inside an in-app browser (no SHA-1 / Android Firebase app).
class AppGoogleIdTokenSource implements GoogleIdTokenSource {
  AppGoogleIdTokenSource({
    required this.navigatorKey,
    required this._toolkit,
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GlobalKey<NavigatorState> navigatorKey;
  final IdentityToolkitClient _toolkit;
  final GoogleSignIn _googleSignIn;
  var _googleInitialized = false;

  @override
  Future<String> getIdToken() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _webViewIdToken();
    }
    try {
      return await _pluginIdToken();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const SignInException('Google sign-in was cancelled');
      }
      return _webViewIdToken();
    } catch (_) {
      return _webViewIdToken();
    }
  }

  Future<String> _pluginIdToken() async {
    if (!_googleInitialized) {
      await _googleSignIn.initialize(
        serverClientId: DefaultFirebaseOptions.googleWebClientId,
      );
      _googleInitialized = true;
    }
    final account = await _googleSignIn.authenticate(
      scopeHint: const ['email', 'profile'],
    );
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const SignInException('Google sign-in did not return an ID token');
    }
    return idToken;
  }

  Future<String> _webViewIdToken() async {
    if (navigatorKey.currentState == null) {
      throw const SignInException('Google sign-in is not ready yet. Try again.');
    }
    final authUri = _toolkit.buildGoogleAuthorizationUrl();
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      throw const SignInException('Google sign-in is not ready yet. Try again.');
    }
    final outcome = await GoogleOauthWebView.open(context, authUri: authUri);
    if (outcome == null || outcome.cancelled) {
      throw const SignInException('Google sign-in was cancelled');
    }
    if (outcome.error != null) {
      throw SignInException(outcome.error!);
    }
    final token = outcome.idToken;
    if (token == null || token.isEmpty) {
      throw const SignInException(
        'Google sign-in did not finish. Try again.',
      );
    }
    return token;
  }

  @override
  Future<void> signOut() async {
    if (!_googleInitialized) return;
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Plugin may be missing on desktop.
    }
  }
}
