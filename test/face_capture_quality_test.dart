import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/face_capture_quality.dart';

FaceObservation observation({
  int faces = 1,
  double yaw = 0,
  double pitch = 0,
  double roll = 0,
  double? left = .98,
  double? right = .96,
  double brightness = 120,
  double detail = 13,
  double centreX = .5,
  double centreY = .5,
}) => FaceObservation(
  faces: faces,
  centerX: centreX,
  centerY: centreY,
  faceWidthFraction: .40,
  faceHeightFraction: .53,
  yaw: yaw,
  pitch: pitch,
  roll: roll,
  leftEyeOpen: left,
  rightEyeOpen: right,
  lumaMean: brightness,
  detailScore: detail,
);

void main() {
  test('front portrait accepts open eyes and rejects closed eyes', () {
    expect(CaptureQualityGate.check(CapturePose.front, observation()).ready, isTrue);
    expect(CaptureQualityGate.check(CapturePose.front,
        observation(left: .15)).message, contains('Open both eyes'));
    expect(CaptureQualityGate.check(CapturePose.front,
        observation(left: null)).ready, isFalse);
    expect(CaptureQualityGate.check(CapturePose.front,
        observation(yaw: 24)).ready, isFalse);
  });

  test('genuine multi-angle yaw thresholds', () {
    expect(CaptureQualityGate.check(CapturePose.left45,
        observation(yaw: -34)).ready, isTrue);
    expect(CaptureQualityGate.check(CapturePose.right45,
        observation(yaw: 35)).ready, isTrue);
    expect(CaptureQualityGate.check(CapturePose.left90,
        observation(yaw: -65)).ready, isTrue);
    expect(CaptureQualityGate.check(CapturePose.right90,
        observation(yaw: 67)).ready, isTrue);
    expect(CaptureQualityGate.check(CapturePose.left90,
        observation(yaw: -35)).ready, isFalse);
  });

  test('yaw can be inverted for mirrored front camera guidance', () {
    expect(CaptureQualityGate.check(CapturePose.right45,
      observation(yaw: -35)).ready, isFalse);
    expect(CaptureQualityGate.check(CapturePose.right45,
      observation(yaw: -35), invertYaw: true).ready, isTrue);
  });

  test('quality gates reject multiple faces and poor framing', () {
    expect(CaptureQualityGate.check(CapturePose.front,
      observation(faces: 2)).message, contains('Only one face'));
    expect(CaptureQualityGate.check(CapturePose.front,
      observation(centreX: .9)).ready, isFalse);
    expect(CaptureQualityGate.check(CapturePose.front,
      observation(pitch: 25)).ready, isFalse);
    expect(CaptureQualityGate.check(CapturePose.front,
      observation(brightness: 18)).ready, isFalse);
    expect(CaptureQualityGate.check(CapturePose.front,
      observation(detail: 2)).ready, isFalse);
    expect(CaptureQualityGate.check(CapturePose.front, null).ready, isFalse);
  });

  test('capture requires consecutive good frames; bad frame resets', () {
    final stable = CaptureStability(requiredFrames: 3);
    const good = CaptureAssessment(true, 'ready');
    const bad = CaptureAssessment(false, 'not ready');
    expect(stable.observe(good), isFalse);
    expect(stable.observe(good), isFalse);
    expect(stable.observe(bad), isFalse);
    expect(stable.streak, 0);
    expect(stable.observe(good), isFalse);
    expect(stable.observe(good), isFalse);
    expect(stable.observe(good), isTrue);
    expect(stable.streak, 0);
  });
}
