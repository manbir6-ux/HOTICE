import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'actor_archive.dart';

/// Small, device-local heuristic QA for a *saved* Actor portrait.
/// This is not a calibrated photography/biometric quality score.
/// Warn rather than automatically deleting consented photos: complex
/// lighting, clothing and backgrounds can legitimately score poorly.
class ActorPhotoQuality {
  const ActorPhotoQuality({
    required this.meanLuma,
    required this.lumaStdDev,
    required this.edgeContrast,
    required this.warnings,
  });

  /// Decode and assess a camera JPEG off the UI isolate. Seven high-
  /// resolution photos must not block the shutter or the review screen.
  /// Reject dangerous pixel dimensions via header inspection BEFORE the
  /// decoder allocates a full image buffer.
  static Future<List<String>> reviewCameraJpeg(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
      throw const FormatException('Camera photo is empty or exceeds size limit.');
    }
    return compute(_assessCapturedJpeg, bytes);
  }

  final double meanLuma;
  final double lumaStdDev;
  final double edgeContrast;
  final List<String> warnings;
  bool get hasWarnings => warnings.isNotEmpty;

  static ActorPhotoQuality assess(img.Image original) {
    if (original.width < 1 || original.height < 1) {
      throw ArgumentError('Invalid captured image size.');
    }
    // Bound CPU and avoid full-resolution processing in the review UI.
    final resized = img.copyResize(original, width: 96, height: 96);
    final rows = <List<double>>[];
    var total = 0.0;
    var squared = 0.0;
    var edges = 0.0;
    var pairs = 0;
    final width = resized.width;
    final height = resized.height;
    for (var y = 0; y < height; y++) {
      final row = <double>[];
      for (var x = 0; x < width; x++) {
        final pixel = resized.getPixel(x, y);
        final value = 0.2126 * pixel.r.toDouble() +
            0.7152 * pixel.g.toDouble() +
            0.0722 * pixel.b.toDouble();
        row.add(value);
        total += value;
        squared += value * value;
        if (x > 0) {
          edges += (value - row[x - 1]).abs();
          pairs++;
        }
        if (y > 0) {
          edges += (value - rows[y - 1][x]).abs();
          pairs++;
        }
      }
      rows.add(row);
    }
    final count = width * height;
    final mean = total / count;
    final variance = math.max(0, squared / count - mean * mean);
    final stddev = math.sqrt(variance);
    final sharpness = pairs == 0 ? 0.0 : edges / pairs;
    final warnings = <String>[];
    if (mean < 55) {
      warnings.add('Very dark photo — try brighter, even lighting.');
    } else if (mean > 215) {
      warnings.add('Very bright photo — reduce direct light or glare.');
    }
    if (stddev < 16) {
      warnings.add('Low contrast — move away from flat light or glare.');
    }
    if (sharpness < 5) {
      warnings.add('Low image detail — keep your head still and retake.');
    }
    return ActorPhotoQuality(
      meanLuma: mean,
      lumaStdDev: stddev,
      edgeContrast: sharpness,
      warnings: List.unmodifiable(warnings),
    );
  }
}

List<String> _assessCapturedJpeg(Uint8List bytes) {
  // A forged 1px JPEG with a 50,000px SOF dimension may otherwise allocate
  // gigabytes when fully decoded. The archive preflight bounds 18MP.
  ActorArchiveCodec.inspectPhotoHeader(bytes);
  final image = img.decodeJpg(bytes);
  if (image == null) {
    throw const FormatException('Camera JPEG cannot be decoded.');
  }
  return ActorPhotoQuality.assess(image).warnings;
}
