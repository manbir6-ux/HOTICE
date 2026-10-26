import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/actor_vault.dart';

void main() {
  test('AES-256-GCM vault payload survives authenticated roundtrip', () async {
    final key = await ActorVaultCrypto.newKey();
    expect((await key.extractBytes()).length, 32);
    final original = Uint8List.fromList(List.generate(2048, (i) => i % 251));
    final locked = await ActorVaultCrypto.seal(
      original, key, associatedData: 'account-a/actor-1.vault',
    );
    expect(locked.length, original.length + 33);
    expect(locked.take(5), [72, 73, 86, 65, 49]);
    expect(locked.sublist(33), isNot(orderedEquals(original)));
    final clear = await ActorVaultCrypto.open(
      locked, key, associatedData: 'account-a/actor-1.vault',
    );
    expect(clear, orderedEquals(original));
  });

  test('vault encryption uses fresh random nonces', () async {
    final key = await ActorVaultCrypto.newKey();
    final original = Uint8List.fromList([1, 2, 3, 4]);
    final first = await ActorVaultCrypto.seal(
        original, key, associatedData: 'owner/a.vault');
    final second = await ActorVaultCrypto.seal(
        original, key, associatedData: 'owner/a.vault');
    expect(first, isNot(orderedEquals(second)));
  });

  test('wrong Actor/account binding, key or altered MAC must fail', () async {
    final key = await ActorVaultCrypto.newKey();
    final another = await ActorVaultCrypto.newKey();
    final locked = await ActorVaultCrypto.seal(
      Uint8List.fromList([2, 5, 8]), key,
      associatedData: 'account-a/portrait.vault',
    );
    await expectLater(
      ActorVaultCrypto.open(
        locked, another, associatedData: 'account-a/portrait.vault',
      ), throwsA(isA<SecretBoxAuthenticationError>()),
    );
    await expectLater(
      ActorVaultCrypto.open(
        locked, key, associatedData: 'account-b/portrait.vault',
      ), throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final tampered = Uint8List.fromList(locked);
    tampered[tampered.length - 1] ^= 0x55;
    await expectLater(
      ActorVaultCrypto.open(
        tampered, key, associatedData: 'account-a/portrait.vault',
      ), throwsA(isA<SecretBoxAuthenticationError>()),
    );
    await expectLater(
      ActorVaultCrypto.open(
        Uint8List.fromList([0, 1, 2]), key,
        associatedData: 'account-a/portrait.vault',
      ), throwsFormatException,
    );
  });
}
