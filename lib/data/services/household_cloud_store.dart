import 'dart:convert';

import 'package:http/http.dart' as http;

/// Minimal remote JSON document store used for household sharing.
abstract class HouseholdCloudStore {
  Future<String> create(Map<String, dynamic> body);
  Future<Map<String, dynamic>?> read(String id);
  Future<void> update(String id, Map<String, dynamic> body);
  Future<void> delete(String id);
}

/// Anonymous JSON host with open CORS — suitable for GitHub Pages clients.
///
/// Docs advertise ~75 days of inactivity before removal; keep syncing while
/// the household is active so the document stays alive.
class JsonBlobHouseholdCloudStore implements HouseholdCloudStore {
  JsonBlobHouseholdCloudStore({http.Client? client})
      : _client = client ?? http.Client();

  static const _base = 'https://jsonblob.com/api/jsonBlob';

  final http.Client _client;

  @override
  Future<String> create(Map<String, dynamic> body) async {
    final response = await _client.post(
      Uri.parse(_base),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw StateError(
        'Could not create household cloud doc (${response.statusCode})',
      );
    }
    final fromHeader = response.headers['x-jsonblob-id'] ??
        response.headers['X-jsonblob-id'];
    if (fromHeader != null && fromHeader.trim().isNotEmpty) {
      return fromHeader.trim();
    }
    final location = response.headers['location'] ?? response.headers['Location'];
    if (location == null || location.isEmpty) {
      throw StateError('Household cloud create missing document id');
    }
    return location.split('/').where((p) => p.isNotEmpty).last;
  }

  @override
  Future<Map<String, dynamic>?> read(String id) async {
    final response = await _client.get(
      Uri.parse('$_base/$id'),
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError(
        'Could not read household cloud doc (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw StateError('Household cloud doc was not a JSON object');
  }

  @override
  Future<void> update(String id, Map<String, dynamic> body) async {
    final response = await _client.put(
      Uri.parse('$_base/$id'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 404) {
      throw StateError('Household cloud doc missing; create a new share link');
    }
    if (response.statusCode != 200) {
      throw StateError(
        'Could not update household cloud doc (${response.statusCode})',
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    final response = await _client.delete(Uri.parse('$_base/$id'));
    if (response.statusCode == 404 || response.statusCode == 405) return;
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw StateError(
        'Could not delete household cloud doc (${response.statusCode})',
      );
    }
  }
}
