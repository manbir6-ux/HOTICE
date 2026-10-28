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

class SceneActor {
  final String avatarName;
  final String sceneName;
  const SceneActor({required this.avatarName, required this.sceneName});
}

class SceneReference {
  final VideoAttachment type;
  final String fileName;
  final int bytes;
  const SceneReference({
    required this.type,
    required this.fileName,
    required this.bytes,
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
  final List<SceneActor> actors;
  final List<SceneReference> referenceFiles;
  final String negativePrompt;
  final int? seed;
  final bool soundEnabled;

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
    this.actors = const <SceneActor>[],
    this.referenceFiles = const <SceneReference>[],
    this.negativePrompt = '',
    this.seed,
    this.soundEnabled = false,
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
        actors: old.actors,
        referenceFiles: old.referenceFiles,
        negativePrompt: old.negativePrompt,
        seed: old.seed,
        soundEnabled: old.soundEnabled,
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
    if (draft.actors.map((a) => a.sceneName.trim().toLowerCase()).toSet().length != draft.actors.length ||
        draft.actors.any((a) => a.sceneName.trim().isEmpty ||
            !avatars.any((av) => av.name == a.avatarName))) {
      throw StateError('Scene actor names must be unique and refer to an existing actor.');
    }
    if (draft.avatarName != 'None' &&
        !avatars.any((avatar) => avatar.name == draft.avatarName)) {
      throw StateError('Selected Actor is not in this demo workspace.');
    }
    if (draft.referenceFiles.any((file) =>
        file.fileName.trim().isEmpty || file.bytes < 0)) {
      throw StateError('Invalid reference file metadata.');
    }
    if (draft.modelId.isNotEmpty) {
      final matches = demoVideoModels.where((m) => m.id == draft.modelId);
      if (matches.isEmpty) {
        throw StateError('Unknown model preview.');
      }
      final model = matches.single;
      final attachments = [
        ...draft.requestedAttachments,
        ...draft.referenceFiles.map((f) => f.type),
      ];
      if (!model.accepts(
            seconds: draft.durationSeconds,
            ratio: draft.aspectRatio,
            inputs: attachments,
          ) ||
          draft.actors.length > model.maxActors ||
          (draft.seed != null && !model.supportsSeed) ||
          (draft.negativePrompt.trim().isNotEmpty && !model.supportsNegativePrompt) ||
          (draft.soundEnabled && !model.supportsSound)) {
        throw StateError('Unsupported model settings, actors, or attachments.');
      }
    }
    // Capture a stable, detached job snapshot after validation.
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
      requestedAttachments: List<VideoAttachment>.unmodifiable(draft.requestedAttachments),
      actors: List<SceneActor>.unmodifiable(draft.actors),
      referenceFiles: List<SceneReference>.unmodifiable(draft.referenceFiles),
      negativePrompt: draft.negativePrompt,
      seed: draft.seed,
      soundEnabled: draft.soundEnabled,
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
        shot.estimatedSeconds > 600 || shot.description.trim().isEmpty)) {
      throw StateError('Storyboard shots require a description and a valid duration.');
    }
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

  /// Versioned local snapshot for the encrypted device archive. It contains
  /// project text and metadata only; never auth tokens, billing state, or raw
  /// camera/media bytes. Every user-authored draft field is round-tripped.
  Map<String, dynamic> exportLocalSnapshot() => {
        'schema': 1,
        'selectedAccount': selectedAccount,
        'theme': themeMode.name,
        'accent': accent.name,
        'font': font.name,
        'workspaces': {
          for (final entry in _workspaces.entries)
            entry.key: {
              'projects': [
                for (final p in entry.value.projects)
                  {'id': p.id, 'title': p.title, 'createdAt': p.createdAt.toIso8601String()}
              ],
              'avatars': [
                for (final a in entry.value.avatars)
                  {'name': a.name, 'style': a.style, 'identityNotes': a.identityNotes}
              ],
              'drafts': [
                for (final d in entry.value.drafts)
                  {
                    'projectId': d.projectId,
                    'project': d.project,
                    'prompt': d.prompt,
                    'model': d.model,
                    'modelId': d.modelId,
                    'aspectRatio': d.aspectRatio,
                    'durationSeconds': d.durationSeconds,
                    'createdAt': d.createdAt.toIso8601String(),
                    'avatarName': d.avatarName,
                    'requestedAttachments': [for (final a in d.requestedAttachments) a.name],
                    'actors': [
                      for (final a in d.actors)
                        {'avatarName': a.avatarName, 'sceneName': a.sceneName}
                    ],
                    'referenceFiles': [
                      for (final f in d.referenceFiles)
                        {'type': f.type.name, 'fileName': f.fileName, 'bytes': f.bytes}
                    ],
                    'negativePrompt': d.negativePrompt,
                    'seed': d.seed,
                    'soundEnabled': d.soundEnabled,
                  }
              ],
              'musicPlans': [
                for (final m in entry.value.musicPlans)
                  {
                    'projectId': m.projectId,
                    'storyBrief': m.storyBrief,
                    'visualStyle': m.visualStyle,
                    'avatarName': m.avatarName,
                    'createdAt': m.createdAt.toIso8601String(),
                    'shots': [
                      for (final shot in m.shots)
                        {'title': shot.title, 'description': shot.description,
                          'estimatedSeconds': shot.estimatedSeconds}
                    ]
                  }
              ]
            }
        }
      };

  /// Restore only authenticated archive content. This never restores an
  /// authenticated server session or grants cloud access.
  void restoreLocalSnapshot(Map<String, dynamic> data) {
    if (data['schema'] != 1 || data['workspaces'] is! Map) {
      throw const FormatException('Unsupported HOTICE local project snapshot.');
    }
    Iterable<Map<String, dynamic>> rows(Object? value) sync* {
      if (value is! List) return;
      for (final row in value) {
        if (row is Map<String, dynamic>) yield row;
      }
    }
    DateTime stamp(Object? value) =>
        DateTime.tryParse(value is String ? value : '') ?? DateTime.now();
    List<VideoAttachment> attachmentTypes(Object? value) {
      if (value is! List) return const [];
      return VideoAttachment.values
          .where((type) => value.contains(type.name)).toList(growable: false);
    }

    final replacement = <String, _DemoWorkspace>{};
    final sources = data['workspaces'] as Map;
    if (sources.length > 30) throw const FormatException('Too many local workspaces.');
    for (final entry in sources.entries) {
      if (entry.key is! String || !isValidDemoEmail(entry.key as String) ||
          entry.value is! Map<String, dynamic>) continue;
      final email = (entry.key as String).toLowerCase();
      final source = entry.value as Map<String, dynamic>;
      final target = _DemoWorkspace();
      for (final row in rows(source['projects']).take(500)) {
        final id = row['id'];
        final title = row['title'];
        if (id is String && id.isNotEmpty && title is String && title.trim().isNotEmpty &&
            !target.projects.any((item) => item.id == id)) {
          target.projects.add(HotProject(id, title, stamp(row['createdAt'])));
        }
      }
      for (final row in rows(source['avatars']).take(100)) {
        final name = row['name'];
        final style = row['style'];
        if (name is String && name.trim().isNotEmpty && style is String &&
            !target.avatars.any((item) => item.name.toLowerCase() == name.toLowerCase())) {
          target.avatars.add(StudioAvatar(name, style,
              identityNotes: row['identityNotes'] is String ? row['identityNotes'] as String : ''));
        }
      }
      for (final row in rows(source['drafts']).take(1000)) {
        final projectId = row['projectId'];
        if (projectId is! String || !target.projects.any((p) => p.id == projectId)) continue;
        final actors = <SceneActor>[];
        for (final actor in rows(row['actors']).take(100)) {
          if (actor['avatarName'] is String && actor['sceneName'] is String &&
              target.avatars.any((a) => a.name == actor['avatarName'])) {
            actors.add(SceneActor(avatarName: actor['avatarName'] as String,
                sceneName: actor['sceneName'] as String));
          }
        }
        final refs = <SceneReference>[];
        for (final ref in rows(row['referenceFiles']).take(100)) {
          final type = VideoAttachment.values.where((v) => v.name == ref['type']);
          if (type.isNotEmpty && ref['fileName'] is String && ref['bytes'] is int &&
              (ref['bytes'] as int) >= 0) {
            refs.add(SceneReference(type: type.first, fileName: ref['fileName'] as String,
                bytes: ref['bytes'] as int));
          }
        }
        final title = target.projects.firstWhere((p) => p.id == projectId).title;
        target.drafts.add(GenerationDraft(
          projectId: projectId, project: title,
          prompt: row['prompt'] is String ? row['prompt'] as String : '',
          model: row['model'] is String ? row['model'] as String : '',
          modelId: row['modelId'] is String ? row['modelId'] as String : '',
          aspectRatio: row['aspectRatio'] is String ? row['aspectRatio'] as String : '16:9',
          durationSeconds: row['durationSeconds'] is int ? row['durationSeconds'] as int : 8,
          createdAt: stamp(row['createdAt']),
          avatarName: row['avatarName'] is String ? row['avatarName'] as String : 'None',
          requestedAttachments: attachmentTypes(row['requestedAttachments']),
          actors: actors,
          referenceFiles: refs,
          negativePrompt: row['negativePrompt'] is String ? row['negativePrompt'] as String : '',
          seed: row['seed'] is int ? row['seed'] as int : null,
          soundEnabled: row['soundEnabled'] == true,
        ));
      }
      for (final row in rows(source['musicPlans']).take(500)) {
        final projectId = row['projectId'];
        if (projectId is! String || !target.projects.any((p) => p.id == projectId)) continue;
        final shots = <StoryboardShot>[];
        for (final shot in rows(row['shots']).take(250)) {
          final duration = shot['estimatedSeconds'];
          final description = shot['description'];
          if (duration is int && duration > 0 && duration <= 600 &&
              description is String && description.trim().isNotEmpty) {
            shots.add(StoryboardShot(shot['title'] is String ? shot['title'] as String : 'Shot',
                description, duration));
          }
        }
        if (shots.isNotEmpty) {
          target.musicPlans.add(MusicVideoPlan(projectId: projectId,
              storyBrief: row['storyBrief'] is String ? row['storyBrief'] as String : '',
              visualStyle: row['visualStyle'] is String ? row['visualStyle'] as String : 'Cinematic realism',
              avatarName: row['avatarName'] is String ? row['avatarName'] as String : 'None',
              shots: shots, createdAt: stamp(row['createdAt'])));
        }
      }
      replacement[email] = target;
    }
    if (replacement.isEmpty) throw const FormatException('Encrypted archive has no valid workspaces.');
    _workspaces..clear()..addAll(replacement);
    accounts..clear()..addAll(replacement.keys);
    final selected = data['selectedAccount'];
    selectedAccount = selected is String && replacement.containsKey(selected.toLowerCase())
        ? selected.toLowerCase() : accounts.first;
    themeMode = ThemeMode.values.firstWhere((v) => v.name == data['theme'], orElse: () => ThemeMode.dark);
    accent = StudioAccent.values.firstWhere((v) => v.name == data['accent'], orElse: () => StudioAccent.electric);
    font = StudioFont.values.firstWhere((v) => v.name == data['font'], orElse: () => StudioFont.modern);
    signedIn = false;
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
