import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../firebase_options.dart';
import 'firestore_rest_codec.dart';

class FirestoreRestClient {
  FirestoreRestClient({
    http.Client? httpClient,
    String? projectId,
    String? apiKey,
    this.tokenProvider,
  })  : _http = httpClient ?? http.Client(),
        _projectId = projectId ?? DefaultFirebaseOptions.web.projectId,
        _apiKey = apiKey ?? DefaultFirebaseOptions.web.apiKey;

  final http.Client _http;
  final String _projectId;
  final String _apiKey;
  final Future<String?> Function()? tokenProvider;
  final _uuid = const Uuid();

  String get _docsBase =>
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

  Future<Map<String, dynamic>?> getDocument(String path) async {
    final response = await _send('GET', _docUri(path));
    if (response.statusCode == 404) return null;
    final json = _decode(response);
    return FirestoreRestCodec.decodeFields(
      json['fields'] as Map<String, dynamic>?,
    );
  }

  Future<void> setDocument(String path, Map<String, dynamic> json) async {
    final response = await _send(
      'PATCH',
      _docUri(path),
      body: {'fields': FirestoreRestCodec.encodeFields(json)},
    );
    _decode(response);
  }

  Future<String> createDocument(
    String collectionPath,
    Map<String, dynamic> json,
  ) async {
    final id = _uuid.v4().replaceAll('-', '').substring(0, 20);
    final response = await _send(
      'POST',
      _collectionUri(collectionPath, documentId: id),
      body: {'fields': FirestoreRestCodec.encodeFields(json)},
    );
    final created = _decode(response);
    final name = created['name'] as String? ?? '';
    final slash = name.lastIndexOf('/');
    if (slash >= 0 && slash < name.length - 1) {
      return name.substring(slash + 1);
    }
    return id;
  }

  Future<void> deleteDocument(String path) async {
    final response = await _send('DELETE', _docUri(path));
    if (response.statusCode == 404) return;
    _decode(response);
  }

  Uri _docUri(String path) {
    return Uri.parse('$_docsBase/$path').replace(queryParameters: {'key': _apiKey});
  }

  Uri _collectionUri(String collectionPath, {String? documentId}) {
    return Uri.parse('$_docsBase/$collectionPath').replace(
      queryParameters: {
        'key': _apiKey,
        'documentId': ?documentId,
      },
    );
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers);
      case 'DELETE':
        return _http.delete(uri, headers: headers);
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: encoded);
      case 'POST':
        return _http.post(uri, headers: headers, body: encoded);
      default:
        throw StateError('Unsupported HTTP $method');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) return {};
      throw StateError('Cloud request failed (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Unexpected cloud response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      final message = error is Map ? error['message'] : decoded['error'];
      throw StateError(message?.toString() ?? 'Cloud request failed');
    }
    return decoded;
  }
}
