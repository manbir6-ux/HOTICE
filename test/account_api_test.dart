import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/account_api.dart';
import 'package:http/http.dart' as http;

void main() {
  final token = List<String>.filled(64, 'a').join();
  final userJson = {'user': {'id': 'user-123', 'email': 'creator@example.com'}};

  test('requires HTTPS for non-local account API origins', () {
    expect(AccountApi(baseUrl: 'https://api.example.com').isConfigured, isTrue);
    expect(AccountApi(baseUrl: 'http://api.example.com').isConfigured, isFalse);
    expect(AccountApi(baseUrl: 'http://localhost:8080').isConfigured, isTrue);
    expect(AccountApi(baseUrl: 'https://api.example.com/path').isConfigured, isFalse);
    expect(AccountApi(baseUrl: 'https://user:pass@api.example.com').isConfigured, isFalse);
  });

  test('stores bearer token only after /me confirms the account', () async {
    final tokens = _MemoryTokens();
    final requests = <http.Request>[];
    final api = AccountApi(
      baseUrl: 'https://api.example.com/',
      tokenStore: tokens,
      client: _Client((request) async {
        requests.add(request);
        if (request.url.path == '/v1/auth/login') {
          expect(jsonDecode(request.body), {'email': 'creator@example.com', 'password': 'very-long-password'});
          return http.Response(jsonEncode({'accessToken': token}), 200);
        }
        expect(request.url.path, '/v1/me');
        expect(request.headers['authorization'], 'Bearer $token');
        return http.Response(jsonEncode(userJson), 200);
      }),
    );

    final user = await api.signIn(' creator@example.com ', 'very-long-password');
    expect(user.id, 'user-123');
    expect(user.email, 'creator@example.com');
    expect(tokens.value, token);
    expect(requests.map((request) => request.url.path), ['/v1/auth/login', '/v1/me']);
    api.dispose();
  });

  test('does not persist a token when account verification fails', () async {
    final tokens = _MemoryTokens();
    final api = AccountApi(
      baseUrl: 'https://api.example.com',
      tokenStore: tokens,
      client: _Client((request) async => request.url.path == '/v1/auth/login'
          ? http.Response(jsonEncode({'accessToken': token}), 200)
          : http.Response(jsonEncode({'error': 'Email verification required.'}), 403)),
    );

    await expectLater(api.signIn('creator@example.com', 'password'), throwsA(isA<AccountApiException>()));
    expect(tokens.value, isNull);
    api.dispose();
  });

  test('clears revoked sessions and preserves tokens during service outages', () async {
    final revokedTokens = _MemoryTokens()..value = token;
    final revokedApi = AccountApi(
      baseUrl: 'https://api.example.com',
      tokenStore: revokedTokens,
      client: _Client((_) async => http.Response(jsonEncode({'error': 'Session expired or revoked.'}), 401)),
    );
    expect(await revokedApi.restoreSession(), isNull);
    expect(revokedTokens.value, isNull);

    final outageTokens = _MemoryTokens()..value = token;
    final outageApi = AccountApi(
      baseUrl: 'https://api.example.com',
      tokenStore: outageTokens,
      client: _Client((_) async => http.Response(jsonEncode({'error': 'Service unavailable.'}), 503)),
    );
    await expectLater(outageApi.restoreSession(), throwsA(isA<AccountApiException>()));
    expect(outageTokens.value, token);
    revokedApi.dispose();
    outageApi.dispose();
  });

  test('registers only through the API and sends only the expected fields', () async {
    final tokens = _MemoryTokens();
    final api = AccountApi(
      baseUrl: 'https://api.example.com',
      tokenStore: tokens,
      client: _Client((request) async {
        expect(request.url.path, '/v1/auth/register');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {'email': 'creator@example.com', 'password': 'very-long-password'});
        return http.Response(jsonEncode({'registered': true}), 201);
      }),
    );
    await api.register('creator@example.com', 'very-long-password');
    expect(tokens.value, isNull);
    api.dispose();
  });
}

class _MemoryTokens implements AccountTokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async { value = token; }
  @override
  Future<void> clear() async { value = null; }
}

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }
}
