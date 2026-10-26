import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/actor_pose_gate.dart';
import 'package:hotice/src/guided_actor_camera.dart';

PoseAssessment check({
  ScanPose pose = ScanPose.front,
  int faces = 1,
  double? yaw = 0,
  double? roll = 0,
  double width = .4,
  double height = .48,
  double x = 0,
  double y = 0,
}) => ActorPoseGate.evaluate(
  pose: pose,
  faceCount: faces,
  yaw: yaw,
  roll: roll,
  faceWidthFraction: width,
  faceHeightFraction: height,
  horizontalCenterOffset: x,
  verticalCenterOffset: y,
);

void main() {
  test('requires a single detectable face', () {
    expect(check(faces: 0).ready, isFalse);
    expect(check(faces: 2).ready, isFalse);
    expect(check(faces: 1).ready, isTrue);
  });

  test('rejects off-centre, too close, too far and tilted faces', () {
    expect(check(x: .3).ready, isFalse);
    expect(check(y: -.3).ready, isFalse);
    expect(check(width: .1).instruction, contains('closer'));
    expect(check(width: .88).instruction, contains('farther'));
    expect(check(roll: 25).ready, isFalse);
    expect(check(yaw: null).ready, isFalse);
  });

  test('chin up/down calibration reverses sensor pitch consistently', () {
    expect(ActorPoseGate.selfiePitch(19), 19);
    expect(ActorPoseGate.selfiePitch(19, reversed: true), -19);
    expect(ActorPoseGate.selfiePitch(null, reversed: true), isNull);
    expect(ActorPoseGate.matchesAngle(
      pose: ScanPose.chinDown,
      yaw: 0,
      roll: 0,
      pitch: ActorPoseGate.selfiePitch(20, reversed: true),
    ), isTrue);
    expect(ActorPoseGate.matchesAngle(
      pose: ScanPose.chinUp,
      yaw: 0,
      roll: 0,
      pitch: ActorPoseGate.selfiePitch(-20, reversed: true),
    ), isTrue);
  });

  test('mirrored selfie camera yaw follows the actor left/right perspective', () {
    expect(ActorPoseGate.selfieYaw(25), -25);
    expect(ActorPoseGate.selfieYaw(-25), 25);
    expect(ActorPoseGate.selfieYaw(null), isNull);
    expect(ActorPoseGate.selfieYaw(25, mirroredFront: false), 25);
    expect(check(pose: ScanPose.left,
        yaw: ActorPoseGate.selfieYaw(25)).ready, isTrue);
    expect(check(pose: ScanPose.right,
        yaw: ActorPoseGate.selfieYaw(-25)).ready, isTrue);
  });

  test('requires distinct front left and right yaw angles', () {
    expect(check(pose: ScanPose.front, yaw: 0).ready, isTrue);
    expect(check(pose: ScanPose.front, yaw: 20).ready, isFalse);
    expect(check(pose: ScanPose.left, yaw: -27).ready, isTrue);
    expect(check(pose: ScanPose.left, yaw: 27).ready, isFalse);
    expect(check(pose: ScanPose.right, yaw: 27).ready, isTrue);
    expect(check(pose: ScanPose.right, yaw: -27).ready, isFalse);
  });

  testWidgets('camera never opens without an explicit consent action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: GuidedActorCameraPage(actorName: 'Test Hero'),
    ));
    expect(find.text('Your face. Your choice.'), findsOneWidget);
    expect(find.text('I agree — start camera'), findsOneWidget);
    expect(find.text('Look straight ahead'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
