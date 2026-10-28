import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotice/src/server_model_manifest.dart';

String manifest({
  String? expires,
  List<Map<String, Object?>>? models,
  int schema = 1,
}) => jsonEncode({
  'schemaVersion': schema,
  'revision': 'sha256-test-fixture',
  'expiresAt': expires ?? '2026-10-29T01:00:00Z',
  'models': models ?? [
    {
      'id': 'runway/gen4.5:image-video',
      'provider': 'runway',
      'modelCode': 'gen4.5',
      'task': 'video',
      'enabled': true,
      'formats': [
        {'aspect': '1280:720', 'resolution': '720p', 'seconds': 5},
        {'aspect': '720:1280', 'resolution': '720p', 'seconds': 10},
      ],
      'imageRoles': ['first_frame'],
      'maxImageCount': 1,
      'maxImageBytes': 2000000,
    }
  ],
});

void main() {
  final now = DateTime.utc(2026, 10, 28);
  test('parses narrowly scoped, expiring versioned backend manifest', () {
    final parsed = ServerModelManifest.parseTrustedBackendJson(
      manifest(), now: now);
    expect(parsed.revision, 'sha256-test-fixture');
    expect(parsed.models.length, 1);
    final model = parsed.lookup('runway/gen4.5:image-video')!;
    expect(model.modelCode, 'gen4.5');
    expect(model.supports(
      aspect: '1280:720', resolution: '720p', seconds: 5,
      imageRoleCounts: {'first_frame': 1}, maxAssetBytes: 1500000,
    ), isTrue);
    expect(model.supports(
      aspect: '1280:720', resolution: '720p', seconds: 10,
    ), isFalse);
    expect(model.supports(
      aspect: '720:1280', resolution: '720p', seconds: 5,
    ), isFalse);
    expect(model.supports(
      aspect: '1280:720', resolution: '720p', seconds: 5,
      imageRoleCounts: {'image_reference': 1},
    ), isFalse);
    expect(model.supports(
      aspect: '1280:720', resolution: '720p', seconds: 5,
      imageRoleCounts: {'first_frame': 2},
    ), isFalse);
    expect(model.supports(
      aspect: '1280:720', resolution: '720p', seconds: 5,
      imageRoleCounts: {'first_frame': 1}, maxAssetBytes: 3000000,
    ), isFalse);
    expect(parsed.lookup('unknown-model'), isNull);
  });

  test('rejects expired or unbounded cache duration', () {
    expect(() => ServerModelManifest.parseTrustedBackendJson(
      manifest(expires: '2026-10-27T10:00:00Z'), now: now),
      throwsFormatException);
    expect(() => ServerModelManifest.parseTrustedBackendJson(
      manifest(expires: '2026-12-01T10:00:00Z'), now: now),
      throwsFormatException);
    expect(() => ServerModelManifest.parseTrustedBackendJson(
      manifest(schema: 2), now: now), throwsFormatException);
  });

  test('rejects duplicate IDs and unknown media roles', () {
    final valid = (jsonDecode(manifest()) as Map<String, dynamic>);
    final original = (valid['models'] as List).single as Map<String, dynamic>;
    final duplicate = [original, Map<String, dynamic>.from(original)];
    expect(() => ServerModelManifest.parseTrustedBackendJson(
      manifest(models: duplicate), now: now), throwsFormatException);
    final wrong = Map<String, dynamic>.from(original)
      ..['imageRoles'] = ['untrusted_mesh'];
    expect(() => ServerModelManifest.parseTrustedBackendJson(
      manifest(models: [wrong]), now: now), throwsFormatException);
  });

  test('unverified or unknown output tuple is never allowed', () {
    final data = jsonDecode(manifest()) as Map<String, dynamic>;
    final original = Map<String, Object?>.from(
        (data['models'] as List).single as Map);
    original['enabled'] = false;
    final disabled = ServerModelManifest.parseTrustedBackendJson(
      manifest(models: [original]), now: now).models.single;
    expect(disabled.supports(aspect: '1280:720', resolution: '720p', seconds: 5),
      isFalse);
    expect(() => ServerModelManifest.parseTrustedBackendJson(
      manifest(models: [
        {...original, 'enabled': true, 'formats': []},
      ]), now: now), throwsFormatException);
  });
}
