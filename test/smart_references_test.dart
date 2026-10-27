import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/smart_references.dart';
import 'package:hotice/src/state.dart';
import 'package:hotice/src/video_models.dart';

AvatarReference face(String id, FaceView view, {String owner = 'Actor'}) =>
    AvatarReference(
      id: id,
      ownerName: owner,
      role: ReferenceRole.avatar,
      format: ReferenceFormat.image,
      mimeType: 'image/jpeg',
      localPath: '/temporary/$id.jpg',
      view: view,
    );

AvatarReference scene(String id, ReferenceRole role) => AvatarReference(
      id: id,
      ownerName: 'film',
      role: role,
      format: ReferenceFormat.image,
      mimeType: 'image/png',
      localPath: '/temporary/$id.png',
    );

ReferenceModelCapability capabilities({
  int images = 4,
  int meshes = 0,
  bool verified = true,
}) => ReferenceModelCapability(
      modelId: 'internal-verification-fixture',
      verified: verified,
      maxImages: images,
      maxMeshes: meshes,
      supportedMimeTypes: [
        'image/jpeg',
        'image/png',
        if (meshes > 0) 'model/gltf-binary',
      ],
    );

void main() {
  final images = [
    face('front', FaceView.front),
    face('left', FaceView.left90),
    face('right', FaceView.right90),
    face('right45', FaceView.right45),
  ];
  AvatarAssetPack pack(Iterable<AvatarReference> assets) => AvatarAssetPack(
        avatarName: 'Actor',
        version: 1,
        assets: assets,
        consented: true,
      );

  test('right side scene prioritises right profile and right 45 over front', () {
    final plan = SmartReferencePlanner.plan(
      avatarPack: pack(images),
      sceneAssets: [
        scene('street', ReferenceRole.location),
        scene('car', ReferenceRole.object),
      ],
      model: capabilities(),
      scenePrompt: 'Night street, show the right side profile of the actor',
    );
    expect(plan.errors, isEmpty);
    expect(plan.selected.map((a) => a.id).toList(),
        ['right', 'right45', 'street', 'car']);
    expect(plan.canSubmit, isTrue);
  });

  test('manual mode only includes selected refs', () {
    final plan = SmartReferencePlanner.plan(
      avatarPack: pack(images),
      sceneAssets: [scene('street', ReferenceRole.location)],
      model: capabilities(),
      scenePrompt: 'Face front',
      autoSelect: false,
      selectedIds: ['left', 'street'],
    );
    expect(plan.selected.map((a) => a.id).toList(), ['left', 'street']);
    expect(plan.errors, isEmpty);
  });

  test('locked media survives auto suggestions and never silently disappears', () {
    final plan = SmartReferencePlanner.plan(
      avatarPack: pack(images),
      sceneAssets: [scene('street', ReferenceRole.location)],
      model: capabilities(images: 2),
      scenePrompt: 'Face front',
      lockedIds: ['street', 'right'],
    );
    expect(plan.selected.map((a) => a.id), containsAll(['street', 'right']));
    expect(plan.imageCount, 2);
  });

  test('too many locked images reports a blocking error', () {
    final plan = SmartReferencePlanner.plan(
      avatarPack: pack(images),
      sceneAssets: [],
      model: capabilities(images: 1),
      scenePrompt: 'Hello',
      lockedIds: ['front', 'left'],
    );
    expect(plan.errors, isNotEmpty);
    expect(plan.canSubmit, isFalse);
  });

  test('mesh is used only if a provider explicitly supports glb', () {
    final glb = AvatarReference(
      id: 'mesh',
      ownerName: 'Actor',
      role: ReferenceRole.avatar,
      format: ReferenceFormat.glb,
      mimeType: 'model/gltf-binary',
      localPath: '/private/head.glb',
      isScanVerified: true,
    );
    final imageOnly = SmartReferencePlanner.plan(
      avatarPack: pack([glb, images.first]),
      sceneAssets: [],
      model: capabilities(),
      scenePrompt: 'Portrait',
    );
    expect(imageOnly.selected.map((a) => a.id), ['front']);
    final threeD = SmartReferencePlanner.plan(
      avatarPack: pack([glb, images.first]),
      sceneAssets: [],
      model: capabilities(meshes: 1),
      scenePrompt: 'Portrait',
    );
    expect(threeD.selected.map((a) => a.id), ['mesh', 'front']);
  });

  test('unknown image model is preview only, not generation ready', () {
    final preview = SmartReferencePlanner.plan(
      avatarPack: pack(images),
      sceneAssets: [],
      model: ReferenceModelCapability.demo(demoVideoModels.first),
      scenePrompt: 'Portrait',
    );
    expect(preview.canSubmit, isFalse);
    expect(preview.warnings.join(' '), contains('preview only'));
  });

  test('missing locked assets, duplicate IDs and bad ownership are rejected', () {
    final missing = SmartReferencePlanner.plan(
      avatarPack: pack(images),
      sceneAssets: [],
      model: capabilities(),
      scenePrompt: 'Hello',
      lockedIds: ['deleted'],
    );
    expect(missing.errors, isNotEmpty);
    final duplicate = SmartReferencePlanner.plan(
      avatarPack: pack([images.first, images.first]),
      sceneAssets: [],
      model: capabilities(),
      scenePrompt: 'Hello',
    );
    expect(duplicate.errors, isNotEmpty);
    final foreign = SmartReferencePlanner.plan(
      avatarPack: pack([face('foreign', FaceView.front, owner: 'Other')]),
      sceneAssets: [],
      model: capabilities(),
      scenePrompt: 'Hello',
    );
    expect(foreign.errors, isNotEmpty);
  });

  test('consent is mandatory for avatar references', () {
    final plan = SmartReferencePlanner.plan(
      avatarPack: AvatarAssetPack(
        avatarName: 'Actor', version: 1, assets: images, consented: false,
      ),
      sceneAssets: [],
      model: capabilities(),
      scenePrompt: 'Hello',
    );
    expect(plan.selected, isEmpty);
    expect(plan.errors, isNotEmpty);
  });

  test('local demo store isolates photos by account and deletes on avatar removal', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    expect(store.addAvatar('Actor', 'Photorealistic'), isTrue);
    expect(store.addAvatarReference('Actor', images.first), isTrue);
    expect(store.avatarPackFor('Actor').assets, hasLength(1));
    store.addAccount('separate@example.com');
    expect(store.avatarPackFor('Actor').assets, isEmpty);
    expect(store.addAvatarReference('Actor', images.first), isFalse);
    store.switchAccount('creator@hotice.demo');
    expect(store.editAvatar('Actor', 'New Actor', 'Cinematic'), isTrue);
    expect(store.avatarPackFor('New Actor').assets.single.ownerName, 'New Actor');
    expect(store.removeAvatar('New Actor'), isTrue);
    expect(store.avatarPackFor('New Actor').assets, isEmpty);
  });

  test('draft refuses reference assets belonging to another project', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    final other = store.addProject('Other project');
    expect(store.addSceneReference(other, scene('street', ReferenceRole.location)
        .withOwner(other)), isTrue);
    expect(
      () => store.queueDraft(GenerationDraft(
        projectId: 'demo-film',
        project: 'Untitled cinematic film',
        prompt: 'A scene',
        model: 'Cinematic Draft · Demo',
        modelId: 'cinematic_demo',
        aspectRatio: '16:9',
        durationSeconds: 8,
        createdAt: DateTime(2026, 10, 28),
        selectedReferenceIds: const ['street'],
      )),
      throwsStateError,
    );
  });

  test('draft freezes reference IDs into an immutable snapshot', () {
    final store = HotIceStore();
    addTearDown(store.dispose);
    final id = store.addProject('Film');
    expect(store.addAvatar('Actor', 'Cinematic'), isTrue);
    expect(store.addAvatarReference('Actor', images.first), isTrue);
    final selected = <String>['front'];
    store.queueDraft(GenerationDraft(
      projectId: id, project: 'Film', prompt: 'Face front',
      model: 'Cinematic Draft · Demo', modelId: 'cinematic_demo',
      avatarName: 'Actor', aspectRatio: '16:9', durationSeconds: 8,
      createdAt: DateTime(2026, 10, 28),
      requestedAttachments: const [VideoAttachment.image],
      selectedReferenceIds: selected,
    ));
    selected.clear();
    expect(store.drafts.first.selectedReferenceIds, ['front']);
    expect(() => store.drafts.first.selectedReferenceIds.clear(),
        throwsUnsupportedError);
  });
}
