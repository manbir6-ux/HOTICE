import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/actor_reference_adapter.dart';
import 'package:hotice/src/actor_touchup.dart';
import 'package:hotice/src/state.dart';
import 'package:hotice/src/video_models.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Auto touch-up is opt-in and source captures are never replaced', () {
    const actor = StudioAvatar(
      'Actor Original', 'Photorealistic',
      capturePaths: ['original.jpg'],
    );
    const actorEnhanced = StudioAvatar(
      'Actor Enhanced', 'Photorealistic',
      capturePaths: ['another.jpg'], autoTouchUp: true,
    );
    final normal = ActorReferenceAdapter.plan(
      model: demoModelById('character_demo'),
      cast: const [
        SceneActor(avatarName: 'Actor Original', sceneName: 'Natural'),
      ],
      library: const [actor, actorEnhanced],
    );
    final enhanced = ActorReferenceAdapter.plan(
      model: demoModelById('character_demo'),
      cast: const [
        SceneActor(avatarName: 'Actor Enhanced', sceneName: 'Beauty'),
      ],
      library: const [actor, actorEnhanced],
    );
    expect(normal.sources.single.autoTouchUp, isFalse);
    expect(enhanced.sources.single.autoTouchUp, isTrue);
    expect(enhanced.sources.single.path, 'another.jpg');
  });

  test('brightness touch-up produces a new image with preserved dimensions', () {
    final original = img.Image(width: 64, height: 80);
    img.fill(original, color: img.ColorRgb8(80, 100, 105));
    final before = original.getPixel(30, 30).r.toInt();
    final processed = ActorTouchUp.softenLighting(original);
    expect(processed.width, 64);
    expect(processed.height, 80);
    expect(processed.getPixel(30, 30).r.toInt(), greaterThan(before));
  });

  test('large reference is never upscaled by touch-up', () {
    final original = img.Image(width: 1800, height: 1200);
    final result = ActorTouchUp.softenLighting(original);
    expect(result.width, lessThanOrEqualTo(1600));
    expect(result.height, lessThanOrEqualTo(1600));
  });
}
