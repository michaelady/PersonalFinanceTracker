import '../../domain/models/models.dart';

/// Per-uid personal ledger stored online. Does not include quote API tokens
/// or the quote cache — those stay in [LocalStore] on the device.
class CloudSnapshotDocument {
  const CloudSnapshotDocument({
    required this.snapshot,
    required this.updatedAt,
  });

  final FinanceSnapshot snapshot;
  final DateTime updatedAt;
}

abstract class UserCloudStore {
  Future<CloudSnapshotDocument?> load(String uid);

  Future<void> save(
    String uid,
    FinanceSnapshot snapshot, {
    required DateTime updatedAt,
  });
}

/// Used when Firebase is not initialized. Writes are no-ops.
class NoOpUserCloudStore implements UserCloudStore {
  const NoOpUserCloudStore();

  @override
  Future<CloudSnapshotDocument?> load(String uid) async => null;

  @override
  Future<void> save(
    String uid,
    FinanceSnapshot snapshot, {
    required DateTime updatedAt,
  }) async {}
}
