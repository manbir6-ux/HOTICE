import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:hotice/src/actor_photo_quality.dart';

void main() {
  test('rejects invalid image dimensions before analysis', () {
    expect(() => ActorPhotoQuality.assess(
      img.Image(width: 0, height: 1),
    ), throwsArgumentError);
  });

  test('dark portraits produce local lighting warnings', () {
    final picture = img.Image(width: 80, height: 80);
    img.fill(picture, color: img.ColorRgb8(12, 15, 18));
    final quality = ActorPhotoQuality.assess(picture);
    expect(quality.meanLuma, lessThan(55));
    expect(quality.hasWarnings, isTrue);
    expect(quality.warnings.join(' '), contains('dark'));
  });

  test('blown-out portrait warns of very bright exposure', () {
    final picture = img.Image(width: 96, height: 96);
    img.fill(picture, color: img.ColorRgb8(250, 250, 248));
    final quality = ActorPhotoQuality.assess(picture);
    expect(quality.meanLuma, greaterThan(215));
    expect(quality.warnings.join(' '), contains('bright'));
  });

  test('a high-detail test image has no uncalibrated exposure warnings', () {
    final picture = img.Image(width: 96, height: 96);
    for (var y = 0; y < 96; y++) {
      for (var x = 0; x < 96; x++) {
        final light = (x + y) % 2 == 0 ? 210 : 45;
        picture.setPixelRgb(x, y, light, light, light);
      }
    }
    final quality = ActorPhotoQuality.assess(picture);
    expect(quality.meanLuma, greaterThan(55));
    expect(quality.meanLuma, lessThan(215));
    expect(quality.lumaStdDev, greaterThan(16));
  });
}
