import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/features/settings/settings_screen.dart';
import 'package:zentho/features/user/user_screen.dart';

import '../fakes/fake_auth_service.dart';
import '../fakes/memory_user_cloud_store.dart';

Future<FinanceRepository> _readyRepo({FakeAuthService? auth}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = FinanceRepository(
    auth: auth ?? FakeAuthService(),
    userCloud: MemoryUserCloudStore(),
    refreshRatesOnInit: false,
  );
  await repo.init();
  final you = repo.profiles.first;
  repo.settings = AppSettings(
    mainCurrency: 'USD',
    activeProfileId: you.id,
    onboardingComplete: true,
  );
  repo.loading = false;
  repo.notifyListeners();
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Settings shows Sign in with Google when signed out',
      (tester) async {
    final repo = await _readyRepo();
    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Using this device only'), findsOneWidget);
  });

  testWidgets('User screen shows signed-in email and Sign out', (tester) async {
    final auth = FakeAuthService();
    final repo = await _readyRepo(auth: auth);
    await repo.signInWithGoogle();

    await tester.pumpWidget(
      ChangeNotifierProvider<FinanceRepository>.value(
        value: repo,
        child: const MaterialApp(home: UserScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Signed in as ada@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });
}
