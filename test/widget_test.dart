import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/main.dart';
import 'package:hotice/src/projects_generation.dart';
import 'package:hotice/src/state.dart';
import 'package:hotice/src/video_models.dart';
import 'package:hotice/src/avatar_identity.dart';
import 'package:hotice/src/music_studio.dart';

void main() {
  test('credit prices use integer US cents', () {
    expect(creditsPerUsd, 100);
    expect(minimumPurchaseUsd * creditsPerUsd, 1000);
    expect(20 * creditsPerUsd, 2000);
    expect(50 * creditsPerUsd, 5000);
  });

  test('project rename and delete keep demo workspaces isolated', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    final first = store.addProject('First name');
    final second = store.addProject('Keep this film');
    store.queueDraft(GenerationDraft(
      projectId: first,
      project: 'First name',
      prompt: 'Opening shot',
      model: 'Cinematic Draft',
      aspectRatio: '16:9',
      durationSeconds: 8,
      createdAt: DateTime(2026, 10, 27),
    ));
    store.saveMusicPlan(MusicVideoPlan(
      projectId: first,
      storyBrief: 'A completed local storyboard',
      visualStyle: 'Anime',
      avatarName: 'None',
      shots: const [StoryboardShot('Scene one', 'A character arrives', 6)],
      createdAt: DateTime(2026, 10, 27),
    ));
    expect(store.renameProject(first, '  Better title  '), isTrue);
    expect(store.projects.any((p) => p.id == first && p.title == 'Better title'), isTrue);
    expect(store.drafts.single.project, 'Better title');
    expect(store.musicPlans.single.projectId, first);
    expect(store.renameProject(first, '  '), isFalse);
    expect(store.renameProject(first, List.filled(61, 'x').join()), isFalse);

    store.addAccount('separate@example.com');
    final other = store.addProject('Other account project');
    expect(store.renameProject(first, 'Illegal rename'), isFalse);
    expect(store.deleteProject(first), isFalse);
    expect(store.projects.single.id, other);
    store.switchAccount('creator@hotice.demo');
    expect(store.deleteProject(first), isTrue);
    expect(store.deleteProject(first), isFalse);
    expect(store.drafts, isEmpty);
    expect(store.musicPlans, isEmpty);
    expect(store.projects.any((p) => p.id == second), isTrue);
    expect(store.projects.any((p) => p.id == first), isFalse);
    store.switchAccount('separate@example.com');
    expect(store.projects.single.id, other);
  });

  testWidgets('project cards support rename and confirmed delete',
      (tester) async {
    final store = HotIceStore();
    addTearDown(store.dispose);
    final id = store.addProject('Manage this film');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnimatedBuilder(
          animation: store,
          builder: (context, _) => ProjectsPage(
            store: store,
            onOpen: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> openOptions() async {
      final menu = find.byKey(ValueKey('project-options-$id'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
    }

    await openOptions();
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Project title'), 'Revised title');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();
    expect(store.projects.first.title, 'Revised title');
    expect(find.text('Revised title'), findsWidgets);

    await openOptions();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete project?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(store.projects.any((p) => p.id == id), isTrue);

    await openOptions();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete project').last);
    await tester.pumpAndSettle();
    expect(store.projects.any((p) => p.id == id), isFalse);
    expect(tester.takeException(), isNull);
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


  test('avatar rename preserves identity and safely rejects duplicate names', () {
    final store = HotIceStore();
    expect(store.addAvatar('Explorer', 'Cinematic',
        identityNotes: 'Short curly hair'), isTrue);
    expect(store.editAvatar('Explorer', 'Nova', 'Cinematic'), isFalse);
    expect(store.editAvatar('Explorer', 'Explorer One', 'Animated',
        identityNotes: 'Curly hair and a green jacket'), isTrue);
    expect(store.avatars.any((a) =>
        a.name == 'Explorer One' &&
        a.identityNotes.contains('green jacket')), isTrue);
    expect(store.removeAvatar('Explorer One'), isTrue);
    expect(store.removeAvatar('Explorer One'), isFalse);
    store.dispose();
  });

  test('reusable avatar identity notes are added across demo video models', () {
    const avatar = StudioAvatar('Explorer', 'Cinematic',
        identityNotes: '  long  dark hair   and a blue jacket ');
    final output = <String>[];
    for (final model in demoVideoModels) {
      final text = AvatarPromptComposer.compose(
        scenePrompt: 'Running through a forest',
        avatar: avatar,
        model: model,
      );
      output.add(text);
      expect(text, contains('long dark hair and a blue jacket'));
      expect(text, contains('Running through a forest'));
    }
    expect(output.toSet().length, 1);
    expect(AvatarPromptComposer.compose(
      scenePrompt: 'Empty shot',
      avatar: null,
      model: demoVideoModels.first,
    ), 'Empty shot');
  });

  test('offline storyboard is editable draft, not a fake audio analysis', () {
    expect(MusicStoryboardTemplates.fromBrief('   '), isEmpty);
    final plan = MusicStoryboardTemplates.fromBrief('  Hero   comes home  ');
    expect(plan.length, 4);
    expect(plan.first.description, contains('Hero comes home'));
    expect(plan.every((shot) => shot.estimatedSeconds > 0), isTrue);
  });

  test('manual music shot schedule computes contiguous scene boundaries', () {
    const shots = [
      StoryboardShot('One', 'Opening', 4),
      StoryboardShot('Two', 'Action', 10),
      StoryboardShot('Three', 'Finale', 6),
    ];
    final cues = MusicStoryboardTimeline.arrange(shots);
    expect(cues.map((c) => c.startSeconds).toList(), [0, 4, 14]);
    expect(cues.map((c) => c.endSeconds).toList(), [4, 14, 20]);
    expect(MusicStoryboardTimeline.clock(cues.last.endSeconds), '00:20');
    expect(MusicStoryboardTimeline.clock(125), '02:05');
    expect(MusicStoryboardTimeline.arrange([]), isEmpty);
  });

  testWidgets('music storyboard scene duration can be edited manually',
      (tester) async {
    final store = HotIceStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MusicVideoStudioPage(store: store)),
    ));
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextField, 'Describe your music video');
    await tester.enterText(field, 'A singer walks toward the sunrise');
    final preview = find.text('Preview storyboard');
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('Estimated runtime: 00:26'), findsOneWidget);

    final duration = find.byKey(const ValueKey('music-shot-duration-0'));
    await tester.ensureVisible(duration);
    await tester.tap(duration);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();
    expect(find.text('Estimated runtime: 00:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('music video drafts are isolated by profile and reject foreign projects', () {
    final store = HotIceStore();
    final plan = MusicVideoPlan(
      projectId: 'demo-film',
      storyBrief: 'A hero returns home',
      visualStyle: 'Cinematic realism',
      avatarName: 'Nova',
      shots: MusicStoryboardTemplates.fromBrief('A hero returns home'),
      createdAt: DateTime(2026, 10, 26),
    );
    store.saveMusicPlan(plan);
    expect(store.musicPlans.single.avatarName, 'Nova');
    store.addAccount('second@example.com');
    expect(store.musicPlans, isEmpty);
    expect(() => store.saveMusicPlan(plan), throwsStateError);
    store.dispose();
  });

  test('foreign Actors are not accepted in normal video scene drafts', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    store.addAvatar('Private Hero', 'Cinematic');
    store.addAccount('other@example.com');
    expect(() => store.queueDraft(GenerationDraft(
      projectId: store.addProject('Other film'),
      project: 'Other film',
      avatarName: 'Private Hero',
      prompt: 'A scene with another profile\'s actor',
      model: 'Cinematic Draft',
      aspectRatio: '16:9',
      durationSeconds: 8,
      createdAt: DateTime(2026, 10, 27),
    )), throwsStateError);
    expect(store.drafts, isEmpty);
  });

  test('normal video drafts retain verified attachment snapshots', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    final mutable = <VideoAttachment>[VideoAttachment.image];
    store.queueDraft(GenerationDraft(
      projectId: 'demo-film',
      project: 'User supplied incorrect project title',
      prompt: 'A quiet sunset',
      model: 'Cinematic Draft · Demo',
      modelId: 'cinematic_demo',
      requestedAttachments: mutable,
      aspectRatio: '16:9',
      durationSeconds: 8,
      createdAt: DateTime(2026, 10, 27),
    ));
    mutable.clear();
    expect(store.drafts.single.project, 'Untitled cinematic film');
    expect(store.drafts.single.requestedAttachments, [VideoAttachment.image]);
    expect(
      () => store.drafts.single.requestedAttachments.add(VideoAttachment.audio),
      throwsUnsupportedError,
    );
  });

  test('saved storyboards snapshot caller-owned mutable shot lists', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    final mutableShots = <StoryboardShot>[
      const StoryboardShot('Opening', 'A safe opening', 6),
    ];
    store.saveMusicPlan(MusicVideoPlan(
      projectId: 'demo-film',
      storyBrief: '  Night ride  ',
      visualStyle: 'Cinematic realism',
      avatarName: 'None',
      shots: mutableShots,
      createdAt: DateTime(2026, 10, 27),
    ));
    mutableShots.clear();
    expect(store.musicPlans.single.shots, hasLength(1));
    expect(store.musicPlans.single.storyBrief, 'Night ride');
    expect(() => store.musicPlans.single.shots.clear(), throwsUnsupportedError);
    expect(() => store.saveMusicPlan(MusicVideoPlan(
      projectId: 'demo-film',
      storyBrief: 'Broken',
      visualStyle: 'Anime',
      avatarName: 'None',
      shots: const [StoryboardShot('Bad', '', 0)],
      createdAt: DateTime(2026, 10, 27),
    )), throwsStateError);
  });

  testWidgets('normal video creative settings remain isolated per project',
      (tester) async {
    final store = HotIceStore();
    final second = store.addProject('Second video');
    expect(store.addAvatar('Test Actor', 'Cinematic'), isTrue);
    addTearDown(store.dispose);

    Future<void> openProject(String id) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GenerationPage(
          store: store, initialProjectId: id,
        )),
      ));
      await tester.pumpAndSettle();
    }

    await openProject('demo-film');
    // Choose a different model, duration, aspect and Actor for film one.
    final modelField = find.widgetWithText(
        DropdownButtonFormField<String>, 'Model preview');
    await tester.ensureVisible(modelField);
    await tester.tap(modelField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Character Focus · Demo').last);
    await tester.pumpAndSettle();
    final portrait = find.text('9:16');
    await tester.ensureVisible(portrait.last);
    await tester.tap(portrait.last);
    await tester.pumpAndSettle();
    final actorField = find.widgetWithText(
        DropdownButtonFormField<String>, 'Avatar');
    await tester.ensureVisible(actorField);
    await tester.tap(actorField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Actor').last);
    await tester.pumpAndSettle();

    await openProject(second);
    expect(find.text('Cinematic Draft · Demo'), findsOneWidget);
    expect(find.text('Character Focus · Demo'), findsNothing);
    expect(find.text('None'), findsWidgets);
    final fourSeconds = find.text('4 seconds');
    await tester.ensureVisible(fourSeconds);
    await tester.tap(fourSeconds);
    await tester.pumpAndSettle();

    await openProject('demo-film');
    expect(find.text('Character Focus · Demo'), findsOneWidget);
    expect(find.text('Test Actor'), findsOneWidget);
    expect(find.text('9:16'), findsOneWidget);
    expect(find.text('8 seconds'), findsOneWidget);

    await openProject(second);
    expect(find.text('Cinematic Draft · Demo'), findsOneWidget);
    expect(find.text('4 seconds'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsaved scene prompts stay with their own projects',
      (tester) async {
    final store = HotIceStore();
    final second = store.addProject('Second film');
    addTearDown(store.dispose);

    Future<void> openProject(String id) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GenerationPage(
              store: store,
              initialProjectId: id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openProject('demo-film');
    final field = find.widgetWithText(TextField, 'Describe your shot');
    await tester.enterText(field, 'FIRST film scene, not for second film');
    await openProject(second);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.enterText(field, 'SECOND film separate scene');
    await openProject('demo-film');
    expect(tester.widget<TextField>(field).controller!.text,
        'FIRST film scene, not for second film');
    expect(tester.takeException(), isNull);
  });

  testWidgets('music project changes retain independent story and shots',
      (tester) async {
    final store = HotIceStore();
    final second = store.addProject('Second music film');
    addTearDown(store.dispose);

    Future<void> openProject(String id) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MusicVideoStudioPage(
              store: store,
              initialProjectId: id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openProject('demo-film');
    final field = find.widgetWithText(TextField, 'Describe your music video');
    await tester.enterText(field, 'First music story');
    final preview = find.text('Preview storyboard');
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.text('Opening'), findsOneWidget);
    final anime = find.widgetWithText(ChoiceChip, 'Anime');
    final fantasy = find.widgetWithText(ChoiceChip, 'Fantasy');
    final cinematic = find.widgetWithText(ChoiceChip, 'Cinematic realism');
    await tester.ensureVisible(anime);
    await tester.tap(anime);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(anime).selected, isTrue);

    await openProject(second);
    // A different film must start with its default visual direction.
    expect(tester.widget<ChoiceChip>(anime).selected, isFalse);
    expect(tester.widget<ChoiceChip>(cinematic).selected, isTrue);
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(find.text('Opening'), findsNothing);
    await tester.enterText(field, 'Second music story');
    await tester.ensureVisible(fantasy);
    await tester.tap(fantasy);
    await tester.pumpAndSettle();
    await openProject('demo-film');
    expect(tester.widget<TextField>(field).controller!.text,
        'First music story');
    expect(find.text('Opening'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(anime).selected, isTrue);
    expect(tester.widget<ChoiceChip>(fantasy).selected, isFalse);

    await openProject(second);
    expect(tester.widget<TextField>(field).controller!.text,
        'Second music story');
    expect(tester.widget<ChoiceChip>(fantasy).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest demo enters projects without a fake password', (tester) async {
    await tester.pumpWidget(const HotIceApp());
    await tester.tap(find.text('Explore demo studio'));
    await tester.pumpAndSettle();
    expect(find.text('Untitled cinematic film'), findsWidgets);
  });

  testWidgets('welcome enters demo login screen', (tester) async {
    await tester.pumpWidget(const HotIceApp());
    expect(find.text('Create without limits.'), findsOneWidget);
    await tester.tap(find.text('Continue with a demo email'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to HOTICE'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
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
