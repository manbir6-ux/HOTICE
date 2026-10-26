import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/actor_vault.dart';
import 'package:hotice/src/state.dart';
import 'package:image/image.dart' as img;

Uint8List _photo(int seed) {
  final image = img.Image(width: 64, height: 80);
  img.fill(image, color: img.ColorRgb8(20 + seed, 60, 120));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  late Directory temp;
  late ActorVault vault;
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i + 10));

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('hotice-vault-test-');
    vault = ActorVault(
      root: temp,
      cacheRoot: temp,
      keyProvider: () async => key,
    );
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('saves only encrypted vault record and restores all seven photos',
      () async {
    final sources = <String>[];
    for (var i = 0; i < 7; i++) {
      final file = File('${temp.path}/capture-$i.jpg');
      await file.writeAsBytes(_photo(i));
      sources.add(file.path);
    }
    final actor = StudioAvatar('Natural Hero', 'Photorealistic',
      identityNotes: 'Original face preserved',
      capturePaths: sources, autoTouchUp: true,
    );
    final id = await vault.save(actor, account: 'first@example.com');
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
    final files = await temp.list(recursive: true).where((f) =>
      f is File && f.path.endsWith('.hav')).toList();
    expect(files.length, 1);
    final bytes = await File(files.single.path).readAsBytes();
    expect(bytes.first, 1);
    expect(String.fromCharCodes(bytes).contains('Natural Hero'), isFalse);
    expect(String.fromCharCodes(bytes).contains('Original face'), isFalse);
    // The vault is not attached to the session-only photo paths.
    for (final path in sources) { await File(path).delete(); }
    final restored = await vault.restore('first@example.com');
    expect(restored.failedRecords, 0);
    expect(restored.actors.single.name, 'Natural Hero');
    expect(restored.actors.single.vaultId, id);
    expect(restored.actors.single.capturePaths.length, 7);
    expect(restored.actors.single.autoTouchUp, isTrue);
    expect(await File(restored.actors.single.capturePaths.first).exists(), isTrue);
  });

  test('different demo profile cannot read another account sealed Actors',
      () async {
    final source = File('${temp.path}/safe.jpg');
    await source.writeAsBytes(_photo(4));
    final id = await vault.save(StudioAvatar('Alice', 'Cinematic',
      capturePaths: [source.path]), account: 'alice@example.com');
    final other = await vault.restore('bob@example.com');
    expect(other.actors, isEmpty);
    expect(other.failedRecords, 0);
    expect((await vault.restore('alice@example.com')).actors.single.vaultId, id);
  });

  test('tampering causes authentication failure without removing record',
      () async {
    final source = File('${temp.path}/safe.jpg');
    await source.writeAsBytes(_photo(8));
    await vault.save(StudioAvatar('Maya', 'Cinematic',
      capturePaths: [source.path]), account: 'maya@example.com');
    final record = (await temp.list(recursive: true).where(
      (f) => f is File && f.path.endsWith('.hav')).first) as File;
    final contents = await record.readAsBytes();
    contents[contents.length - 1] ^= 0x20;
    await record.writeAsBytes(contents, flush: true);
    final result = await vault.restore('maya@example.com');
    expect(result.actors, isEmpty);
    expect(result.failedRecords, 1);
    expect(await record.exists(), isTrue);
  });

  test('updating metadata preserves same vault id; deleting erases record',
      () async {
    final source = File('${temp.path}/safe.jpg');
    await source.writeAsBytes(_photo(10));
    final id = await vault.save(StudioAvatar('Old', 'Animated',
      capturePaths: [source.path]), account: 'a@example.com');
    final renamed = await vault.save(StudioAvatar('Updated', 'Cinematic',
      capturePaths: [source.path], vaultId: id, autoTouchUp: true,
    ), account: 'a@example.com');
    expect(renamed, id);
    final first = await vault.restore('a@example.com');
    expect(first.actors.single.name, 'Updated');
    expect(first.actors.single.autoTouchUp, isTrue);
    await vault.delete(id, account: 'a@example.com');
    final afterDelete = await vault.restore('a@example.com');
    expect(afterDelete.actors, isEmpty);
    expect(afterDelete.failedRecords, 0);
  });

  test('invalid record IDs cannot traverse out of the private vault',
      () async {
    await expectLater(
      vault.delete('../stolen', account: 'a@example.com'),
      throwsFormatException,
    );
  });

  test('invalid or lost OS key cannot silently decrypt Actor photos',
      () async {
    final source = File('${temp.path}/safe.jpg');
    await source.writeAsBytes(_photo(11));
    await vault.save(StudioAvatar('Secure', 'Photorealistic',
      capturePaths: [source.path]), account: 'a@example.com');
    final wrongKey = ActorVault(
      root: temp, cacheRoot: temp,
      keyProvider: () async => Uint8List(32),
    );
    final restored = await wrongKey.restore('a@example.com');
    expect(restored.actors, isEmpty);
    expect(restored.failedRecords, 1);
  });
}
