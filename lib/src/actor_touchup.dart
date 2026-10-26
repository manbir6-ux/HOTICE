import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Optional, non-destructive appearance adjustment for provider references.
/// Original face photos are never overwritten or re-shaped. This is a subtle
/// *global* lighting/colour touch-up, not a skin segmentation or beauty model.
class ActorTouchUp {
  static img.Image softenLighting(img.Image original) {
    final upright = img.bakeOrientation(original);
    // Constrain generated preview/AI reference memory use, never upscale.
    final longSide = upright.width > upright.height
        ? upright.width : upright.height;
    final safe = longSide > 1600
        ? img.copyResize(
            upright,
            width: upright.width >= upright.height ? 1600 : null,
            height: upright.height > upright.width ? 1600 : null,
          )
        : upright;
    return img.adjustColor(
      safe,
      brightness: 1.045,
      contrast: 1.025,
      saturation: 1.012,
      gamma: 0.985,
    );
  }

  static Future<String> prepareCopy(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists() || await source.length() > 12 * 1024 * 1024) {
      throw StateError('Original Actor photo is missing or too large.');
    }
    final decoded = img.decodeImage(await source.readAsBytes());
    if (decoded == null || decoded.width < 32 || decoded.height < 32 ||
        decoded.width * decoded.height > 18000000) {
      throw StateError('Could not decode an Actor photo for touch-up.');
    }
    final processed = softenLighting(decoded);
    final folder = Directory(
      '${(await getTemporaryDirectory()).path}/hotice_actor_touchups',
    );
    await folder.create(recursive: true);
    final name = DateTime.now().microsecondsSinceEpoch.toString();
    final file = File('${folder.path}/touchup_$name.jpg');
    await file.writeAsBytes(img.encodeJpg(processed, quality: 91),
        flush: true);
    return file.path;
  }
}
