import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/data/persistence/firestore_household_cloud_store.dart';
import 'package:zentho/domain/services/household_invite.dart';

Map<String, dynamic> _packedDoc({
  String inviteKey = 'abcdefghij',
  String updatedAt = '2026-09-02T12:00:00.000Z',
}) {
  return {
    'v': 1,
    'inviteKey': inviteKey,
    'updatedAt': updatedAt,
    'snapshot': {
      'settings': {
        'mainCurrency': 'USD',
        'activeProfileId': 'you',
        'onboardingComplete': true,
      },
      'profiles': const [],
      'accounts': const [],
      'categories': const [],
      'transactions': const [],
      'budgets': const [],
      'goals': const [],
      'rates': const [],
      'holdings': const [],
    },
  };
}

void main() {
  test('create uses auto-id and stores the packed map as-is', () async {
    final firestore = FakeFirebaseFirestore();
    final store = FirestoreHouseholdCloudStore(firestore: firestore);
    final body = _packedDoc();

    final id = await store.create(body);
    expect(id, isNotEmpty);

    final raw = await firestore.collection('households').doc(id).get();
    expect(raw.data()?['updatedAt'], '2026-09-02T12:00:00.000Z');
    expect(raw.data()?['inviteKey'], 'abcdefghij');
    expect(raw.data()?['v'], 1);

    final read = await store.read(id);
    expect(read?['updatedAt'], isA<String>());
    final parsed = HouseholdCloudDocument.fromJson(read!);
    expect(parsed.inviteKey, 'abcdefghij');
    expect(parsed.updatedAt, DateTime.utc(2026, 9, 2, 12));
  });

  test('read converts nested Firestore Timestamps to ISO strings', () async {
    final firestore = FakeFirebaseFirestore();
    final store = FirestoreHouseholdCloudStore(firestore: firestore);
    await firestore.collection('households').doc('hh1').set({
      'v': 1,
      'inviteKey': 'abcdefghij',
      'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 2, 12)),
      'snapshot': {
        'nestedAt': Timestamp.fromDate(DateTime.utc(2026, 1, 15, 8, 30)),
      },
    });

    final read = await store.read('hh1');
    expect(read, isNotNull);
    expect(read!['updatedAt'], '2026-09-02T12:00:00.000Z');
    final snapshot = Map<String, dynamic>.from(read['snapshot'] as Map);
    expect(snapshot['nestedAt'], '2026-01-15T08:30:00.000Z');
  });

  test('read returns null when the household doc is missing', () async {
    final store = FirestoreHouseholdCloudStore(firestore: FakeFirebaseFirestore());
    expect(await store.read('missing'), isNull);
  });

  test('update of a missing doc throws StateError', () async {
    final store = FirestoreHouseholdCloudStore(firestore: FakeFirebaseFirestore());
    expect(
      () => store.update('missing', _packedDoc()),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Household cloud doc missing; create a new share link',
        ),
      ),
    );
  });

  test('update overwrites an existing packed doc', () async {
    final firestore = FakeFirebaseFirestore();
    final store = FirestoreHouseholdCloudStore(firestore: firestore);
    final id = await store.create(_packedDoc(inviteKey: 'abcdefghij'));
    await store.update(
      id,
      _packedDoc(
        inviteKey: 'abcdefghij',
        updatedAt: '2026-09-03T00:00:00.000Z',
      ),
    );
    final read = await store.read(id);
    expect(read?['updatedAt'], '2026-09-03T00:00:00.000Z');
    expect(read?['inviteKey'], 'abcdefghij');
  });

  test('delete ignores a missing household doc', () async {
    final store = FirestoreHouseholdCloudStore(firestore: FakeFirebaseFirestore());
    await store.delete('missing');
  });
}
