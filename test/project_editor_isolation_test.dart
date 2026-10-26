import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/projects_generation.dart';
import 'package:hotice/src/scene_controls.dart';
import 'package:hotice/src/state.dart';
import 'package:hotice/src/video_models.dart';

void main() {
  testWidgets('a new project never inherits Actor identities or attachments',
      (tester) async {
    tester.view.physicalSize = const Size(950, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final store = HotIceStore();
    addTearDown(store.dispose);
    store.addAvatar('Scan A', 'Cinematic');
    final other = store.addProject('Project B');

    Future<void> open(String id) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GenerationPage(
            store: store,
            initialProjectId: id,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await open('demo-film');
    final text = find.widgetWithText(TextField, 'Describe your shot');
    await tester.enterText(text, 'Secret idea for Project A');

    final initial = tester.widget<SceneCastAndReferences>(
      find.byType(SceneCastAndReferences),
    );
    initial.onCastChanged(const [
      SceneActor(avatarName: 'Scan A', sceneName: 'Hero A'),
    ]);
    await tester.pumpAndSettle();
    final withCast = tester.widget<SceneCastAndReferences>(
      find.byType(SceneCastAndReferences),
    );
    withCast.onReferencesChanged(const [
      SceneReference(
        type: VideoAttachment.image,
        fileName: 'secret_portrait_a.jpg',
        bytes: 2048,
      ),
    ]);
    await tester.pumpAndSettle();

    await open(other);
    expect(tester.widget<TextField>(text).controller!.text, isEmpty);
    final second = tester.widget<SceneCastAndReferences>(
      find.byType(SceneCastAndReferences),
    );
    expect(second.cast, isEmpty);
    expect(second.references, isEmpty);

    await tester.enterText(text, 'Project B only');
    await open('demo-film');
    expect(tester.widget<TextField>(text).controller!.text,
      'Secret idea for Project A');
    final restored = tester.widget<SceneCastAndReferences>(
      find.byType(SceneCastAndReferences),
    );
    expect(restored.cast.single.sceneName, 'Hero A');
    expect(restored.references.single.fileName, 'secret_portrait_a.jpg');
    expect(tester.takeException(), isNull);
  });
}
