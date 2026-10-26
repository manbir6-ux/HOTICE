/// Pose advice is an *approximate* quality gate, not 3D geometry
/// or biometric identity verification. Device-specific mirror behaviour
/// must be tested before shipping outside the demo.
enum ScanPose { front, left, right }

class PoseAssessment {
  final bool ready;
  final String instruction;
  const PoseAssessment(this.ready, this.instruction);
}

class ActorPoseGate {
  /// ML Kit's raw yaw can be reversed relative to the *user's own*
  /// left/right direction on the mirrored front camera. Normalise it once
  /// for both preview and the actual captured still. Physical devices must
  /// still verify camera-manufacturer orientation behaviour.
  static double? selfieYaw(double? raw, {bool mirroredFront = true}) =>
      raw == null ? null : (mirroredFront ? -raw : raw);


  static PoseAssessment evaluate({
    required ScanPose pose,
    required int faceCount,
    required double? yaw,
    required double? roll,
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
    switch (pose) {
      case ScanPose.front:
        return yaw.abs() < 11
            ? const PoseAssessment(true, 'Front angle ready')
            : const PoseAssessment(false, 'Look straight at the camera');
      case ScanPose.left:
        return yaw <= -18 && yaw >= -48
            ? const PoseAssessment(true, 'Left angle ready')
            : const PoseAssessment(false, 'Slowly turn your head to the left');
      case ScanPose.right:
        return yaw >= 18 && yaw <= 48
            ? const PoseAssessment(true, 'Right angle ready')
            : const PoseAssessment(false, 'Slowly turn your head to the right');
    }
  }
}
