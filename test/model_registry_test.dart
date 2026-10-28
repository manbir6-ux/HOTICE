import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/model_registry.dart';

AiRequest video(AiCapability spec, {
  int seconds = 8, String? ratio, String? resolution,
  List<AiAsset> assets = const [],
}) => AiRequest(
  task: AiTask.video,
  prompt: 'A stylish cinematic street scene',
  seconds: seconds,
  aspect: ratio ?? (spec.aspects.isEmpty ? null : spec.aspects.first),
  resolution: resolution ?? (spec.resolutions.isEmpty ? null : spec.resolutions.first),
  assets: assets,
);

const first = AiAsset('start', AiMediaRole.firstFrame, 10000, 'image/jpeg');
const last = AiAsset('end', AiMediaRole.lastFrame, 12000, 'image/jpeg');
const face = AiAsset('face', AiMediaRole.imageReference, 9000, 'image/png');
const mesh = AiAsset('mesh', AiMediaRole.nativeMesh, 13000, 'model/gltf-binary');

void main() {
  test('every research record has unique provider-scoped ID and docs', () {
    final items = HoticeAiCatalog.entries;
    expect(items, isNotEmpty);
    expect(items.map((e) => e.id).toSet().length, items.length);
    for (final item in items) {
      expect(item.id, contains('/'));
      expect(item.docsUrl.startsWith('https://'), isTrue);
      expect(item.provider, isNotEmpty);
      expect(item.route, isNotEmpty);
      expect(HoticeAiCatalog.find(item.id), same(item));
    }
    expect(HoticeAiCatalog.find('not-a-real-model'), isNull);
  });

  test('Gemini Omni text vs image-to-video have separate input contracts', () {
    final text = HoticeAiCatalog.find('google/omni-1.1:text-video')!;
    final image = HoticeAiCatalog.find('google/omni-1.1:image-video')!;
    expect(text.validate(AiRequest(task: AiTask.video,
      prompt: 'Cinematic landscape', aspect: '16:9',
      resolution: '720p')), isEmpty);
    expect(text.validate(video(text)), isNotEmpty);
    expect(text.validate(video(text, seconds: 11)), isNotEmpty);
    expect(text.validate(video(text, assets: [first])), isNotEmpty);
    AiRequest imageIntent(List<AiAsset> assets) => AiRequest(
      task: AiTask.video, prompt: 'Film', aspect: '16:9',
      resolution: '720p', assets: assets,
    );
    expect(image.validate(imageIntent([first])), isEmpty);
    expect(image.validate(imageIntent([first, last])), isEmpty);
    expect(image.validate(imageIntent([face])), isNotEmpty);
    expect(image.validate(imageIntent([last])), isNotEmpty);
    expect(image.validate(imageIntent([first, last, face])), isNotEmpty);
    expect(image.validate(imageIntent([first, mesh])), isNotEmpty);
  });

  test('Runway rejects aspect labels and accepts provider pixel dimensions', () {
    final model = HoticeAiCatalog.find('runway/gen4.5:text-video')!;
    expect(model.validate(video(model, ratio: '16:9')), isNotEmpty);
    expect(model.validate(video(model, ratio: '1280:720')), isEmpty);
    expect(model.validate(video(model, seconds: 1)), isNotEmpty);
    expect(model.validate(video(model, seconds: 10)), isEmpty);
    final image = HoticeAiCatalog.find('runway/gen4.5:image-video')!;
    expect(image.validate(video(image, ratio: '960:960', assets: [first])), isEmpty);
    expect(image.validate(video(image, assets: [first, last])), isNotEmpty);
  });

  test('Luma and unverified hosted Kling fail closed', () {
    for (final id in [
      'luma/ray-2:video',
      'runway/kling4:text-video',
      'google/omni-1.1:multi-reference',
    ]) {
      final item = HoticeAiCatalog.find(id)!;
      final params = video(item);
      expect(item.validate(params), isNotEmpty);
    }
  });

  test('retired Sora and Gemini Veo preview cannot be selected for jobs', () {
    for (final item in HoticeAiCatalog.entries
        .where((item) => item.status == AiStatus.retired)) {
      expect(item.validate(AiRequest(
        task: AiTask.video,
        prompt: 'A scene', seconds: 8, aspect: '16:9', resolution: '720p',
      )), isNotEmpty);
    }
  });

  test('image, script and speech models reject video jobs', () {
    for (final item in HoticeAiCatalog.entries
        .where((item) => item.task != AiTask.video)) {
      expect(item.validate(AiRequest(
        task: AiTask.video,
        prompt: 'A scene', seconds: 8,
      )), isNotEmpty);
    }
  });

  test('transcription requires exactly one audio asset and no fake text prompt', () {
    final openai = HoticeAiCatalog.find('openai/gpt-transcribe:audio')!;
    const upload = AiAsset('song', AiMediaRole.audioReference, 125000, 'audio/mpeg');
    expect(openai.validate(AiRequest(
      task: AiTask.transcription, prompt: '', assets: [upload],
    )), isEmpty);
    expect(openai.validate(AiRequest(
      task: AiTask.transcription, prompt: '',
    )), isNotEmpty);
    expect(openai.validate(AiRequest(
      task: AiTask.transcription, prompt: '', assets: [upload, upload],
    )), isNotEmpty);
    final google = HoticeAiCatalog.find('google/gemini-3.5-transcribe:audio')!;
    expect(google.validate(AiRequest(
      task: AiTask.transcription, prompt: '', assets: [upload],
    )), isEmpty);
  });

  test('duplicate reference IDs and bad file metadata are rejected', () {
    final model = HoticeAiCatalog.find('runway/gen4.5:image-video')!;
    expect(model.validate(video(model, assets: [first, first])), isNotEmpty);
    expect(model.validate(video(model, assets: [
      const AiAsset('', AiMediaRole.firstFrame, 0, ''),
    ])), isNotEmpty);
  });

  test('no runtime calls without all authenticated server gates', () {
    const all = AiApiReadiness(
      backendAuthenticated: true, keyTested: true,
      entitlementVerified: true, priceVerified: true,
      quotaVerified: true, schemaProbed: true, uploadsVerified: true,
    );
    expect(all.complete, isTrue);
    const missingPrice = AiApiReadiness(
      backendAuthenticated: true, keyTested: true,
      entitlementVerified: true, priceVerified: false,
      quotaVerified: true, schemaProbed: true, uploadsVerified: true,
    );
    expect(missingPrice.complete, isFalse);
  });

  test('provider failures are categorized and retries need deduplication', () {
    expect(AiFailure.category(401), 'authentication_or_entitlement');
    expect(AiFailure.category(422), 'invalid_or_retired_model');
    expect(AiFailure.category(402), 'billing');
    expect(AiFailure.category(429), 'rate_limit_or_transient');
    expect(AiFailure.category(503), 'provider_outage');
    expect(AiFailure.candidateForSafeRetry(429), isTrue);
    expect(AiFailure.candidateForSafeRetry(400), isFalse);
  });
}
