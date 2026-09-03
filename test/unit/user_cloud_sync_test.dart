import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/domain/models/models.dart';

import '../fakes/fake_auth_service.dart';
import '../fakes/memory_user_cloud_store.dart';

Future<FinanceRepository> readyLocalRepo({
  required FakeAuthService auth,
  required MemoryUserCloudStore cloud,
}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = FinanceRepository(
    auth: auth,
    userCloud: cloud,
    refreshRatesOnInit: false,
  );
  await repo.init();
  final you = repo.profiles.first;
  await repo.addAccount(
    Account.create(
      name: 'Checking',
      type: AccountType.checking,
      currencyCode: 'USD',
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
      openingBalance: 250,
    ),
  );
  return repo;
}

void main() {
  test('signed-out stays local', () async {
    final auth = FakeAuthService();
    final cloud = MemoryUserCloudStore();
    final repo = await readyLocalRepo(auth: auth, cloud: cloud);

    expect(repo.signedInUser, isNull);
    expect(cloud.docs, isEmpty);
    expect(repo.accounts, hasLength(1));
    expect(repo.accounts.single.name, 'Checking');
  });

  test('first sign-in uploads local snapshot', () async {
    final auth = FakeAuthService();
    final cloud = MemoryUserCloudStore();
    final repo = await readyLocalRepo(auth: auth, cloud: cloud);
    expect(cloud.docs, isEmpty);

    await repo.signInWithGoogle();

    expect(repo.signedInUser?.email, 'ada@example.com');
    expect(cloud.docs.containsKey('user-1'), isTrue);
    final remote = cloud.docs['user-1']!;
    expect(remote.snapshot.accounts, hasLength(1));
    expect(remote.snapshot.accounts.single.name, 'Checking');
    expect(repo.lastCloudSyncedAt, isNotNull);
  });

  test('second device loads cloud snapshot', () async {
    final cloud = MemoryUserCloudStore();

    final device1 = await readyLocalRepo(
      auth: FakeAuthService(uid: 'user-1'),
      cloud: cloud,
    );
    await device1.signInWithGoogle();
    expect(cloud.docs['user-1']!.snapshot.accounts.single.name, 'Checking');

    SharedPreferences.setMockInitialValues({});
    final device2 = FinanceRepository(
      auth: FakeAuthService(uid: 'user-1', email: 'ada@example.com'),
      userCloud: cloud,
      refreshRatesOnInit: false,
    );
    await device2.init();
    expect(device2.accounts, isEmpty);

    await device2.signInWithGoogle();

    expect(device2.accounts, hasLength(1));
    expect(device2.accounts.single.name, 'Checking');
    expect(device2.settings.onboardingComplete, isTrue);
  });

  test('sign-out does not wipe local', () async {
    final auth = FakeAuthService();
    final cloud = MemoryUserCloudStore();
    final repo = await readyLocalRepo(auth: auth, cloud: cloud);
    await repo.signInWithGoogle();
    expect(repo.signedInUser, isNotNull);

    await repo.signOut();

    expect(repo.signedInUser, isNull);
    expect(repo.accounts, hasLength(1));
    expect(repo.accounts.single.name, 'Checking');
    expect(cloud.docs.containsKey('user-1'), isTrue);
  });

  test('cloud wins when both exist and cloud is newer', () async {
    final auth = FakeAuthService();
    final cloud = MemoryUserCloudStore();
    final repo = await readyLocalRepo(auth: auth, cloud: cloud);
    final you = repo.profiles.first;
    final newer = FinanceSnapshot(
      settings: repo.settings,
      profiles: repo.profiles,
      accounts: [
        Account.create(
          name: 'Cloud Savings',
          type: AccountType.savings,
          currencyCode: 'USD',
          ownerProfileId: you.id,
          visibility: VisibilityScope.shared,
          openingBalance: 900,
        ),
      ],
      categories: repo.categories,
      transactions: const [],
      budgets: const [],
      goals: const [],
      rates: repo.rates,
      holdings: const [],
    );
    await cloud.save(
      'user-1',
      newer,
      updatedAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

    await repo.signInWithGoogle();

    expect(repo.accounts.single.name, 'Cloud Savings');
    expect(repo.accounts.single.openingBalance, 900);
  });

  test('quote tokens are not uploaded', () async {
    final auth = FakeAuthService();
    final cloud = MemoryUserCloudStore();
    final repo = await readyLocalRepo(auth: auth, cloud: cloud);
    await repo.setFinnhubToken('secret-finnhub');
    await repo.setAlphaVantageToken('secret-av');
    await repo.setTwelveDataToken('secret-td');

    await repo.signInWithGoogle();

    final json = cloud.docs['user-1']!.snapshot.toJson();
    expect(json.keys, isNot(contains('finnhubToken')));
    expect(json.keys, isNot(contains('quotes')));
    expect(json.toString(), isNot(contains('secret-finnhub')));
    expect(json.toString(), isNot(contains('secret-av')));
    expect(json.toString(), isNot(contains('secret-td')));
    expect(repo.finnhubToken, 'secret-finnhub');
  });

  test('sign-in on empty onboarding does not skip setup or upload', () async {
    SharedPreferences.setMockInitialValues({});
    final cloud = MemoryUserCloudStore();
    final repo = FinanceRepository(
      auth: FakeAuthService(),
      userCloud: cloud,
      refreshRatesOnInit: false,
    );
    await repo.init();
    expect(repo.settings.onboardingComplete, isFalse);

    await repo.signInWithGoogle();

    expect(repo.signedInUser?.email, 'ada@example.com');
    expect(repo.settings.onboardingComplete, isFalse);
    expect(repo.accounts, isEmpty);
    expect(cloud.docs, isEmpty);
  });

  test('signed-in local save also writes Firestore', () async {
    final auth = FakeAuthService();
    final cloud = MemoryUserCloudStore();
    final repo = await readyLocalRepo(auth: auth, cloud: cloud);
    await repo.signInWithGoogle();

    await repo.addAccount(
      Account.create(
        name: 'Savings',
        type: AccountType.savings,
        currencyCode: 'USD',
        ownerProfileId: repo.profiles.first.id,
        visibility: VisibilityScope.shared,
      ),
    );

    expect(cloud.docs['user-1']!.snapshot.accounts, hasLength(2));
    expect(
      cloud.docs['user-1']!.snapshot.accounts.map((a) => a.name),
      containsAll(['Checking', 'Savings']),
    );
  });
}
