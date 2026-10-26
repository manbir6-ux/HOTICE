import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:hotice/src/actor_reference_adapter.dart';
import 'package:hotice/src/state.dart';
import 'package:hotice/src/video_models.dart';

const cast = [
  SceneActor(avatarName: 'A', sceneName: 'Hero'),
  SceneActor(avatarName: 'B', sceneName: 'Villain'),
];
const actors = [
  StudioAvatar('A', 'Cinematic', capturePaths: ['a_front', 'a_left', 'a_right']),
  StudioAvatar('B', 'Cinematic', capturePaths: ['b_front', 'b_left', 'b_right']),
];

void main() {
  test('single image slot yields ONE combined image preserving both actors', () {
    final plan = ActorReferenceAdapter.plan(
      model: demoModelById('cinematic_demo'),
      cast: cast,
      library: actors,
    );
    expect(plan.delivery, ActorReferenceDelivery.contactSheet);
    expect(plan.imageCount, 1);
    expect(plan.sources.map((s) => s.sceneName).toList(), ['Hero', 'Villain']);
    expect(plan.sources.map((s) => s.angle).toList(), ['front', 'front']);
    expect(plan.notes.single, contains('composite'));
  });

  test('multiple slots fairly prioritize each face then secondary angles', () {
    final plan = ActorReferenceAdapter.plan(
      model: demoModelById('character_demo'),
      cast: cast,
      library: actors,
    );
    expect(plan.delivery, ActorReferenceDelivery.individualImages);
    expect(plan.sources.map((s) => s.path), [
      'a_front', 'b_front', 'a_left', 'b_left',
    ]);
    expect(plan.imageCount, 4);
  });

  test('separate reference images consume the same attachment budget', () {
    final plan = ActorReferenceAdapter.plan(
      model: demoModelById('character_demo'),
      cast: cast,
      library: actors,
      otherImageAttachments: 3,
    );
    expect(plan.delivery, ActorReferenceDelivery.contactSheet);
    expect(plan.imageCount, 1);
    expect(
      () => ActorReferenceAdapter.plan(
        model: demoModelById('character_demo'),
        cast: cast,
        library: actors,
        otherImageAttachments: 5,
      ),
      throwsStateError,
    );
  });

  test('text-only model gets no face images but has named actor descriptions', () {
    final plan = ActorReferenceAdapter.plan(
      model: demoModelById('storyboard_demo'),
      cast: [cast.first],
      library: actors,
    );
    expect(plan.delivery, ActorReferenceDelivery.textOnly);
    expect(plan.imageCount, 0);
  });

  test('actor without photos uses text-only identity fallback', () {
    const notesOnly = [
      StudioAvatar('A', 'Cinematic', identityNotes: 'Dark wavy hair')
    ];
    final plan = ActorReferenceAdapter.plan(
      model: demoModelById('cinematic_demo'),
      cast: [cast.first],
      library: notesOnly,
    );
    expect(plan.imageCount, 0);
    expect(plan.notes.single, contains('no captured photos'));
  });

  test('rejects duplicate actor names and unowned Actor identity', () {
    expect(
      () => ActorReferenceAdapter.plan(
        model: demoModelById('character_demo'),
        cast: [...cast, const SceneActor(avatarName: 'A', sceneName: 'hero')],
        library: actors,
      ),
      throwsStateError,
    );
    expect(
      () => ActorReferenceAdapter.plan(
        model: demoModelById('character_demo'),
        cast: [const SceneActor(avatarName: 'Missing', sceneName: 'Hero')],
        library: actors,
      ),
      throwsStateError,
    );
  });

  test('contact-sheet image really composites portraits without stretching', () {
    final a = image.Image(width: 80, height: 120);
    image.fill(a, color: image.ColorRgb8(230, 20, 30));
    final b = image.Image(width: 120, height: 80);
    image.fill(b, color: image.ColorRgb8(15, 200, 25));
    final sheet = ActorContactSheet.compose(
      portraits: [a, b], cellSize: 160,
    );
    expect(sheet.width, 320);
    expect(sheet.height, 160);
    final red = sheet.getPixel(80, 80);
    final green = sheet.getPixel(240, 80);
    expect(red.r.toInt(), greaterThan(180));
    expect(green.g.toInt(), greaterThan(160));
    expect(image.encodeJpg(sheet), isNotEmpty);
  });

  test('rejects invalid contact sheet counts', () {
    expect(
      () => ActorContactSheet.compose(portraits: const []),
      throwsArgumentError,
    );
  });
}
