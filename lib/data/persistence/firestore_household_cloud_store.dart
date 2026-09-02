import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/household_cloud_store.dart';

/// Anonymous household invite documents at `households/{id}`.
///
/// Packed body is `{v, inviteKey, updatedAt (ISO-8601 string), snapshot}`.
/// Invite links stay usable without signing in; quote caches and API tokens
/// are not part of [HouseholdCloudDocument] and must not be written here.
class FirestoreHouseholdCloudStore implements HouseholdCloudStore {
  FirestoreHouseholdCloudStore({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  static const collectionId = 'households';

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(collectionId);

  @override
  Future<String> create(Map<String, dynamic> body) async {
    final ref = _col.doc();
    await ref.set(body);
    return ref.id;
  }

  @override
  Future<Map<String, dynamic>?> read(String id) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    return _stringKeyMap(data);
  }

  @override
  Future<void> update(String id, Map<String, dynamic> body) async {
    final ref = _col.doc(id);
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('Household cloud doc missing; create a new share link');
    }
    await ref.set(body);
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _col.doc(id).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') return;
      rethrow;
    }
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
