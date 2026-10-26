import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'actor_archive.dart';
import 'state.dart';

/// Encrypted local Actor archive, bound to one device's OS-protected key.
/// This protects stored files at rest, not unlocked app sessions, Android
/// screenshots, or exported .hoticeactor ZIPs (those remain unencrypted).
///
/// The UI still uses temporary *decrypted* JPGs during an active session;
/// main.dart purges these cache images before restoring the encrypted vault.
/// No networking, account authentication, cloud backup or biometric liveness.
class ActorVault {
  ActorVault({
    Directory? root,
    Future<Uint8List> Function()? keyProvider,
  }) : _root = root,
       _keyProvider = keyProvider;

  final Directory? _root;
  final Future<Uint8List> Function()? _keyProvider;

  static const int _formatVersion = 1;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const int maxActorRecords = 30;
  static const String _keyStorageName = 'hotice.actor.vault.key.v1';

  final AesGcm _cipher = AesGcm.with256bits();
  final Random _random = Random.secure();

  Future<Uint8List> _keyBytes() async {
    if (_keyProvider != null) {
      final bytes = await _keyProvider();
      if (bytes.length != 32) throw StateError('Actor vault key is invalid.');
      return bytes;
    }
    const secure = FlutterSecureStorage();
    final existing = await secure.read(key: _keyStorageName);
    if (existing != null) {
      final bytes = base64Url.decode(base64Url.normalize(existing));
      if (bytes.length != 32) {
        throw StateError('Existing secure Actor key is corrupt.');
      }
      return Uint8List.fromList(bytes);
    }
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    await secure.write(key: _keyStorageName, value: base64UrlEncode(bytes));
    return bytes;
  }

  Future<Directory> _accountDirectory(String account) async {
    final normalized = account.trim().toLowerCase();
    if (normalized.isEmpty) throw ArgumentError('Account cannot be empty.');
    // Hash names rather than putting email addresses into filesystem paths.
    final digest = await Sha256().hash(utf8.encode(normalized));
    final dir = Directory(
      '${(_root ?? await getApplicationSupportDirectory()).path}'
      '/hotice_private_actors/${_hex(digest.bytes)}',
    );
    await dir.create(recursive: true);
    return dir;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

  String _newId() =>
      _hex(List<int>.generate(16, (_) => _random.nextInt(256)));

  static final RegExp _validId = RegExp(r'^[0-9a-f]{32}$');
  static void _checkId(String id) {
    if (!_validId.hasMatch(id)) {
      throw const FormatException('Invalid Actor record ID.');
    }
  }

  Future<Uint8List> _encrypt(
      Uint8List bytes, String account, String id) async {
    final key = await _keyBytes();
    final nonce = _cipher.newNonce();
    final encrypted = await _cipher.encrypt(
      bytes,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: utf8.encode('HOTICE-Actor-V1:${account.toLowerCase()}:$id'),
    );
    return Uint8List.fromList([
      _formatVersion,
      ...encrypted.nonce,
      ...encrypted.mac.bytes,
      ...encrypted.cipherText,
    ]);
  }

  Future<Uint8List> _decrypt(
      Uint8List bytes, String account, String id) async {
    if (bytes.length < 1 + _nonceLength + _tagLength ||
        bytes[0] != _formatVersion) {
      throw const FormatException('Actor vault format is invalid.');
    }
    final nonce = bytes.sublist(1, 1 + _nonceLength);
    final mac = Mac(bytes.sublist(
      1 + _nonceLength, 1 + _nonceLength + _tagLength,
    ));
    final ciphertext = bytes.sublist(1 + _nonceLength + _tagLength);
    try {
      final plain = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: mac),
        secretKey: SecretKey(await _keyBytes()),
        aad: utf8.encode('HOTICE-Actor-V1:${account.toLowerCase()}:$id'),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Actor vault authentication failed; data may be damaged.',
      );
    }
  }

  /// Atomically create/update the sealed record. Never writes plaintext
  /// archives to the persistent application-support directory.
  Future<String> save(StudioAvatar actor, {required String account}) async {
    if (actor.capturePaths.isEmpty) {
      throw StateError('A scanned photo is required to save an Actor.');
    }
    final id = actor.vaultId ?? _newId();
    _checkId(id);
    final folder = await _accountDirectory(account);
    final target = File('${folder.path}/$id.hav');
    if (!await target.exists() &&
        (await folder.list().where((f) => f.path.endsWith('.hav')).length) >=
            maxActorRecords) {
      throw StateError('Actor vault limit reached (30). Export or delete one.');
    }
    final packed = await ActorArchiveCodec.exportActor(actor);
    final sealed = await _encrypt(packed, account, id);
    final temporary = File('${folder.path}/$id.${_newId()}.pending');
    try {
      await temporary.writeAsBytes(sealed, flush: true);
      // Android/iOS filesystems use atomic rename within the same directory.
      await temporary.rename(target.path);
      return id;
    } finally {
      if (await temporary.exists()) {
        await temporary.delete().catchError((_) => temporary);
      }
    }
  }

  Future<void> delete(String id, {required String account}) async {
    _checkId(id);
    final dir = await _accountDirectory(account);
    final target = File('${dir.path}/$id.hav');
    if (await target.exists()) await target.delete();
  }

  /// Decrypts only valid sealed records and materializes temporary JPEGs.
  /// Invalid/tampered records are not deleted. The UI should display the
  /// skipped-record count instead of silently claiming everything restored.
  Future<ActorVaultLoadResult> restore(String account) async {
    final folder = await _accountDirectory(account);
    final restored = <StudioAvatar>[];
    var failed = 0;
    await for (final item in folder.list(followLinks: false)) {
      if (item is! File || !item.path.endsWith('.hav')) continue;
      final id = item.uri.pathSegments.last.replaceFirst('.hav', '');
      if (!_validId.hasMatch(id)) {
        failed++;
        continue;
      }
      try {
        final size = await item.length();
        if (size <= 0 || size > ActorArchiveCodec.maxArchiveBytes + 64) {
          throw const FormatException('Stored Actor record exceeds size limit.');
        }
        final packed = await _decrypt(
          await item.readAsBytes(), account, id,
        );
        final profile = ActorArchiveCodec.decode(packed);
        final photos = await ActorArchiveCodec.importToTemporaryFolder(profile);
        restored.add(StudioAvatar(
          profile.name, profile.style,
          identityNotes: profile.notes,
          capturePaths: List<String>.unmodifiable(photos),
          autoTouchUp: profile.autoTouchUp,
          vaultId: id,
        ));
      } catch (_) {
        failed++;
      }
    }
    // Library order is stable by record name; never trust filesystem order.
    restored.sort((a, b) => a.name.compareTo(b.name));
    return ActorVaultLoadResult(
      List<StudioAvatar>.unmodifiable(restored), failed,
    );
  }
}

class ActorVaultLoadResult {
  const ActorVaultLoadResult(this.actors, this.failedRecords);
  final List<StudioAvatar> actors;
  final int failedRecords;
}
