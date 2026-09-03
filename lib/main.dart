import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/auth/app_google_id_token_source.dart';
import 'data/auth/auth_service.dart';
import 'data/auth/firebase_auth_service.dart';
import 'data/auth/identity_toolkit_client.dart';
import 'data/auth/rest_google_auth_service.dart';
import 'data/persistence/firestore_household_cloud_store.dart';
import 'data/persistence/firestore_rest_client.dart';
import 'data/persistence/firestore_rest_household_cloud_store.dart';
import 'data/persistence/firestore_rest_user_cloud_store.dart';
import 'data/persistence/firestore_user_cloud_store.dart';
import 'data/persistence/user_cloud_store.dart';
import 'data/repositories/finance_repository.dart';
import 'data/services/household_cloud_store.dart';
import 'firebase_options.dart';

final zenthoNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AuthService auth = const SignedOutAuthService();
  UserCloudStore userCloud = const NoOpUserCloudStore();
  HouseholdCloudStore? householdCloud;
  if (DefaultFirebaseOptions.isConfigured) {
    try {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        auth = FirebaseAuthService();
        userCloud = FirestoreUserCloudStore();
        householdCloud = FirestoreHouseholdCloudStore();
      } else {
        // Native Firebase Auth rejects the web appId with INVALID_APP_ID.
        // Identity Toolkit + Firestore REST talk to the same project/rules.
        final toolkit = IdentityToolkitClient();
        final restAuth = RestGoogleAuthService(
          toolkit: toolkit,
          tokenSource: AppGoogleIdTokenSource(
            navigatorKey: zenthoNavigatorKey,
            toolkit: toolkit,
          ),
        );
        await restAuth.restore();
        final userDocs = FirestoreRestClient(tokenProvider: restAuth.idToken);
        auth = restAuth;
        userCloud = FirestoreRestUserCloudStore(client: userDocs);
        householdCloud = FirestoreRestHouseholdCloudStore(
          client: FirestoreRestClient(),
        );
      }
    } catch (e, st) {
      debugPrint('Firebase failed to initialize: $e\n$st');
    }
  }

  final repo = FinanceRepository(
    auth: auth,
    userCloud: userCloud,
    householdCloud: householdCloud,
  );
  runApp(
    ChangeNotifierProvider.value(
      value: repo,
      child: ZenthoApp(navigatorKey: zenthoNavigatorKey),
    ),
  );
  await repo.init();
}
