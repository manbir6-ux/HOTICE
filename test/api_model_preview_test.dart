import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/api_model_preview_panel.dart';

void main() {
  testWidgets('API preview uses provider-specific aspects and no fake Omni duration',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: ApiVideoPreviewPanel(prompt: 'A mountain sunrise'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Real API model settings preview'));
    await tester.pumpAndSettle();
    expect(find.text('API output dimensions'), findsOneWidget);
    expect(find.text('16:9'), findsWidgets);
    expect(find.textContaining('Output length is automatic'), findsOneWidget);
    expect(find.text('API duration'), findsNothing);

    final dropdown = find.widgetWithText(
        DropdownButtonFormField<String>, 'Research API model');
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Runway Gen-4.5 · Text to Video').last);
    await tester.pumpAndSettle();

    expect(find.text('1280:720'), findsWidgets);
    expect(find.text('API duration'), findsOneWidget);
    expect(find.text('720p'), findsWidgets);
    expect(find.textContaining('Native 3D mesh: not supported'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
