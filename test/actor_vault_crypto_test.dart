import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/actor_vault.dart';
import 'package:hotice/src/state.dart';

void main() {
  test('vault restore prunes deleted/corrupt cached Actors without erasing presets',
      () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    expect(store.addAvatar('Deleted on disk', 'Cinematic',
        capturePaths: ['unavailable.jpg']), isTrue);
    expect(store.addAvatar('Saved on disk', 'Photorealistic',
        capturePaths: ['old.jpg']), isTrue);
    store.reconcileVaultActors(const [
      StudioAvatar('Saved on disk', 'Cinematic',
          capturePaths: ['decrypted-fresh.jpg']),
    ]);
    expect(store.avatars.any((a) => a.name == 'Deleted on disk'), isFalse);
    expect(store.avatars.singleWhere((a) => a.name == 'Saved on disk')
        .capturePaths, ['decrypted-fresh.jpg']);
    expect(store.avatars.any((a) => a.name == 'Nova'), isTrue);
    expect(
      () => store.reconcileVaultActors(const [
        StudioAvatar('Duplicate', 'Cinematic'),
        StudioAvatar('duplicate', 'Cinematic'),
      ]),
      throwsStateError,
    );
  });

  test('restoring an Actor replaces stale decrypted paths in same workspace', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    expect(store.addAvatar('Original Hero', 'Cinematic',
        capturePaths: ['expired-temp.jpg']), isTrue);
    store.restoreAvatar(const StudioAvatar(
        'Original Hero', 'Photorealistic',
        identityNotes: 'New metadata',
        capturePaths: ['fresh-decrypted.jpg'],
        autoTouchUp: true,
    ));
    expect(store.avatars.where((a) => a.name == 'Original Hero').length, 1);
    final hero = store.avatars.singleWhere((a) => a.name == 'Original Hero');
    expect(hero.capturePaths, ['fresh-decrypted.jpg']);
    expect(hero.autoTouchUp, isTrue);

    store.addAccount('second-actor@hotice.demo');
    store.restoreAvatar(const StudioAvatar('Second', 'Cinematic',
        capturePaths: ['second.jpg']));
    store.switchAccount('creator@hotice.demo');
    final restored = store.avatars.singleWhere(
        (a) => a.name == 'Original Hero');
    expect(restored.capturePaths, ['fresh-decrypted.jpg']);
  });

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
