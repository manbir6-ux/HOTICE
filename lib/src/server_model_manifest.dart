import 'dart:convert';

/// Strict schema for a signed/authenticated HOTICE backend model manifest.
/// This is not an on-device authority to charge or dispatch provider jobs.
class ServerModelManifest {
  ServerModelManifest._(this.revision, this.validUntil, this.models);
  final String revision;
  final DateTime validUntil;
  final List<ServerModelMode> models;

  static ServerModelManifest parseTrustedBackendJson(String body,
      {DateTime? now}) {
    final parsed = jsonDecode(body);
    if (parsed is! Map<String, dynamic> || parsed['schemaVersion'] != 1) {
      throw const FormatException('Unsupported model manifest schema.');
    }
    final revision = parsed['revision'];
    final expires = DateTime.tryParse(parsed['expiresAt']?.toString() ?? '');
    final entries = parsed['models'];
    final time = now ?? DateTime.now().toUtc();
    if (revision is! String || revision.trim().isEmpty ||
        expires == null || expires.isBefore(time) ||
        expires.difference(time) > const Duration(days: 7) ||
        entries is! List || entries.length > 500) {
      throw const FormatException('Expired or invalid model manifest.');
    }
    final ids = <String>{};
    final models = <ServerModelMode>[];
    for (final raw in entries) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid model entry.');
      }
      final model = ServerModelMode.fromJson(raw);
      if (!ids.add(model.id)) throw const FormatException('Duplicate model ID.');
      models.add(model);
    }
    return ServerModelManifest._(
      revision, expires.toUtc(), List<ServerModelMode>.unmodifiable(models));
  }

  ServerModelMode? lookup(String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}

class ServerModelMode {
  ServerModelMode._(this.id, this.provider, this.modelCode,
      this.task, this.enabled, this.formats, this.imageRoles,
      this.maxImageCount, this.maxImageBytes);

  final String id, provider, modelCode, task;
  final bool enabled;
  final List<ServerModelFormat> formats;
  final Set<String> imageRoles;
  final int maxImageCount;
  final int maxImageBytes;

  static ServerModelMode fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final provider = json['provider'];
    final model = json['modelCode'];
    final task = json['task'];
    final enabled = json['enabled'];
    final formats = json['formats'];
    final imageRoles = json['imageRoles'];
    final maxImageCount = json['maxImageCount'];
    final maxImageBytes = json['maxImageBytes'];

    if (id is! String || !RegExp(r'^[a-z0-9][a-z0-9/_:.-]{2,160}$').hasMatch(id) ||
        provider is! String || provider.isEmpty ||
        model is! String || model.isEmpty ||
        !const ['video', 'image', 'script', 'speech', 'transcription'].contains(task) ||
        enabled is! bool || formats is! List || formats.length > 1000 ||
        imageRoles is! List ||
        !imageRoles.every((r) => r is String &&
            const ['first_frame', 'last_frame', 'image_reference'].contains(r)) ||
        maxImageCount is! int || maxImageCount < 0 || maxImageCount > 100 ||
        maxImageBytes is! int || maxImageBytes < 0 ||
        maxImageBytes > 1024 * 1024 * 1024) {
      throw const FormatException('Invalid model capabilities.');
    }
    final parsedFormats = <ServerModelFormat>[];
    for (final value in formats) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid output combination.');
      }
      parsedFormats.add(ServerModelFormat.fromJson(value));
    }
    if (enabled && parsedFormats.isEmpty) {
      throw const FormatException('Enabled model needs validated formats.');
    }
    return ServerModelMode._(
        id, provider, model, task, enabled,
        List<ServerModelFormat>.unmodifiable(parsedFormats),
        Set<String>.unmodifiable(imageRoles.cast<String>().toSet()),
        maxImageCount, maxImageBytes);
  }

  bool supports({
    required String aspect,
    required String resolution,
    int? seconds,
    Map<String, int> imageRoleCounts = const {},
    int maxAssetBytes = 0,
  }) {
    if (!enabled) return false;
    if (!formats.any((item) =>
        item.aspect == aspect && item.resolution == resolution &&
        item.seconds == seconds)) return false;
    var images = 0;
    for (final entry in imageRoleCounts.entries) {
      if (entry.value < 0 || !imageRoles.contains(entry.key)) return false;
      images += entry.value;
      if (entry.key == 'first_frame' && entry.value > 1) return false;
      if (entry.key == 'last_frame' && entry.value > 1) return false;
    }
    if ((imageRoleCounts['last_frame'] ?? 0) > 0 &&
        (imageRoleCounts['first_frame'] ?? 0) != 1) return false;
    if (images > maxImageCount || maxAssetBytes < 0 ||
        (images > 0 && (maxImageBytes == 0 ||
          maxAssetBytes > maxImageBytes))) return false;
    return true;
  }
}

class ServerModelFormat {
  const ServerModelFormat(this.aspect, this.resolution, this.seconds);
  final String aspect, resolution;
  /// Null is a documented automatic/non-controllable video duration.
  final int? seconds;

  factory ServerModelFormat.fromJson(Map<String, dynamic> json) {
    final aspect = json['aspect'];
    final resolution = json['resolution'];
    final seconds = json['seconds'];
    if (aspect is! String || aspect.isEmpty ||
        resolution is! String || resolution.isEmpty ||
        (seconds != null && (seconds is! int || seconds < 1 || seconds > 3600))) {
      throw const FormatException('Unverified format tuple.');
    }
    return ServerModelFormat(aspect, resolution, seconds);
  }
}
