import 'package:flutter_test/flutter_test.dart';
import 'package:zentho/data/auth/identity_toolkit_client.dart';
import 'package:zentho/data/persistence/firestore_rest_codec.dart';

void main() {
  test('googleIdTokenFromRedirect reads the Firebase handler fragment', () {
    const url =
        'https://zentho-db83e.firebaseapp.com/__/auth/handler#id_token=abc.def.ghi&state=xyz';
    expect(googleIdTokenFromRedirect(url), 'abc.def.ghi');
  });

  test('googleIdTokenFromRedirect ignores unrelated URLs', () {
    expect(
      googleIdTokenFromRedirect('https://accounts.google.com/o/oauth2/auth'),
      isNull,
    );
  });

  test('googleIdTokenFromRedirect throws on OAuth error', () {
    expect(
      () => googleIdTokenFromRedirect(
        'https://zentho-db83e.firebaseapp.com/__/auth/handler#error=access_denied',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('Firestore REST codec round-trips ints, doubles, and nested maps', () {
    final json = {
      'updatedAt': '2026-09-03T12:00:00.000Z',
      'snapshot': {
        'profiles': [
          {'id': 'you', 'name': 'Ada', 'colorHex': 0xFF0B6E6E},
        ],
        'accounts': [
          {'name': 'Checking', 'openingBalance': 250.5},
        ],
        'on': true,
      },
    };

    final fields = FirestoreRestCodec.encodeFields(json);
    expect(fields['updatedAt'], {'stringValue': '2026-09-03T12:00:00.000Z'});
    final decoded = FirestoreRestCodec.decodeFields(fields);
    expect(decoded['updatedAt'], '2026-09-03T12:00:00.000Z');
    final snapshot = decoded['snapshot'] as Map<String, dynamic>;
    final profile = (snapshot['profiles'] as List).first as Map<String, dynamic>;
    expect(profile['colorHex'], 0xFF0B6E6E);
    expect(profile['colorHex'], isA<int>());
    final account = (snapshot['accounts'] as List).first as Map<String, dynamic>;
    expect(account['openingBalance'], 250.5);
    expect(snapshot['on'], isTrue);
  });

  test('Firestore REST codec reads integerValue strings', () {
    final decoded = FirestoreRestCodec.decodeFields({
      'colorHex': {'integerValue': '11894766'},
    });
    expect(decoded['colorHex'], 11894766);
  });
}
