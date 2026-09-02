import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/models.dart';
import 'user_cloud_store.dart';

/// Stores [FinanceSnapshot] JSON at `users/{uid}/data/snapshot`.
class FirestoreUserCloudStore implements UserCloudStore {
  FirestoreUserCloudStore({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid).collection('data').doc('snapshot');

  @override
  Future<CloudSnapshotDocument?> load(String uid) async {
    final snap = await _doc(uid).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    final rawSnapshot = data['snapshot'];
    if (rawSnapshot is! Map) return null;
    return CloudSnapshotDocument(
      snapshot: FinanceSnapshot.fromJson(_stringKeyMap(rawSnapshot)),
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
    await _doc(uid).set({
      'updatedAt': Timestamp.fromDate(utc),
      'snapshot': snapshot.toJson(),
    });
  }

  static DateTime _parseUpdatedAt(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      return DateTime.parse(value).toUtc();
    }
    return DateTime.now().toUtc();
  }

  static Map<String, dynamic> _stringKeyMap(Map<dynamic, dynamic> input) {
    return {
      for (final entry in input.entries)
        entry.key.toString(): _convert(entry.value),
    };
  }

  static Object? _convert(Object? value) {
    if (value is Map) return _stringKeyMap(value);
    if (value is List) {
      return [for (final item in value) _convert(item)];
    }
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    return value;
  }
}
