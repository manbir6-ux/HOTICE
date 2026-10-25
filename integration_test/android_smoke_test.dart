import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hotice/main.dart';

/// Runs as a genuine Flutter Android application on a booted Android emulator.
/// It checks navigation with real Android view metrics, not just fake test size.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HOTICE Android guest demo smoke: navigate, create, edit and switch',
      (tester) async {
    await tester.pumpWidget(const HotIceApp());
    await tester.pumpAndSettle();
    expect(find.text('Explore demo studio'), findsOneWidget);

    await tester.tap(find.text('Explore demo studio'));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Android smoke project');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Scene composer'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Switch between the two generation modes.
    await tester.tap(find.text('Music video studio'));
    await tester.pumpAndSettle();
    expect(find.text('Music Video Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Normal video'));
    await tester.pumpAndSettle();

    // Navigate across the same tabs as an ordinary phone user.
    await tester.tap(find.text('Avatars').last);
    await tester.pumpAndSettle();
    expect(find.text('Avatar Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Credits').last);
    await tester.pumpAndSettle();
    expect(find.text('HOTICE Credits'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings & appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance & settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(find.text('Accounts'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
