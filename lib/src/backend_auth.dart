import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const hoticeApiBaseUrl = String.fromEnvironment('HOTICE_API_BASE_URL');

class BackendAuthException implements Exception {
  const BackendAuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class BackendUser {
  const BackendUser({required this.id, required this.email});

  final String id;
  final String email;
}

abstract interface class SessionTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureSessionTokenStore implements SessionTokenStore {
  SecureSessionTokenStore({FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;

  static const _key = 'hotice-api-session-token-v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Password authentication for the shared HOTICE API.
///
/// The base URL is public configuration, never a credential. HTTPS is required
/// except for loopback hosts used by local development. Redirects are disabled
/// so credentials and bearer tokens cannot be forwarded to another host.
class BackendAuthClient {
  BackendAuthClient({
    required Uri baseUri,
    SessionTokenStore? tokenStore,
    http.Client? client,
  })  : _baseUri = _validateBaseUri(baseUri),
        _tokenStore = tokenStore ?? SecureSessionTokenStore(),
        _client = client ?? http.Client();

  final Uri _baseUri;
  final SessionTokenStore _tokenStore;
  final http.Client _client;

  static Uri _validateBaseUri(Uri value) {
    final loopback = value.host == 'localhost' ||
        value.host == '127.0.0.1' ||
        value.host == '::1';
    if ((value.scheme != 'https' && !(loopback && value.scheme == 'http')) ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment) {
      throw const BackendAuthException(
        'The HOTICE API address must use HTTPS.',
      );
    }
    return value.replace(path: value.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  static BackendAuthClient? fromEnvironment({
    SessionTokenStore? tokenStore,
    http.Client? client,
  }) {
    final value = hoticeApiBaseUrl.trim();
    if (value.isEmpty) return null;
    try {
      return BackendAuthClient(
        baseUri: Uri.parse(value),
        tokenStore: tokenStore,
        client: client,
      );
    } on FormatException {
      return null;
    } on BackendAuthException {
      return null;
    }
  }

  Uri _endpoint(String path) => _baseUri.replace(
        path: '${_baseUri.path}/$path',
        query: null,
        fragment: null,
      );

  Future<BackendUser> signIn(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || password.isEmpty || password.length > 256) {
      throw const BackendAuthException('Enter your email and password.');
    }

    final response = await _send(
      'POST',
      'v1/auth/login',
      jsonBody: {'email': normalized, 'password': password},
    );
    _checkSuccess(response, 'Sign-in failed. Check your email and password.');

    final body = _decodeObject(response);
    final token = body['accessToken'];
    if (token is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) {
      throw const BackendAuthException('The HOTICE server returned an invalid session.');
    }

    try {
      // Verify the returned token before persisting it. A successful login
      // response alone must not establish a client identity.
      final user = await _loadUser(token);
      if (user.email != normalized) {
        throw const BackendAuthException('The HOTICE server returned a different account.');
      }
      await _tokenStore.write(token);
      return user;
    } on BackendAuthException {
      await _revokeBestEffort(token);
      rethrow;
    } catch (_) {
      await _revokeBestEffort(token);
      throw const BackendAuthException(
        'Could not securely save your HOTICE session on this device.',
      );
    }
  }

  /// Restore a session only after the server confirms the token. Network
  /// failures preserve the token for a later attempt; revoked sessions clear it.
  Future<BackendUser?> restoreSession() async {
    final token = await _tokenStore.read();
    if (token == null || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) {
      if (token != null) await _tokenStore.delete();
      return null;
    }
    try {
      return await _loadUser(token);
    } on BackendAuthException catch (error) {
      if (error.statusCode == 401) await _tokenStore.delete();
      return null;
    }
  }

  Future<void> signOut() async {
    final token = await _tokenStore.read();
    if (token == null) return;
    try {
      final response = await _send('POST', 'v1/auth/logout', token: token);
      _checkSuccess(response, 'The server could not revoke this session.');
    } finally {
      // Remove the local bearer token even when offline. The server-side
      // session then expires under its configured short TTL.
      await _tokenStore.delete();
    }
  }

  Future<BackendUser> _loadUser(String token) async {
    final response = await _send('GET', 'v1/me', token: token);
    _checkSuccess(response, 'Your HOTICE session is no longer valid.');
    final body = _decodeObject(response);
    final user = body['user'];
    if (user is! Map<String, dynamic> ||
        user['id'] is! String ||
        user['email'] is! String) {
      throw const BackendAuthException('The HOTICE server returned an invalid account.');
    }
    return BackendUser(
      id: user['id'] as String,
      email: (user['email'] as String).trim().toLowerCase(),
    );
  }

  Future<void> _revokeBestEffort(String token) async {
    try {
      await _send('POST', 'v1/auth/logout', token: token);
    } catch (_) {
      // Never replace the original verification/storage error.
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? token,
    Map<String, Object?>? jsonBody,
  }) async {
    final request = http.Request(method, _endpoint(path))
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    }
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    try {
      final streamed = await _client.send(request).timeout(const Duration(seconds: 20));
      return await http.Response.fromStream(streamed).timeout(const Duration(seconds: 20));
    } on Exception {
      throw const BackendAuthException('Could not reach the HOTICE server.');
    }
  }

  void _checkSuccess(http.Response response, String failureMessage) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendAuthException(
        response.statusCode == 401 || response.statusCode == 403
            ? failureMessage
            : 'The HOTICE server is unavailable. Try again later.',
        statusCode: response.statusCode,
      );
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) return value;
    } on FormatException {
      // Use one safe error below; never surface raw server response text.
    }
    throw const BackendAuthException('The HOTICE server returned an invalid response.');
  }

  void close() => _client.close();
}
