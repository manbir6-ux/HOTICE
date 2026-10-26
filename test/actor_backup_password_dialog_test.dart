import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/actor_backup_password_dialog.dart';

void main() {
  testWidgets('export requires strong matching password and can be cancelled',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? created;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            created = await requestActorBackupPassword(
              context, creatingBackup: true,
            );
          },
          child: const Text('Export Actor'),
        )),
      ),
    ));
    await tester.tap(find.text('Export Actor'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    expect(tester.widget<TextField>(fields.first).obscureText, isTrue);
    await tester.enterText(fields.first, 'weak');
    await tester.enterText(fields.last, 'weak');
    await tester.tap(find.text('Encrypt backup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12 and 256 characters'), findsOneWidget);

    await tester.enterText(fields.first, 'Long-secret-for-HOTICE-2026');
    await tester.enterText(fields.last, 'Different-secret-HOTICE');
    await tester.tap(find.text('Encrypt backup'));
    await tester.pumpAndSettle();
    expect(find.textContaining('do not match'), findsOneWidget);

    await tester.enterText(fields.last, 'Long-secret-for-HOTICE-2026');
    await tester.tap(find.text('Encrypt backup'));
    await tester.pumpAndSettle();
    expect(created, 'Long-secret-for-HOTICE-2026');
  });

  testWidgets('encrypted import requests password without confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    String? entered;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            entered = await requestActorBackupPassword(
              context, creatingBackup: false,
            );
          },
          child: const Text('Import Actor'),
        )),
      ),
    ));
    await tester.tap(find.text('Import Actor'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'PreviouslySetPassword');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(entered, 'PreviouslySetPassword');
  });
}
