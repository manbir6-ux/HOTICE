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
    this.maxInputs = const <VideoAttachment, int>{},
    this.maxActors = 1,
    this.priceBand = 'Unpriced preview',
    this.supportsSeed = false,
    this.supportsNegativePrompt = false,
    this.supportsSound = false,
  });

  final String id;
  final String label;

  /// Valid combinations: duration -> supported aspect ratios.
  final Map<int, List<String>> formatsBySeconds;
  final List<VideoAttachment> attachments;
  /// UI test limits only; do not treat these as live provider contracts.
  final Map<VideoAttachment, int> maxInputs;
  final int maxActors;
  final String priceBand;
  final bool supportsSeed;
  final bool supportsNegativePrompt;
  final bool supportsSound;

  int maximumFor(VideoAttachment type) =>
      maxInputs[type] ?? (attachments.contains(type) ? 1 : 0);

  String? validateInputs(Iterable<VideoAttachment> requested) {
    for (final type in VideoAttachment.values) {
      final count = requested.where((input) => input == type).length;
      if (count > maximumFor(type)) {
        return 'Selected model supports up to ${maximumFor(type)} ${type.label.toLowerCase()} file(s).';
      }
    }
    return null;
  }

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
      validateInputs(requested) == null;

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
    maxInputs: {VideoAttachment.image: 1},
    priceBand: 'Budget · illustrative',
    maxActors: 2,
  ),
  VideoModelProfile(
    id: 'character_demo',
    label: 'Character Focus · Demo',
    formatsBySeconds: {
      4: ['16:9', '9:16'],
      8: ['16:9', '9:16'],
    },
    attachments: [VideoAttachment.image, VideoAttachment.video],
    maxInputs: {VideoAttachment.image: 4, VideoAttachment.video: 1},
    priceBand: 'Balanced · illustrative',
    maxActors: 4,
    supportsSeed: true,
    supportsNegativePrompt: true,
  ),
  VideoModelProfile(
    id: 'storyboard_demo',
    label: 'Storyboard Mode · Demo',
    formatsBySeconds: {
      4: ['16:9', '1:1'],
      8: ['16:9', '1:1'],
      10: ['16:9'],
    },
    priceBand: 'Premium · illustrative',
    maxActors: 1,
  ),
  // This *planning preset* is based on Google's published Gemini Omni Flash
  // developer docs. Input counts and "maxActors" here are conservative HOTICE
  // demo policies, NOT claims of official maximums or a connected provider.
  // The production model list must come from the secure server catalog.
  VideoModelProfile(
    id: 'gemini_omni_flash_preview',
    label: 'Gemini Omni Flash · Integration preview',
    formatsBySeconds: {
      3: ['16:9', '9:16'],
      5: ['16:9', '9:16'],
      10: ['16:9', '9:16'],
    },
    attachments: [
      VideoAttachment.image, VideoAttachment.video, VideoAttachment.audio,
    ],
    maxInputs: {
      VideoAttachment.image: 2,
      VideoAttachment.video: 1,
      VideoAttachment.audio: 1,
    },
    maxActors: 3,
    priceBand: 'Price not connected',
  ),
  VideoModelProfile(
    id: 'multimodal_demo',
    label: 'Multimodal Studio · Demo',
    formatsBySeconds: {
      4: ['16:9', '9:16', '1:1'],
      8: ['16:9', '9:16', '1:1'],
      12: ['16:9', '9:16'],
    },
    attachments: [VideoAttachment.image, VideoAttachment.video, VideoAttachment.audio],
    maxInputs: {VideoAttachment.image: 7, VideoAttachment.video: 2, VideoAttachment.audio: 1},
    maxActors: 6,
    supportsSeed: true,
    supportsNegativePrompt: true,
    supportsSound: true,
    priceBand: 'Premium+ · illustrative',
  ),
];

VideoModelProfile demoModelById(String id) => demoVideoModels.firstWhere(
      (model) => model.id == id,
      orElse: () => demoVideoModels.first,
    );
