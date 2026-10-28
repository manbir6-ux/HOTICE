import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AccountUser {
  const AccountUser({required this.id, required this.email});

  final String id;
  final String email;

  factory AccountUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    if (user is! Map<String, dynamic> ||
        user['id'] is! String ||
        user['email'] is! String) {
      throw const AccountApiException('The account service returned an invalid response.');
    }
    return AccountUser(id: user['id'] as String, email: user['email'] as String);
  }
}

abstract interface class AccountTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureAccountTokenStore implements AccountTokenStore {
  SecureAccountTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'hotice.account.session.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class AccountApiException implements Exception {
  const AccountApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Shared authenticated HOTICE account API client. No API key is stored here;
/// the optional base URL is a public deployment address supplied at build time.
class AccountApi {
  AccountApi({
    String? baseUrl,
    http.Client? client,
    AccountTokenStore? tokenStore,
  })  : _baseUrl = (baseUrl ?? const String.fromEnvironment('HOTICE_API_BASE_URL')).trim(),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _tokenStore = tokenStore ?? SecureAccountTokenStore();

  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final AccountTokenStore _tokenStore;

  bool get isConfigured => _validBaseUri() != null;

  Uri? _validBaseUri() {
    final uri = Uri.tryParse(_baseUrl);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty || uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (uri.scheme != 'https' && !(local && uri.scheme == 'http')) return null;
    return uri;
  }

  Future<AccountUser?> restoreSession() async {
    String? token;
    try {
      token = await _tokenStore.read();
    } on Exception {
      // Secure-storage plugin initialization can fail on unsupported or test
      // platforms. Keep guest mode available; never fall back to plain storage.
      return null;
    }
    if (token == null || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) {
      if (token != null) await _tokenStore.clear();
      return null;
    }
    try {
      return AccountUser.fromJson(await _request('GET', '/v1/me', token: token));
    } on AccountApiException catch (error) {
      // A network/service outage must not destroy a still-valid local session.
      // Only an explicit authorization rejection invalidates the stored token.
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _tokenStore.clear();
        return null;
      }
      rethrow;
    }
  }

  Future<AccountUser> signIn(String email, String password) async {
    final response = await _request('POST', '/v1/auth/login', body: {
      'email': email.trim(),
      'password': password,
    });
    final token = response['accessToken'];
    if (token is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) {
      throw const AccountApiException('The account service returned an invalid sign-in response.');
    }
    final user = AccountUser.fromJson(await _request('GET', '/v1/me', token: token));
    await _tokenStore.write(token);
    return user;
  }

  Future<void> register(String email, String password) async {
    await _request('POST', '/v1/auth/register', body: {
      'email': email.trim(),
      'password': password,
    });
  }

  Future<void> resendVerification(String email) async {
    await _request('POST', '/v1/auth/verification/resend', body: {'email': email.trim()});
  }

  Future<void> requestPasswordReset(String email) async {
    await _request('POST', '/v1/auth/password-reset/request', body: {'email': email.trim()});
  }

  Future<void> signOut() async {
    String? token;
    try {
      token = await _tokenStore.read();
    } on Exception {
      await _tokenStore.clear();
      return;
    }
    try {
      if (token != null) await _request('POST', '/v1/auth/logout', token: token);
    } finally {
      await _tokenStore.clear();
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Map<String, String>? body,
  }) async {
    final base = _validBaseUri();
    if (base == null) {
      throw const AccountApiException(
        'Account sign-in is not configured. Install a build connected to the secure HOTICE service.',
      );
    }
    final uri = base.resolve(path);
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';
    late http.Response response;
    try {
      response = method == 'GET'
          ? await _client.get(uri, headers: headers).timeout(const Duration(seconds: 15))
          : await _client.post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const AccountApiException('Could not reach the HOTICE account service. Check your connection and try again.');
    }
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(response.body);
      if (value is! Map<String, dynamic>) throw const FormatException();
      decoded = value;
    } on FormatException {
      throw const AccountApiException('The HOTICE account service returned an invalid response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final serverMessage = decoded['error'];
      final safeMessage = serverMessage is String && serverMessage.length <= 160
          ? serverMessage
          : 'Account request failed. Please try again.';
      throw AccountApiException(safeMessage, statusCode: response.statusCode);
    }
    return decoded;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
