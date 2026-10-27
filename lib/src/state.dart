import 'dart:math';

import 'package:flutter/material.dart';
import 'video_models.dart';

/// Pricing is in whole US cents to avoid floating point billing errors.
const int creditsPerUsd = 100;
const int minimumPurchaseUsd = 10;

/// This validates only the local UI demo. It is not authentication.
bool isValidDemoEmail(String value) {
  final email = value.trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
}

/// New device projects use UUIDv4 IDs suitable for a future opt-in cloud API.
/// Older seeded demo project IDs remain legacy examples; never upload those
/// without an explicit migration to UUIDs and ownership verification.
String createLocalProjectId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

class HotProject {
  final String id;
  final String title;
  final DateTime createdAt;
  const HotProject(this.id, this.title, this.createdAt);
}

class StudioAvatar {
  final String name;
  final String style;
  final String identityNotes;
  const StudioAvatar(this.name, this.style, {this.identityNotes = ''});
}

class StoryboardShot {
  final String title;
  final String description;
  final int estimatedSeconds;
  const StoryboardShot(this.title, this.description, this.estimatedSeconds);
}

/// A text-only offline planning draft. There is no audio or AI analysis.
class MusicVideoPlan {
  final String projectId;
  final String storyBrief;
  final String visualStyle;
  final String avatarName;
  final List<StoryboardShot> shots;
  final DateTime createdAt;
  const MusicVideoPlan({
    required this.projectId,
    required this.storyBrief,
    required this.visualStyle,
    required this.avatarName,
    required this.shots,
    required this.createdAt,
  });
}

class GenerationDraft {
  final String project;
  final String prompt;
  final String model;
  final String aspectRatio;
  final int durationSeconds;
  final DateTime createdAt;
  final String projectId;
  final String avatarName;
  final String modelId;
  final List<VideoAttachment> requestedAttachments;

  const GenerationDraft({
    required this.project,
    required this.prompt,
    required this.model,
    required this.aspectRatio,
    required this.durationSeconds,
    required this.createdAt,
    this.projectId = '',
    this.avatarName = 'None',
    this.modelId = '',
    this.requestedAttachments = const <VideoAttachment>[],
  });
}

enum StudioAccent {
  electric('Electric', Color(0xFF8F72FF)),
  ocean('Ocean', Color(0xFF2CB9C7)),
  ember('Ember', Color(0xFFF47A6C)),
  glacier('Glacier', Color(0xFF589CF7)),
  moss('Moss', Color(0xFF65B986));

  const StudioAccent(this.label, this.color);
  final String label;
  final Color color;
}

enum StudioFont {
  modern('Modern', null),
  editorial('Editorial', 'serif'),
  technical('Technical', 'monospace');

  const StudioFont(this.label, this.family);
  final String label;
  final String? family;
}

/// Ephemeral demo data for one profile. Never treat this as cloud security.
class _DemoWorkspace {
  _DemoWorkspace({bool seed = false}) {
    if (seed) {
      projects.addAll([
        HotProject('demo-film', 'Untitled cinematic film',
            DateTime(2026, 10, 25)),
        HotProject('demo-social', 'Social teaser',
            DateTime(2026, 10, 24)),
      ]);
      avatars.add(const StudioAvatar('Nova', 'Cinematic'));
    }
  }

  final List<HotProject> projects = [];
  final List<StudioAvatar> avatars = [];
  final List<GenerationDraft> drafts = [];
  final List<MusicVideoPlan> musicPlans = [];
  int demoCredits = 1000;
}

class HotIceStore extends ChangeNotifier {
  bool signedIn = false;
  ThemeMode themeMode = ThemeMode.dark;
  StudioAccent accent = StudioAccent.electric;
  StudioFont font = StudioFont.modern;
  String selectedAccount = 'creator@hotice.demo';
  final List<String> accounts = ['creator@hotice.demo'];

  final Map<String, _DemoWorkspace> _workspaces = {
    'creator@hotice.demo': _DemoWorkspace(seed: true),
  };

  _DemoWorkspace get _workspace => _workspaces.putIfAbsent(
        selectedAccount,
        () => _DemoWorkspace(),
      );

  int get demoCredits => _workspace.demoCredits;
  List<HotProject> get projects => _workspace.projects;
  List<StudioAvatar> get avatars => _workspace.avatars;
  List<GenerationDraft> get drafts => _workspace.drafts;
  List<MusicVideoPlan> get musicPlans => _workspace.musicPlans;

  void signInDemo(String email) {
    final normalized = email.trim().toLowerCase();
    if (!isValidDemoEmail(normalized)) return;
    if (!accounts.contains(normalized)) accounts.add(normalized);
    _workspaces.putIfAbsent(normalized, () => _DemoWorkspace());
    selectedAccount = normalized;
    signedIn = true;
    notifyListeners();
  }

  void signOut() {
    signedIn = false;
    notifyListeners();
  }

  void addAccount(String email) {
    final normalized = email.trim().toLowerCase();
    if (!isValidDemoEmail(normalized)) return;
    if (!accounts.contains(normalized)) accounts.add(normalized);
    _workspaces.putIfAbsent(normalized, () => _DemoWorkspace());
    selectedAccount = normalized;
    notifyListeners();
  }

  void switchAccount(String email) {
    final normalized = email.trim().toLowerCase();
    if (!accounts.contains(normalized)) return;
    selectedAccount = normalized;
    notifyListeners();
  }

  String addProject(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed.length > 60) {
      throw ArgumentError.value(title, 'title', 'Project title must be 1–60 characters.');
    }
    final id = createLocalProjectId();
    projects.insert(0, HotProject(id, trimmed, DateTime.now()));
    notifyListeners();
    return id;
  }

  /// Rename only a project owned by the currently selected demo workspace.
  /// Keep its stable ID and refresh labels captured in existing scene drafts.
  bool renameProject(String projectId, String newTitle) {
    final title = newTitle.trim();
    final index = projects.indexWhere((p) => p.id == projectId);
    if (index < 0 || title.isEmpty || title.length > 60) return false;
    final current = projects[index];
    if (current.title == title) return true;
    projects[index] = HotProject(current.id, title, current.createdAt);
    for (var i = 0; i < drafts.length; i++) {
      final old = drafts[i];
      if (old.projectId != projectId) continue;
      drafts[i] = GenerationDraft(
        project: title,
        prompt: old.prompt,
        model: old.model,
        aspectRatio: old.aspectRatio,
        durationSeconds: old.durationSeconds,
        createdAt: old.createdAt,
        projectId: old.projectId,
        avatarName: old.avatarName,
        modelId: old.modelId,
        requestedAttachments: old.requestedAttachments,
      );
    }
    notifyListeners();
    return true;
  }

  /// Permanently remove the in-memory project and all associated draft data
  /// in this one demo profile. A UI confirmation is required before calling.
  /// This is not a cloud-delete or biometric Actor vault operation.
  bool deleteProject(String projectId) {
    final index = projects.indexWhere((p) => p.id == projectId);
    if (index < 0) return false;
    projects.removeAt(index);
    drafts.removeWhere((draft) => draft.projectId == projectId);
    musicPlans.removeWhere((plan) => plan.projectId == projectId);
    notifyListeners();
    return true;
  }

  /// Avoid duplicate values in the avatar dropdown.
  bool addAvatar(String name, String style, {String identityNotes = ''}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == 'none' ||
        avatars.any((a) => a.name.toLowerCase() == trimmed.toLowerCase())) {
      return false;
    }
    avatars.insert(0, StudioAvatar(trimmed, style, identityNotes: identityNotes.trim()));
    notifyListeners();
    return true;
  }

  bool editAvatar(String originalName, String newName, String style,
      {String identityNotes = ''}) {
    final index = avatars.indexWhere((a) => a.name == originalName);
    final name = newName.trim();
    if (index < 0 || name.isEmpty || name.toLowerCase() == 'none' ||
        avatars.any((a) => a.name != originalName &&
            a.name.toLowerCase() == name.toLowerCase())) {
      return false;
    }
    avatars[index] = StudioAvatar(name, style, identityNotes: identityNotes.trim());
    notifyListeners();
    return true;
  }

  bool removeAvatar(String name) {
    final oldLength = avatars.length;
    avatars.removeWhere((a) => a.name == name);
    if (avatars.length == oldLength) return false;
    // Existing scene drafts remain historical snapshots of their creation.
    notifyListeners();
    return true;
  }

  void queueDraft(GenerationDraft draft) {
    // Prevent a stale project selection from being saved to another profile.
    if (draft.projectId.isNotEmpty &&
        !projects.any((p) => p.id == draft.projectId)) {
      throw StateError('The selected project is not in this demo workspace.');
    }
    // Prevent synthetic scene drafts from referring to an Actor belonging
    // to another demo workspace. This is data integrity, NOT authentication.
    if (draft.avatarName != 'None' &&
        !avatars.any((avatar) => avatar.name == draft.avatarName)) {
      throw StateError('Selected Actor is not in this demo workspace.');
    }
    if (draft.modelId.isNotEmpty) {
      final matches = demoVideoModels.where((m) => m.id == draft.modelId);
      if (matches.isEmpty ||
          !matches.single.accepts(
            seconds: draft.durationSeconds,
            ratio: draft.aspectRatio,
            inputs: draft.requestedAttachments,
          )) {
        throw StateError('Unsupported output or attachment for this model.');
      }
    }
    // Capture a stable job snapshot. The caller must not be able to mutate
    // validated attachment settings after this draft is stored.
    final canonicalProject = projects.where((p) => p.id == draft.projectId);
    drafts.insert(0, GenerationDraft(
      project: canonicalProject.isEmpty ? draft.project : canonicalProject.first.title,
      prompt: draft.prompt,
      model: draft.model,
      aspectRatio: draft.aspectRatio,
      durationSeconds: draft.durationSeconds,
      createdAt: draft.createdAt,
      projectId: draft.projectId,
      avatarName: draft.avatarName,
      modelId: draft.modelId,
      requestedAttachments:
          List<VideoAttachment>.unmodifiable(draft.requestedAttachments),
    ));
    notifyListeners();
  }

  void saveMusicPlan(MusicVideoPlan plan) {
    if (!projects.any((p) => p.id == plan.projectId)) {
      throw StateError('The selected project is not in this demo workspace.');
    }
    if (plan.storyBrief.trim().isEmpty || plan.shots.isEmpty) {
      throw StateError('A story and storyboard shots are required.');
    }
    if (plan.avatarName != 'None' &&
        !avatars.any((avatar) => avatar.name == plan.avatarName)) {
      throw StateError('Avatar belongs to a different workspace.');
    }
    if (plan.shots.any((shot) => shot.estimatedSeconds <= 0 ||
        shot.estimatedSeconds > 600 ||
        shot.description.trim().isEmpty)) {
      throw StateError('Storyboard shots require a description and a valid duration.');
    }
    // Store a detached immutable snapshot, not a caller-owned mutable List.
    // Otherwise editing an unsaved storyboard can silently rewrite history.
    musicPlans.insert(0, MusicVideoPlan(
      projectId: plan.projectId,
      storyBrief: plan.storyBrief.trim(),
      visualStyle: plan.visualStyle,
      avatarName: plan.avatarName,
      shots: List<StoryboardShot>.unmodifiable(plan.shots),
      createdAt: plan.createdAt,
    ));
    notifyListeners();
  }

  void updateTheme(ThemeMode value) {
    themeMode = value;
    notifyListeners();
  }

  void updateAccent(StudioAccent value) {
    accent = value;
    notifyListeners();
  }

  void updateFont(StudioFont value) {
    font = value;
    notifyListeners();
  }
}
