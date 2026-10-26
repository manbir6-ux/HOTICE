import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hotice/main.dart';
import 'package:hotice/src/actor_archive.dart';
import 'package:hotice/src/actor_vault.dart';
import 'package:hotice/src/state.dart';
import 'package:image/image.dart' as image;
import 'dart:typed_data';
import 'dart:io';

/// Runs as a genuine Flutter Android application on a booted Android emulator.
/// It checks navigation with real Android view metrics, not just fake test size.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HOTICE Android guest demo smoke: navigate, create, edit and switch',
      (tester) async {
    await tester.pumpWidget(const HotIceApp());
    await tester.pumpAndSettle();
    expect(find.text('Explore demo studio'), findsOneWidget);

    await tester.tap(find.text('Explore demo studio'));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Android smoke project');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Scene composer'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Switch between the two generation modes.
    await tester.tap(find.text('Music video studio'));
    await tester.pumpAndSettle();
    expect(find.text('Music Video Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Normal video'));
    await tester.pumpAndSettle();

    // Navigate across the same tabs as an ordinary phone user.
    await tester.tap(find.text('Actors').last);
    await tester.pumpAndSettle();
    expect(find.text('Actors Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Credits').last);
    await tester.pumpAndSettle();
    expect(find.text('HOTICE Credits'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings & appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance & settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(find.text('Accounts'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Encrypted Actor vault: Keystore-backed device roundtrip',
      (tester) async {
    // A synthetic colour patch is used, never a real person's face.
    final synthetic = image.Image(width: 80, height: 100);
    image.fill(synthetic, color: image.ColorRgb8(80, 130, 180));
    final jpeg = Uint8List.fromList(image.encodeJpg(synthetic));
    final archive = ActorArchiveImport(
      'Vault CI Actor', 'Photorealistic', 'Synthetic image test',
      [jpeg, jpeg, jpeg],
    );
    final account = 'android-vault-ci@hotice.demo';
    final vault = ActorLocalVault.instance;
    final first = await vault.load(account);
    // Idempotent cleanup in case a persistent emulator is reused.
    for (final actor in first.actors) {
      await vault.delete(account, actor.name);
      for (final p in actor.capturePaths) {
        try { await File(p).delete(); } catch (_) {}
      }
    }
    final paths = await ActorArchiveCodec.importToTemporaryFolder(archive);
    final actor = StudioAvatar(
      archive.name, archive.style,
      identityNotes: archive.notes,
      capturePaths: paths,
      autoTouchUp: true,
    );
    try {
      await vault.save(account, actor);
      final restored = await vault.load(account);
      expect(restored.failedEntries, 0);
      expect(restored.actors.single.name, 'Vault CI Actor');
      expect(restored.actors.single.autoTouchUp, isTrue);
      expect(restored.actors.single.capturePaths.length, 3);
      for (final path in restored.actors.single.capturePaths) {
        expect(File(path).existsSync(), isTrue);
        expect(File(path).readAsBytesSync(), orderedEquals(jpeg));
      }
      final renamed = StudioAvatar(
        'Vault CI Actor Renamed', actor.style,
        identityNotes: 'Updated encrypted metadata',
        capturePaths: restored.actors.single.capturePaths,
        autoTouchUp: false,
      );
      await vault.save(account, renamed, formerName: actor.name);
      final afterRename = await vault.load(account);
      expect(afterRename.actors.single.name, 'Vault CI Actor Renamed');
      expect(afterRename.actors.single.autoTouchUp, isFalse);

      // Account-bound storage must never restore another demo workspace's
      // encrypted Actor, even on the same physical installation.
      final oldDecryptedPath = afterRename.actors.single.capturePaths.first;
      expect(await File(oldDecryptedPath).exists(), isTrue);

      // Simulate an app sign-out: zero remaining decrypted JPG copies without
      // deleting encrypted Actor originals. Then restore like a new sign-in.
      await vault.lockSession();
      expect(await File(oldDecryptedPath).exists(), isFalse);
      final afterSignIn = await vault.load(account);
      expect(afterSignIn.failedEntries, 0);
      expect(afterSignIn.actors.single.name, 'Vault CI Actor Renamed');
      final reopenedPath = afterSignIn.actors.single.capturePaths.first;
      expect(await File(reopenedPath).exists(), isTrue);

      final other = await vault.load('vault-other-ci@hotice.demo');
      expect(other.actors, isEmpty);
      // Switching accounts must remove plaintext from the previous account,
      // leaving only its encrypted vault records available for later restore.
      expect(await File(reopenedPath).exists(), isFalse);
      await vault.load(account);
      await vault.delete(account, 'Vault CI Actor Renamed');
      final afterDeletion = await vault.load(account);
      expect(afterDeletion.actors, isEmpty);
    } finally {
      for (final path in paths) {
        try { await File(path).delete(); } catch (_) {}
      }
      final last = await vault.load(account);
      for (final remaining in last.actors) {
        await vault.delete(account, remaining.name);
        for (final p in remaining.capturePaths) {
          try { await File(p).delete(); } catch (_) {}
        }
      }
    }
  });

  testWidgets('Encrypted Actor vault serializes writes and protects names',
      (tester) async {
    final sample = image.Image(width: 64, height: 80);
    image.fill(sample, color: image.ColorRgb8(65, 100, 125));
    final jpeg = Uint8List.fromList(image.encodeJpg(sample));
    final account = 'vault-race-ci@hotice.demo';
    final vault = ActorLocalVault.instance;
    final tempPaths = <String>{};

    final old = await vault.load(account);
    for (final actor in old.actors) {
      tempPaths.addAll(actor.capturePaths);
      await vault.delete(account, actor.name);
    }
    final source = ActorArchiveImport('Test', 'Cinematic', '',
        [jpeg, jpeg, jpeg]);
    final paths = await ActorArchiveCodec.importToTemporaryFolder(source);
    tempPaths.addAll(paths);
    final first = StudioAvatar(
      'Race Actor A', 'Cinematic', capturePaths: paths,
    );
    final second = StudioAvatar(
      'Race Actor B', 'Cinematic', capturePaths: paths,
    );
    try {
      // Two concurrent writes formerly raced on one global vault index.
      await Future.wait([
        vault.save(account, first),
        vault.save(account, second),
      ]);
      final loaded = await vault.load(account);
      for (final a in loaded.actors) { tempPaths.addAll(a.capturePaths); }
      expect(loaded.failedEntries, 0);
      expect(loaded.actors.map((a) => a.name).toSet(),
          {'Race Actor A', 'Race Actor B'});

      await expectLater(
        vault.save(account, StudioAvatar(
          second.name, second.style, capturePaths: paths,
        ), formerName: first.name),
        throwsA(isA<StateError>()),
      );
      final preserved = await vault.load(account);
      for (final a in preserved.actors) { tempPaths.addAll(a.capturePaths); }
      expect(preserved.actors.map((a) => a.name).toSet(),
          {'Race Actor A', 'Race Actor B'});

      await Future.wait([
        vault.delete(account, 'Race Actor A'),
        vault.delete(account, 'Race Actor B'),
      ]);
      final after = await vault.load(account);
      expect(after.actors, isEmpty);
    } finally {
      final remainder = await vault.load(account);
      for (final actor in remainder.actors) {
        tempPaths.addAll(actor.capturePaths);
        await vault.delete(account, actor.name);
      }
      for (final path in tempPaths) {
        try { await File(path).delete(); } catch (_) {}
      }
    }
  });
}