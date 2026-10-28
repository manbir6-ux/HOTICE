import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('queues, polls and cancels a mock job with the secure server token', () async {
    final vault = MemoryTokenStore()..value = token;
    final requests = <http.Request>[];
    final job = {
      'id': '01234567-89ab-4cde-8fab-0123456789ab',
      'status': 'queued',
      'attempts': 0,
      'maxAttempts': 3,
      'reservedCredits': 5,
      'chargedCredits': 0,
      'result': null,
      'errorCode': null,
    };
    final client = BackendAuthClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenStore: vault,
      client: MockClient((request) async {
        requests.add(request);
        expect(request.followRedirects, isFalse);
        expect(request.headers['authorization'], 'Bearer $token');
        if (request.url.path == '/v1/jobs/quote') {
          expect(jsonDecode(request.body)['request']['modelId'], 'hotice.mock.video.v1');
          return jsonResponse(200, {'quoteToken': 'signed-quote'});
        }
        if (request.url.path == '/v1/jobs' && request.method == 'POST') {
          expect(request.headers['Idempotency-Key'], 'hotice-dry-run-00000001');
          expect(jsonDecode(request.body)['quoteToken'], 'signed-quote');
          return jsonResponse(201, {'job': job});
        }
        if (request.url.path.endsWith('/cancel')) {
          return jsonResponse(200, {'job': {...job, 'status': 'cancelled'}});
        }
        return jsonResponse(200, {'job': job});
      }),
    );

    final created = await client.submitMockVideoJob(
      'An ocean at dusk', idempotencyKey: 'hotice-dry-run-00000001',
    );
    expect(created.status, 'queued');
    expect(created.reservedCredits, 5);
    expect((await client.getMockVideoJob(created.id)).id, created.id);
    expect((await client.cancelMockVideoJob(created.id)).status, 'cancelled');
    expect(requests, hasLength(4));
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
}
