import 'package:zentho/data/persistence/user_cloud_store.dart';
import 'package:zentho/domain/models/models.dart';

class MemoryUserCloudStore implements UserCloudStore {
  final Map<String, CloudSnapshotDocument> docs = {};

  @override
  Future<CloudSnapshotDocument?> load(String uid) async {
    final doc = docs[uid];
    if (doc == null) return null;
    return CloudSnapshotDocument(
      snapshot: FinanceSnapshot.fromJson(doc.snapshot.toJson()),
      updatedAt: doc.updatedAt.toUtc(),
    );
  }

  @override
  Future<void> save(
    String uid,
    FinanceSnapshot snapshot, {
    required DateTime updatedAt,
  }) async {
    docs[uid] = CloudSnapshotDocument(
      snapshot: FinanceSnapshot.fromJson(snapshot.toJson()),
      updatedAt: updatedAt.toUtc(),
    );
  }
}
