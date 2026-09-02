/// Minimal remote JSON document store used for household sharing.
abstract class HouseholdCloudStore {
  Future<String> create(Map<String, dynamic> body);
  Future<Map<String, dynamic>?> read(String id);
  Future<void> update(String id, Map<String, dynamic> body);
  Future<void> delete(String id);
}

/// Used when Firebase is not initialized (tests, failed plugin init).
/// Sharing requires Firestore after Firebase starts.
class UnavailableHouseholdCloudStore implements HouseholdCloudStore {
  const UnavailableHouseholdCloudStore();

  Never _unavailable() =>
      throw StateError('Household sharing requires Firebase');

  @override
  Future<String> create(Map<String, dynamic> body) => _unavailable();

  @override
  Future<Map<String, dynamic>?> read(String id) => _unavailable();

  @override
  Future<void> update(String id, Map<String, dynamic> body) => _unavailable();

  @override
  Future<void> delete(String id) => _unavailable();
}
