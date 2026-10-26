/// On-device framing heuristics, NOT a 3D/biometric identity guarantee.
/// Selfie yaw and pitch directions need physical camera QA across OEMs.
enum ScanPose {
  front,
  left,
  right,
  leftProfile,
  rightProfile,
  chinUp,
  chinDown,
}

class PoseAssessment {
  final bool ready;
  final String instruction;
  const PoseAssessment(this.ready, this.instruction);
}

class ActorPoseGate {
  /// ML Kit selfie yaw can run opposite to the actor's own left/right.
  static double? selfieYaw(double? raw, {bool mirroredFront = true}) =>
      raw == null ? null : (mirroredFront ? -raw : raw);

  /// Some front-camera/OEM sensor orientations reverse X rotation.
  /// This is an explicit camera QA calibration toggle, not identity analysis.
  static double? selfiePitch(double? raw, {bool reversed = false}) =>
      raw == null ? null : (reversed ? -raw : raw);

  static String instruction(ScanPose pose) => switch (pose) {
        ScanPose.front => 'Look straight at the camera',
        ScanPose.left => 'Turn your head slightly LEFT',
        ScanPose.right => 'Turn your head slightly RIGHT',
        ScanPose.leftProfile => 'Turn further LEFT, to about 45 degrees',
        ScanPose.rightProfile => 'Turn further RIGHT, to about 45 degrees',
        ScanPose.chinUp => 'Look forward and raise your chin slightly',
        ScanPose.chinDown => 'Look forward and lower your chin slightly',
      };

  /// Evaluate the SAME pose on preview frames and the saved still.
  /// A user perspective and a fixed sign convention must be tested on device.
  static bool matchesAngle({
    required ScanPose pose,
    required double? yaw,
    required double? roll,
    double? pitch,
  }) {
    if (yaw == null || roll == null || roll.abs() > 18) return false;
    return switch (pose) {
      ScanPose.front => yaw.abs() < 11,
      ScanPose.left => yaw <= -18 && yaw >= -37,
      ScanPose.right => yaw >= 18 && yaw <= 37,
      ScanPose.leftProfile => yaw <= -38 && yaw >= -60,
      ScanPose.rightProfile => yaw >= 38 && yaw <= 60,
      ScanPose.chinUp => yaw.abs() <= 14 &&
          pitch != null && pitch >= 12 && pitch <= 35,
      ScanPose.chinDown => yaw.abs() <= 14 &&
          pitch != null && pitch <= -12 && pitch >= -35,
    };
  }

  static PoseAssessment evaluate({
    required ScanPose pose,
    required int faceCount,
    required double? yaw,
    required double? roll,
    double? pitch,
    required double faceWidthFraction,
    required double faceHeightFraction,
    required double horizontalCenterOffset,
    required double verticalCenterOffset,
  }) {
    if (faceCount == 0) {
      return const PoseAssessment(false, 'Position your face inside the guide');
    }
    if (faceCount != 1) {
      return const PoseAssessment(false, 'Only one face can be scanned at a time');
    }
    if (faceWidthFraction < .16 || faceHeightFraction < .18) {
      return const PoseAssessment(false, 'Move closer to the camera');
    }
    if (faceWidthFraction > .78 || faceHeightFraction > .85) {
      return const PoseAssessment(false, 'Move slightly farther away');
    }
    if (horizontalCenterOffset.abs() > .23 ||
        verticalCenterOffset.abs() > .23) {
      return const PoseAssessment(false, 'Move your face to the centre');
    }
    if (yaw == null || roll == null) {
      return const PoseAssessment(false, 'Keep your face visible');
    }
    if (roll.abs() > 18) {
      return const PoseAssessment(false, 'Keep your head upright');
    }
    if (matchesAngle(pose: pose, yaw: yaw, roll: roll, pitch: pitch)) {
      return const PoseAssessment(true, 'Angle ready');
    }
    return PoseAssessment(false, instruction(pose));
  }
}
