import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zentho/data/auth/identity_toolkit_client.dart';
import 'package:zentho/data/auth/rest_google_auth_service.dart';
import 'package:zentho/data/persistence/firestore_rest_client.dart';
import 'package:zentho/data/persistence/firestore_rest_household_cloud_store.dart';
import 'package:zentho/data/persistence/firestore_rest_user_cloud_store.dart';

class _FixedTokenSource implements GoogleIdTokenSource {
  _FixedTokenSource(this.token);
  final String token;

  @override
  Future<String> getIdToken() async => token;

  @override
  Future<void> signOut() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RestGoogleAuthService signs in through Identity Toolkit', () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      expect(request.url.path, contains('accounts:signInWithIdp'));
      return http.Response(
        jsonEncode({
          'localId': 'uid-1',
          'email': 'ada@example.com',
          'displayName': 'Ada',
          'idToken': 'id-token',
          'refreshToken': 'refresh-token',
          'expiresIn': '3600',
        }),
        200,
      );
    });

    final auth = RestGoogleAuthService(
      toolkit: IdentityToolkitClient(httpClient: client, apiKey: 'test-key'),
      tokenSource: _FixedTokenSource('google-id-token'),
    );
    final user = await auth.signInWithGoogle();
    expect(user.uid, 'uid-1');
    expect(user.email, 'ada@example.com');
    expect(await auth.idToken(), 'id-token');
  });

  test('Firestore REST user store loads a snapshot document', () async {
    final client = MockClient((request) async {
      expect(request.url.path, contains('users/uid-1/data/snapshot'));
      expect(request.headers['Authorization'], 'Bearer id-token');
      return http.Response(
        jsonEncode({
          'fields': {
            'updatedAt': {'stringValue': '2026-09-03T12:00:00.000Z'},
            'snapshot': {
              'mapValue': {
                'fields': {
                  'settings': {
                    'mapValue': {
                      'fields': {
                        'mainCurrency': {'stringValue': 'USD'},
                        'activeProfileId': {'stringValue': 'you'},
                        'onboardingComplete': {'booleanValue': true},
                      },
                    },
                  },
                  'profiles': {
                    'arrayValue': {
                      'values': [
                        {
                          'mapValue': {
                            'fields': {
                              'id': {'stringValue': 'you'},
                              'name': {'stringValue': 'Ada'},
                              'colorHex': {'integerValue': '740462'},
                            },
                          },
                        },
                      ],
                    },
                  },
                  'accounts': {'arrayValue': {}},
                  'categories': {'arrayValue': {}},
                  'transactions': {'arrayValue': {}},
                  'budgets': {'arrayValue': {}},
                  'goals': {'arrayValue': {}},
                  'rates': {'arrayValue': {}},
                  'holdings': {'arrayValue': {}},
                  'shareTransactions': {'arrayValue': {}},
                },
              },
            },
          },
        }),
        200,
      );
    });

    final store = FirestoreRestUserCloudStore(
      client: FirestoreRestClient(
        httpClient: client,
        projectId: 'zentho-db83e',
        apiKey: 'test-key',
        tokenProvider: () async => 'id-token',
      ),
    );
    final doc = await store.load('uid-1');
    expect(doc, isNotNull);
    expect(doc!.snapshot.settings.mainCurrency, 'USD');
    expect(doc.snapshot.profiles.single.name, 'Ada');
    expect(doc.updatedAt, DateTime.utc(2026, 9, 3, 12));
  });

  test('Firestore REST household store creates and reads a share doc', () async {
    http.Request? created;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        created = request;
        return http.Response(
          jsonEncode({
            'name':
                'projects/zentho-db83e/databases/(default)/documents/households/abc123',
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'fields': {
            'inviteKey': {'stringValue': 'abcdefghij'},
            'updatedAt': {'stringValue': '2026-09-03T12:00:00.000Z'},
            'v': {'integerValue': '1'},
            'snapshot': {
              'mapValue': {
                'fields': {
                  'settings': {
                    'mapValue': {
                      'fields': {
                        'mainCurrency': {'stringValue': 'USD'},
                      },
                    },
                  },
                },
              },
            },
          },
        }),
        200,
      );
    });

    final store = FirestoreRestHouseholdCloudStore(
      client: FirestoreRestClient(
        httpClient: client,
        projectId: 'zentho-db83e',
        apiKey: 'test-key',
      ),
    );
    final id = await store.create({
      'v': 1,
      'inviteKey': 'abcdefghij',
      'updatedAt': '2026-09-03T12:00:00.000Z',
      'snapshot': {
        'settings': {'mainCurrency': 'USD'},
      },
    });
    expect(id, 'abc123');
    expect(created, isNotNull);

    final read = await store.read('abc123');
    expect(read?['inviteKey'], 'abcdefghij');
    expect(read?['v'], 1);
  });
}
