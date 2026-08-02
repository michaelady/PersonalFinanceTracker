import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/repositories/finance_repository.dart';
import 'package:zentho/data/services/household_cloud_store.dart';
import 'package:zentho/domain/models/models.dart';
import 'package:zentho/domain/services/household_invite.dart';

class MemoryCloudStore implements HouseholdCloudStore {
  final Map<String, Map<String, dynamic>> docs = {};
  var nextId = 1;

  @override
  Future<String> create(Map<String, dynamic> body) async {
    final id = 'cloud-${nextId++}';
    docs[id] = Map<String, dynamic>.from(body);
    return id;
  }

  @override
  Future<void> delete(String id) async {
    docs.remove(id);
  }

  @override
  Future<Map<String, dynamic>?> read(String id) async =>
      docs[id] == null ? null : Map<String, dynamic>.from(docs[id]!);

  @override
  Future<void> update(String id, Map<String, dynamic> body) async {
    if (!docs.containsKey(id)) {
      throw StateError('Household cloud doc missing; create a new share link');
    }
    docs[id] = Map<String, dynamic>.from(body);
  }
}

Future<FinanceRepository> readyRepo(HouseholdCloudStore cloud) async {
  SharedPreferences.setMockInitialValues({});
  final repo = FinanceRepository(
    householdCloud: cloud,
    refreshRatesOnInit: false,
  );
  await repo.init();
  final you = HouseholdProfile.create('Alex');
  repo.profiles = [you];
  repo.settings = AppSettings(
    mainCurrency: 'CHF',
    activeProfileId: you.id,
    onboardingComplete: true,
  );
  repo.rates = [const CurrencyRate(code: 'CHF', rateToMain: 1)];
  repo.categories = [
    SpendCategory.create(
      name: 'Salary',
      iconName: 'pay',
      colorHex: 1,
      isIncome: true,
    ),
  ];
  repo.accounts = [
    Account.create(
      name: 'Main',
      type: AccountType.checking,
      currencyCode: 'CHF',
      ownerProfileId: you.id,
      visibility: VisibilityScope.shared,
      openingBalance: 100,
    ),
  ];
  repo.transactions = [];
  repo.budgets = [];
  repo.goals = [];
  repo.loading = false;
  return repo;
}

void main() {
  test('invite link encode/decode', () {
    final link = HouseholdInvite.buildShareLink(
      cloudId: 'abc',
      inviteKey: 'secret',
      base: Uri.parse('https://michaelady.github.io/PersonalFinanceTracker/'),
    );
    expect(link, contains('hh=abc'));
    expect(link, contains('k=secret'));
    final parsed = HouseholdInvite.parseShareLink(link);
    expect(parsed?.cloudId, 'abc');
    expect(parsed?.inviteKey, 'secret');
  });

  test('enable sharing then join on another device', () async {
    final cloud = MemoryCloudStore();
    final host = await readyRepo(cloud);
    final link = await host.enableHouseholdSharing(
      base: Uri.parse('https://example.test/app/'),
    );
    expect(host.settings.householdSharingEnabled, isTrue);
    expect(cloud.docs.length, 1);

    final parsed = HouseholdInvite.parseShareLink(link)!;
    final guest = await readyRepo(cloud);
    await guest.joinHousehold(
      cloudId: parsed.cloudId,
      inviteKey: parsed.inviteKey,
      displayName: 'Sam',
    );

    expect(guest.settings.householdSharingEnabled, isTrue);
    expect(guest.profiles.map((p) => p.name), containsAll(['Alex', 'Sam']));
    expect(guest.activeProfile?.name, 'Sam');
    expect(guest.accounts, hasLength(1));

    // Host pulls the new member.
    await host.syncHousehold(pullOnly: true);
    expect(host.profiles.map((p) => p.name), contains('Sam'));
  });

  test('clear all wipes local data and returns to onboarding', () async {
    final cloud = MemoryCloudStore();
    final repo = await readyRepo(cloud);
    await repo.enableHouseholdSharing(
      base: Uri.parse('https://example.test/'),
    );
    expect(repo.accounts, isNotEmpty);

    await repo.clearAllData();
    expect(repo.settings.onboardingComplete, isFalse);
    expect(repo.accounts, isEmpty);
    expect(repo.transactions, isEmpty);
    expect(repo.settings.householdSharingEnabled, isFalse);
  });

  test('local edits push to cloud for the other member', () async {
    final cloud = MemoryCloudStore();
    final host = await readyRepo(cloud);
    final link = await host.enableHouseholdSharing(
      base: Uri.parse('https://example.test/'),
    );
    final parsed = HouseholdInvite.parseShareLink(link)!;

    final guest = await readyRepo(cloud);
    await guest.joinHousehold(
      cloudId: parsed.cloudId,
      inviteKey: parsed.inviteKey,
      displayName: 'Sam',
    );

    await guest.addTransaction(
      MoneyTransaction.create(
        type: TransactionType.expense,
        amount: 42,
        currencyCode: 'CHF',
        accountId: guest.accounts.first.id,
        categoryId: guest.categories.first.id,
        ownerProfileId: guest.settings.activeProfileId,
        visibility: VisibilityScope.shared,
        date: DateTime(2026, 8, 2),
        note: 'Shared coffee',
      ),
    );
    await guest.syncHousehold(pushOnly: true);

    await host.syncHousehold(pullOnly: true);
    expect(
      host.transactions.any((t) => t.note == 'Shared coffee'),
      isTrue,
    );
  });
}
