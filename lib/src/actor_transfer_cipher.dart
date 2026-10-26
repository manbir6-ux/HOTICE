import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'actor_archive.dart';

/// Password-protected, user-exported Actor package.
///
/// Format: ASCII "HACE2" + 16-byte random salt + 12-byte random nonce
/// + 16-byte GCM MAC + ciphertext of a normal HOTICE_ACTOR ZIP.
/// No keys, passwords or private images are sent to a network service.
/// Passwords are not saved. Losing the password makes the export unrecoverable.
/// Legacy v1 unencrypted ZIP imports remain an *explicit* opt-in in the UI.
class ActorTransferCipher {
  static const _magic = 'HACE2';
  static const _saltBytes = 16;
  static const _nonceBytes = 12;
  static const _macBytes = 16;
  static const _headerSize = 5 + _saltBytes + _nonceBytes + _macBytes;
  static const _aad = 'HOTICE-ACTOR-EXPORT-V2';
  static const _iterations = 180000;

  static final _cipher = AesGcm.with256bits();
  static final _pbkdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );

  static bool isEncrypted(Uint8List bytes) =>
      bytes.length >= _headerSize &&
      bytes[0] == 0x48 && bytes[1] == 0x41 &&
      bytes[2] == 0x43 && bytes[3] == 0x45 && bytes[4] == 0x32;

  static bool isLegacyZip(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 && bytes[1] == 0x4b &&
      bytes[2] == 0x03 && bytes[3] == 0x04;

  static Future<SecretKey> _deriveKey(String password, List<int> salt) =>
      _pbkdf.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: salt,
      );

  static Future<Uint8List> encrypt(
    Uint8List zip, {
    required String password,
  }) async {
    if (password.length < 12 || password.length > 256) {
      throw const FormatException(
        'Actor backup password must contain 12–256 characters.',
      );
    }
    if (!isLegacyZip(zip) ||
        zip.length > ActorArchiveCodec.maxArchiveBytes) {
      throw const FormatException('Invalid Actor ZIP for encryption.');
    }
    // Validate *before* encrypting, so a protected backup never contains
    // arbitrary or malformed face archives disguised as HOTICE Actors.
    ActorArchiveCodec.decode(zip);
    final random = Random.secure();
    final salt = List<int>.generate(
      _saltBytes, (_) => random.nextInt(256),
    );
    final nonce = List<int>.generate(
      _nonceBytes, (_) => random.nextInt(256),
    );
    final key = await _deriveKey(password, salt);
    final box = await _cipher.encrypt(
      zip,
      secretKey: key,
      nonce: nonce,
      aad: ascii.encode(_aad),
    );
    return Uint8List.fromList([
      ...ascii.encode(_magic),
      ...salt,
      ...box.nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  static Future<Uint8List> decrypt(
    Uint8List contents, {
    required String password,
  }) async {
    if (!isEncrypted(contents) ||
        contents.length <= _headerSize ||
        contents.length > ActorArchiveCodec.maxArchiveBytes + _headerSize) {
      throw const FormatException('Not a supported encrypted HOTICE Actor.');
    }
    if (password.isEmpty) {
      throw const FormatException('An Actor backup password is required.');
    }
    final salt = contents.sublist(5, 5 + _saltBytes);
    final nonce = contents.sublist(
      5 + _saltBytes, 5 + _saltBytes + _nonceBytes,
    );
    final mac = contents.sublist(
      5 + _saltBytes + _nonceBytes, _headerSize,
    );
    final encrypted = contents.sublist(_headerSize);
    try {
      final plain = await _cipher.decrypt(
        SecretBox(encrypted, nonce: nonce, mac: Mac(mac)),
        secretKey: await _deriveKey(password, salt),
        aad: ascii.encode(_aad),
      );
      if (plain.length > ActorArchiveCodec.maxArchiveBytes) {
        throw const FormatException('Decrypted Actor archive exceeds limit.');
      }
      final bytes = Uint8List.fromList(plain);
      // Strictly validate ZIP metadata/photos after authenticated decryption.
      ActorArchiveCodec.decode(bytes);
      return bytes;
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Could not unlock Actor backup. Wrong password or modified file.',
      );
    }
  }
}
