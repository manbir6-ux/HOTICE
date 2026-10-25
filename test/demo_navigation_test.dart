import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/main.dart';
import 'package:hotice/src/dialogs.dart';

void main() {
  testWidgets('project dialog closes cleanly before opening its studio',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const HotIceApp());
    final demo = find.text('Explore demo studio');
    await tester.ensureVisible(demo);
    await tester.tap(demo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    expect(find.text('New film project'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Project title'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'My test film');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    // Route.completed callbacks may settle after the closing animation frame.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Scene composer'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Music video studio'));
    await tester.pumpAndSettle();
    expect(find.text('Music Video Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog owner survives pop transition and parent page swap',
      (tester) async {
    var moved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: moved
                ? const Center(child: Text('Next page'))
                : Builder(builder: (buttonContext) {
                    return TextButton(
                      onPressed: () async {
                        final result = await showHotIceTextDialog(
                          buttonContext,
                          title: 'Test transition',
                          label: 'Description',
                          confirmLabel: 'Save',
                          maxLength: 120,
                        );
                        if (buttonContext.mounted && result != null) {
                          setState(() => moved = true);
                        }
                      },
                      child: const Text('Open editor'),
                    );
                  }),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Story begins');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Next page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a dialog does not change screen or leak dependents',
      (tester) async {
    var changed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showHotIceTextDialog(
                  context,
                  title: 'Cancel test',
                  label: 'Your draft',
                  confirmLabel: 'Save',
                );
                changed = result != null;
              },
              child: const Text('Edit draft'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(changed, isFalse);
    expect(find.text('Edit draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo account switch and appearance changes do not replace app',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const HotIceApp());
    final demo = find.text('Explore demo studio');
    await tester.ensureVisible(demo);
    await tester.tap(demo);
    await tester.pumpAndSettle();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'tester@example.com');
    final add = find.text('Add / switch account');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    // Switching profiles intentionally resets the shell to its Projects tab.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(find.text('tester@example.com'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings & appearance'));
    await tester.pumpAndSettle();
    final color = find.text('Ocean');
    await tester.ensureVisible(color);
    await tester.tap(color);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('normal video unsaved prompt survives switching between tabs',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const HotIceApp());
    await tester.tap(find.text('Explore demo studio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    final shot = find.widgetWithText(TextField, 'Describe your shot');
    expect(shot, findsOneWidget);
    await tester.enterText(shot, 'Keep this unsaved forest scene');
    await tester.testTextInput.hide();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Avatars'));
    await tester.pumpAndSettle();
    expect(find.text('Avatar Studio'), findsOneWidget);
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(shot).controller!.text,
      'Keep this unsaved forest scene',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('new project selection still reaches generator with retained tabs',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const HotIceApp());
    await tester.tap(find.text('Explore demo studio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Fresh project');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final dropdown = find.byType(DropdownButtonFormField<String>).first;
    expect(dropdown, findsOneWidget);
    expect(tester.widget<DropdownButtonFormField<String>>(dropdown).value,
        isNotNull);
    expect(find.text('Scene composer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
