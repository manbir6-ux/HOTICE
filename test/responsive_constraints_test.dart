import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/welcome.dart';
import 'package:hotice/src/projects_generation.dart';
import 'package:hotice/src/generation_hub.dart';
import 'package:hotice/src/music_studio.dart';
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
              child: Material(
                child: ProjectsPage(store: store, onOpen: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final error = tester.takeException();
      expect(error, isNull, reason: 'Projects grid failed at width $width');
    }
  });
  testWidgets('Mode switch preserves unsaved normal video scene text',
      (tester) async {
    final store = HotIceStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenerationHubPage(store: store, initialProjectId: 'demo-film'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final promptField = find.widgetWithText(TextField, 'Describe your shot');
    expect(promptField, findsOneWidget);
    await tester.enterText(promptField, 'Keep this very important scene text');
    await tester.tap(find.text('Music video studio'));
    await tester.pumpAndSettle();
    expect(find.text('Music Video Studio'), findsOneWidget);
    await tester.tap(find.text('Normal video'));
    await tester.pumpAndSettle();
    expect(
      find.text('Keep this very important scene text'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Saved music storyboards can be reopened for editing',
      (tester) async {
    final store = HotIceStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MusicVideoStudioPage(store: store, initialProjectId: 'demo-film'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Describe your music video');
    await tester.enterText(field, 'Original forest music video');
    final preview = find.text('Preview storyboard');
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    final save = find.text('Save storyboard draft');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.musicPlans, hasLength(1));

    await tester.enterText(field, 'Changed draft text');
    final original = find.text('Original forest music video');
    await tester.ensureVisible(original);
    await tester.tap(original);
    await tester.pumpAndSettle();
    final editing = tester.widget<TextField>(field);
    expect(editing.controller!.text, 'Original forest music video');
    expect(tester.takeException(), isNull);
  });

}
