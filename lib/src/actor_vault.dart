import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'actor_archive.dart';
import 'state.dart';

/// V1 per-device authenticated encryption for consented Actor photo archives.
/// It is not user authentication, a biometric vault certification, or cloud
/// sync. Decrypted photos remain in app-private TEMP for camera/scene preview,
/// and are removed at next app startup by the existing cleanup policy.
class ActorVaultCrypto {
  static const _magic = 'HIVA1';
  static final AesGcm _aes = AesGcm.with256bits();

  static Future<SecretKey> newKey() => _aes.newSecretKey();

  static Future<Uint8List> seal(
    Uint8List plaintext,
    SecretKey key, {
    required String associatedData,
  }) async {
    if (plaintext.isEmpty || associatedData.isEmpty) {
      throw const FormatException('Vault input and account binding required.');
    }
    final box = await _aes.encrypt(
      plaintext,
      secretKey: key,
      aad: utf8.encode(associatedData),
    );
    return Uint8List.fromList([
      ...ascii.encode(_magic),
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  static Future<Uint8List> open(
    Uint8List encrypted,
    SecretKey key, {
    required String associatedData,
  }) async {
    if (encrypted.length < 34 ||
        ascii.decode(encrypted.sublist(0, 5), allowInvalid: true) != _magic ||
        associatedData.isEmpty) {
      throw const FormatException('Unrecognized Actor vault format.');
    }
    final box = SecretBox(
      encrypted.sublist(33),
      nonce: encrypted.sublist(5, 17),
      mac: Mac(encrypted.sublist(17, 33)),
    );
    final bytes = await _aes.decrypt(
      box,
      secretKey: key,
      aad: utf8.encode(associatedData),
    );
    return Uint8List.fromList(bytes);
  }
}

class ActorVaultLoad {
  const ActorVaultLoad(this.actors, this.failedEntries);
  final List<StudioAvatar> actors;
  final int failedEntries;
}

/// Device-only vault. All files contain AES-256-GCM ciphertext; key bytes
/// are stored in Android Keystore-backed / iOS Keychain-backed plugin storage.
/// V1 intentionally does NOT back up keys or vault files across devices.
class ActorLocalVault {
  ActorLocalVault._();
  static final ActorLocalVault instance = ActorLocalVault._();

  static const _keyName = 'hotice.actor.vault.v1';
  static const _maxFileBytes = ActorArchiveCodec.maxArchiveBytes + 64;
  static const _storage = FlutterSecureStorage();

  final Map<String, String> _nameToFile = {};
  String? _loadedAccount;
  SecretKey? _cachedKey;
  // All account loads, saves and deletes share one queue. Otherwise an
  // asynchronous import/scan can write under another workspace's index.
  Future<void> _serialTail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _serialTail.then((_) => operation());
    _serialTail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static String _normalize(String name) => name.trim().toLowerCase();

  static Future<String> _accountHash(String email) async {
    final digest = await Sha256().hash(utf8.encode(email.trim().toLowerCase()));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  Future<Directory> _directoryFor(String account) async {
    final hash = await _accountHash(account);
    return Directory(
      '${(await getApplicationSupportDirectory()).path}/hotice_actor_vault_v1/$hash',
    );
  }

  Future<SecretKey> _key({required bool create}) async {
    if (_cachedKey != null) return _cachedKey!;
    final saved = await _storage.read(key: _keyName);
    if (saved != null) {
      final bytes = base64Decode(saved);
      if (bytes.length != 32) {
        throw StateError('Stored Actor vault key is invalid.');
      }
      _cachedKey = SecretKey(bytes);
      return _cachedKey!;
    }
    if (!create) {
      throw StateError('Device Actor vault key unavailable; existing records cannot be opened.');
    }
    final generated = await ActorVaultCrypto.newKey();
    await _storage.write(
      key: _keyName,
      value: base64Encode(await generated.extractBytes()),
    );
    _cachedKey = generated;
    return generated;
  }

  /// Restore only profiles belonging to the currently active demo workspace.
  /// Serialized with writes to keep account indexes and files consistent.
  /// Damaged records fail closed and stay encrypted for recovery.
  Future<ActorVaultLoad> load(String account) =>
      _serial(() => _loadInternal(account));

  Future<ActorVaultLoad> _loadInternal(String account) async {
    final folder = await _directoryFor(account);
    _nameToFile.clear();
    _loadedAccount = null;
    if (!await folder.exists()) {
      _loadedAccount = account;
      return const ActorVaultLoad([], 0);
    }
    final entries = await folder.list(followLinks: false).toList();
    final records = entries.whereType<File>().where(
        (file) => RegExp(r'^[0-9a-f]{32}[.]vault$')
            .hasMatch(file.uri.pathSegments.last)).toList();
    if (records.isEmpty) {
      _loadedAccount = account;
      return const ActorVaultLoad([], 0);
    }
    final key = await _key(create: false);
    final hash = await _accountHash(account);
    final actors = <StudioAvatar>[];
    var failed = 0;
    for (final file in records) {
      try {
        if (await file.length() < 34 || await file.length() > _maxFileBytes) {
          throw const FormatException('Unsupported encrypted entry size.');
        }
        final data = await ActorVaultCrypto.open(
          await file.readAsBytes(), key,
          associatedData: '$hash/${file.uri.pathSegments.last}',
        );
        final profile = ActorArchiveCodec.decode(data);
        final lower = _normalize(profile.name);
        if (_nameToFile.containsKey(lower)) {
          throw const FormatException('Duplicate Actor name in vault.');
        }
        final paths = await ActorArchiveCodec.importToTemporaryFolder(profile);
        _nameToFile[lower] = file.path;
        actors.add(StudioAvatar(
          profile.name, profile.style,
          identityNotes: profile.notes,
          capturePaths: List.unmodifiable(paths),
          autoTouchUp: profile.autoTouchUp,
        ));
      } catch (_) {
        failed++;
      }
    }
    // No automatic sync or stale-account imports, only the active workspace.
    _loadedAccount = account;
    return ActorVaultLoad(List.unmodifiable(actors), failed);
  }

  Future<void> save(String account, StudioAvatar actor,
      {String? formerName}) => _serial(
        () => _saveInternal(account, actor, formerName: formerName),
      );

  Future<void> _saveInternal(String account, StudioAvatar actor,
      {String? formerName}) async {
    if (_loadedAccount != account) {
      throw StateError('Actor vault not loaded for this workspace.');
    }
    final folder = await _directoryFor(account);
    await folder.create(recursive: true);
    final oldPath = _nameToFile[_normalize(formerName ?? actor.name)];
    final currentOwner = _nameToFile[_normalize(actor.name)];
    if (currentOwner != null && currentOwner != oldPath) {
      throw StateError('Another Actor already owns that vault name.');
    }
    if (formerName != null && oldPath == null) {
      throw StateError('Original Actor not found in encrypted vault.');
    }
    final random = Random.secure();
    final newId = List.generate(16, (_) =>
        random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final path = '${folder.path}/$newId.vault';
    final temp = File('$path.pending');
    final key = await _key(create: true);
    final hash = await _accountHash(account);
    // The source file is a validated, consented HOTICE actor ZIP; raw photos
    // never become persistent unencrypted files in the support directory.
    final zip = await ActorArchiveCodec.exportActor(actor);
    final encrypted = await ActorVaultCrypto.seal(
      zip, key, associatedData: '$hash/$newId.vault',
    );
    if (encrypted.length > _maxFileBytes) {
      throw StateError('Encrypted Actor exceeds the local vault limit.');
    }
    try {
      await temp.writeAsBytes(encrypted, flush: true);
      await temp.rename(path);
      // Commit the name index only once old data has been deleted.
      // If deletion fails, roll the new copy back to avoid conflicting
      // versions being restored in arbitrary directory order next launch.
      if (oldPath != null && oldPath != path) {
        try {
          final previous = File(oldPath);
          if (await previous.exists()) await previous.delete();
        } catch (_) {
          try { await File(path).delete(); } catch (_) {}
          rethrow;
        }
      }
      _nameToFile.remove(_normalize(formerName ?? actor.name));
      _nameToFile[_normalize(actor.name)] = path;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> delete(String account, String actorName) =>
      _serial(() => _deleteInternal(account, actorName));

  Future<void> _deleteInternal(String account, String actorName) async {
    if (_loadedAccount != account) {
      throw StateError('Actor vault not loaded for this workspace.');
    }
    final path = _nameToFile[_normalize(actorName)];
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
    _nameToFile.remove(_normalize(actorName));
  }
}
