import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/welcome.dart';
import 'package:hotice/src/projects_generation.dart';
import 'package:hotice/src/state.dart';

void main() {
  testWidgets('Welcome layout never creates negative-width constraints',
      (tester) async {
    // Reproduces the real Android FIRST exception:
    // BoxConstraints(w=-50.0, 0.0<=h<=Infinity; NOT NORMALIZED)
    for (final width in <double>[0, 1, 25, 49, 50, 51, 120, 240, 320, 393, 820, 1000]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              height: 780,
              child: WelcomePage(
                onStart: () {},
                onDemoStart: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Welcome layout failed at width $width');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Projects grid is safe at tiny and medium widths',
      (tester) async {
    final store = HotIceStore();
    addTearDown(store.dispose);
    for (final width in <double>[0, 1, 36, 80, 240, 320, 393, 820]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              height: 780,
              child: ProjectsPage(store: store, onOpen: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump();
      final error = tester.takeException();
      expect(error, isNull, reason: 'Projects grid failed at width $width');
    }
  });
}
