import '../../domain/models/models.dart';
import 'firestore_rest_client.dart';
import 'user_cloud_store.dart';

/// Personal ledger via Firestore REST, authenticated with an Identity Toolkit
/// ID token instead of the Android Firebase Auth SDK.
class FirestoreRestUserCloudStore implements UserCloudStore {
  FirestoreRestUserCloudStore({required this._client});

  final FirestoreRestClient _client;

  String _path(String uid) => 'users/$uid/data/snapshot';

  @override
  Future<CloudSnapshotDocument?> load(String uid) async {
    final data = await _client.getDocument(_path(uid));
    if (data == null) return null;
    final rawSnapshot = data['snapshot'];
    if (rawSnapshot is! Map) return null;
    return CloudSnapshotDocument(
      snapshot: FinanceSnapshot.fromJson(
        {
          for (final entry in rawSnapshot.entries)
            entry.key.toString(): entry.value,
        },
      ),
      updatedAt: _parseUpdatedAt(data['updatedAt']),
    );
  }

  @override
  Future<void> save(
    String uid,
    FinanceSnapshot snapshot, {
    required DateTime updatedAt,
  }) async {
    final utc = updatedAt.toUtc();
    await _client.setDocument(_path(uid), {
      'updatedAt': utc.toIso8601String(),
      'snapshot': snapshot.toJson(),
    });
  }

  static DateTime _parseUpdatedAt(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      return DateTime.parse(value).toUtc();
    }
    return DateTime.now().toUtc();
  }
}
