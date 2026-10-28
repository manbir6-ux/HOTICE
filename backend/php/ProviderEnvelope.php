<?php
declare(strict_types=1);

namespace HOTICE\AI;

use InvalidArgumentException;
use RuntimeException;

/**
 * Server-only request envelope builders for TWO text-only video workflows.
 *
 * Not an HTTP endpoint or a functioning payments/generation service.
 * A trusted authenticated server job service must check quota, account
 * entitlement, asset access, price, ledger reservation and idempotency.
 *
 * NEVER call this from Flutter or put API credentials in a mobile bundle.
 */
final class ProviderEnvelope
{
    /**
     * @param array<string,mixed> $intent Already validated by server.
     * @param array<string,bool> $gates Server-derived booleans, never client supplied.
     * @return array{method:string,host:string,path:string,headers:array<string,string>,json:array<string,mixed>}
     */
    public static function create(string $profile, array $intent, array $gates): array
    {
        foreach ([
            'authenticated', 'entitled', 'keyTested', 'priceQuoted',
            'quotaAvailable', 'idempotentJobSaved', 'schemaVerified'
        ] as $gate) {
            if (($gates[$gate] ?? false) !== true) {
                throw new RuntimeException('Refusing unverified server gate: ' . $gate);
            }
        }
        $prompt = $intent['prompt'] ?? null;
        if (!is_string($prompt) || trim($prompt) === '' || strlen($prompt) > 20000) {
            throw new InvalidArgumentException('Invalid prompt.');
        }
        if (($intent['assetCount'] ?? 0) !== 0) {
            throw new InvalidArgumentException('This server-only builder supports text only.');
        }
        $ratio = $intent['ratio'] ?? null;
        $resolution = $intent['resolution'] ?? null;
        $seconds = $intent['seconds'] ?? null;
        if (!is_string($ratio) || !is_string($resolution) || !is_int($seconds)) {
            throw new InvalidArgumentException('Missing validated video fields.');
        }
        if ($profile === 'google/omni-1.1:text-video') {
            if (!in_array($ratio, ['16:9', '9:16'], true) ||
                !in_array($resolution, ['360p', '720p', '1080p', '4k'], true) ||
                $seconds < 3 || $seconds > 10) {
                throw new InvalidArgumentException('Invalid Gemini Omni settings.');
            }
            // The current REST guide does NOT document an exact duration
            // request field. We do not invent one. A back-end probe must
            // confirm effective output length and corresponding pricing.
            return [
                'method' => 'POST',
                'host' => 'https://generativelanguage.googleapis.com',
                'path' => '/v1beta/interactions',
                'headers' => ['Content-Type' => 'application/json'],
                'json' => [
                    'model' => 'gemini-omni-1.1-flash',
                    'input' => trim($prompt),
                    'response_format' => [
                        'type' => 'video',
                        'aspect_ratio' => $ratio,
                        'resolution' => $resolution,
                        'delivery' => 'uri',
                    ],
                ],
            ];
        }
        if ($profile === 'runway/gen4.5:text-video') {
            if (!in_array($ratio, ['1280:720', '720:1280'], true) ||
                $resolution !== '720p' || $seconds < 2 || $seconds > 10) {
                throw new InvalidArgumentException('Invalid Runway Gen-4.5 settings.');
            }
            return [
                'method' => 'POST',
                'host' => 'https://api.dev.runwayml.com',
                'path' => '/v1/text_to_video',
                'headers' => [
                    'Content-Type' => 'application/json',
                    'X-Runway-Version' => '2024-11-06',
                ],
                'json' => [
                    'model' => 'gen4.5',
                    'promptText' => trim($prompt),
                    'ratio' => $ratio,
                    'duration' => $seconds,
                ],
            ];
        }
        throw new InvalidArgumentException('Unsupported or retired provider profile.');
    }

    /**
     * Inject keys server-side from non-webroot environment, not user input.
     * Return only to the HTTP transport; NEVER serialize/log authorization.
     *
     * @param array{headers:array<string,string>,host:string} $envelope
     * @return array<string,string>
     */
    public static function secretHeaders(string $profile, array $envelope): array
    {
        $google = $profile === 'google/omni-1.1:text-video';
        $runway = $profile === 'runway/gen4.5:text-video';
        if (!$google && !$runway) {
            throw new InvalidArgumentException('No credential policy for model.');
        }
        $name = $google ? 'HOTICE_GOOGLE_API_KEY' : 'HOTICE_RUNWAY_API_KEY';
        $value = getenv($name);
        if (!is_string($value) || $value === '') {
            throw new RuntimeException('Server API credential is not configured.');
        }
        $expectedHost = $google
            ? 'https://generativelanguage.googleapis.com'
            : 'https://api.dev.runwayml.com';
        if (($envelope['host'] ?? null) !== $expectedHost) {
            throw new RuntimeException('Upstream host is not allowlisted.');
        }
        $headers = $envelope['headers'];
        if ($google) {
            $headers['x-goog-api-key'] = $value;
        } else {
            $headers['Authorization'] = 'Bearer ' . $value;
        }
        return $headers;
    }
}
