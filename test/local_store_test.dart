import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/local_store.dart';
import 'package:hotice/src/state.dart';

void main() {
  test('encrypted archive persists projects and draft workspaces across restarts',
      () async {
    final dir = await Directory.systemTemp.createTemp('hotice-local-test-');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final archive = HotIceLocalArchive(
      directory: dir,
      keyLoader: () async => List<int>.filled(32, 41),
    );
    final first = HotIceStore();
    final id = first.addProject('Private sunset project');
    first.queueDraft(GenerationDraft(
      projectId: id,
      project: 'Private sunset project',
      prompt: 'At sunrise, a red kite flies over water.',
      model: 'Cinematic Draft',
      aspectRatio: '16:9',
      durationSeconds: 8,
      createdAt: DateTime(2026, 10, 27),
    ));
    first.addAvatar('Local Hero', 'Cinematic', identityNotes: 'Brown eyes');
    first.addAccount('second@example.com');
    final secondId = first.addProject('Second device profile');
    first.signInDemo('second@example.com');
    archive.enqueue(first.exportLocalSnapshot());
    await archive.flush();

    final dataFile = File('${dir.path}/hotice-projects-v1.aes');
    expect(await dataFile.exists(), isTrue);
    final raw = await dataFile.readAsString();
    expect(raw, isNot(contains('Private sunset project')));
    expect(raw, isNot(contains('Brown eyes')));
    expect(raw, isNot(contains('second@example.com')));

    final restored = await archive.restore();
    expect(restored, isNotNull);
    final afterRestart = HotIceStore();
    afterRestart.restoreLocalSnapshot(restored!);
    expect(afterRestart.signedIn, isFalse);
    expect(afterRestart.selectedAccount, 'second@example.com');
    expect(afterRestart.projects.any((p) => p.id == secondId), isTrue);
    afterRestart.switchAccount('creator@hotice.demo');
    expect(afterRestart.projects.any((p) => p.id == id), isTrue);
    expect(afterRestart.drafts.single.prompt, contains('red kite'));
    expect(afterRestart.avatars.any((a) => a.name == 'Local Hero'), isTrue);
    expect(afterRestart.projects.any((p) => p.id == secondId), isFalse);
    first.dispose();
    afterRestart.dispose();
  });

  test('corrupt primary falls back to previous authenticated backup',
      () async {
    final dir = await Directory.systemTemp.createTemp('hotice-recovery-');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final archive = HotIceLocalArchive(
      directory: dir,
      keyLoader: () async => List<int>.filled(32, 23),
    );
    final store = HotIceStore();
    store.addProject('Original preserved project');
    archive.enqueue(store.exportLocalSnapshot());
    await archive.flush();
    store.addProject('Newest not yet durable');
    archive.enqueue(store.exportLocalSnapshot());
    await archive.flush();
    await File('${dir.path}/hotice-projects-v1.aes')
        .writeAsString('corrupted-primary');
    final restored = await archive.restore();
    final copy = HotIceStore();
    copy.restoreLocalSnapshot(restored!);
    expect(copy.projects.any((p) => p.title == 'Original preserved project'),
        isTrue);
    expect(copy.projects.any((p) => p.title == 'Newest not yet durable'),
        isFalse);
    store.dispose();
    copy.dispose();
  });

  test('wrong device key fails closed without resetting local files',
      () async {
    final dir = await Directory.systemTemp.createTemp('hotice-key-test-');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final archive = HotIceLocalArchive(
      directory: dir,
      keyLoader: () async => List<int>.filled(32, 4),
    );
    final store = HotIceStore();
    archive.enqueue(store.exportLocalSnapshot());
    await archive.flush();
    final file = File('${dir.path}/hotice-projects-v1.aes');
    final before = await file.readAsBytes();
    final wrongDevice = HotIceLocalArchive(
      directory: dir,
      keyLoader: () async => List<int>.filled(32, 5),
    );
    await expectLater(wrongDevice.restore(),
        throwsA(isA<HotIceLocalArchiveException>()));
    expect(await file.readAsBytes(), before);
    store.dispose();
  });
}

