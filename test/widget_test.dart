import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/main.dart';
import 'package:hotice/src/projects_generation.dart';
import 'package:hotice/src/state.dart';

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
