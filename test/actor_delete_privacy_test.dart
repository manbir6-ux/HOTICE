import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/state.dart';
import 'package:hotice/src/video_models.dart';

void main() {
  test('deleting an Actor removes that cast from saved local drafts', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    expect(store.addAvatar('Hero', 'Cinematic'), isTrue);
    expect(store.addAvatar('Extra', 'Cinematic'), isTrue);
    final date = DateTime(2026, 10, 27);
    for (final name in ['Hero', 'Extra']) {
      store.queueDraft(GenerationDraft(
        projectId: 'demo-film',
        project: 'Untitled film',
        prompt: 'Scene involving $name',
        modelId: 'character_demo',
        model: 'Character demo',
        aspectRatio: '16:9',
        durationSeconds: 8,
        actors: [SceneActor(avatarName: name, sceneName: 'Lead')],
        referenceFiles: const [
          SceneReference(
            type: VideoAttachment.image,
            fileName: 'sample.jpg',
            bytes: 2048,
            localPath: '/tmp/sample.jpg',
          ),
        ],
        createdAt: date,
      ));
      store.saveMusicPlan(MusicVideoPlan(
        projectId: 'demo-film',
        storyBrief: 'Music video for $name',
        visualStyle: 'Cinematic',
        avatarName: name,
        shots: const [StoryboardShot('Entrance', 'Scene one', 6)],
        createdAt: date,
      ));
    }
    expect(store.drafts.length, 2);
    expect(store.musicPlans.length, 2);
    expect(store.removeAvatar('hero'), isTrue);
    expect(store.avatars.any((a) => a.name == 'Hero'), isFalse);
    expect(store.drafts.single.actors.single.avatarName, 'Extra');
    expect(store.musicPlans.single.avatarName, 'Extra');
    expect(store.avatars.any((a) => a.name == 'Extra'), isTrue);
  });

  test('deleting an unknown Actor does not change the library', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    expect(store.removeAvatar('Missing'), isFalse);
    expect(store.avatars.single.name, 'Nova');
  });
}
