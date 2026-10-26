<?php
declare(strict_types=1);

require_once __DIR__ . '/../src/GeminiOmniPayload.php';

use Hotice\Provider\GeminiOmniPayload;

function check(bool $condition, string $message): void {
    if (!$condition) throw new RuntimeException($message);
}
function refuses(callable $callback): void {
    try { $callback(); } catch (InvalidArgumentException $e) { return; }
    throw new RuntimeException('Expected rejected input');
}

$p = GeminiOmniPayload::prepare('Hero enters the scene', '9:16');
check($p['model'] === 'gemini-omni-1.1-flash', 'wrong provider model');
check(count($p['input']) === 1, 'unexpected refs');
check($p['response_format']['aspect_ratio'] === '9:16', 'wrong ratio');
check(!isset($p['generation_config']), 'unexpected advanced setting');

// Real 1x1 PNG fixture: reject fake JPEG labels and arbitrary base64.
$photo = [
    'data' => 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO8F0WQAAAAASUVORK5CYII=',
    'mime_type' => 'image/png',
];
$p = GeminiOmniPayload::prepare('A cinematic shot', '16:9',
    [$photo, $photo], 'reference_to_video');
check(count($p['input']) === 3, 'two images and a text prompt expected');
check($p['generation_config']['video_config']['task'] === 'reference_to_video',
    'wrong task');
refuses(fn() => GeminiOmniPayload::prepare('', '16:9'));
refuses(fn() => GeminiOmniPayload::prepare('Scene', '1:1'));
refuses(fn() => GeminiOmniPayload::prepare('Scene', '9:16',
    [$photo, $photo, $photo]));
refuses(fn() => GeminiOmniPayload::prepare('Scene', '16:9',
    [['data' => base64_encode('fake-image-binary'),
      'mime_type' => 'image/png']]));
refuses(fn() => GeminiOmniPayload::prepare('Scene', '16:9',
    [['data' => $photo['data'], 'mime_type' => 'image/jpeg']]));
refuses(fn() => GeminiOmniPayload::prepare('Scene', '16:9',
    [['data' => 'bad$!', 'mime_type' => 'image/jpeg']]));
refuses(fn() => GeminiOmniPayload::prepare('Scene', '16:9', [], 'not_real'));
echo "Gemini Omni server-only payload contract checks passed.\n";
