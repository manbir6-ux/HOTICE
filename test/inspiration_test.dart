import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/main.dart';
import 'package:hotice/src/inspiration_catalog.dart';
import 'package:hotice/src/state.dart';
import 'package:hotice/src/video_models.dart';

void main() {
  test('catalog contains only approved, original templates with valid demo models',
      () async {
    final all = await InspirationCatalog.load();
    expect(all.length, greaterThanOrEqualTo(5));
    expect(all.map((t) => t.id).toSet().length, all.length);
    for (final item in all) {
      expect(item.prompt, isNotEmpty);
      expect(demoVideoModels.any((m) => m.id == item.modelId), isTrue);
      expect(item.previewUrl, isNull,
          reason: 'Seed media must not masquerade as cleared videos.');
    }
  });

  test('catalog skips unapproved source and rejects duplicate IDs', () {
    const prefix = '{"schemaVersion":1,"templates":';
    expect(InspirationCatalog.decode('$prefix[]'), isEmpty);
    final entry = {
      'id': 'x',
      'title': 'Test',
      'category': 'Test',
      'tags': <String>['Test'],
      'modelId': 'cinematic_demo',
      'prompt': 'A calm camera move.',
      'actorSlots': <String>[],
      'promptStatus': 'editorial_original',
      'publicationStatus': 'pending',
      'origin': 'external',
    };
    final approved = {
      ...entry,
      'publicationStatus': 'approved',
      'origin': 'hotice_original',
    };
    // Construct JSON by encoding so no source strings are interpolated as JSON.
    expect(InspirationCatalog.decode(
      '{"schemaVersion":1,"templates":[${_json(entry)}]}',
    ), isEmpty);
    expect(() => InspirationCatalog.decode(
      '{"schemaVersion":1,"templates":[${_json(approved)},${_json(approved)}]}',
    ), throwsFormatException);
  });

  test('Use this prompt replaces actor slots with unique scene roles', () async {
    final templates = await InspirationCatalog.load();
    final template = templates.firstWhere((t) => t.actorSlots.length == 2);
    const cast = [
      SceneActor(avatarName: 'Nova', sceneName: 'Hero'),
      SceneActor(avatarName: 'Nova', sceneName: 'Rival'),
    ];
    final result = InspirationPromptBuilder.compile(template, cast);
    expect(result, contains('Hero'));
    expect(result, contains('Rival'));
    expect(result, isNot(contains('{{Actor1}}')));
    expect(() => InspirationPromptBuilder.compile(template, cast.take(1).toList()),
        throwsStateError);
  });

  testWidgets('inspiration action loads template into normal video composer',
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
    await tester.tap(find.byTooltip('Inspiration Library'));
    await tester.pumpAndSettle();
    expect(find.text('Inspiration Library'), findsWidgets);
    final use = find.text('Use this prompt').first;
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Describe your shot');
    expect(field, findsOneWidget);
    final text = tester.widget<TextField>(field).controller!.text;
    expect(text, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}

String _json(Map<String, Object> source) {
  // Plain Flutter foundation JSON encoding, no platform dependencies.
  return const JsonEncoder().convert(source);
}
