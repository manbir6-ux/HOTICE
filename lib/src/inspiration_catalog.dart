import 'dart:convert';

import 'package:flutter/services.dart';

import 'state.dart';
import 'video_models.dart';

/// Immutable, publicly approved prompt entry. Not an assertion that external
/// media was made with HOTICE, and not a real vendor API configuration.
class InspirationTemplate {
  const InspirationTemplate({
    required this.id,
    required this.title,
    required this.category,
    required this.tags,
    required this.modelId,
    required this.prompt,
    required this.actorSlots,
    required this.promptStatus,
    this.previewUrl,
  });

  final String id;
  final String title;
  final String category;
  final List<String> tags;
  final String modelId;
  final String prompt;
  final List<String> actorSlots;
  final String promptStatus;
  final String? previewUrl;

  static InspirationTemplate fromJson(Map<String, dynamic> json) {
    final entry = InspirationTemplate(
      id: json['id'] as String,
      title: json['title'] as String,
      category: json['category'] as String,
      tags: List<String>.unmodifiable((json['tags'] as List).cast<String>()),
      modelId: json['modelId'] as String,
      prompt: json['prompt'] as String,
      actorSlots:
          List<String>.unmodifiable((json['actorSlots'] as List).cast<String>()),
      promptStatus: json['promptStatus'] as String,
      previewUrl: json['previewUrl'] as String?,
    );
    if (entry.id.trim().isEmpty ||
        entry.title.trim().isEmpty ||
        entry.prompt.trim().isEmpty ||
        entry.actorSlots.toSet().length != entry.actorSlots.length ||
        entry.actorSlots.any((slot) => !RegExp(r'^Actor[0-9]+$').hasMatch(slot)) ||
        entry.actorSlots.any((slot) => !entry.prompt.contains('{{$slot}}')) ||
        !demoVideoModels.any((m) => m.id == entry.modelId)) {
      throw const FormatException('Invalid HOTICE inspiration template.');
    }
    return entry;
  }
}

class InspirationCatalog {
  const InspirationCatalog._();

  static List<InspirationTemplate> decode(String jsonSource) {
    final json = jsonDecode(jsonSource) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported inspiration catalog version.');
    }
    final items = <InspirationTemplate>[];
    final ids = <String>{};
    for (final raw in json['templates'] as List) {
      final entryJson = raw as Map<String, dynamic>;
      // The client consumes only published, approved templates.
      if (entryJson['publicationStatus'] != 'approved') continue;
      if (entryJson['origin'] != 'hotice_original' &&
          entryJson['origin'] != 'licensed') {
        continue;
      }
      final entry = InspirationTemplate.fromJson(entryJson);
      if (!ids.add(entry.id)) {
        throw const FormatException('Duplicate inspiration template ID.');
      }
      items.add(entry);
    }
    return List<InspirationTemplate>.unmodifiable(items);
  }

  static Future<List<InspirationTemplate>> load() async {
    final json = await rootBundle.loadString(
      'web/public/assets/inspiration.json',
    );
    return decode(json);
  }
}

/// Resolve placeholder references by ordered scene cast; not by string input
/// from remote content. Character reference assets must be provided via the
/// selected model's actual accepted reference mechanism in a later phase.
class InspirationPromptBuilder {
  static String compile(InspirationTemplate template, List<SceneActor> cast) {
    if (cast.length < template.actorSlots.length) {
      throw StateError('Assign the required scene actors first.');
    }
    var prompt = template.prompt;
    for (var i = 0; i < template.actorSlots.length; i++) {
      prompt = prompt.replaceAll(
        '{{${template.actorSlots[i]}}}',
        cast[i].sceneName.trim(),
      );
    }
    if (RegExp(r'\{\{Actor[0-9]+\}\}').hasMatch(prompt)) {
      throw StateError('Unassigned actor placeholder.');
    }
    return prompt;
  }
}
