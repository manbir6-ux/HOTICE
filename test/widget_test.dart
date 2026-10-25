import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/main.dart';
import 'package:hotice/src/projects_generation.dart';
import 'package:hotice/src/state.dart';
import 'package:hotice/src/video_models.dart';

void main() {
  test('credit prices use integer US cents', () {
    expect(creditsPerUsd, 100);
    expect(minimumPurchaseUsd * creditsPerUsd, 1000);
    expect(20 * creditsPerUsd, 2000);
    expect(50 * creditsPerUsd, 5000);
  });

  test('demo profile email validation rejects malformed inputs', () {
    expect(isValidDemoEmail('creator@example.com'), isTrue);
    expect(isValidDemoEmail('creator@'), isFalse);
    expect(isValidDemoEmail('not-an-email'), isFalse);
    expect(isValidDemoEmail('x@y.z'), isTrue);
  });

  test('demo account switching isolates projects, drafts and avatars', () {
    final store = HotIceStore();
    final firstAccount = store.selectedAccount;
    final firstProject = store.addProject('First account film');
    expect(store.projects.any((p) => p.id == firstProject), isTrue);
    expect(store.addAvatar('First Actor', 'Cinematic'), isTrue);
    store.queueDraft(GenerationDraft(
      projectId: firstProject,
      project: 'First account film',
      avatarName: 'First Actor',
      prompt: 'A cinematic opening scene',
      model: 'Cinematic Draft',
      aspectRatio: '16:9',
      durationSeconds: 8,
      createdAt: DateTime(2026, 10, 26),
    ));

    store.addAccount('second@example.com');
    expect(store.selectedAccount, 'second@example.com');
    expect(store.projects, isEmpty);
    expect(store.avatars, isEmpty);
    expect(store.drafts, isEmpty);
    expect(store.demoCredits, 1000);

    final secondProject = store.addProject('Second account film');
    expect(store.projects.single.id, secondProject);
    store.switchAccount(firstAccount);
    expect(store.projects.any((p) => p.id == firstProject), isTrue);
    expect(store.projects.any((p) => p.id == secondProject), isFalse);
    expect(store.avatars.any((a) => a.name == 'First Actor'), isTrue);
    expect(store.drafts.single.avatarName, 'First Actor');
    store.dispose();
  });

  test('avatar dropdown names remain unique', () {
    final store = HotIceStore();
    expect(store.addAvatar('Hero', 'Cinematic'), isTrue);
    expect(store.addAvatar(' hero ', 'Animated'), isFalse);
    expect(store.addAvatar('   ', 'Animated'), isFalse);
    expect(store.avatars.where((a) => a.name == 'Hero').length, 1);
    store.dispose();
  });

  test('draft cannot be attached to another demo workspace project', () {
    final store = HotIceStore();
    store.addAccount('second@example.com');
    expect(
      () => store.queueDraft(GenerationDraft(
        projectId: 'demo-film',
        project: 'Unowned project',
        prompt: 'Not permitted',
        model: 'Cinematic Draft',
        aspectRatio: '16:9',
        durationSeconds: 8,
        createdAt: DateTime(2026, 10, 26),
      )),
      throwsStateError,
    );
    store.dispose();
  });

  test('model profiles filter duration and ratios as a pair', () {
    final cinematic = demoModelById('cinematic_demo');
    final character = demoModelById('character_demo');
    final storyboard = demoModelById('storyboard_demo');

    expect(cinematic.durations, [4, 8, 10]);
    expect(cinematic.supportsOutput(10, '1:1'), isFalse);
    expect(cinematic.supportsOutput(10, '16:9'), isTrue);
    expect(character.durations, [4, 8]);
    expect(character.supportsOutput(10, '16:9'), isFalse);
    expect(storyboard.supportsOutput(8, '9:16'), isFalse);
    expect(storyboard.supportsOutput(8, '1:1'), isTrue);
  });

  test('attachment types are validated per model', () {
    final cinematic = demoModelById('cinematic_demo');
    final character = demoModelById('character_demo');
    final storyboard = demoModelById('storyboard_demo');

    expect(cinematic.supportsAttachments([VideoAttachment.image]), isTrue);
    expect(cinematic.supportsAttachments([VideoAttachment.audio]), isFalse);
    expect(character.supportsAttachments([VideoAttachment.video]), isTrue);
    expect(storyboard.supportsAttachments([VideoAttachment.image]), isFalse);
  });

  test('unverified pricing must not produce a generation credit quote', () {
    for (final model in demoVideoModels) {
      for (final seconds in model.durations) {
        for (final ratio in model.ratiosFor(seconds)) {
          expect(model.quoteCredits(seconds, ratio), isNull);
        }
      }
    }
  });

  test('quoted credits require a matching verified configuration', () {
    const profile = VideoModelProfile(
      id: 'verified_test',
      label: 'Internal quote test',
      formatsBySeconds: {
        4: ['16:9'],
        8: ['16:9'],
      },
      creditsByFormat: {'4|16:9': 45},
    );
    expect(profile.quoteCredits(4, '16:9'), 45);
    expect(profile.quoteCredits(8, '16:9'), isNull);
    expect(profile.quoteCredits(4, '9:16'), isNull);
  });

  test('draft storage rejects unsupported model settings or media', () {
    final store = HotIceStore();
    expect(
      () => store.queueDraft(GenerationDraft(
        projectId: 'demo-film',
        project: 'Untitled cinematic film',
        prompt: 'Test scene',
        model: 'Character Focus · Demo',
        modelId: 'character_demo',
        aspectRatio: '16:9',
        durationSeconds: 10,
        createdAt: DateTime(2026, 10, 26),
      )),
      throwsStateError,
    );
    expect(
      () => store.queueDraft(GenerationDraft(
        projectId: 'demo-film',
        project: 'Untitled cinematic film',
        prompt: 'Test scene',
        model: 'Cinematic Draft · Demo',
        modelId: 'cinematic_demo',
        requestedAttachments: [VideoAttachment.audio],
        aspectRatio: '16:9',
        durationSeconds: 4,
        createdAt: DateTime(2026, 10, 26),
      )),
      throwsStateError,
    );
    store.dispose();
  });

  testWidgets('welcome enters demo login screen', (tester) async {
    await tester.pumpWidget(const HotIceApp());
    expect(find.text('Create without limits.'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to HOTICE'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('generation page tolerates an account with no projects',
      (tester) async {
    final store = HotIceStore();
    store.addAccount('empty@example.com');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GenerationPage(store: store))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scene composer'), findsOneWidget);
    expect(find.text('Save generation draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
