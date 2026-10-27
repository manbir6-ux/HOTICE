import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Explicit failure, rather than silently overwriting an archive that cannot
/// be decrypted (e.g., Android restores a data file without its Keystore key).
class HotIceLocalArchiveException implements Exception {
  const HotIceLocalArchiveException(this.message);
  final String message;
  @override
  String toString() => 'HOTICE local archive unavailable: $message';
}

/// A device-private and authenticated-encryption archive for SMALL project
/// metadata/storyboards. This is not the generated media storage engine, the
/// password vault, or the cloud sync client.
class HotIceLocalArchive {
  HotIceLocalArchive({
    required this.directory,
    required this.keyLoader,
  });

  final Directory directory;
  final Future<List<int>> Function() keyLoader;
  final AesGcm _algorithm = AesGcm.with256bits();
  Future<void> _queue = Future<void>.value();

  static const _fileName = 'hotice-projects-v1.aes';
  static const _keyName = 'hotice-projects-encryption-key-v1';
  static const _maxJsonBytes = 2 * 1024 * 1024;

  File get _primary => File('${directory.path}/$_fileName');
  File get _backup => File('${directory.path}/$_fileName.bak');
  File get _pending => File('${directory.path}/$_fileName.tmp');

  static Future<HotIceLocalArchive> openOnDevice() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return HotIceLocalArchive(directory: dir, keyLoader: () async {
      const secrets = FlutterSecureStorage();
      final stored = await secrets.read(key: _keyName);
      if (stored != null) {
        final key = base64Decode(stored);
        if (key.length != 32) {
          throw const HotIceLocalArchiveException('Invalid device encryption key.');
        }
        return key;
      }

      // Never silently generate a new key over a device-backup/restored file
      // that still needs the original key.
      if (await File('${dir.path}/$_fileName').exists() ||
          await File('${dir.path}/$_fileName.bak').exists()) {
        throw const HotIceLocalArchiveException(
            'Device key unavailable for existing encrypted project data.');
      }
      final entropy = Random.secure();
      final key = List<int>.generate(32, (_) => entropy.nextInt(256));
      await secrets.write(key: _keyName, value: base64Encode(key));
      return key;
    });
  }

  Future<Map<String, dynamic>?> restore() async {
    final hasMain = await _primary.exists();
    final hasBackup = await _backup.exists();
    if (!hasMain && !hasBackup) return null;
    final key = await keyLoader();
    for (final candidate in <File>[_primary, _backup]) {
      if (!await candidate.exists()) continue;
      try {
        final blob = await candidate.readAsString();
        final sealed = jsonDecode(blob);
        if (sealed is! Map<String, dynamic> || sealed['version'] != 1) {
          throw const FormatException('Unsupported local archive version.');
        }
        final secretBox = SecretBox(
          base64Decode(sealed['cipherText'] as String),
          nonce: base64Decode(sealed['nonce'] as String),
          mac: Mac(base64Decode(sealed['mac'] as String)),
        );
        final clear = await _algorithm.decrypt(
          secretBox,
          secretKey: SecretKey(key),
        );
        if (clear.length > _maxJsonBytes) {
          throw const FormatException('Archive exceeds local data limit.');
        }
        final data = jsonDecode(utf8.decode(clear));
        if (data is! Map<String, dynamic> || data['schema'] != 1) {
          throw const FormatException('Unsupported project archive schema.');
        }
        return data;
      } catch (_) {
        // A half-written primary may be recoverable from the prior backup.
      }
    }
    throw const HotIceLocalArchiveException(
        'Both the current archive and its backup could not be decrypted.');
  }

  /// Every snapshot is captured synchronously by HotIceStore. Queue writes
  /// serially so rapid edits cannot reorder snapshots or corrupt files.
  void enqueue(Map<String, dynamic> snapshot) {
    final frozen = jsonEncode(snapshot);
    _queue = _queue.then((_) => _write(frozen)).catchError((Object error) {
      // Keep later writes alive, but report to Flutter diagnostics.
      // The failed archive remains intact; no unencrypted fallback is used.
      stderr.writeln('HOTICE local archive write failed: ${error.runtimeType}');
    });
  }

  Future<void> flush() => _queue;

  Future<void> _write(String clearJson) async {
    final plain = utf8.encode(clearJson);
    if (plain.length > _maxJsonBytes) {
      throw const HotIceLocalArchiveException('Project archive exceeds 2 MiB.');
    }
    await directory.create(recursive: true);
    final key = await keyLoader();
    final box = await _algorithm.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: _algorithm.newNonce(),
    );
    final wrapped = jsonEncode(<String, Object>{
      'version': 1,
      'cipherText': base64Encode(box.cipherText),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
    });
    await _pending.writeAsString(wrapped, flush: true);
    if (await _primary.exists()) {
      if (await _backup.exists()) await _backup.delete();
      await _primary.rename(_backup.path);
    }
    await _pending.rename(_primary.path);
  }
}
