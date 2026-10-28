<?php
declare(strict_types=1);

require_once __DIR__ . '/../php/ProviderEnvelope.php';

use HOTICE\AI\ProviderEnvelope;

function check(bool $ok, string $message): void {
    if (!$ok) throw new RuntimeException($message);
}
function rejects(callable $action, string $message): void {
    try {
        $action();
    } catch (InvalidArgumentException | RuntimeException $e) {
        return;
    }
    throw new RuntimeException('Expected rejection: ' . $message);
}

$gates = [
    'authenticated' => true,
    'entitled' => true,
    'keyTested' => true,
    'priceQuoted' => true,
    'quotaAvailable' => true,
    'idempotentJobSaved' => true,
    'schemaVerified' => true,
];
$google = ProviderEnvelope::create(
    'google/omni-1.1:text-video',
    ['prompt' => 'A forest at dawn', 'seconds' => null,
     'ratio' => '16:9', 'resolution' => '720p', 'assetCount' => 0],
    $gates,
);
check($google['host'] === 'https://generativelanguage.googleapis.com', 'Google host');
check($google['json']['model'] === 'gemini-omni-1.1-flash', 'Google ID');
check(!isset($google['json']['duration']), 'No undocumented duration field');
check(!isset($google['headers']['x-goog-api-key']), 'Secrets must not be in plan');

$runway = ProviderEnvelope::create(
    'runway/gen4.5:text-video',
    ['prompt' => 'Driving through a city', 'seconds' => 8,
     'ratio' => '1280:720', 'resolution' => '720p', 'assetCount' => 0],
    $gates,
);
check($runway['json']['duration'] === 8, 'Runway duration');
check($runway['json']['model'] === 'gen4.5', 'Runway ID');
check($runway['headers']['X-Runway-Version'] === '2024-11-06', 'Version');
check(!isset($runway['headers']['Authorization']), 'No key in plan');

rejects(fn() => ProviderEnvelope::create(
    'openai/sora-2:retired',
    ['prompt' => 'Test', 'seconds' => 8, 'ratio' => '16:9',
     'resolution' => '720p'], $gates), 'Retired API');
rejects(fn() => ProviderEnvelope::create(
    'google/omni-1.1:text-video',
    ['prompt' => 'Test', 'seconds' => 8, 'ratio' => '16:9',
     'resolution' => '720p'], $gates), 'Do not silently drop requested duration');
rejects(fn() => ProviderEnvelope::create(
    'runway/gen4.5:text-video',
    ['prompt' => 'Test', 'seconds' => 8, 'ratio' => '16:9',
     'resolution' => '720p'], $gates), 'Runway requires pixel ratio');
rejects(fn() => ProviderEnvelope::create(
    'runway/gen4.5:text-video',
    ['prompt' => 'Test', 'seconds' => 12, 'ratio' => '1280:720',
     'resolution' => '720p'], $gates), 'Runway duration limit');
rejects(fn() => ProviderEnvelope::create(
    'runway/gen4.5:text-video',
    ['prompt' => 'Test', 'seconds' => 8, 'ratio' => '1280:720',
     'resolution' => '720p', 'assetCount' => 1], $gates), 'Text builder cannot upload');
$missingQuote = $gates;
$missingQuote['priceQuoted'] = false;
rejects(fn() => ProviderEnvelope::create(
    'runway/gen4.5:text-video',
    ['prompt' => 'Test', 'seconds' => 8, 'ratio' => '1280:720',
     'resolution' => '720p'], $missingQuote), 'Mandatory quote');
putenv('HOTICE_RUNWAY_API_KEY');
rejects(fn() => ProviderEnvelope::secretHeaders(
    'runway/gen4.5:text-video', $runway), 'Unconfigured secret');
putenv('HOTICE_RUNWAY_API_KEY=local-inert-test-value');
rejects(fn() => ProviderEnvelope::secretHeaders(
    'runway/gen4.5:text-video',
    array_merge($runway, ['host' => 'https://malicious.invalid'])
), 'SSRF host allowlist');
$headers = ProviderEnvelope::secretHeaders('runway/gen4.5:text-video', $runway);
check($headers['Authorization'] === 'Bearer local-inert-test-value',
    'Server-only credential header');
putenv('HOTICE_RUNWAY_API_KEY');

echo "HOTICE PHP provider request policy: 11 checks passed.\n";
