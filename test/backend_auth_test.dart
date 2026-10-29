import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/account_credits.dart';
import 'package:hotice/src/backend_auth.dart';
import 'package:hotice/src/state.dart';
import 'package:hotice/src/welcome.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryTokenStore implements SessionTokenStore {
  String? value;

  @override
  Future<void> delete() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String token) async => value = token;
}

final token = List<String>.filled(64, 'a').join();

http.Response jsonResponse(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('login verifies identity before storing a server token', () async {
    final vault = MemoryTokenStore();
    final seen = <http.Request>[];
    final client = BackendAuthClient(
      baseUri: Uri.parse('https://api.example.test/v1-root/'),
      tokenStore: vault,
      client: MockClient((request) async {
        seen.add(request);
        if (request.url.path == '/v1-root/v1/auth/login') {
          expect(request.method, 'POST');
          expect(request.followRedirects, isFalse);
          expect(request.headers['authorization'], isNull);
          expect(jsonDecode(request.body), {
            'email': 'maker@example.com',
            'password': 'a long private passphrase',
          });
          return jsonResponse(200, {
            'accessToken': token,
            'tokenType': 'Bearer',
            'expiresAt': '2026-10-28T12:00:00Z',
          });
        }
        expect(request.url.path, '/v1-root/v1/me');
        expect(request.headers['authorization'], 'Bearer $token');
        return jsonResponse(200, {
          'user': {'id': 'user-123', 'email': 'maker@example.com'},
          'cloud': {'active': false},
        });
      }),
    );

    final user = await client.signIn(' MAKER@example.com ', 'a long private passphrase');

    expect(user.id, 'user-123');
    expect(user.email, 'maker@example.com');
    expect(vault.value, token);
    expect(seen, hasLength(2));
    client.close();
  });

  test('does not store a token when server identity does not match login', () async {
    final vault = MemoryTokenStore();
    final client = BackendAuthClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: vault,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return jsonResponse(200, {'accessToken': token});
        }
        if (request.url.path.endsWith('/me')) {
          return jsonResponse(200, {
            'user': {'id': 'other', 'email': 'someone-else@example.com'},
          });
        }
        expect(request.url.path, '/v1/auth/logout');
        expect(request.headers['authorization'], 'Bearer $token');
        return jsonResponse(200, {'ok': true});
      }),
    );

    await expectLater(
      client.signIn('maker@example.com', 'password'),
      throwsA(isA<BackendAuthException>()),
    );
    expect(vault.value, isNull);
    client.close();
  });

  test('rejects non-HTTPS non-loopback API addresses', () {
    expect(
      () => BackendAuthClient(baseUri: Uri.parse('http://api.example.test')),
      throwsA(isA<BackendAuthException>()),
    );
    final local = BackendAuthClient(
      baseUri: Uri.parse('http://localhost:8080'),
    );
    local.close();
  });

  test('revoked session is removed, while network failure keeps it for retry', () async {
    final vault = MemoryTokenStore()..value = token;
    final unauthorized = BackendAuthClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: vault,
      client: MockClient((_) async => jsonResponse(401, {'error': 'expired'})),
    );
    expect(await unauthorized.restoreSession(), isNull);
    expect(vault.value, isNull);
    unauthorized.close();

    vault.value = token;
    final offline = BackendAuthClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: vault,
      client: MockClient((_) async => throw Exception('private transport detail')),
    );
    expect(await offline.restoreSession(), isNull);
    expect(vault.value, token);
    offline.close();
  });

  test('sign-out removes local token even when server revocation fails', () async {
    final vault = MemoryTokenStore()..value = token;
    final client = BackendAuthClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: vault,
      client: MockClient((request) async {
        expect(request.url.path, '/v1/auth/logout');
        expect(request.headers['authorization'], 'Bearer $token');
        return jsonResponse(503, {'error': 'internal details are not exposed'});
      }),
    );

    await expectLater(client.signOut(), throwsA(isA<BackendAuthException>()));
    expect(vault.value, isNull);
    client.close();
  });

  test(
      'account export validates and returns only the documented server snapshot',
      () async {
        final vault = MemoryTokenStore()..value = token;
        final client = BackendAuthClient(
          baseUri: Uri.parse('https://api.example.test'),
          tokenStore: vault,
          client: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/v1/me/export');
            expect(request.headers['authorization'], 'Bearer $token');
            return jsonResponse(200, {
              'format': 'hotice-account-export-v1',
              'account': {'email': 'maker@example.com'},
              'cloudProjects': [],
              'generationJobs': [],
              'includedMediaBytes': false,
              'deviceLocalProjectsIncluded': false,
            });
          }),
        );

        final export = await client.exportAccountData();
        expect(export['format'], 'hotice-account-export-v1');
        expect(export['account'], {'email': 'maker@example.com'});
        expect(vault.value, token, reason: 'Export must not alter the session.');
        client.close();
      });

  test(
      'account deletion requires exact confirmation and clears token on success',
      () async {
        final vault = MemoryTokenStore()..value = token;
        var calls = 0;
        final client = BackendAuthClient(
          baseUri: Uri.parse('https://api.example.test'),
          tokenStore: vault,
          client: MockClient((request) async {
            calls++;
            expect(request.method, 'DELETE');
            expect(request.url.path, '/v1/me');
            expect(request.headers['authorization'], 'Bearer $token');
            expect(jsonDecode(request.body), {
              'confirmation': 'DELETE',
              'password': 'correct horse battery staple',
            });
            return jsonResponse(200, {
              'deleted': true,
              'accountDataRemoved': true,
              'queuedMediaFiles': 0,
            });
          }),
        );

        await expectLater(
          client.deleteAccount(
              password: 'correct horse battery staple', confirmation: 'delete'),
          throwsA(isA<BackendAuthException>()),
        );
        expect(calls, 0,
            reason: 'Non-exact confirmation must never reach the API.');
        expect(vault.value, token);
        final result = await client.deleteAccount(
          password: 'correct horse battery staple', confirmation: 'DELETE',
        );
        expect(result['deleted'], isTrue);
        expect(vault.value, isNull);
        await expectLater(
          client.deleteAccount(
              password: 'correct horse battery staple', confirmation: 'DELETE'),
          throwsA(isA<BackendAuthException>()),
        );
        expect(calls, 1,
            reason: 'A repeated deletion cannot reuse a deleted session.');
        client.close();
      });

  test('failed account deletion preserves token so server state can be checked', () async {
    final vault = MemoryTokenStore()..value = token;
    final client = BackendAuthClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: vault,
      client: MockClient((_) async => jsonResponse(403, {'error': 'private detail'})),
    );
    await expectLater(
      client.deleteAccount(password: 'wrong password', confirmation: 'DELETE'),
      throwsA(isA<BackendAuthException>()),
    );
    expect(vault.value, token);
    client.close();
  });

  test('expired session is cleared when account deletion is rejected', () async {
    final vault = MemoryTokenStore()..value = token;
    final client = BackendAuthClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: vault,
      client: MockClient((_) async => jsonResponse(401, {'error': 'expired'})),
    );
    await expectLater(
      client.deleteAccount(password: 'correct horse battery staple', confirmation: 'DELETE'),
      throwsA(isA<BackendAuthException>()),
    );
    expect(vault.value, isNull);
    client.close();
  });

  test('store marks only server-verified account as authenticated', () {
    final store = HotIceStore();
    store.signInDemo('guest@example.com');
    expect(store.backendAuthenticated, isFalse);

    store.signInBackend('creator@example.com');
    expect(store.backendAuthenticated, isTrue);
    expect(store.selectedAccount, 'creator@example.com');

    store.signOut();
    expect(store.backendAuthenticated, isFalse);
    store.dispose();
  });

  test('account preferences are loaded and replaced through authenticated APIs',
      () async {
    final vault = MemoryTokenStore()..value = token;
    var putCalls = 0;
    final client = BackendAuthClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: vault,
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer $token');
        if (request.method == 'GET') {
          expect(request.url.path, '/v1/me/preferences');
          return jsonResponse(200, {
            'preferences': {
              'themeMode': 'system',
              'accent': 'ocean',
              'font': 'editorial',
              'updatedAt': '2026-10-29 00:00:00',
            },
          });
        }
        putCalls++;
        expect(request.method, 'PUT');
        expect(request.url.path, '/v1/me/preferences');
        expect(jsonDecode(request.body), {
          'themeMode': 'dark',
          'accent': 'ember',
          'font': 'technical',
        });
        return jsonResponse(200, {
          'preferences': {
            'themeMode': 'dark',
            'accent': 'ember',
            'font': 'technical',
          },
        });
      }),
    );

    expect(await client.loadAccountPreferences(), {
      'themeMode': 'system',
      'accent': 'ocean',
      'font': 'editorial',
      'updatedAt': '2026-10-29 00:00:00',
    });
    expect(await client.saveAccountPreferences(
      themeMode: 'dark', accent: 'ember', font: 'technical',
    ), {
      'themeMode': 'dark',
      'accent': 'ember',
      'font': 'technical',
    });
    await expectLater(
      client.saveAccountPreferences(
        themeMode: 'dark', accent: 'not-supported', font: 'technical',
      ),
      throwsA(isA<BackendAuthException>()),
    );
    expect(putCalls, 1, reason: 'Invalid local preference values never reach the API.');
    expect(vault.value, token);
    client.close();
  });

  testWidgets('signed-in appearance settings load and save account preferences',
      (tester) async {
    final store = HotIceStore()..signInBackend('maker@example.com');
    final saved = <Map<String, String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SettingsPage(
          store: store,
          onLoadAccountPreferences: () async => {
            'themeMode': 'system',
            'accent': 'ocean',
            'font': 'editorial',
          },
          onSaveAccountPreferences: ({
            required themeMode,
            required accent,
            required font,
          }) async {
            saved.add({
              'themeMode': themeMode,
              'accent': accent,
              'font': font,
            });
            return {
              'themeMode': themeMode,
              'accent': accent,
              'font': font,
            };
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(store.themeMode, ThemeMode.system);
    expect(store.accent, StudioAccent.ocean);
    expect(store.font, StudioFont.editorial);
    expect(find.text('Synced with your HOTICE account.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Ember'));
    await tester.pumpAndSettle();
    expect(store.accent, StudioAccent.ember);
    expect(saved, hasLength(1));
    expect(saved.single, {
      'themeMode': 'system',
      'accent': 'ember',
      'font': 'editorial',
    });
    expect(tester.takeException(), isNull);
    store.dispose();
  });

  testWidgets('server login form submits credentials to the auth callback',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? submittedEmail;
    String? submittedPassword;
    await tester.pumpWidget(MaterialApp(
      home: BackendLoginPage(
        onBack: () {},
        onSubmit: (email, password) async {
          submittedEmail = email;
          submittedPassword = password;
        },
      ),
    ));

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'maker@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret password');
    final submit = find.text('Sign in');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(submittedEmail, 'maker@example.com');
    expect(submittedPassword, 'secret password');
    expect(tester.widget<EditableText>(find.descendant(of: find.byType(TextFormField).last, matching: find.byType(EditableText))).obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated account page requires exact confirmation before deletion',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final store = HotIceStore()..signInBackend('maker@example.com');
    var deleteCalls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AccountsPage(
          store: store,
          onExportAccount: () async => {
            'format': 'hotice-account-export-v1',
            'account': {'email': 'maker@example.com'},
          },
          onDeleteAccount: (password, confirmation) async {
            deleteCalls++;
            expect(password, 'correct horse battery staple');
            expect(confirmation, 'DELETE');
            return {
              'deleted': true,
              'accountDataRemoved': true,
              'queuedMediaFiles': 0,
            };
          },
        ),
      ),
    ));
    expect(find.text('Export account data'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete HOTICE account?'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'correct horse battery staple');
    await tester.enterText(fields.at(1), 'delete');
    await tester.tap(find.text('Permanently delete'));
    await tester.pumpAndSettle();
    expect(find.text('Type DELETE exactly and enter your current password.'), findsOneWidget);
    expect(deleteCalls, 0);

    await tester.enterText(fields.at(1), 'DELETE');
    await tester.tap(find.text('Permanently delete'));
    await tester.pumpAndSettle();
    expect(deleteCalls, 1);
    expect(store.backendAuthenticated, isFalse);
    expect(tester.takeException(), isNull);
    store.dispose();
  });
}
