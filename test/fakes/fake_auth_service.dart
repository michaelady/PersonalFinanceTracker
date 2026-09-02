import 'dart:async';

import 'package:zentho/data/auth/auth_service.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({
    this.uid = 'user-1',
    this.email = 'ada@example.com',
    this.displayName = 'Ada',
    AuthUser? signedIn,
  }) : _user = signedIn;

  final String uid;
  final String email;
  final String displayName;

  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  bool get isAvailable => true;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  @override
  Future<AuthUser> signInWithGoogle() async {
    _user = AuthUser(uid: uid, email: email, displayName: displayName);
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}
