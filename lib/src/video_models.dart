/// Capabilities for HOTICE's UI-only demo workflows.
///
/// These are NOT real vendor models. No provider API or payment gateway is
/// connected. Production capabilities and prices must come from a verified,
/// versioned provider catalog controlled by the server.
enum VideoAttachment {
  image('Reference image'),
  video('Reference video'),
  audio('Reference audio');

  const VideoAttachment(this.label);
  final String label;
}

class VideoModelProfile {
  const VideoModelProfile({
    required this.id,
    required this.label,
    required this.formatsBySeconds,
    this.attachments = const <VideoAttachment>[],
    this.creditsByFormat = const <String, int>{},
  });

  final String id;
  final String label;

  /// Valid combinations: duration -> supported aspect ratios.
  final Map<int, List<String>> formatsBySeconds;
  final List<VideoAttachment> attachments;

  /// Key format: "seconds|ratio", value: HOTICE Credits.
  /// Empty means pricing is not confirmed and checkout MUST be disabled.
  final Map<String, int> creditsByFormat;

  List<int> get durations {
    final values = formatsBySeconds.keys.toList()..sort();
    return values;
  }

  List<String> ratiosFor(int seconds) =>
      formatsBySeconds[seconds] ?? const <String>[];

  bool supportsOutput(int seconds, String ratio) =>
      ratiosFor(seconds).contains(ratio);

  bool supportsAttachments(Iterable<VideoAttachment> requested) =>
      requested.every(attachments.contains);

  int? quoteCredits(int seconds, String ratio) {
    if (!supportsOutput(seconds, ratio)) return null;
    final amount = creditsByFormat['$seconds|$ratio'];
    return amount != null && amount > 0 ? amount : null;
  }

  /// Do not silently accept an invalid combination on save/send.
  bool accepts({
    required int seconds,
    required String ratio,
    Iterable<VideoAttachment> inputs = const <VideoAttachment>[],
  }) =>
      supportsOutput(seconds, ratio) && supportsAttachments(inputs);
}

/// Illustrative presets to exercise dynamic UI while real provider models
/// and their current prices are NOT configured. Constraints are sample values.
const List<VideoModelProfile> demoVideoModels = [
  VideoModelProfile(
    id: 'cinematic_demo',
    label: 'Cinematic Draft · Demo',
    formatsBySeconds: {
      4: ['16:9', '9:16', '1:1'],
      8: ['16:9', '9:16', '1:1'],
      10: ['16:9', '9:16'],
    },
    attachments: [VideoAttachment.image],
  ),
  VideoModelProfile(
    id: 'character_demo',
    label: 'Character Focus · Demo',
    formatsBySeconds: {
      4: ['16:9', '9:16'],
      8: ['16:9', '9:16'],
    },
    attachments: [VideoAttachment.image, VideoAttachment.video],
  ),
  VideoModelProfile(
    id: 'storyboard_demo',
    label: 'Storyboard Mode · Demo',
    formatsBySeconds: {
      4: ['16:9', '1:1'],
      8: ['16:9', '1:1'],
      10: ['16:9'],
    },
  ),
];

VideoModelProfile demoModelById(String id) => demoVideoModels.firstWhere(
      (model) => model.id == id,
      orElse: () => demoVideoModels.first,
    );
