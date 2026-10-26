import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/actor_pose_gate.dart';
import 'package:hotice/src/avatar_studio.dart';
import 'package:hotice/src/state.dart';

void main() {
  test('seven distinct scan views require different real face angles', () {
    expect(ScanPose.values.length, 7);
    expect(
      ActorPoseGate.matchesAngle(
        pose: ScanPose.front, yaw: 0, roll: 0,
      ),
      isTrue,
    );
    expect(
      ActorPoseGate.matchesAngle(
        pose: ScanPose.leftProfile, yaw: -45, roll: 0,
      ),
      isTrue,
    );
    expect(
      ActorPoseGate.matchesAngle(
        pose: ScanPose.rightProfile, yaw: 45, roll: 0,
      ),
      isTrue,
    );
    expect(
      ActorPoseGate.matchesAngle(
        pose: ScanPose.leftProfile, yaw: -25, roll: 0,
      ),
      isFalse,
    );
    expect(
      ActorPoseGate.matchesAngle(
        pose: ScanPose.chinUp, yaw: 0, roll: 0, pitch: 20,
      ),
      isTrue,
    );
    expect(
      ActorPoseGate.matchesAngle(
        pose: ScanPose.chinDown, yaw: 0, roll: 0, pitch: -20,
      ),
      isTrue,
    );
    expect(
      ActorPoseGate.matchesAngle(
        pose: ScanPose.chinDown, yaw: 0, roll: 0, pitch: 20,
      ),
      isFalse,
    );
    expect(
      ActorPoseGate.matchesAngle(
        pose: ScanPose.chinUp, yaw: 0, roll: 0,
      ),
      isFalse,
    );
  });

  testWidgets('new Actor has a name-first guided-only creation flow',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final store = HotIceStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AvatarsPage(store: store)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Actors Studio'), findsOneWidget);
    expect(find.text('New actor'), findsOneWidget);
    expect(find.text('Actor name'), findsOneWidget);
    expect(find.text('Continue to guided camera'), findsOneWidget);
    expect(find.text('Save actor'), findsNothing);
    expect(find.text('Quick actor'), findsNothing);

    // Actor creation cannot bypass live-camera capture just by entering
    // a name. The UI only offers navigation to the consent-protected scan.
    await tester.enterText(find.widgetWithText(TextField, 'Actor name'), 'Hero 7');
    expect(store.avatars.any((a) => a.name == 'Hero 7'), isFalse);
    expect(tester.takeException(), isNull);
  });
}
