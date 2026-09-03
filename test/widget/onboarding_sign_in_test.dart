import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/app.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/features/shell/app_shell.dart';
import 'package:zentho/features/user/account_cloud_section.dart';

import '../fakes/fake_auth_service.dart';
import '../fakes/memory_user_cloud_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpOnboarding(
    WidgetTester tester,
    FinanceRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: repo,
        child: const ZenthoApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('onboarding offers the same Google sign-in as User',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FinanceRepository(
      auth: FakeAuthService(),
      userCloud: MemoryUserCloudStore(),
      refreshRatesOnInit: false,
    );
    await repo.init();
    await pumpOnboarding(tester, repo);

    expect(find.text(AccountCloudSection.googleSignInLabel), findsOneWidget);
    expect(find.textContaining('household ledger'), findsOneWidget);
    expect(find.text('Using this device only'), findsOneWidget);
    expect(find.text('Enter Zentho'), findsOneWidget);
  });

  testWidgets('onboarding sign-in without cloud data stays on setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FinanceRepository(
      auth: FakeAuthService(),
      userCloud: MemoryUserCloudStore(),
      refreshRatesOnInit: false,
    );
    await repo.init();
    await pumpOnboarding(tester, repo);

    await tester.tap(find.text(AccountCloudSection.googleSignInLabel));
    await tester.pumpAndSettle();

    expect(find.text('Signed in as ada@example.com'), findsWidgets);
    expect(find.text('Enter Zentho'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('onboarding sign-in with a cloud ledger opens the app',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cloud = MemoryUserCloudStore();
    final device1 = FinanceRepository(
      auth: FakeAuthService(uid: 'user-1'),
      userCloud: cloud,
      refreshRatesOnInit: false,
    );
    await device1.init();
    device1.settings = device1.settings.copyWith(onboardingComplete: true);
    await device1.addAccount(
      Account.create(
        name: 'Cloud Checking',
        type: AccountType.checking,
        currencyCode: 'USD',
        ownerProfileId: device1.profiles.first.id,
        visibility: VisibilityScope.shared,
        openingBalance: 80,
      ),
    );
    await device1.signInWithGoogle();

    SharedPreferences.setMockInitialValues({});
    final device2 = FinanceRepository(
      auth: FakeAuthService(uid: 'user-1', email: 'ada@example.com'),
      userCloud: cloud,
      refreshRatesOnInit: false,
    );
    await device2.init();
    expect(device2.settings.onboardingComplete, isFalse);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: device2,
        child: const ZenthoApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(AccountCloudSection.googleSignInLabel), findsOneWidget);

    await tester.tap(find.text(AccountCloudSection.googleSignInLabel));
    await tester.pumpAndSettle();

    expect(find.text('Enter Zentho'), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);
    expect(device2.settings.onboardingComplete, isTrue);
    expect(device2.accounts.single.name, 'Cloud Checking');
  });
}
