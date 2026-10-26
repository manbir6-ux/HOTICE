import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/actor_archive.dart';
import 'package:hotice/src/actor_transfer_cipher.dart';
import 'package:image/image.dart' as img;

Uint8List _actorZip() {
  final image = img.Image(width: 70, height: 90);
  img.fill(image, color: img.ColorRgb8(90, 150, 170));
  return ActorArchiveCodec.encode(
    name: 'Private Hero',
    style: 'Cinematic',
    notes: 'Consent-based Actor reference',
    photos: [
      Uint8List.fromList(img.encodeJpg(image)),
    ],
    autoTouchUp: false,
  );
}

void main() {
  test('encrypted Actor backup authenticates and restores original images',
      () async {
    final zip = _actorZip();
    expect(ActorTransferCipher.isLegacyZip(zip), isTrue);
    final encoded = await ActorTransferCipher.encrypt(
      zip, password: 'Vault-passphrase-20+',
    );
    expect(ActorTransferCipher.isEncrypted(encoded), isTrue);
    expect(ActorTransferCipher.isLegacyZip(encoded), isFalse);
    expect(encoded, isNot(orderedEquals(zip)));
    // No obvious ZIP magic, Actor name or raw JPEG bytes in output header.
    expect(encoded.sublist(0, 5), orderedEquals('HACE2'.codeUnits));
    final decrypted = await ActorTransferCipher.decrypt(
      encoded, password: 'Vault-passphrase-20+',
    );
    expect(decrypted, orderedEquals(zip));
    final actor = ActorArchiveCodec.decode(decrypted);
    expect(actor.name, 'Private Hero');
    expect(actor.photos.length, 1);
  });

  test('wrong password fails authenticated decryption', () async {
    final encoded = await ActorTransferCipher.encrypt(
      _actorZip(), password: 'Correct-passphrase-22',
    );
    await expectLater(
      ActorTransferCipher.decrypt(
        encoded, password: 'Wrong-passphrase-99',
      ),
      throwsFormatException,
    );
  });

  test('even one corrupted ciphertext byte is rejected', () async {
    final encoded = await ActorTransferCipher.encrypt(
      _actorZip(), password: 'Correct-passphrase-22',
    );
    final tampered = Uint8List.fromList(encoded);
    tampered[tampered.length - 2] ^= 0x40;
    await expectLater(
      ActorTransferCipher.decrypt(
        tampered, password: 'Correct-passphrase-22',
      ),
      throwsFormatException,
    );
    await expectLater(
      ActorTransferCipher.decrypt(
        encoded.sublist(0, 18), password: 'Correct-passphrase-22',
      ),
      throwsFormatException,
    );
  });

  test('protects against empty and weak backup passwords', () async {
    final zip = _actorZip();
    await expectLater(
      ActorTransferCipher.encrypt(zip, password: '123'),
      throwsFormatException,
    );
    await expectLater(
      ActorTransferCipher.encrypt(zip, password: ''),
      throwsFormatException,
    );
    await expectLater(
      ActorTransferCipher.decrypt(zip, password: 'MyPassword1234'),
      throwsFormatException,
    );
  });

  test('randomly salted backups of same Actor are different', () async {
    final zip = _actorZip();
    final first = await ActorTransferCipher.encrypt(
      zip, password: 'Same-long-password-123',
    );
    final second = await ActorTransferCipher.encrypt(
      zip, password: 'Same-long-password-123',
    );
    expect(first, isNot(orderedEquals(second)));
  });
}
