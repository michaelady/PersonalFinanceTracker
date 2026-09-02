import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/auth/auth_service.dart';
import 'data/auth/firebase_auth_service.dart';
import 'data/persistence/firestore_user_cloud_store.dart';
import 'data/persistence/user_cloud_store.dart';
import 'data/repositories/finance_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AuthService auth = const SignedOutAuthService();
  UserCloudStore userCloud = const NoOpUserCloudStore();
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      auth = FirebaseAuthService();
      userCloud = FirestoreUserCloudStore();
    } catch (e, st) {
      debugPrint('Firebase failed to initialize: $e\n$st');
    }
  }

  final repo = FinanceRepository(auth: auth, userCloud: userCloud);
  await repo.init();
  runApp(
    ChangeNotifierProvider.value(
      value: repo,
      child: const ZenthoApp(),
    ),
  );
}
