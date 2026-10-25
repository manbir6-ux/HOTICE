import 'state.dart';
import 'video_models.dart';

/// Produces a reusable TEXT identity note for the offline UI prototype.
/// This is not a biometric identity lock, face scan, or vendor-specific API.
class AvatarPromptComposer {
  static String identityCard(StudioAvatar avatar) {
    final notes = avatar.identityNotes.trim().replaceAll(RegExp(r'\\s+'), ' ');
    final details = notes.isEmpty
        ? 'No appearance notes yet.'
        : notes;
    return 'Character: ' + avatar.name.trim() +
        '. Preferred visual treatment: ' + avatar.style +
        '. Consistent appearance notes: ' + details;
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
