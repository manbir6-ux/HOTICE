import 'state.dart';
import 'video_models.dart';

/// Produces a reusable TEXT identity note for the offline UI prototype.
/// This is not a biometric identity lock, face scan, or vendor-specific API.
class AvatarPromptComposer {
  static String identityCard(StudioAvatar avatar) {
    final notes = avatar.identityNotes.trim().replaceAll(RegExp(r'\s+'), ' ');
    final details = notes.isEmpty
        ? 'No appearance notes yet.'
        : notes;
    return 'Character: ' + avatar.name.trim() +
        '. Preferred visual treatment: ' + avatar.style +
        '. Consistent appearance notes: ' + details;
  }

  /// Named roles remain distinct even when the same saved actor is cast
  /// as different roles in separate scenes. This only prepares text.
  static String composeActors({
    required String scenePrompt,
    required List<SceneActor> cast,
    required List<StudioAvatar> library,
    required VideoModelProfile model,
  }) {
    final prompt = scenePrompt.trim();
    if (cast.isEmpty) return prompt;
    if (cast.length > model.maxActors) {
      throw StateError('This model preview supports at most ${model.maxActors} scene actors.');
    }
    final names = <String>{};
    final descriptions = <String>[];
    for (final actor in cast) {
      final displayName = actor.sceneName.trim();
      if (displayName.isEmpty || !names.add(displayName.toLowerCase())) {
        throw StateError('Each scene actor needs a unique display name.');
      }
      final matches = library.where((a) => a.name == actor.avatarName);
      if (matches.isEmpty) throw StateError('Actor not in the current library.');
      descriptions.add('Role "$displayName": ${identityCard(matches.first)}');
    }
    return '$prompt\n\n[HOTICE CAST — TEXT PREVIEW ONLY]\n'
        '${descriptions.join('\n')}\n'
        'Use the assigned names consistently. Exact visual identity requires '
        'provider-supported references.';
  }

  /// Keep one user-written scene prompt; append a separately reusable identity
  /// card for demo model handoff. Real adapters must use validated model-specific
  /// reference mechanisms. Text alone cannot promise face consistency.
  static String compose({
    required String scenePrompt,
    required StudioAvatar? avatar,
    required VideoModelProfile model,
  }) {
    final scene = scenePrompt.trim();
    if (avatar == null) return scene;
    // All demo profiles allow text prompts. No real vendor capability implied.
    if (!demoVideoModels.any((m) => m.id == model.id)) return scene;
    return scene + '\n\n[HOTICE character guide — text preview]\n' +
        identityCard(avatar) +
        '\nKeep the same character traits across shots where supported.';
  }
}
