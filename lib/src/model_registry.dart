/// Source-backed research catalog. It DOES NOT authorize an API call.
/// Server must verify keys, roles, quotas, prices, model version and inputs.
enum AiTask { script, image, video, speech, transcription }
enum AiMediaRole { imageReference, firstFrame, lastFrame, videoReference, audioReference, nativeMesh }
enum AiStatus { active, researchOnly, retired }

class AiAsset {
  const AiAsset(this.id, this.role, this.bytes, this.mime);
  final String id, mime;
  final AiMediaRole role;
  final int bytes;
}

class AiRequest {
  AiRequest({required this.task, required this.prompt, this.seconds,
    this.aspect, this.resolution, Iterable<AiAsset> assets = const []})
      : assets = List.unmodifiable(assets);
  final AiTask task;
  final String prompt;
  final int? seconds;
  final String? aspect, resolution;
  final List<AiAsset> assets;
}

class AiCapability {
  const AiCapability({
    required this.id, required this.provider, required this.name,
    required this.task, required this.route, required this.docsUrl,
    required this.status, this.apiVersion = '', this.workflow = '',
    this.aspects = const [], this.resolutions = const [],
    this.minSeconds, this.maxSeconds, this.exactSeconds = const [],
    this.roles = const [], this.allowedMimes = const [],
    this.maxSingleAssetBytes, this.imageLimit, this.videoLimit,
    this.controlsDuration = true,
    this.audioLimit, this.meshLimit = 0, this.firstFrameRequired = false,
    this.notes = '',
  });

  final String id, provider, name, route, docsUrl, apiVersion, workflow, notes;
  final AiTask task;
  final AiStatus status;
  final List<String> aspects, resolutions;
  final int? minSeconds, maxSeconds, imageLimit, videoLimit, audioLimit, meshLimit;
  final List<int> exactSeconds;
  final List<AiMediaRole> roles;
  final List<String> allowedMimes;
  final int? maxSingleAssetBytes;
  final bool firstFrameRequired, controlsDuration;

  List<String> validate(AiRequest request) {
    final errors = <String>[];
    if (status != AiStatus.active) errors.add('Model is unavailable or not yet fully verified.');
    if (request.task != task) errors.add('Wrong task for this model.');
    if (task != AiTask.transcription && request.prompt.trim().isEmpty) {
      errors.add('Prompt cannot be empty.');
    }
    if (task == AiTask.transcription &&
        request.assets.where((a) => a.role == AiMediaRole.audioReference).length != 1) {
      errors.add('Transcription needs exactly one audio upload.');
    }
    if (task == AiTask.video) {
      final length = request.seconds;
      if ((!controlsDuration && length != null) ||
          (controlsDuration && (length == null ||
            (exactSeconds.isNotEmpty && !exactSeconds.contains(length)) ||
            (exactSeconds.isEmpty &&
                (minSeconds == null || maxSeconds == null ||
                 length < minSeconds! || length > maxSeconds!))))) {
        errors.add('Video duration is not supported or unverified.');
      }
      if (!aspects.contains(request.aspect)) errors.add('Unsupported aspect ratio.');
      if (!resolutions.contains(request.resolution)) errors.add('Unsupported output resolution.');
    } else if (request.seconds != null) {
      errors.add('Duration applies only to video.');
    }
    final ids = <String>{};
    for (final asset in request.assets) {
      if (!roles.contains(asset.role)) errors.add('Unsupported media reference role.');
      if (asset.id.isEmpty || !ids.add(asset.id)) errors.add('Invalid or duplicate media ID.');
      if (asset.bytes <= 0 || asset.mime.isEmpty) {
        errors.add('Unverified file MIME or size.');
      }
      if (!allowedMimes.contains(asset.mime.toLowerCase())) {
        errors.add('Unverified or unsupported media MIME type.');
      }
      if (maxSingleAssetBytes != null && asset.bytes > maxSingleAssetBytes!) {
        errors.add('File exceeds documented per-upload size limit.');
      }
    }
    final images = request.assets.where((a) =>
      a.role == AiMediaRole.firstFrame ||
      a.role == AiMediaRole.lastFrame ||
      a.role == AiMediaRole.imageReference).length;
    final videos = request.assets.where((a) =>
      a.role == AiMediaRole.videoReference).length;
    final audio = request.assets.where((a) =>
      a.role == AiMediaRole.audioReference).length;
    final meshes = request.assets.where((a) =>
      a.role == AiMediaRole.nativeMesh).length;
    void guard(int count, int? maximum, String category) {
      if (count > 0 && (maximum == null || count > maximum)) {
        errors.add('Reference limit for ' + category + ' is unknown or exceeded.');
      }
    }
    guard(images, imageLimit, 'images');
    guard(videos, videoLimit, 'videos');
    guard(audio, audioLimit, 'audio');
    guard(meshes, meshLimit, '3D files');
    final first = request.assets.where((a) => a.role == AiMediaRole.firstFrame).length;
    final last = request.assets.where((a) => a.role == AiMediaRole.lastFrame).length;
    if (first > 1 || last > 1) errors.add('Only one first/last frame per generation.');
    if (last > 0 && first != 1) errors.add('Last frame must accompany a first frame.');
    if (firstFrameRequired && first != 1) errors.add('A first frame is required.');
    return List.unmodifiable(errors);
  }
}

/// Server-enforced readiness; client hints are never a substitute for auth.
class AiApiReadiness {
  const AiApiReadiness({required this.backendAuthenticated,
    required this.keyTested, required this.entitlementVerified,
    required this.priceVerified, required this.quotaVerified,
    required this.schemaProbed, required this.uploadsVerified});
  final bool backendAuthenticated, keyTested, entitlementVerified;
  final bool priceVerified, quotaVerified, schemaProbed, uploadsVerified;
  bool get complete => backendAuthenticated && keyTested && entitlementVerified &&
    priceVerified && quotaVerified && schemaProbed && uploadsVerified;
}

class AiFailure {
  static String category(int code) {
    if (code == 401 || code == 403) return 'authentication_or_entitlement';
    if (code == 402) return 'billing';
    if (code == 400 || code == 404 || code == 422) return 'invalid_or_retired_model';
    if (code == 408 || code == 425 || code == 429) return 'rate_limit_or_transient';
    if (code >= 500 && code < 600) return 'provider_outage';
    return 'unknown';
  }
  /// A retry also requires server-side idempotency/no-job-created evidence.
  static bool candidateForSafeRetry(int code) =>
      code == 408 || code == 425 || code == 429 ||
      (code >= 500 && code < 600);
}

/// Verified against linked official documentation on 2026-10-28.
/// These are research snapshots. No billable job is enabled by this list.
class HoticeAiCatalog {
  static const entries = <AiCapability>[
    AiCapability(
      id: 'google/omni-1.1:text-video', provider: 'Google Gemini API',
      name: 'Gemini Omni 1.1 Flash · Text to Video',
      task: AiTask.video, workflow: 'text_to_video',
      route: 'POST /v1beta/interactions', status: AiStatus.active,
      docsUrl: 'https://ai.google.dev/gemini-api/docs/omni',
      aspects: ['16:9','9:16'],
      resolutions: ['360p','720p','1080p','4k'],
      minSeconds: 3, maxSeconds: 10, controlsDuration: false,
      notes: '1080p and 4K are upscaled. No native 3D mesh input.',
    ),
    AiCapability(
      id: 'google/omni-1.1:image-video', provider: 'Google Gemini API',
      name: 'Gemini Omni 1.1 Flash · Keyframe Video',
      task: AiTask.video, workflow: 'image_to_video',
      route: 'POST /v1beta/interactions', status: AiStatus.active,
      docsUrl: 'https://ai.google.dev/gemini-api/docs/omni',
      aspects: ['16:9','9:16'],
      resolutions: ['360p','720p','1080p','4k'],
      minSeconds: 3, maxSeconds: 10, controlsDuration: false,
      roles: [AiMediaRole.firstFrame,AiMediaRole.lastFrame],
      allowedMimes: ['image/jpeg','image/png'],
      firstFrameRequired: true, imageLimit: 2,
      notes: 'Two keyframes are NOT interchangeable with two identity references.',
    ),
    AiCapability(
      id: 'google/omni-1.1:multi-reference', provider: 'Google Gemini API',
      name: 'Gemini Omni Flash · Multi-reference research',
      task: AiTask.video, workflow: 'reference_to_video',
      route: 'POST /v1beta/interactions', status: AiStatus.researchOnly,
      docsUrl: 'https://ai.google.dev/gemini-api/docs/omni',
      aspects: ['16:9','9:16'],
      resolutions: ['360p','720p','1080p','4k'],
      minSeconds: 3, maxSeconds: 10, controlsDuration: false,
      roles: [AiMediaRole.imageReference,AiMediaRole.videoReference],
      notes: 'Joint reference counts unknown; block until server validates model and asset semantics.',
    ),
    AiCapability(
      id: 'runway/gen4.5:text-video', provider: 'Runway API',
      name: 'Runway Gen-4.5 · Text to Video',
      task: AiTask.video, workflow: 'text_to_video',
      route: 'POST /v1/text_to_video', apiVersion: '2024-11-06',
      status: AiStatus.active,
      docsUrl: 'https://docs.dev.runwayml.com/assets/inputs/',
      aspects: ['1280:720','720:1280'],
      resolutions: ['720p'], minSeconds: 2, maxSeconds: 10,
      notes: 'API uses pixel ratios rather than 16:9 labels.',
    ),
    AiCapability(
      id: 'runway/gen4.5:image-video', provider: 'Runway API',
      name: 'Runway Gen-4.5 · Image to Video',
      task: AiTask.video, workflow: 'image_to_video',
      route: 'POST /v1/image_to_video', apiVersion: '2024-11-06',
      status: AiStatus.active,
      docsUrl: 'https://docs.dev.runwayml.com/assets/inputs/',
      aspects: ['1280:720','720:1280','1584:672','1104:832','832:1104','672:1584','960:960'],
      resolutions: ['720p'], minSeconds: 2, maxSeconds: 10,
      roles: [AiMediaRole.firstFrame], imageLimit: 1,
      allowedMimes: ['image/jpeg','image/png'],
      firstFrameRequired: true,
      notes: 'One prompt image, not an arbitrary 4-reference avatar mode.',
    ),
    AiCapability(
      id: 'runway/kling4:text-video', provider: 'Runway API (Kling hosted)',
      name: 'Kling 4 via Runway · Research',
      task: AiTask.video, workflow: 'text_to_video',
      route: 'POST /v1/text_to_video', apiVersion: '2024-11-06',
      status: AiStatus.researchOnly,
      docsUrl: 'https://docs.dev.runwayml.com/assets/inputs/',
      aspects: ['1280:720','720:1280','940:940','1460:624','1920:1080','1080:1920','1440:1440','2200:940'],
      resolutions: ['720p','1080p'],
      minSeconds: 3,maxSeconds: 30,
      notes: 'Requires resolution-ratio pair validation. Runway gateway is not native Kling API.',
    ),
    AiCapability(
      id: 'luma/ray-2:video', provider: 'Luma Dream Machine',
      name: 'Luma Ray 2 · Research',
      task: AiTask.video, route: 'POST /dream-machine/v1/generations/video',
      status: AiStatus.researchOnly,
      docsUrl: 'https://docs.lumalabs.ai/reference/creategeneration',
      aspects: ['1:1','16:9','9:16','4:3','3:4','21:9','9:21'],
      notes: 'Version-specific duration and resolution limits not yet verified.',
    ),
    AiCapability(
      id: 'google/nano-banana-2:image', provider: 'Google Gemini API',
      name: 'Nano Banana 2 · Image',
      task: AiTask.image, route: 'generateContent',
      status: AiStatus.active,
      docsUrl: 'https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-image',
      resolutions: ['0.5K','1K','2K','4K'],
      notes: 'Image creation/editing. Reference count unknown for particular workflow.',
    ),
    AiCapability(
      id: 'openai/gpt-6.1-sol:script', provider: 'OpenAI API',
      name: 'GPT-6.1 Sol · Script',
      task: AiTask.script, route: 'POST /v1/responses',
      status: AiStatus.active,
      docsUrl: 'https://developers.openai.com/api/docs/models',
    ),
    AiCapability(
      id: 'anthropic/claude-sonnet-5:script', provider: 'Anthropic API',
      name: 'Claude Sonnet 5 · Script research',
      task: AiTask.script, route: 'POST /v1/messages',
      status: AiStatus.researchOnly,
      docsUrl: 'https://docs.anthropic.com/en/docs/about-claude/model-deprecations',
      notes: 'Exact model access and account entitlement need live verification.',
    ),
    AiCapability(
      id: 'elevenlabs/eleven_multilingual_v2:speech', provider: 'ElevenLabs API',
      name: 'Eleven Multilingual v2 · Speech',
      task: AiTask.speech, route: 'POST /v1/text-to-speech/{voice_id}',
      status: AiStatus.active,
      docsUrl: 'https://elevenlabs.io/docs/api-reference/text-to-speech/convert',
      notes: 'Voice ID, model availability, char limits and billing must come from backend.',
    ),
    AiCapability(
      id: 'openai/gpt-transcribe:audio', provider: 'OpenAI API',
      name: 'GPT Transcribe · Audio to Text',
      task: AiTask.transcription, route: 'POST /v1/audio/transcriptions',
      status: AiStatus.active,
      docsUrl: 'https://developers.openai.com/api/docs/guides/speech-to-text',
      roles: [AiMediaRole.audioReference], audioLimit: 1,
      allowedMimes: ['audio/mpeg','audio/mp4','video/mp4','audio/x-m4a','audio/wav','audio/webm'],
      maxSingleAssetBytes: 25000000,
      notes: 'Up to 25 MB, supported format list documented; no automatic promise of word timestamps. Separate voice identification pipeline where required.',
    ),
    AiCapability(
      id: 'google/gemini-3.5-transcribe:audio',
      provider: 'Google Gemini API',
      name: 'Gemini 3.5 Transcribe · Word timing',
      task: AiTask.transcription, route: 'POST /v1beta/interactions',
      status: AiStatus.active,
      docsUrl: 'https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe',
      roles: [AiMediaRole.audioReference], audioLimit: 1,
      allowedMimes: ['audio/mpeg','audio/wav'],
      notes: '1h basic audio; 30m when diarization or word timestamps active. Timestamps incompatible with custom vocabulary; diarization also conflicts with custom vocabulary. Feature switches must validate together.',
    ),
    AiCapability(
      id: 'openai/gpt-4o-transcribe-diarize:deprecated',
      provider: 'OpenAI API',
      name: 'GPT-4o Transcribe Diarize · Deprecated',
      task: AiTask.transcription, route: 'POST /v1/audio/transcriptions',
      status: AiStatus.researchOnly,
      docsUrl: 'https://developers.openai.com/api/docs/guides/speech-to-text',
      roles: [AiMediaRole.audioReference], audioLimit: 1,
      notes: 'Scheduled API shutdown 26 February 2027; do not integrate as a new default.',
    ),
    AiCapability(
      id: 'openai/sora-2:retired', provider: 'OpenAI API',
      name: 'Sora 2 · Retired September 2026',
      task: AiTask.video, route: '(retired) /v1/videos',
      status: AiStatus.retired,
      docsUrl: 'https://developers.openai.com/api/docs/deprecations',
    ),
    AiCapability(
      id: 'google/veo3.1-preview:retired', provider: 'Google Gemini API',
      name: 'Veo 3.1 Preview · Retired on Gemini API',
      task: AiTask.video, route: '(retired) generateVideos',
      status: AiStatus.retired,
      docsUrl: 'https://ai.google.dev/gemini-api/docs/video',
      notes: 'Runway/enterprise Veo endpoints are separate products; never conflate them.',
    ),
  ];
  static AiCapability? find(String key) {
    for (final item in entries) {
      if (item.id == key) return item;
    }
    return null;
  }
}
