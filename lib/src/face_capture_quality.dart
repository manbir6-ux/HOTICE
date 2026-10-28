/// Testable, platform-independent gates for guided RGB multi-view capture.
/// This is NOT 3D reconstruction, identity verification or liveness proof.
enum CapturePose {
  front('Front portrait', 'Look straight ahead, eyes open'),
  left45('Left three-quarter', 'Turn slowly toward your left shoulder'),
  right45('Right three-quarter', 'Turn slowly toward your right shoulder'),
  left90('Left profile', 'Turn farther left to show your profile'),
  right90('Right profile', 'Turn farther right to show your profile');

  const CapturePose(this.label, this.instruction);
  final String label;
  final String instruction;
}

class FaceObservation {
  const FaceObservation({
    required this.faces,
    required this.centerX,
    required this.centerY,
    required this.faceWidthFraction,
    required this.faceHeightFraction,
    required this.yaw,
    required this.pitch,
    required this.roll,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.lumaMean,
    this.detailScore,
  });

  final int faces;
  final double centerX;
  final double centerY;
  final double faceWidthFraction;
  final double faceHeightFraction;
  /// Detector-reported Euler Y. Sign can vary with camera mirroring/platform.
  final double? yaw;
  final double? pitch;
  final double? roll;
  final double? leftEyeOpen;
  final double? rightEyeOpen;
  /// Sampled brightness/detail heuristics, not calibrated imaging metrics.
  final double? lumaMean;
  final double? detailScore;
}

class CaptureAssessment {
  const CaptureAssessment(this.ready, this.message);
  final bool ready;
  final String message;
}

/// "Left" and "right" map to detector yaw sign on the chosen camera.
/// The preview is mirrored on most front-facing devices: verify on hardware.
class CaptureQualityGate {
  static CaptureAssessment check(CapturePose pose, FaceObservation? face,
      {bool invertYaw = false}) {
    if (face == null || face.faces == 0) {
      return const CaptureAssessment(false, 'Move into the oval to show your face');
    }
    if (face.faces != 1) {
      return const CaptureAssessment(false, 'Only one face may be visible');
    }
    if (face.faceWidthFraction < .18 || face.faceHeightFraction < .18) {
      return const CaptureAssessment(false, 'Move a little closer');
    }
    if (face.faceWidthFraction > .82 || face.faceHeightFraction > .87) {
      return const CaptureAssessment(false, 'Move a little farther back');
    }
    if ((face.centerX - .5).abs() > .21 ||
        (face.centerY - .5).abs() > .23) {
      return const CaptureAssessment(false, 'Keep your head in the centre');
    }
    if (face.lumaMean != null && face.lumaMean! < 35) {
      return const CaptureAssessment(false, 'Find brighter, even lighting');
    }
    if (face.lumaMean != null && face.lumaMean! > 230) {
      return const CaptureAssessment(false, 'Avoid very bright direct light');
    }
    // Lightweight edge contrast heuristic. Production must calibrate against
    // phone-specific sensors and evaluate image motion as well.
    if (face.detailScore != null && face.detailScore! < 4) {
      return const CaptureAssessment(false, 'Hold steady; the image looks soft');
    }
    final yaw = face.yaw;
    final pitch = face.pitch;
    final roll = face.roll;
    if (yaw == null || pitch == null || roll == null) {
      return const CaptureAssessment(false, 'Adjust lighting for face tracking');
    }
    if (pitch.abs() > 18 || roll.abs() > 16) {
      return const CaptureAssessment(false, 'Keep your head level');
    }
    final correctedYaw = invertYaw ? -yaw : yaw;
    switch (pose) {
      case CapturePose.front:
        if (correctedYaw.abs() > 12) {
          return const CaptureAssessment(false, 'Look straight ahead');
        }
        if (face.leftEyeOpen == null || face.rightEyeOpen == null) {
          return const CaptureAssessment(false, 'Make sure both eyes are visible');
        }
        if (face.leftEyeOpen! < .70 || face.rightEyeOpen! < .70) {
          return const CaptureAssessment(false, 'Open both eyes');
        }
      case CapturePose.left45:
        if (correctedYaw > -18 || correctedYaw < -52) {
          return const CaptureAssessment(false, 'Turn slowly toward your left');
        }
      case CapturePose.right45:
        if (correctedYaw < 18 || correctedYaw > 52) {
          return const CaptureAssessment(false, 'Turn slowly toward your right');
        }
      case CapturePose.left90:
        if (correctedYaw > -48 || correctedYaw < -82) {
          return const CaptureAssessment(false, 'Show more of your left profile');
        }
      case CapturePose.right90:
        if (correctedYaw < 48 || correctedYaw > 82) {
          return const CaptureAssessment(false, 'Show more of your right profile');
        }
    }
    return const CaptureAssessment(true, 'Hold still — capturing automatically');
  }
}

/// A short stable window prevents a single lucky detector frame from firing.
class CaptureStability {
  CaptureStability({this.requiredFrames = 3});
  final int requiredFrames;
  int _streak = 0;

  int get streak => _streak;
  bool observe(CaptureAssessment assessment) {
    if (!assessment.ready) {
      _streak = 0;
      return false;
    }
    _streak++;
    if (_streak >= requiredFrames) {
      _streak = 0;
      return true;
    }
    return false;
  }

  void reset() => _streak = 0;
}
