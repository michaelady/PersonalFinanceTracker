import '../services/household_cloud_store.dart';
import 'firestore_rest_client.dart';

/// Anonymous household invite docs via Firestore REST (no Firebase Auth SDK).
class FirestoreRestHouseholdCloudStore implements HouseholdCloudStore {
  FirestoreRestHouseholdCloudStore({required this._client});

  static const collectionId = 'households';

  final FirestoreRestClient _client;

  @override
  Future<String> create(Map<String, dynamic> body) {
    return _client.createDocument(collectionId, body);
  }

  @override
  Future<Map<String, dynamic>?> read(String id) {
    return _client.getDocument('$collectionId/$id');
  }

  @override
  Future<void> update(String id, Map<String, dynamic> body) async {
    final existing = await _client.getDocument('$collectionId/$id');
    if (existing == null) {
      throw StateError('Household cloud doc missing; create a new share link');
    }
    await _client.setDocument('$collectionId/$id', body);
  }

  @override
  Future<void> delete(String id) {
    return _client.deleteDocument('$collectionId/$id');
  }
}
